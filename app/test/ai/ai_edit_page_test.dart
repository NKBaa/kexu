import 'dart:convert';

import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/ai_client_provider.dart';
import 'package:course_timetable/features/ai/ai_edit_page.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Timetable _seed() => Timetable(
      semester: Semester(
        id: 's1',
        name: '2025 秋季学期',
        startMonday: DateTime(2025, 9, 1),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: [
        Course(
          id: 'c1',
          semesterId: 's1',
          name: '高等数学',
          teacher: '张老师',
          sessions: [
            Session(
              id: 'ss1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: List.generate(16, (i) => i + 1),
            ),
          ],
        ),
      ],
    );

const AiModelConfig _textConfig = AiModelConfig(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'k',
  model: 'm',
);

const AppSettings _configuredSettings = AppSettings(
  aiConfig: AiConfig(text: _textConfig),
);

class _FakeTimetableController extends TimetableController {
  _FakeTimetableController(this.current);

  Timetable current;

  @override
  Future<Timetable> build() async => current;

  @override
  Future<void> replaceTimetable(Timetable next, {bool recordHistory = true, String? description}) async {
    current = next;
    state = AsyncData(next);
  }
}

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this.settings);

  final AppSettings settings;

  @override
  Future<AppSettings> build() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    state = AsyncData(settings);
  }
}

http.Response _chatResponse(String content) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      })),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// 依次返回 [contents] 里各条模型回复，并记录每次请求。
MockClient _sequenceClient(List<String> contents, List<http.Request> requests) {
  var index = 0;
  return MockClient((request) async {
    requests.add(request);
    final content = contents[index < contents.length ? index : contents.length - 1];
    index++;
    return _chatResponse(content);
  });
}

Widget _wrap({
  required _FakeTimetableController timetable,
  required _FakeSettingsController settings,
  required AiClient client,
}) {
  return ProviderScope(
    overrides: [
      timetableProvider.overrideWith(() => timetable),
      settingsProvider.overrideWith(() => settings),
      textAiClientProvider.overrideWithValue(client),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const AiEditPage(),
    ),
  );
}

void _bigWindow(WidgetTester tester, {double w = 1400, double h = 2000}) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('对话式流程：反问 → 点候选 → 带历史第二轮 → 出方案 → 应用', (tester) async {
    _bigWindow(tester);
    final requests = <http.Request>[];
    final client = AiClient(
      config: _textConfig,
      httpClient: _sequenceClient(
        [
          '{"summary":"","ask":"你要改哪一门高数？",'
              '"options":["高等数学","高等数学（上）"],"ops":[]}',
          '{"summary":"把高等数学教师改成李四","ops":[{"kind":"updateCourse",'
              '"courseName":"高等数学","args":{"patch":{"teacher":"李四"}}}]}',
        ],
        requests,
      ),
    );
    final controller = _FakeTimetableController(_seed());

    await tester.pumpWidget(
      _wrap(
        timetable: controller,
        settings: _FakeSettingsController(_configuredSettings),
        client: client,
      ),
    );
    await tester.pumpAndSettle();

    // 顶部「现在」信息条
    expect(find.textContaining('现在：'), findsOneWidget);

    // 第一轮：用户说简称「高数」，模型反问并给候选
    await tester.enterText(find.byKey(const ValueKey('ai_edit_input')), '把高数老师改成李四');
    await tester.tap(find.byKey(const ValueKey('ai_edit_send')));
    await tester.pumpAndSettle();

    expect(find.textContaining('你要改哪一门高数？'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_edit_option_高等数学')), findsOneWidget);

    // 点候选 chip 作为下一轮输入
    await tester.tap(find.byKey(const ValueKey('ai_edit_option_高等数学')));
    await tester.pumpAndSettle();

    // 第二轮请求必须带上历史：system + 用户1 + 助手1 + 本轮用户 prompt
    expect(requests, hasLength(2));
    final secondBody =
        jsonDecode(utf8.decode(requests[1].bodyBytes)) as Map<String, dynamic>;
    final messages = secondBody['messages'] as List;
    expect(messages, hasLength(4));
    expect(messages.map((m) => (m as Map)['role']), ['system', 'user', 'assistant', 'user']);
    expect((messages[1] as Map)['content'], '把高数老师改成李四');
    expect((messages[2] as Map)['content'], contains('你要改哪一门高数？'));

    // 方案卡片出现，应用后课表变化
    expect(find.byKey(const ValueKey('ai_edit_plan_card')), findsOneWidget);
    expect(find.textContaining('修改方案'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai_edit_apply')));
    await tester.pumpAndSettle();

    expect(controller.current.courses.first.teacher, '李四');
    expect(find.text('执行结果'), findsOneWidget);
    expect(find.textContaining('成功应用'), findsWidgets);
    // 提示条 2 秒后自动消失，推进掉 Timer，避免测试结束时报 pending timer。
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('空输入给出中文友好提示，不发请求', (tester) async {
    _bigWindow(tester);
    final requests = <http.Request>[];
    final client = AiClient(
      config: _textConfig,
      httpClient: _sequenceClient(['{"ops":[]}'], requests),
    );

    await tester.pumpWidget(
      _wrap(
        timetable: _FakeTimetableController(_seed()),
        settings: _FakeSettingsController(_configuredSettings),
        client: client,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai_edit_send')));
    await tester.pumpAndSettle();

    expect(find.textContaining('请先描述你想怎么改课表'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('未配置语言模型时提示去设置页配置', (tester) async {
    _bigWindow(tester);
    final requests = <http.Request>[];
    final client = AiClient(
      config: _textConfig,
      httpClient: _sequenceClient(['{"ops":[]}'], requests),
    );

    await tester.pumpWidget(
      _wrap(
        timetable: _FakeTimetableController(_seed()),
        settings: _FakeSettingsController(const AppSettings()),
        client: client,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('ai_edit_input')), '把高数改成单周');
    await tester.tap(find.byKey(const ValueKey('ai_edit_send')));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有配置语言模型'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('清空按钮会清空对话记录', (tester) async {
    _bigWindow(tester);
    final requests = <http.Request>[];
    final client = AiClient(
      config: _textConfig,
      httpClient: _sequenceClient(
        ['{"summary":"信息不足，请补充要改哪一门课。","ops":[]}'],
        requests,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        timetable: _FakeTimetableController(_seed()),
        settings: _FakeSettingsController(_configuredSettings),
        client: client,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('ai_edit_input')), '改一下课');
    await tester.tap(find.byKey(const ValueKey('ai_edit_send')));
    await tester.pumpAndSettle();

    expect(find.text('改一下课'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai_edit_clear')));
    await tester.pumpAndSettle();

    expect(find.text('改一下课'), findsNothing);
    expect(find.textContaining('信息不足'), findsNothing);
  });

  testWidgets('AI 页面提供上传课表图片入口', (tester) async {
    _bigWindow(tester);
    await tester.pumpWidget(
      _wrap(
        timetable: _FakeTimetableController(_seed()),
        settings: _FakeSettingsController(_configuredSettings),
        client: AiClient(
          config: _textConfig,
          httpClient: _sequenceClient(['{}'], <http.Request>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai_edit_add_image')), findsOneWidget);
  });
}

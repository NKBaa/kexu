import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/ai_exception.dart';
import 'package:course_timetable/features/settings/widgets/ai_config_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假客户端：只实现配置页用到的 listModels。
class _FakeAiClient extends AiClient {
  _FakeAiClient({
    required super.config,
    this.models = const <String>[],
    this.error,
  });

  final List<String> models;
  final AiException? error;

  @override
  Future<List<String>> listModels() async {
    final e = error;
    if (e != null) throw e;
    return models;
  }
}

/// 窄屏（手机）下的 AI 配置表单布局回归测试。
///
/// 背景：预设名「自定义（任意 OpenAI 兼容服务）」很长，`DropdownButtonFormField`
/// 默认 `isExpanded: false` 会按最长条目撑宽，在 360dp 的手机上文字顶出输入框边框。
/// 修复方式是 `isExpanded: true` + 省略号；这里用窄屏渲染防止回归。
void main() {
  Future<void> pumpForm(
    WidgetTester tester, {
    required double width,
    AiConfig initial = const AiConfig(),
    AiClient Function(AiModelConfig config)? clientFactory,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: AiModelSectionForm(
              isVision: true,
              initial: initial.vision,
              onSave: (_) async {},
              clientFactory: clientFactory,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('360dp 窄屏下预设下拉不溢出', (tester) async {
    await pumpForm(tester, width: 360);

    // 布局溢出会以 FlutterError 形式被 tester 捕获。
    expect(tester.takeException(), isNull);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('服务商预设'), findsOneWidget);
  });

  testWidgets('选择 CottonAPI 预设后自动填入地址与模型', (tester) async {
    await pumpForm(tester, width: 360);

    // 打开视觉模型分区的预设下拉。
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CottonAPI（推荐）').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller?.text)
        .toList();
    expect(values, contains('https://api.cottonapi.cloud/v1'));
    expect(values, contains('gemini-3.8-flash'));
  });

  testWidgets('点「获取模型列表」后出现选择入口，选择后填入模型名', (tester) async {
    await pumpForm(
      tester,
      width: 360,
      initial: const AiConfig(
        vision: AiModelConfig(baseUrl: 'https://api.test/v1', model: ''),
      ),
      clientFactory: (cfg) => _FakeAiClient(
        config: cfg,
        models: const ['alpha', 'beta', 'gemini-3.8-flash'],
      ),
    );

    expect(find.text('选择模型（已获取 3 个）'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai_model_fetch_button')).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('选择模型（已获取 3 个）'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai_model_list_button')).first);
    await tester.pumpAndSettle();
    // 服务端返回的模型名命中名单时，列表中标注能力。
    expect(find.textContaining('CottonAPI · 图片 + 文本'), findsOneWidget);
    expect(find.textContaining('课表推荐'), findsNothing);
    await tester.tap(find.text('gemini-3.8-flash').last);
    await tester.pumpAndSettle();

    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller?.text)
        .toList();
    expect(values, contains('gemini-3.8-flash'));
  });

  testWidgets('已填地址与 Key 时打开页面自动获取模型列表', (tester) async {
    await pumpForm(
      tester,
      width: 360,
      initial: const AiConfig(
        vision: AiModelConfig(
          baseUrl: 'https://api.test/v1',
          apiKey: 'sk-test',
          model: '',
        ),
      ),
      clientFactory: (cfg) => _FakeAiClient(
        config: cfg,
        models: const ['m1', 'm2'],
      ),
    );

    // 无需点按钮，静默预取后直接出现选择入口。
    expect(find.text('选择模型（已获取 2 个）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('获取失败时展示中文错误提示', (tester) async {
    await pumpForm(
      tester,
      width: 360,
      initial: const AiConfig(
        vision: AiModelConfig(baseUrl: 'https://api.test/v1', model: ''),
      ),
      clientFactory: (cfg) => _FakeAiClient(
        config: cfg,
        error: AiException.badResponse('该服务不支持 /models 接口'),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ai_model_fetch_button')).first);
    await tester.pumpAndSettle();

    expect(find.text('该服务不支持 /models 接口'), findsWidgets);
  });
}

import 'dart:convert';

import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/ai_exception.dart';
import 'package:course_timetable/features/schedule/schedule_event_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AiClient _client(String content) => AiClient(
      config: const AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
      ),
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

void main() {
  test('AI 返回的 JSON 被解析成日程', () async {
    final events = await ScheduleEventAiService(
      client: _client(
        '{"events":[{"title":"交高数作业","date":"2026-11-05",'
        '"startTime":"15:00","endTime":"16:00","note":"教三 201"},'
        '{"title":"社团例会","date":"2026-11-06","startTime":null,'
        '"endTime":null,"note":""}]}',
      ),
    ).plan('下周三交高数作业，下周四社团例会', now: DateTime(2026, 11, 1));

    expect(events, hasLength(2));
    expect(events.first.title, '交高数作业');
    expect(events.first.dateKey, '2026-11-05');
    expect(events.first.startTime, '15:00');
    expect(events.last.allDay, isTrue);
  });

  test('多轮日程编辑会发送历史并返回修改后的完整方案', () async {
    late http.Request captured;
    final client = AiClient(
      config: const AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'm',
      ),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"events":[{"title":"交高数作业","date":"2026-11-05",'
                          '"startTime":"20:00","endTime":null,"note":""}]}',
                },
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final turn = await ScheduleEventAiService(client: client).planTurn(
      '把时间改成晚上八点',
      now: DateTime(2026, 11, 1),
      history: [
        AiChatMessage.user('明天下午三点交高数作业'),
        AiChatMessage.assistant(
          '{"events":[{"title":"交高数作业","date":"2026-11-02",'
          '"startTime":"15:00","endTime":null,"note":""}]}',
        ),
      ],
    );

    expect(turn.events.single.startTime, '20:00');
    final body =
        jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
    final messages = body['messages'] as List;
    expect(messages, hasLength(4));
    expect(
      messages.map((message) => (message as Map)['role']),
      ['system', 'user', 'assistant', 'user'],
    );
    expect((messages[1] as Map)['content'], '明天下午三点交高数作业');
    expect((messages[2] as Map)['content'], contains('交高数作业'));
    expect((messages[3] as Map)['content'], contains('保留历史中未被要求改动的事项'));
  });
  test('Markdown 代码块也能解析', () {
    final events = ScheduleEventAiService.parseEvents(
      '```json\n{"events":[{"title":"报名截止","date":"2026-11-05"}]}\n```',
    );
    expect(events.single.title, '报名截止');
  });

  test('无有效 events 时抛出可展示异常', () {
    expect(
      () => ScheduleEventAiService.parseEvents('{"events":[]}'),
      throwsA(isA<AiException>()),
    );
    expect(
      () => ScheduleEventAiService.parseEvents('not json'),
      throwsA(isA<AiException>()),
    );
  });
}

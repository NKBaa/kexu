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

import 'dart:convert';
import 'dart:typed_data';

import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/nl_edit.dart';
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
          sessions: [
            Session(
              id: 'ss1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: const [1, 2, 3],
            ),
          ],
        ),
      ],
    );

void main() {
  test('带图片的改课表请求把图片发给语言模型，并保留多轮历史', () async {
    http.Request? captured;
    final client = AiClient(
      config: const AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: 'vision-language-model',
      ),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"summary":"好的","ops":[]}'},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await NlEditService(client: client).planTurn(
      '按图片改课表',
      current: _seed(),
      history: const [AiChatMessage.user('上一轮问题')],
      images: [
        AiImageAttachment(
          bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 0x01]),
          mimeType: 'jpg',
          name: 'timetable.jpg',
        ),
      ],
    );

    expect(captured, isNotNull);
    final body = jsonDecode(utf8.decode(captured!.bodyBytes)) as Map;
    final messages = body['messages'] as List;
    expect(messages, hasLength(3));
    expect((messages[0] as Map)['role'], 'system');
    expect((messages[1] as Map)['content'], '上一轮问题');

    final last = messages[2] as Map;
    expect(last['role'], 'user');
    final content = last['content'] as List;
    expect((content[0] as Map)['type'], 'text');
    expect((content[0] as Map)['text'], contains('按图片改课表'));
    final image = content[1] as Map;
    expect(image['type'], 'image_url');
    expect((image['image_url'] as Map)['url'], startsWith('data:image/jpeg;base64,'));
  });

  test('纯文本改课表仍走普通 chatMessages', () async {
    http.Request? captured;
    final client = AiClient(
      config: const AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'text-model',
      ),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"summary":"好的","ops":[]}'},
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await NlEditService(client: client).planTurn(
      '把高数改成单周',
      current: _seed(),
    );

    final body = jsonDecode(utf8.decode(captured!.bodyBytes)) as Map;
    final messages = body['messages'] as List;
    expect(messages, hasLength(2));
    expect((messages[1] as Map)['content'], isA<String>());
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/ai_exception.dart';
import 'package:course_timetable/features/ai/ai_image_intent.dart';
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

AiImageAttachment _image() => AiImageAttachment(
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 0x01]),
      mimeType: 'jpg',
      name: 'timetable.jpg',
    );

http.Response _chat(String content) => http.Response(
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

void main() {
  test('有语言模型时图片直接发给语言模型', () async {
    http.Request? captured;
    final text = AiClient(
      config: const AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'multimodal-text',
      ),
      httpClient: MockClient((request) async {
        captured = request;
        return _chat('{"summary":"好的","ops":[]}');
      }),
    );
    final vision = AiClient(
      config: const AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'vision',
      ),
      httpClient: MockClient((_) async => _chat('不应调用识图模型')),
    );

    final result = await AiImageIntentService().plan(
      instruction: '按图片改课表',
      current: _seed(),
      images: [_image()],
      history: const [],
      textClient: text,
      visionClient: vision,
      textConfigured: true,
      visionConfigured: true,
    );

    final body = jsonDecode(utf8.decode(captured!.bodyBytes)) as Map;
    final content = (body['messages'] as List).last['content'] as List;
    expect(content.any((e) => e['type'] == 'image_url'), isTrue);
    expect(result.historyText, '按图片改课表');
  });

  test('没有语言模型时由识图模型转述，再用转述生成方案', () async {
    final requests = <http.Request>[];
    var index = 0;
    final vision = AiClient(
      config: const AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'vision-only',
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        index++;
        if (index == 1) {
          return _chat('高等数学，周一第 1-2 节，第 1-3 周');
        }
        return _chat('{"summary":"好的","ops":[]}');
      }),
    );
    final text = AiClient(
      config: const AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        model: 'unused',
      ),
      httpClient: MockClient((_) async => _chat('不应调用语言模型')),
    );

    final result = await AiImageIntentService().plan(
      instruction: '按图片改课表',
      current: _seed(),
      images: [_image()],
      history: const [],
      textClient: text,
      visionClient: vision,
      textConfigured: false,
      visionConfigured: true,
    );

    expect(requests, hasLength(2));
    final first = jsonDecode(utf8.decode(requests[0].bodyBytes)) as Map;
    expect(
      ((first['messages'] as List).last['content'] as List)
          .any((e) => e['type'] == 'image_url'),
      isTrue,
    );
    final second = jsonDecode(utf8.decode(requests[1].bodyBytes)) as Map;
    expect(utf8.decode(requests[1].bodyBytes), contains('高等数学，周一第 1-2 节'));
    expect(
      (second['messages'] as List).last['content'],
      contains('图片内容转述'),
    );
    expect(result.historyText, contains('图片内容转述'));
  });

  test('没有任何模型时给出可展示的错误', () async {
    final client = AiClient(
      config: const AiModelConfig(baseUrl: 'https://api.example.com/v1'),
      httpClient: MockClient((_) async => _chat('{}')),
    );
    await expectLater(
      AiImageIntentService().plan(
        instruction: '按图片改课表',
        current: _seed(),
        images: [_image()],
        history: const [],
        textClient: client,
        visionClient: client,
        textConfigured: false,
        visionConfigured: false,
      ),
      throwsA(isA<AiException>()),
    );
  });
}

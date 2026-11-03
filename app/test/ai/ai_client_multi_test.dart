import 'dart:convert';
import 'dart:typed_data';

import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/ai_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = AiModelConfig(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  model: 'test-model',
);

http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response okText(String text) => jsonResponse({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': text},
        },
      ],
    });

Map<String, dynamic> requestBody(http.Request request) =>
    jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;

Uint8List pngBytes() =>
    Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);

void main() {
  group('chatMessages 多轮对话', () {
    test('按顺序发送历史消息并保留 system', () async {
      late http.Request captured;
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          captured = request;
          return okText('{"ask":"你想改哪门课？"}');
        }),
      );

      final reply = await client.chatMessages(
        const [
          AiChatMessage.user('把明天的课改到后天'),
          AiChatMessage.assistant('{"ask":"你要改哪门课？","ops":[]}'),
          AiChatMessage.user('高数'),
        ],
        system: '你是课表助手',
      );

      expect(reply, '{"ask":"你想改哪门课？"}');
      final messages = requestBody(captured)['messages'] as List;
      expect(messages.length, 4);
      expect(messages[0]['role'], 'system');
      expect(messages[1]['role'], 'user');
      expect(messages[2]['role'], 'assistant');
      expect(messages[3]['role'], 'user');
      expect(messages[3]['content'], '高数');
    });

    test('跳过空白消息；全空时报 invalidInput 且不发请求', () async {
      var called = false;
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          called = true;
          return okText('ok');
        }),
      );

      await expectLater(
        client.chatMessages(const [AiChatMessage.user('   ')]),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.invalidInput)),
      );
      expect(called, isFalse);
    });
  });

  group('chatWithImages 多图请求', () {
    test('多张图片按顺序放进同一条 user 消息，且各自带正确 MIME', () async {
      late http.Request captured;
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          captured = request;
          return okText('{"courses":[]}');
        }),
      );

      final png = pngBytes();
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 4, 5, 6]);
      final text = await client.chatWithImages(
        images: [
          AiImageAttachment(bytes: png, mimeType: 'png'),
          AiImageAttachment(bytes: jpeg),
        ],
        prompt: '识别这两张课表',
        system: '系统提示',
      );

      expect(text, '{"courses":[]}');
      final messages = requestBody(captured)['messages'] as List;
      expect(messages.first['role'], 'system');
      final content = (messages.last as Map)['content'] as List;
      expect(content.length, 3);
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], '识别这两张课表');
      expect(content[1]['type'], 'image_url');
      expect(content[2]['type'], 'image_url');

      final firstUrl = (content[1]['image_url'] as Map)['url'] as String;
      final secondUrl = (content[2]['image_url'] as Map)['url'] as String;
      expect(firstUrl, startsWith('data:image/png;base64,'));
      expect(secondUrl, startsWith('data:image/jpeg;base64,'));
      expect(
        base64Decode(firstUrl.substring('data:image/png;base64,'.length)),
        png,
      );
    });

    test('没有图片时报 invalidInput', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => okText('x')),
      );
      await expectLater(
        client.chatWithImages(images: const [], prompt: 'x'),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.invalidInput)),
      );
    });

    test('其中一张为空图片时整体拒绝，不发请求', () async {
      var called = false;
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          called = true;
          return okText('x');
        }),
      );
      await expectLater(
        client.chatWithImages(
          images: [
            AiImageAttachment(bytes: pngBytes()),
            AiImageAttachment(bytes: Uint8List(0)),
          ],
          prompt: 'x',
        ),
        throwsA(isA<AiException>()
            .having((e) => e.kind, 'kind', AiErrorKind.invalidInput)),
      );
      expect(called, isFalse);
    });
  });
}

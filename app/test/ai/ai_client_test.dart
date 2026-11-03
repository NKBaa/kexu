import 'dart:convert';
import 'dart:typed_data';

import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/features/ai/ai_client.dart';
import 'package:course_timetable/features/ai/ai_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 构造一个 UTF-8 的 JSON 响应（避免中文在默认编码下乱码）。
http.Response jsonResponse(Object body, {int status = 200}) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

const _config = AiModelConfig(
  baseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  model: 'test-model',
  temperature: 0.2,
  timeoutSeconds: 30,
);

Matcher throwsAiException(AiErrorKind kind, {String? messageContains, int? statusCode}) {
  var matcher = isA<AiException>().having((e) => e.kind, 'kind', kind);
  if (messageContains != null) {
    matcher = matcher.having((e) => e.message, 'message', contains(messageContains));
  }
  if (statusCode != null) {
    matcher = matcher.having((e) => e.statusCode, 'statusCode', statusCode);
  }
  return throwsA(matcher);
}

void main() {
  group('resolveImageMimeType', () {
    test('按文件头识别 png / jpeg / gif / webp', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0]);
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]);
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      final webp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF.... 
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);
      expect(resolveImageMimeType(png), 'image/png');
      expect(resolveImageMimeType(jpeg), 'image/jpeg');
      expect(resolveImageMimeType(gif), 'image/gif');
      expect(resolveImageMimeType(webp), 'image/webp');
    });

    test('无法识别文件头时使用调用方提示，其次默认 jpeg', () {
      final unknown = Uint8List.fromList([1, 2, 3, 4]);
      expect(resolveImageMimeType(unknown, hint: 'image/png'), 'image/png');
      expect(resolveImageMimeType(unknown, hint: 'png'), 'image/png');
      expect(resolveImageMimeType(unknown, hint: 'image/PNG'), 'image/png');
      expect(resolveImageMimeType(unknown, hint: 'jpg'), 'image/jpeg');
      expect(resolveImageMimeType(unknown), 'image/jpeg');
      expect(resolveImageMimeType(unknown, hint: 'application/pdf'), 'image/jpeg');
    });

    test('文件头优先于错误的提示', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(resolveImageMimeType(png, hint: 'image/jpeg'), 'image/png');
    });
  });

  group('AiClient 请求构造', () {
    test('chatText 使用 POST + Bearer + 标准 body', () async {
      late http.Request captured;
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          captured = request;
          return jsonResponse({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '  你好，我是模型  '},
                'finish_reason': 'stop',
              },
            ],
          });
        }),
      );

      final text = await client.chatText('把高数改成单周', system: '你是课表助手');
      expect(text, '你好，我是模型');

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://api.example.com/v1/chat/completions');
      expect(captured.headers['Authorization'], 'Bearer sk-test');
      expect(captured.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['model'], 'test-model');
      expect(body['temperature'], 0.2);
      final messages = body['messages'] as List;
      expect(messages.length, 2);
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], '你是课表助手');
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], '把高数改成单周');
    });

    test('baseUrl 已含 /chat/completions 时不会重复拼接', () async {
      late Uri captured;
      final client = AiClient(
        config: _config.copyWith(baseUrl: 'https://api.example.com/v1/chat/completions/'),
        httpClient: MockClient((request) async {
          captured = request.url;
          return jsonResponse({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          });
        }),
      );
      await client.chatText('hi');
      expect(captured.toString(), 'https://api.example.com/v1/chat/completions');
    });

    test('没有 API Key 时不发送 Authorization 头（本地模型）', () async {
      late http.Request captured;
      final client = AiClient(
        config: _config.copyWith(apiKey: '', baseUrl: 'http://127.0.0.1:11434/v1'),
        httpClient: MockClient((request) async {
          captured = request;
          return jsonResponse({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          });
        }),
      );
      await client.chatText('hi');
      expect(captured.headers.containsKey('Authorization'), isFalse);
      expect(captured.url.toString(), 'http://127.0.0.1:11434/v1/chat/completions');
    });

    test('空图片字节立刻报 invalidInput，不发请求', () async {
      var called = false;
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          called = true;
          return jsonResponse({});
        }),
      );
      await expectLater(
        client.chatWithImages(
          images: [AiImageAttachment(bytes: Uint8List(0))],
          prompt: 'x',
        ),
        throwsAiException(AiErrorKind.invalidInput, messageContains: '图片'),
      );
      expect(called, isFalse);
    });
  });

  group('AiClient 响应解析', () {
    test('content 为分段数组时拼接文本', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => jsonResponse({
              'choices': [
                {
                  'message': {
                    'content': [
                      {'type': 'text', 'text': '第一段'},
                      {'type': 'text', 'text': '第二段'},
                    ],
                  },
                },
              ],
            })),
      );
      expect(await client.chatText('hi'), '第一段\n第二段');
    });

    test('空 choices 报 badResponse', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => jsonResponse({'choices': []})),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.badResponse, messageContains: 'choices'),
      );
    });

    test('HTTP 200 + error 字段也当失败处理', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => jsonResponse({
              'error': {'message': '额度不足', 'code': 'insufficient_quota'},
            })),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.badResponse, messageContains: '额度不足'),
      );
    });

    test('响应不是 JSON 报 badResponse 并带片段', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient(
          (request) async => http.Response('<html>gateway error</html>', 200),
        ),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.badResponse, messageContains: '不是 JSON'),
      );
    });

    test('finish_reason=length 且内容为空时报截断', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => jsonResponse({
              'choices': [
                {
                  'message': {'content': ''},
                  'finish_reason': 'length',
                },
              ],
            })),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.badResponse, messageContains: '截断'),
      );
    });

    test('finish_reason=content_filter 报安全策略', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => jsonResponse({
              'choices': [
                {
                  'message': {'content': null},
                  'finish_reason': 'content_filter',
                },
              ],
            })),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.badResponse, messageContains: '安全'),
      );
    });
  });

  group('AiClient 错误映射', () {
    test('HTTP 401 带状态码、Key 提示与响应片段', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient(
          (request) async => jsonResponse(
            {
              'error': {'message': 'invalid api key'},
            },
            status: 401,
          ),
        ),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(
          AiErrorKind.http,
          messageContains: 'API Key',
          statusCode: 401,
        ),
      );
    });

    test('HTTP 404 提示检查 baseUrl', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => http.Response('not found', 404)),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.http, messageContains: 'baseUrl', statusCode: 404),
      );
    });

    test('HTTP 429 提示限流', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => http.Response('rate limited', 429)),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.http, messageContains: '频繁', statusCode: 429),
      );
    });

    test('网络异常映射为 network', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          throw http.ClientException('Failed host lookup');
        }),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.network, messageContains: '网络'),
      );
    });

    test('超时映射为 timeout', () async {
      final client = AiClient(
        config: _config.copyWith(timeoutSeconds: 1),
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          return jsonResponse({
            'choices': [
              {
                'message': {'content': 'late'},
              },
            ],
          });
        }),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.timeout, messageContains: '超时'),
      );
    });

    test('未配置时直接报 notConfigured，不发请求', () async {
      var called = false;
      final client = AiClient(
        config: const AiModelConfig(),
        httpClient: MockClient((request) async {
          called = true;
          return jsonResponse({});
        }),
      );
      await expectLater(
        client.chatText('hi'),
        throwsAiException(AiErrorKind.notConfigured),
      );
      expect(called, isFalse);
    });

    test('temperature 异常值会被夹到合法区间', () async {
      late http.Request captured;
      final client = AiClient(
        config: _config.copyWith(temperature: 9.5),
        httpClient: MockClient((request) async {
          captured = request;
          return jsonResponse({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          });
        }),
      );
      await client.chatText('hi');
      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['temperature'], 2.0);
    });
  });

  group('AiClient 生命周期', () {
    test('config 可在设置变更后替换', () async {
      late http.Request captured;
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          captured = request;
          return jsonResponse({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          });
        }),
      );
      client.config = _config.copyWith(model: 'glm-4v-flash', apiKey: 'new-key');
      await client.chatText('hi');
      expect(captured.headers['Authorization'], 'Bearer new-key');
      final body = jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, dynamic>;
      expect(body['model'], 'glm-4v-flash');
    });

    test('dispose 后再调用抛 StateError，重复 dispose 安全', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient(
          (request) async => jsonResponse({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
        ),
      );
      client.dispose();
      client.dispose();
      await expectLater(client.chatText('hi'), throwsStateError);
    });
  });

  group('AiClient 模型列表', () {
    test('GET {baseUrl}/models，带 Bearer，返回去重排序后的 id', () async {
      late http.Request seen;
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async {
          seen = request;
          return jsonResponse({
            'data': [
              {'id': 'qwen-vl-max'},
              {'id': 'deepseek-chat'},
              {'id': 'qwen-vl-max'},
            ],
          });
        }),
      );
      final models = await client.listModels();
      expect(seen.method, 'GET');
      expect(seen.url.toString(), 'https://api.example.com/v1/models');
      expect(seen.headers['Authorization'], 'Bearer sk-test');
      expect(models, ['deepseek-chat', 'qwen-vl-max']);
    });

    test('兼容 models / result / 字符串数组，且无 Key 时不发 Authorization', () async {
      Future<List<String>> run(Object body) {
        final client = AiClient(
          config: const AiModelConfig(baseUrl: 'https://local/v1', model: 'm'),
          httpClient: MockClient((request) async {
            expect(request.headers.containsKey('Authorization'), isFalse);
            return jsonResponse(body);
          }),
        );
        return client.listModels();
      }

      expect(await run({'models': [{'name': 'b'}, {'name': 'a'}]}), ['a', 'b']);
      expect(await run({'result': ['m2', 'm1']}), ['m1', 'm2']);
      expect(await run(['z', 'a']), ['a', 'z']);
    });

    test('HTTP 错误映射为 http，空列表映射为 badResponse', () async {
      final bad = AiClient(
        config: _config,
        httpClient: MockClient((request) async => http.Response('nope', 401)),
      );
      await expectLater(
        bad.listModels(),
        throwsAiException(AiErrorKind.http, statusCode: 401),
      );

      final empty = AiClient(
        config: _config,
        httpClient: MockClient((request) async => jsonResponse({'data': []})),
      );
      await expectLater(
        empty.listModels(),
        throwsAiException(AiErrorKind.badResponse),
      );
    });

    test('网络异常映射为 network', () async {
      final client = AiClient(
        config: _config,
        httpClient: MockClient((request) async => throw http.ClientException('boom')),
      );
      await expectLater(
        client.listModels(),
        throwsAiException(AiErrorKind.network),
      );
    });
  });

  group('AiException', () {
    test('toString 带类型、消息与状态码', () {
      final e = AiException.http(statusCode: 401, bodySnippet: 'bad key');
      expect(e.toString(), contains('http'));
      expect(e.toString(), contains('401'));
      expect(e.toString(), contains('bad key'));
    });

    test('parse 异常截断超长原始输出', () {
      final longText = 'x' * 2000;
      final e = AiException.parse('解析失败', rawOutput: longText);
      expect(e.bodySnippet!.length, lessThanOrEqualTo(601));
      expect(e.bodySnippet, endsWith('…'));
    });

    test('truncateBody 压缩空白并截断', () {
      expect(AiException.truncateBody('  a\n\n b  '), 'a b');
      expect(AiException.truncateBody('a' * 100, maxLength: 10), '${'a' * 10}…');
    });
  });
}


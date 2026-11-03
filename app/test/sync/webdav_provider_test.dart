import 'dart:convert';
import 'dart:io';

import 'package:course_timetable/data/sync/sync_config.dart';
import 'package:course_timetable/data/sync/sync_provider.dart';
import 'package:course_timetable/data/sync/webdav_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const WebDavConfig _config = WebDavConfig(
  url: 'https://dav.example.com/dav/',
  username: 'alice',
  password: 'secret-pass',
  remotePath: '/course_timetable/timetable.json',
);

const String _fileUrl =
    'https://dav.example.com/dav/course_timetable/timetable.json';
const String _dirUrl = 'https://dav.example.com/dav/course_timetable/';

/// 构造 PROPFIND 的多状态响应；[prefixed] 控制是否带 `D:` 命名空间前缀。
String _propfindXml({
  bool prefixed = true,
  String href = '/dav/course_timetable/timetable.json',
  String? lastModified = 'Sun, 18 Oct 2026 08:30:00 GMT',
  String? etag = '"abc123"',
}) {
  final tag = prefixed ? 'D:' : '';
  final ns = prefixed ? ' xmlns:D="DAV:"' : ' xmlns="DAV:"';
  final props = <String>[
    if (lastModified != null)
      '<${tag}getlastmodified>$lastModified</${tag}getlastmodified>',
    if (etag != null) '<${tag}getetag>$etag</${tag}getetag>',
    '<${tag}resourcetype/>',
  ].join();
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<${tag}multistatus$ns>'
      '<${tag}response>'
      '<${tag}href>$href</${tag}href>'
      '<${tag}propstat><${tag}prop>$props</${tag}prop>'
      '<${tag}status>HTTP/1.1 200 OK</${tag}status></${tag}propstat>'
      '</${tag}response>'
      '</${tag}multistatus>';
}

WebDavProvider _provider(
  Future<http.Response> Function(http.Request request) handler, {
  WebDavConfig config = _config,
}) => WebDavProvider(config: config, httpClient: MockClient(handler));

String _bodyOf(http.Request request) => utf8.decode(request.bodyBytes);

void main() {
  test('displayName 为 WebDAV', () {
    final provider = _provider((_) async => http.Response('', 200));
    expect(provider.displayName, 'WebDAV');
  });

  group('download', () {
    for (final prefixed in <bool>[true, false]) {
      test('文件存在时返回内容与元数据（${prefixed ? '带' : '不带'}命名空间前缀）', () async {
        final seen = <http.Request>[];
        const content = '{"name":"高等数学","teacher":"张老师"}';
        final provider = _provider((request) async {
          seen.add(request);
          if (request.method == 'PROPFIND') {
            expect(request.headers['depth'], '1');
            expect(_bodyOf(request), contains('getlastmodified'));
            expect(_bodyOf(request), contains('getetag'));
            expect(_bodyOf(request), contains('resourcetype'));
            return http.Response(
              _propfindXml(prefixed: prefixed),
              207,
              headers: <String, String>{
                'content-type': 'application/xml; charset=utf-8',
              },
            );
          }
          if (request.method == 'GET') {
            return http.Response.bytes(
              utf8.encode(content),
              200,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response('', 405);
        });

        final doc = await provider.download();

        expect(doc, isNotNull);
        expect(doc!.content, content);
        expect(doc.versionTag, '"abc123"');
        expect(doc.modifiedAt, DateTime.utc(2026, 10, 18, 8, 30));
        expect(seen.map((r) => r.method), <String>['PROPFIND', 'GET']);
        expect(seen.first.url.toString(), _fileUrl);
        expect(seen.last.url.toString(), _fileUrl);
      });
    }

    test('PROPFIND 404 时返回 null 且不发起 GET', () async {
      final seen = <http.Request>[];
      final provider = _provider((request) async {
        seen.add(request);
        return http.Response('not found', 404);
      });

      final doc = await provider.download();

      expect(doc, isNull);
      expect(seen.map((r) => r.method), <String>['PROPFIND']);
    });

    test('PROPFIND 409 时也视为不存在', () async {
      final provider = _provider((_) async => http.Response('', 409));
      expect(await provider.download(), isNull);
    });

    test('PROPFIND 成功但响应里没有该文件时返回 null', () async {
      final seen = <http.Request>[];
      final provider = _provider((request) async {
        seen.add(request);
        return http.Response(
          '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:"></D:multistatus>',
          207,
        );
      });

      expect(await provider.download(), isNull);
      expect(seen.map((r) => r.method), <String>['PROPFIND']);
    });

    test('GET 返回 401 时抛凭据错误', () async {
      final provider = _provider((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(_propfindXml(), 207);
        }
        return http.Response('', 401);
      });

      await expectLater(
        provider.download(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('密码'),
          ),
        ),
      );
    });

    test('GET 返回 5xx 时抛服务器错误', () async {
      final provider = _provider((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(_propfindXml(), 207);
        }
        return http.Response('', 503);
      });

      await expectLater(
        provider.download(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('服务器错误'),
          ),
        ),
      );
    });

    test('响应含中文时按 UTF-8 解码不乱码', () async {
      const content = '{"name":"大学英语（二）","note":"第 3 周停课"}';
      final provider = _provider((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(_propfindXml(), 207);
        }
        return http.Response.bytes(utf8.encode(content), 200);
      });

      final doc = await provider.download();
      expect(doc!.content, content);
    });
  });

  group('upload', () {
    test('PUT 成功，请求头与正文正确', () async {
      final seen = <http.Request>[];
      final provider = _provider((request) async {
        seen.add(request);
        if (request.method == 'MKCOL') return http.Response('', 405);
        return http.Response('', 201);
      });

      const content = '{"courses":[]}';
      await provider.upload(content);

      expect(seen.map((r) => r.method), <String>['MKCOL', 'PUT']);
      expect(seen.first.url.toString(), _dirUrl);
      final put = seen.last;
      expect(put.url.toString(), _fileUrl);
      expect(put.headers['content-type'], 'application/json; charset=utf-8');
      expect(_bodyOf(put), content);
      expect(put.headers['authorization'], startsWith('Basic '));
    });

    test('父目录不存在时逐级 MKCOL（405 视为已存在）', () async {
      final seen = <http.Request>[];
      final provider = _provider(
        (request) async {
          seen.add(request);
          if (request.method == 'MKCOL') {
            // 第一级已存在，第二级新建成功。
            return http.Response('', seen.length == 1 ? 405 : 201);
          }
          return http.Response('', 201);
        },
        config: const WebDavConfig(
          url: 'https://dav.example.com/dav/',
          username: 'alice',
          password: 'secret-pass',
          remotePath: '/a/b/timetable.json',
        ),
      );

      await provider.upload('{}');

      expect(seen.map((r) => r.method), <String>['MKCOL', 'MKCOL', 'PUT']);
      expect(seen.map((r) => r.url.toString()).toList(), <String>[
        'https://dav.example.com/dav/a/',
        'https://dav.example.com/dav/a/b/',
        'https://dav.example.com/dav/a/b/timetable.json',
      ]);
    });

    test('PUT 返回 401 时抛凭据错误', () async {
      final provider = _provider((request) async {
        if (request.method == 'MKCOL') return http.Response('', 201);
        return http.Response('', 401);
      });

      await expectLater(
        provider.upload('{}'),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('密码'),
          ),
        ),
      );
    });

    test('PUT 返回 507 时提示空间不足', () async {
      final provider = _provider((request) async {
        if (request.method == 'MKCOL') return http.Response('', 201);
        return http.Response('', 507);
      });

      await expectLater(
        provider.upload('{}'),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('空间不足'),
          ),
        ),
      );
    });
  });

  group('testConnection', () {
    test('200 正常返回，探测的是父目录', () async {
      final seen = <http.Request>[];
      final provider = _provider((request) async {
        seen.add(request);
        return http.Response('', 200);
      });

      await provider.testConnection();

      expect(seen, hasLength(1));
      expect(seen.single.method, 'PROPFIND');
      expect(seen.single.url.toString(), _dirUrl);
      expect(seen.single.headers['depth'], '0');
    });

    test('207 也视为连通', () async {
      final provider = _provider(
        (_) async => http.Response(
          '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:"></D:multistatus>',
          207,
        ),
      );

      await expectLater(provider.testConnection(), completes);
    });

    test('401 抛 SyncException 且提示应用密码', () async {
      final provider = _provider(
        (_) async => http.Response('unauthorized', 401),
      );

      await expectLater(
        provider.testConnection(),
        throwsA(
          isA<SyncException>()
              .having((e) => e.message, 'message', contains('密码'))
              .having((e) => e.message, 'message', contains('应用密码'))
              .having((e) => e.detail, 'detail', contains('401')),
        ),
      );
    });

    test('404 提示远端路径不存在', () async {
      final provider = _provider((_) async => http.Response('', 404));

      await expectLater(
        provider.testConnection(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('路径不存在'),
          ),
        ),
      );
    });

    test('5xx 提示服务器错误', () async {
      final provider = _provider((_) async => http.Response('', 502));

      await expectLater(
        provider.testConnection(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('服务器错误'),
          ),
        ),
      );
    });
  });

  group('认证', () {
    test('Basic 认证头为 base64(username:password)', () async {
      String? authHeader;
      final provider = _provider(
        (request) async {
          authHeader = request.headers['authorization'];
          return http.Response('', 404);
        },
        config: const WebDavConfig(
          url: 'https://dav.example.com/dav/',
          username: 'user',
          password: 'pass',
          remotePath: '/course_timetable/timetable.json',
        ),
      );

      await provider.download();

      // base64('user:pass') === 'dXNlcjpwYXNz'
      expect(authHeader, 'Basic dXNlcjpwYXNz');
      expect(authHeader, 'Basic ${base64Encode(utf8.encode('user:pass'))}');
    });

    test('用户名与密码都为空时不带认证头', () async {
      String? authHeader = 'sentinel';
      final provider = _provider(
        (request) async {
          authHeader = request.headers['authorization'];
          return http.Response('', 404);
        },
        config: const WebDavConfig(
          url: 'https://dav.example.com/dav/',
          remotePath: '/course_timetable/timetable.json',
        ),
      );

      await provider.download();

      expect(authHeader, isNull);
    });
  });

  group('中文内容往返', () {
    test('upload 后 download 内容一致且不乱码', () async {
      const content = '{"name":"高等数学","teacher":"李老师","note":"单周上课"}';
      final store = <String, List<int>>{};
      final provider = _provider((request) async {
        switch (request.method) {
          case 'PROPFIND':
            return http.Response(_propfindXml(etag: '"v2"'), 207);
          case 'MKCOL':
            return http.Response('', 405);
          case 'PUT':
            store[request.url.toString()] = request.bodyBytes;
            return http.Response('', 201);
          case 'GET':
            final bytes = store[request.url.toString()];
            if (bytes == null) return http.Response('', 404);
            return http.Response.bytes(bytes, 200);
        }
        return http.Response('', 405);
      });

      await provider.upload(content);
      expect(utf8.decode(store[_fileUrl]!), content);

      final doc = await provider.download();
      expect(doc!.content, content);
      expect(doc.versionTag, '"v2"');
    });
  });

  group('配置与网络错误', () {
    test('服务器地址为空时抛 SyncException', () async {
      final provider = _provider(
        (_) async => http.Response('', 200),
        config: const WebDavConfig(remotePath: '/timetable.json'),
      );

      await expectLater(
        provider.download(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('服务器地址'),
          ),
        ),
      );
    });

    test('SocketException 映射为网络连接失败', () async {
      final provider = _provider((_) async {
        throw SocketException('connection refused');
      });

      await expectLater(
        provider.testConnection(),
        throwsA(
          isA<SyncException>().having(
            (e) => e.message,
            'message',
            contains('网络连接失败'),
          ),
        ),
      );
    });

    test('dispose 后不可再用', () async {
      final provider = _provider((_) async => http.Response('', 200));
      provider.dispose();

      await expectLater(
        provider.testConnection(),
        throwsA(isA<SyncException>()),
      );
    });
  });

  test('RemoteDocument 类型可用（接口约定）', () {
    const doc = RemoteDocument(content: '{}');
    expect(doc.content, '{}');
    expect(doc.modifiedAt, isNull);
    expect(doc.versionTag, isNull);
  });
}

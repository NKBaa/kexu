import 'dart:io';

import 'package:course_timetable/data/local/document_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟「应用支持目录不可写」的存储，用于验证降级链。
///
/// 真实场景包括：企业策略锁定的 Roaming 目录、只读配置文件系统、
/// 杀软拦截写入等 —— 这些情况下 App 不应崩溃，而应退化到可用目录。
///
/// 注意：这里**不能**传 `baseDirectory`，否则会走测试注入的短路分支，
/// 就验证不到候选链了。
class _FailingFirstStore extends DocumentStore {
  _FailingFirstStore(super.fileName, {required this.fallbackDir});

  /// 第二个候选（模拟「文档目录」）返回的真实可写目录。
  final Directory fallbackDir;

  final List<String> attempted = <String>[];

  @override
  List<Future<Directory> Function()> defaultDirectoryCandidates() {
    return <Future<Directory> Function()>[
      () async {
        attempted.add('应用支持目录');
        throw const FileSystemException('Creation failed', r'C:\fake\AppData');
      },
      () async {
        attempted.add('文档目录');
        return fallbackDir;
      },
      () async {
        attempted.add('系统临时目录');
        return Directory.systemTemp;
      },
    ];
  }
}

/// 所有候选都失败。
class _AllFailingStore extends DocumentStore {
  _AllFailingStore(super.fileName);

  @override
  List<Future<Directory> Function()> defaultDirectoryCandidates() {
    return <Future<Directory> Function()>[
      () async => throw const FileSystemException('denied', 'a'),
      () async => throw const FileSystemException('denied', 'b'),
      () async => throw const FileSystemException('denied', 'c'),
    ];
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('store_fallback_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('数据目录降级链', () {
    test('首选目录失败时自动降级到下一个候选', () async {
      final store = _FailingFirstStore('t.json', fallbackDir: root);

      final dir = await store.directory();

      expect(store.attempted, ['应用支持目录', '文档目录']);
      expect(dir.path, contains('course_timetable'));
    });

    test('降级后读写依然可用', () async {
      final store = _FailingFirstStore('t.json', fallbackDir: root);

      await store.writeJson({'ok': true});
      final back = await store.readJson();

      expect(back, isNotNull);
      expect(back!['ok'], isTrue);
    });

    test('所有候选都失败时抛出 DocumentStoreException（而不是裸异常）', () async {
      final store = _AllFailingStore('t.json');

      expect(
        () => store.directory(),
        throwsA(isA<DocumentStoreException>()),
      );
    });

    test('absolutePath 在目录不可用时也不抛异常', () async {
      final store = _AllFailingStore('t.json');

      // 这是设置页会调用的方法，绝不能因为目录问题让页面崩掉
      final path = await store.absolutePath();

      expect(path, contains('不可用'));
    });
  });
}

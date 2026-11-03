import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 数据目录无法创建时抛出的异常。
class DocumentStoreException implements Exception {
  final String message;
  const DocumentStoreException(this.message);

  @override
  String toString() => message;
}

/// 本地 JSON 文档存储。
///
/// 课表数据量很小（几十门课、几十 KB），因此**不使用数据库**，
/// 而是把整份课表作为一个 JSON 文档原子写入磁盘。好处：
/// - Android / Windows 行为完全一致，无需 sqflite 的平台分支；
/// - 批量增删改、AI 批量操作、导入导出都退化成简单的列表操作，不易出 bug；
/// - 天然支持「整份快照备份 / 回滚」。
///
/// 写入采用「临时文件 + 替换」策略，避免写到一半断电导致文件损坏。
///
/// 目录选择带**降级链**：应用支持目录 → 文档目录 → 系统临时目录。
/// 在受限环境（企业策略、只读配置、杀软拦截）下前者可能不可写，
/// 此时宁可退化到临时目录继续可用，也不要让整个 App 崩掉。
class DocumentStore {
  DocumentStore(this.fileName, {this.backupKeep = 10, this.baseDirectory});

  /// 文件名，如 `timetable.json`。
  final String fileName;

  /// 保留的历史备份份数。
  final int backupKeep;

  /// 可选的根目录覆盖（测试注入用；为 null 时走系统目录降级链）。
  final Directory? baseDirectory;

  Directory? _dir;
  File? _file;

  /// 覆盖数据目录的环境变量名。
  ///
  /// 设置后（例如 `COURSE_TIMETABLE_DATA_DIR=D:\课表数据`）数据文件会放在该目录下，
  /// 用途：
  /// - **便携模式**：把数据放在 U 盘或程序目录旁，换机即用；
  /// - 受限环境：系统配置目录不可写时，手动指定一个可写位置；
  /// - 自动化测试：让程序在受控目录下运行。
  static const String dataDirEnvVar = 'COURSE_TIMETABLE_DATA_DIR';

  /// 数据目录（App 私有支持目录，卸载即清除）。
  Future<Directory> directory() async {
    if (_dir != null) return _dir!;

    // 测试注入：直接用指定根目录，不依赖 path_provider。
    final injected = baseDirectory;
    if (injected != null) {
      final dir = Directory('${injected.path}${Platform.pathSeparator}course_timetable');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _dir = dir;
      return dir;
    }

    // 环境变量覆盖：优先于系统默认目录。
    final override = Platform.environment[dataDirEnvVar]?.trim();
    if (override != null && override.isNotEmpty) {
      final dir = Directory(override);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _dir = dir;
      return dir;
    }

    Object? lastError;
    final attempts = defaultDirectoryCandidates();

    for (var i = 0; i < attempts.length; i++) {
      final label = directoryCandidateLabels[i < directoryCandidateLabels.length ? i : 0];
      final getBase = attempts[i];
      try {
        final base = await getBase();
        final dir = Directory('${base.path}${Platform.pathSeparator}course_timetable');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        _dir = dir;
        return dir;
      } catch (e) {
        lastError = e;
        debugPrint('数据目录候选「$label」不可用：$e');
      }
    }

    throw DocumentStoreException(
      '无法创建数据目录（已尝试应用支持目录、文档目录与临时目录）。'
      '请检查磁盘空间与目录权限。原始错误：$lastError',
    );
  }

  /// 数据目录的候选列表，按优先级排列。
  ///
  /// 抽成方法是为了让测试可以覆写它来验证降级链，
  /// 而不必去 mock path_provider 的平台通道。
  @visibleForTesting
  List<Future<Directory> Function()> defaultDirectoryCandidates() =>
      <Future<Directory> Function()>[
        getApplicationSupportDirectory,
        getApplicationDocumentsDirectory,
        () async => Directory.systemTemp,
      ];

  /// 与 [defaultDirectoryCandidates] 一一对应的可读名称（用于日志）。
  @visibleForTesting
  List<String> get directoryCandidateLabels =>
      const ['应用支持目录', '文档目录', '系统临时目录'];

  Future<File> file() async {
    if (_file != null) return _file!;
    final dir = await directory();
    _file = File('${dir.path}${Platform.pathSeparator}$fileName');
    return _file!;
  }

  /// 数据文件的绝对路径（用于在设置页展示给用户）。
  ///
  /// 这个方法是**不会抛异常**的：路径展示属于辅助信息，
  /// 不该因为目录不可用就让设置页崩掉。
  Future<String> absolutePath() async {
    try {
      return (await file()).path;
    } catch (e) {
      return '（不可用：$e）';
    }
  }

  /// 读取 JSON；文件不存在或内容损坏时返回 null。
  Future<Map<String, dynamic>?> readJson() async {
    try {
      final f = await file();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } on FormatException {
      // 内容损坏：尝试从最近的备份恢复
      return _recoverFromBackup();
    } catch (_) {
      return null;
    }
  }

  /// 原子写入 JSON。
  Future<void> writeJson(Map<String, dynamic> data) async {
    final f = await file();
    final text = const JsonEncoder.withIndent('  ').convert(data);

    // 先备份现有文件
    if (await f.exists()) {
      await _backup(f);
    }

    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text, flush: true);

    try {
      if (await f.exists()) {
        await f.delete();
      }
      await tmp.rename(f.path);
    } catch (_) {
      // 极端情况下 rename 失败，退回直接写入
      await f.writeAsString(text, flush: true);
      if (await tmp.exists()) {
        await tmp.delete();
      }
    }
  }

  /// 删除数据文件（清空课表用）。
  Future<void> delete() async {
    final f = await file();
    if (await f.exists()) await f.delete();
  }

  // ------------------------------------------------------------------ 备份
  Future<Directory> _backupDir() async {
    final dir = await directory();
    final b = Directory('${dir.path}${Platform.pathSeparator}backups');
    if (!await b.exists()) await b.create(recursive: true);
    return b;
  }

  Future<void> _backup(File source) async {
    try {
      final b = await _backupDir();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final name = fileName.replaceAll('.json', '');
      await source.copy('${b.path}${Platform.pathSeparator}${name}_$stamp.json');
      await _pruneBackups(b, name);
    } catch (_) {
      // 备份失败不应阻断主流程
    }
  }

  Future<void> _pruneBackups(Directory b, String prefix) async {
    final files = await b
        .list()
        .where((e) => e is File && e.path.contains(prefix))
        .cast<File>()
        .toList();
    if (files.length <= backupKeep) return;
    files.sort((a, c) => a.path.compareTo(c.path));
    for (final f in files.take(files.length - backupKeep)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// 列出可用备份（新到旧）。
  Future<List<File>> listBackups() async {
    try {
      final b = await _backupDir();
      final name = fileName.replaceAll('.json', '');
      final files = await b
          .list()
          .where((e) => e is File && e.path.contains(name))
          .cast<File>()
          .toList();
      files.sort((a, c) => c.path.compareTo(a.path));
      return files;
    } catch (_) {
      return const [];
    }
  }

  /// 读取最新的可解析备份；没有备份时返回 null。
  ///
  /// 用于主设置文件异常（损坏/被重置为默认）时恢复关键配置。
  Future<Map<String, dynamic>?> readLatestBackupJson() => _recoverFromBackup();

  Future<Map<String, dynamic>?> _recoverFromBackup() async {
    final backups = await listBackups();
    for (final f in backups) {
      try {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}

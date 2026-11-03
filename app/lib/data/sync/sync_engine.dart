import 'dart:convert';

import '../models/bell_schedule.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../models/timetable.dart';

/// 计算一个稳定的内容哈希（FNV-1a 32 位）。
///
/// 用途：判断「某门课相对上次同步有没有被改过」。
/// 之所以不依赖时间戳，是因为**多设备的时钟不可信** ——
/// 手机和电脑的时间可能差几分钟甚至更多，用它做冲突判定会得出错误结论。
/// 内容哈希不需要时钟，只看内容是否真的变了。
///
/// 用 32 位而不是 64 位：Dart 的 `int` 是 64 位**有符号**，
/// 64 位乘法会溢出成负数，`toRadixString(16)` 就会输出 `-xxxx` 这种带负号的串。
/// 32 位配合 `& 0xFFFFFFFF` 掩码可以保证结果始终是 8 位小写十六进制。
/// 课表规模下碰撞概率可忽略；真需要更强校验时再换 crypto。
String contentHash(Object? value) {
  final text = value is String ? value : jsonEncode(value);
  const int offset = 0x811c9dc5;
  const int prime = 0x01000193;
  const int mask = 0xFFFFFFFF;
  var hash = offset;
  final bytes = utf8.encode(text);
  for (final b in bytes) {
    hash ^= b;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// 一条冲突记录（用户需要知道「哪门课两端都改了」）。
class SyncConflict {
  /// 课程名（可能为空，例如学期设置冲突）。
  final String subject;

  /// 人类可读说明。
  final String description;

  /// 最终采用了哪一端：`local` 或 `remote`。
  final String resolvedBy;

  const SyncConflict({
    required this.subject,
    required this.description,
    required this.resolvedBy,
  });

  @override
  String toString() => '$subject：$description（采用${resolvedBy == 'local' ? '本机' : '远端'}版本）';
}

/// 合并结果。
class MergeResult {
  /// 合并后的课表。
  final Timetable merged;

  /// 合并结果是否与本地不同（需要写回本地）。
  final bool differsFromLocal;

  /// 合并结果是否与远端不同（需要上传）。
  final bool differsFromRemote;

  /// 发生的冲突列表。
  final List<SyncConflict> conflicts;

  /// 统计：本地新增 / 远端新增 / 本地删除 / 远端删除 / 采用远端。
  final int localAdded;
  final int remoteAdded;
  final int localDeleted;
  final int remoteDeleted;
  final int tookRemote;

  const MergeResult({
    required this.merged,
    required this.differsFromLocal,
    required this.differsFromRemote,
    this.conflicts = const [],
    this.localAdded = 0,
    this.remoteAdded = 0,
    this.localDeleted = 0,
    this.remoteDeleted = 0,
    this.tookRemote = 0,
  });

  bool get hasConflicts => conflicts.isNotEmpty;

  String get summary {
    final parts = <String>[];
    if (localAdded > 0) parts.add('本机新增 $localAdded');
    if (remoteAdded > 0) parts.add('远端新增 $remoteAdded');
    if (tookRemote > 0) parts.add('采用远端 $tookRemote');
    if (localDeleted > 0) parts.add('本机删除 $localDeleted');
    if (remoteDeleted > 0) parts.add('远端删除 $remoteDeleted');
    if (conflicts.isNotEmpty) parts.add('冲突 ${conflicts.length}');
    if (parts.isEmpty) return '两端一致，无需改动';
    return parts.join('，');
  }
}

/// 三方合并引擎。
///
/// 输入「本地 / 远端 / 上次同步的基线」三份课表，输出合并结果。
/// 这是纯函数，不碰网络也不碰磁盘，因此可以完整单测 ——
/// 而同步功能最容易出 bug 的恰恰就是这里。
///
/// 合并粒度是**课程**（不是整个文件），所以「电脑上加了 A 课、
/// 手机上删了 B 课」这种并行修改不会互相覆盖。
class SyncEngine {
  const SyncEngine();

  /// 合并课表。
  ///
  /// [base] 为 null 表示首次同步（没有基线），此时按「远端优先补齐、
  /// 本地优先保留」的保守策略处理。
  MergeResult merge({
    required Timetable local,
    required Timetable remote,
    Timetable? base,
  }) {
    final conflicts = <SyncConflict>[];

    final localById = {for (final c in local.courses) c.id: c};
    final remoteById = {for (final c in remote.courses) c.id: c};
    final baseById = {for (final c in base?.courses ?? const <Course>[]) c.id: c};

    // 基线哈希：用于判断某门课相对上次同步是否被改动过
    final baseHash = {
      for (final e in baseById.entries) e.key: contentHash(e.value.toJson()),
    };

    final allIds = <String>{
      ...localById.keys,
      ...remoteById.keys,
      ...baseById.keys,
    };

    final merged = <Course>[];
    var localAdded = 0;
    var remoteAdded = 0;
    var localDeleted = 0;
    var remoteDeleted = 0;
    var tookRemote = 0;

    for (final id in allIds) {
      final l = localById[id];
      final r = remoteById[id];
      final b = baseById[id];
      final bh = baseHash[id];

      final lChanged = l != null && (bh == null || contentHash(l.toJson()) != bh);
      final rChanged = r != null && (bh == null || contentHash(r.toJson()) != bh);

      // 两端都存在
      if (l != null && r != null) {
        final lh = contentHash(l.toJson());
        final rh = contentHash(r.toJson());
        if (lh == rh) {
          merged.add(l); // 完全一致
        } else if (lChanged && !rChanged) {
          merged.add(l); // 只有本机改了
        } else if (!lChanged && rChanged) {
          merged.add(r); // 只有远端改了
          tookRemote++;
        } else {
          // 两端都改了且内容不同 —— 真冲突。
          // 策略：保留本机版本（用户此刻正在这台设备上操作），
          // 并显式记录冲突让用户知晓，而不是静默丢弃任何一边。
          merged.add(l);
          conflicts.add(SyncConflict(
            subject: l.name,
            description: '两端都修改了这门课',
            resolvedBy: 'local',
          ));
        }
        continue;
      }

      // 只有本机有
      if (l != null && r == null) {
        if (b == null) {
          merged.add(l); // 本机新增
          localAdded++;
        } else if (!lChanged) {
          // 本机没改，远端删了 —— 接受远端删除
          remoteDeleted++;
        } else {
          // 本机改了、远端删了 —— 冲突，保留本机
          merged.add(l);
          conflicts.add(SyncConflict(
            subject: l.name,
            description: '本机修改了这门课，但远端已删除',
            resolvedBy: 'local',
          ));
        }
        continue;
      }

      // 只有远端有
      if (l == null && r != null) {
        if (b == null) {
          merged.add(r); // 远端新增
          remoteAdded++;
        } else if (!rChanged) {
          // 远端没改，本机删了 —— 接受本机删除
          localDeleted++;
        } else {
          // 远端改了、本机删了 —— 冲突，保留远端（避免丢失远端的新改动）
          merged.add(r);
          tookRemote++;
          conflicts.add(SyncConflict(
            subject: r.name,
            description: '远端修改了这门课，但本机已删除',
            resolvedBy: 'remote',
          ));
        }
        continue;
      }

      // 两端都没有但基线有 —— 两端都删了，保持删除
      localDeleted++;
    }

    // 保持稳定顺序：按星期与节次排序，让两端合并后顺序一致，
    // 避免仅因顺序不同而被判定为「又变了」造成反复上传。
    merged.sort((a, b) {
      final ad = _firstDay(a);
      final bd = _firstDay(b);
      if (ad != bd) return ad.compareTo(bd);
      final ap = _firstPeriod(a);
      final bp = _firstPeriod(b);
      if (ap != bp) return ap.compareTo(bp);
      return a.name.compareTo(b.name);
    });

    // 学期与作息：同样按「谁改了谁生效」处理
    final semester = _pickScalar(
      local: local.semester.toJson(),
      remote: remote.semester.toJson(),
      base: base?.semester.toJson(),
      conflicts: conflicts,
      subject: '学期设置',
    );
    // 作息可能是多套方案（夏季/秋季），整体作为一个配置项参与三方选择，
    // 不能只比第一套 —— 否则多端同步会静默丢掉新增的方案。
    final schedules = _pickScalar(
      local: local.schedules.map((s) => s.toJson()).toList(),
      remote: remote.schedules.map((s) => s.toJson()).toList(),
      base: base?.schedules.map((s) => s.toJson()).toList(),
      conflicts: conflicts,
      subject: '作息时间',
    );

    final mergedTimetable = Timetable(
      semester: Semester.fromJson(Map<String, dynamic>.from(semester as Map)),
      schedules: (schedules as List)
          .map((e) => BellSchedule.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      courses: merged,
    );

    return MergeResult(
      merged: mergedTimetable,
      differsFromLocal: _differs(mergedTimetable, local),
      differsFromRemote: _differs(mergedTimetable, remote),
      conflicts: conflicts,
      localAdded: localAdded,
      remoteAdded: remoteAdded,
      localDeleted: localDeleted,
      remoteDeleted: remoteDeleted,
      tookRemote: tookRemote,
    );
  }

  /// 对「整体性设置」（学期、作息）做同样的三方选择。
  Object? _pickScalar({
    required Object? local,
    required Object? remote,
    required Object? base,
    required List<SyncConflict> conflicts,
    required String subject,
  }) {
    final lh = contentHash(local);
    final rh = contentHash(remote);
    if (lh == rh) return local;

    final bh = base == null ? null : contentHash(base);
    final lChanged = bh == null || lh != bh;
    final rChanged = bh == null || rh != bh;

    if (lChanged && !rChanged) return local;
    if (!lChanged && rChanged) return remote;

    // 两端都改了：本机优先，并记录冲突
    conflicts.add(SyncConflict(
      subject: subject,
      description: '两端都修改了$subject',
      resolvedBy: 'local',
    ));
    return local;
  }

  /// 比较两份课表是否有实质差异。
  ///
  /// 关键：先做**规范化**（课程按 id 排序）再比较。
  /// 否则「内容完全相同、只是课程顺序不同」会被误判为有差异，
  /// 导致每次同步都反复上传同一份数据（同步抖动）。
  bool _differs(Timetable a, Timetable b) =>
      contentHash(_canonical(a)) != contentHash(_canonical(b));

  /// 把课表转成与顺序无关的规范化 JSON 结构。
  Object _canonical(Timetable t) {
    final courses = t.courses.map((c) => c.toJson()).toList()
      ..sort((x, y) => (x['id'] ?? '').toString().compareTo((y['id'] ?? '').toString()));
    // 作息按「方案 id」排序并逐套排序节次，避免顺序差异被误判成内容变化
    final schedules = t.schedules.map((s) {
      final slots = s.slots.map((x) => x.toJson()).toList()
        ..sort((a, b) => ((a['period'] ?? 0) as int).compareTo((b['period'] ?? 0) as int));
      final json = s.toJson();
      json['slots'] = slots;
      return json;
    }).toList()
      ..sort((x, y) => (x['id'] ?? '').toString().compareTo((y['id'] ?? '').toString()));
    return {
      'semester': t.semester.toJson(),
      'schedules': schedules,
      'courses': courses,
    };
  }

  static int _firstDay(Course c) {
    var d = 99;
    for (final s in c.sessions) {
      if (s.dayOfWeek < d) d = s.dayOfWeek;
    }
    return d;
  }

  static int _firstPeriod(Course c) {
    var p = 999;
    for (final s in c.sessions) {
      if (s.startPeriod < p) p = s.startPeriod;
    }
    return p;
  }
}

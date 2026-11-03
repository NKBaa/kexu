import 'dart:convert';

import '../../core/utils/ids.dart';
import '../local/document_store.dart';
import '../models/timetable.dart';

/// 一条「修改历史」记录：某次修改**之前**的课表快照。
///
/// 保存整份 [Timetable]（而不是 diff）的原因：课表数据量很小（几十 KB），
/// 快照实现简单、回退绝对可靠，也不会因为某次 diff 写错而回退成坏数据。
class TimetableHistoryEntry {
  final String id;

  /// 记录时间（这次修改发生的时间）。
  final DateTime savedAt;

  /// 修改前的课表快照。
  final Timetable timetable;

  /// 这次修改的一句话说明，如「删除课程「高等数学」」；旧数据可能为空。
  final String description;

  const TimetableHistoryEntry({
    required this.id,
    required this.savedAt,
    required this.timetable,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'savedAt': savedAt.toIso8601String(),
        'timetable': timetable.toJson(),
        'description': description,
      };

  static TimetableHistoryEntry? fromJson(Map<String, dynamic> json) {
    try {
      final raw = json['timetable'];
      if (raw is! Map) return null;
      final at = DateTime.tryParse((json['savedAt'] ?? '').toString());
      return TimetableHistoryEntry(
        id: (json['id'] ?? '').toString(),
        savedAt: at ?? DateTime.now(),
        timetable: Timetable.fromJson(Map<String, dynamic>.from(raw)),
        description: (json['description'] ?? '').toString().trim(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// 课表修改历史仓储（最近 [maxEntries] 次，默认 20）。
///
/// 设计要点：
/// - 只保存「修改前」的快照，回退时把快照重新写入课表即可；
/// - 快照按时间从旧到新排列，超过上限时丢弃最旧的一条；
/// - 内容相同的连续快照会去重，避免拖动/重复保存塞满历史；
/// - 读写失败不抛给 UI：历史属于辅助能力，不能影响课表本身的保存。
class TimetableHistoryRepository {
  TimetableHistoryRepository({DocumentStore? store, int? maxEntries})
      : maxEntries = maxEntries ?? defaultMaxEntries,
        _store = store ?? DocumentStore('history.json', backupKeep: 1);

  /// 最多保留的版本数。
  static const int defaultMaxEntries = 20;

  final DocumentStore _store;
  final int maxEntries;

  /// 读取全部历史（旧 → 新）。
  Future<List<TimetableHistoryEntry>> load() async {
    try {
      final json = await _store.readJson();
      if (json == null) return <TimetableHistoryEntry>[];
      final raw = json['entries'];
      if (raw is! List) return <TimetableHistoryEntry>[];
      final entries = <TimetableHistoryEntry>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final entry = TimetableHistoryEntry.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (entry != null) entries.add(entry);
      }
      if (entries.length > maxEntries) {
        entries.removeRange(0, entries.length - maxEntries);
      }
      return entries;
    } catch (_) {
      return <TimetableHistoryEntry>[];
    }
  }

  /// 记录一次修改：[previous] 是修改前的课表。
  ///
  /// [next] 用于判断是否真的有变化（内容相同则不记录）；
  /// [at] 可注入时间，便于测试；
  /// [description] 给用户看的修改说明（撤销/重做时展示）。
  Future<void> push(
    Timetable previous, {
    Timetable? next,
    DateTime? at,
    String? description,
  }) async {
    if (next != null && sameTimetable(previous, next)) return;
    final entries = await load();
    if (entries.isNotEmpty && sameTimetable(entries.last.timetable, previous)) {
      return; // 连续保存同一份内容时去重
    }
    entries.add(
      TimetableHistoryEntry(
        id: newId(),
        savedAt: at ?? DateTime.now(),
        timetable: previous,
        description: (description ?? '').trim(),
      ),
    );
    while (entries.length > maxEntries) {
      entries.removeAt(0);
    }
    await _write(entries);
  }

  /// 回退最近一次修改：弹出并返回最新的快照；没有历史时返回 null。
  Future<TimetableHistoryEntry?> undoLatest() async {
    final entries = await load();
    if (entries.isEmpty) return null;
    final entry = entries.removeLast();
    await _write(entries);
    return entry;
  }

  Future<void> _write(List<TimetableHistoryEntry> entries) async {
    await _store.writeJson({
      'version': 1,
      'entries': [for (final e in entries) e.toJson()],
    });
  }

  /// 两份课表内容是否完全一致（按 JSON 比较，忽略对象引用）。
  static bool sameTimetable(Timetable a, Timetable b) {
    if (identical(a, b)) return true;
    try {
      return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
    } catch (_) {
      return false;
    }
  }
}

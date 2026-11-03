import 'dart:convert';
import 'dart:io';

import '../../core/utils/ids.dart';
import '../local/document_store.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../models/timetable.dart';

/// 课表仓储：负责把 [Timetable] 读/写到本地文档，并提供整体替换与导入导出。
///
/// 所有「增删改」都发生在内存中的 [Timetable] 副本上，再由调用方（Provider）
/// 统一持久化。这样批量操作与 AI 批量修改天然是原子的。
class TimetableRepository {
  TimetableRepository({DocumentStore? store})
      : _store = store ?? DocumentStore('timetable.json');

  final DocumentStore _store;

  /// 读取课表。首次运行（无文件）时返回一个默认课表：
  /// 学期从「本周一」开始、16 周、无课程。
  ///
  /// 数据目录不可用或文件损坏时也回退到默认课表，不让启动流程中断。
  Future<Timetable> load() async {
    try {
      final json = await _store.readJson();
      if (json == null) return _defaultTimetable();
      return Timetable.fromJson(json);
    } catch (_) {
      // 结构不兼容或存储不可用时，不让用户直接丢数据，而是回退到默认课表
      return _defaultTimetable();
    }
  }

  Future<void> save(Timetable timetable) async {
    await _store.writeJson(timetable.toJson());
  }

  /// 导出为可读 JSON 文本（用于分享/备份）。
  String exportToJsonText(Timetable t) =>
      const JsonEncoder.withIndent('  ').convert(t.toJson());

  /// 从 JSON 文本导入。
  ///
  /// 返回解析结果；[replaceIds] 为 true 时会重新生成所有 id，
  /// 避免与现有数据冲突（用于「合并导入」场景）。
  Timetable importFromJsonText(String text, {bool replaceIds = false}) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('文件内容不是合法的课表 JSON 对象');
    }
    var t = Timetable.fromJson(Map<String, dynamic>.from(decoded));
    if (replaceIds) {
      t = _reassignIds(t);
    }
    return t;
  }

  Timetable _reassignIds(Timetable t) {
    final semester = t.semester.copyWith();
    final courses = t.courses
        .map((c) => Course(
              id: newId(),
              semesterId: semester.id,
              name: c.name,
              teacher: c.teacher,
              courseCode: c.courseCode,
              credit: c.credit,
              note: c.note,
              colorIndex: c.colorIndex,
              sessions: c.sessions
                  .map((s) => Session(
                        id: newId(),
                        dayOfWeek: s.dayOfWeek,
                        startPeriod: s.startPeriod,
                        endPeriod: s.endPeriod,
                        weeks: s.weeks,
                        location: s.location,
                        teacher: s.teacher,
                      ))
                  .toList(),
              adjustments: c.adjustments
                  .map((a) => Adjustment(
                        id: newId(),
                        type: a.type,
                        fromDate: a.fromDate,
                        toDate: a.toDate,
                        startPeriod: a.startPeriod,
                        endPeriod: a.endPeriod,
                        location: a.location,
                        note: a.note,
                      ))
                  .toList(),
            ))
        .toList();
    return t.copyWith(semester: semester, courses: courses);
  }

  /// 把课表写入用户指定的文件路径（导出）。
  Future<void> exportToFile(Timetable t, String path) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(exportToJsonText(t), flush: true);
  }

  /// 数据文件位置（设置页展示用）。
  Future<String> dataFilePath() => _store.absolutePath();

  Timetable _defaultTimetable() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return Timetable(
      semester: Semester(
        id: newId(),
        name: _guessSemesterName(now),
        startMonday: monday,
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: const [],
    );
  }

  /// 依据当前月份猜一个学期名（3-7 月为春季学期，其余为秋季学期）。
  String _guessSemesterName(DateTime now) {
    if (now.month >= 2 && now.month <= 7) {
      return '${now.year} 学年春季学期';
    }
    final year = now.month <= 1 ? now.year - 1 : now.year;
    return '$year 学年秋季学期';
  }
}

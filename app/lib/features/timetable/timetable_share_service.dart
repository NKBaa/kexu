import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/holiday_utils.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/holiday.dart';
import '../../data/models/semester.dart';
import '../../data/models/timetable.dart';

/// 课表分享：把当前课表导出为 `.ics` 日历文件或 `.json` 数据文件，
/// 再交给系统分享面板。
///
/// 日历文件按「每次课的实际日期」展开成 VEVENT：
/// - 周次来自 `Session.weeks`，日期由学期第 1 周周一换算；
/// - 起止时间取**当天生效的作息**（支持夏季/冬季多套作息）；
/// - 节假日当天的课不写入日历；
/// - 每门课/每个时段/每次课生成一个稳定 UID，重复导入日历不会产生大量重复事件。
class TimetableShareService {
  const TimetableShareService();

  /// 生成 iCalendar（RFC 5545）文本，纯函数，便于测试。
  String buildIcs(
    Timetable timetable, {
    List<Holiday> holidays = const [],
    DateTime? now,
  }) {
    final stamp = _utcStamp(now ?? DateTime.now());
    final occurrences = <_IcsOccurrence>[];

    for (final course in timetable.courses) {
      for (final session in course.sessions) {
        for (final week in session.weeks) {
          if (week < 1 || week > timetable.semester.totalWeeks) continue;
          final date = dateOfWeekDay(
            timetable.semester.startMonday,
            week,
            session.dayOfWeek,
          );
          if (holidayForDate(holidays, date) != null) continue;

          final slots = timetable.slotsForDate(date);
          final startSlot = _slotOf(slots, session.startPeriod);
          final endSlot = _slotOf(slots, session.endPeriod);
          if (startSlot == null || endSlot == null) continue;
          final start = _combine(date, startSlot.start);
          final end = _combine(date, endSlot.end);
          if (start == null || end == null || !end.isAfter(start)) continue;

          final location = (session.location ?? '').trim();
          final teacher = (session.teacher ?? course.teacher ?? '').trim();
          occurrences.add(
            _IcsOccurrence(
              uid: 'kexu-${course.id}-${session.id}-${formatDateKey(date)}@kexu',
              start: start,
              end: end,
              summary: course.name,
              description: [
                if (teacher.isNotEmpty) '教师：$teacher',
                '第${session.startPeriod}-${session.endPeriod}节',
                '第$week周',
                if (course.note != null && course.note!.trim().isNotEmpty)
                  course.note!.trim(),
              ].join('\n'),
              location: location,
            ),
          );
        }
      }
    }

    occurrences.sort((a, b) => a.start.compareTo(b.start));

    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Kexu//Timetable Share//CN')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH')
      ..writeln('X-WR-CALNAME:${_escape(timetable.semester.name)}')
      ..writeln('X-WR-CALDESC:课序导出的课表')
      ..writeln('X-WR-TIMEZONE:Asia/Shanghai')
      ..writeln('BEGIN:VTIMEZONE')
      ..writeln('TZID:Asia/Shanghai')
      ..writeln('BEGIN:STANDARD')
      ..writeln('DTSTART:19700101T000000')
      ..writeln('TZOFFSETFROM:+0800')
      ..writeln('TZOFFSETTO:+0800')
      ..writeln('TZNAME:CST')
      ..writeln('END:STANDARD')
      ..writeln('END:VTIMEZONE');

    for (final item in occurrences) {
      buffer
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:${_escape(item.uid)}')
        ..writeln('DTSTAMP:$stamp')
        ..writeln('DTSTART;TZID=Asia/Shanghai:${_localStamp(item.start)}')
        ..writeln('DTEND;TZID=Asia/Shanghai:${_localStamp(item.end)}')
        ..writeln('SUMMARY:${_escape(item.summary)}')
        ..writeln('DESCRIPTION:${_escape(item.description)}')
        ..writeln('LOCATION:${_escape(item.location)}')
        ..writeln('CATEGORIES:课表')
        ..writeln('STATUS:CONFIRMED')
        ..writeln('TRANSP:OPAQUE')
        ..writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    return _foldIcsLines(buffer.toString());
  }

  /// 生成课表 JSON 文本（与数据管理里的备份格式一致）。
  String buildJson(Timetable timetable) =>
      const JsonEncoder.withIndent('  ').convert(timetable.toJson());

  /// 写 `.ics` 到临时目录，返回文件。
  Future<File> writeIcs(
    Timetable timetable, {
    List<Holiday> holidays = const [],
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final file = await _shareFile('kexu-timetable-${_dateStamp(at)}.ics');
    await file.writeAsString(
      buildIcs(timetable, holidays: holidays, now: at),
      flush: true,
    );
    return file;
  }

  /// 写 `.json` 到临时目录，返回文件。
  Future<File> writeJson(Timetable timetable, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final file = await _shareFile('kexu-timetable-${_dateStamp(at)}.json');
    await file.writeAsString(buildJson(timetable), flush: true);
    return file;
  }

  /// 生成 `.ics` 并打开系统分享面板。
  Future<ShareResult> shareIcs(
    Timetable timetable, {
    List<Holiday> holidays = const [],
    DateTime? now,
  }) async {
    final file = await writeIcs(timetable, holidays: holidays, now: now);
    return _share(
      file,
      mimeType: 'text/calendar',
      subject: '课序课表 · ${timetable.semester.name}',
      text: '来自课序的日历文件，导入日历后按日期显示每次课。',
    );
  }

  /// 生成 `.json` 并打开系统分享面板。
  Future<ShareResult> shareJson(Timetable timetable, {DateTime? now}) async {
    final file = await writeJson(timetable, now: now);
    return _share(
      file,
      mimeType: 'application/json',
      subject: '课序课表 · ${timetable.semester.name}',
      text: '来自课序的课表数据，可在「数据管理」中导入。',
    );
  }

  Future<ShareResult> _share(
    File file, {
    required String mimeType,
    required String subject,
    required String text,
  }) {
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
        text: text,
        title: subject,
      ),
    );
  }

  Future<File> _shareFile(String name) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}kexu-share');
    await folder.create(recursive: true);
    return File('${folder.path}${Platform.pathSeparator}$name');
  }

  static TimeSlot? _slotOf(List<TimeSlot> slots, int period) {
    for (final slot in slots) {
      if (slot.period == period) return slot;
    }
    return null;
  }

  static DateTime? _combine(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim());
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static String _localStamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}T${two(d.hour)}${two(d.minute)}00';
  }

  static String _utcStamp(DateTime d) {
    final utc = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  static String _dateStamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}';
  }

  /// iCalendar 文本转义：反斜杠、分号、逗号、换行。
  static String _escape(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\r\n', '\\n')
        .replaceAll('\n', '\\n');
  }

  /// RFC 5545 要求每行不超过 75 字节，超长行用 CRLF + 空格折行。
  static String _foldIcsLines(String text) {
    final out = StringBuffer();
    for (final raw in text.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) {
        out.write('\r\n');
        continue;
      }
      var current = '';
      for (final rune in line.runes) {
        final ch = String.fromCharCode(rune);
        if (utf8.encode(current + ch).length > 74 && current.isNotEmpty) {
          out
            ..write(current)
            ..write('\r\n ');
          current = ch;
        } else {
          current += ch;
        }
      }
      out
        ..write(current)
        ..write('\r\n');
    }
    return out.toString();
  }
}

class _IcsOccurrence {
  const _IcsOccurrence({
    required this.uid,
    required this.start,
    required this.end,
    required this.summary,
    required this.description,
    required this.location,
  });

  final String uid;
  final DateTime start;
  final DateTime end;
  final String summary;
  final String description;
  final String location;
}

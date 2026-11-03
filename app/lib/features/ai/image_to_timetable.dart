/// 「图片 → 课表草稿」的编排与解析。
///
/// 分两层：
/// - [ImageToTimetableService.parseImages]：
///   发请求（多模态，可多图），拿模型原始文本；
/// - [ImageToTimetableService.parseModelOutput]：纯函数式解析，不联网，便于单测。
///
/// 解析层做了大量容错：模型可能输出 `{"courses":[...]}`、裸数组、扁平课程对象，
/// 周次可能是数组或 `"1-8周(单)"` 字符串，字段可能用中文键名。
/// 所有「回退/丢弃」都会写进 [DraftCourse.warnings]，交给 UI 原样提示用户。
///
/// 多图支持：一次选多张截图时，按 [maxImagesPerRequest] 分批发给视觉模型，
/// 每批结果再跨批合并（同名课程合并、同时段周次取并集），
/// 这样「单周截图 + 双周截图」能拼成完整周次，分页截图也不会出现重复课程。
library;

import '../../core/utils/json_utils.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/draft.dart';
import 'ai_client.dart';
import 'ai_exception.dart';
import 'prompts.dart';

/// 单次请求最多携带的图片张数。
///
/// 图片会以 base64 塞进同一条消息，张数太多会让请求体过大（很多服务商有上限），
/// 视觉模型也容易漏看后面的图，因此超过这个数量就分批请求、再在客户端合并。
const int maxImagesPerRequest = 4;

/// 一次「多图 → 课表」识别的结果。
class ImageParseResult {
  /// 合并后的草稿课程（同名课程合并、同时段周次取并集）。
  final List<DraftCourse> courses;

  /// 批次级告警（如「第 1 批（第 1-4 张）识别失败：……」）。
  ///
  /// 与 [DraftCourse.warnings] 分开：后者只针对某门课，
  /// 这里的问题影响整体导入（部分图片没识别成功），需要单独提示用户。
  final List<String> warnings;

  /// 图片若明确是单日课表，模型会返回该日期；整周课表为 null。
  final DateTime? detectedDate;

  const ImageParseResult({
    this.courses = const [],
    this.warnings = const [],
    this.detectedDate,
  });
}

/// 图片转课表服务。
class ImageToTimetableService {
  // 命名参数名对外是 client，字段是私有的，无法使用 initializing formal。
  // ignore: prefer_initializing_formals
  ImageToTimetableService({required AiClient client}) : _client = client;

  final AiClient _client;

  /// 解析一组课表截图（多选多图），返回合并后的草稿课程与批次级告警。
  ///
  /// 处理流程：
  /// 1. 图片按 [maxImagesPerRequest] 分批，每批一次 [AiClient.chatWithImages] 请求，
  ///    prompt 用 [buildImageToTimetablePrompt] 并带上本批张数与偏移量；
  /// 2. 每批各自用 [parseModelOutput] 解析（含单批内的容错与去重）；
  /// 3. 跨批用 [mergeCourses] 合并：同名课程合并成一条，
  ///    「同一天 + 同起止节 + 同地点」的时段合并成一条并取周次并集
  ///    ——「单周截图 + 双周截图」就是这样拼成完整周次的。
  ///
  /// 容错策略：**部分批次失败不中断整体流程**。成功的批次照常返回，
  /// 失败原因写进 [ImageParseResult.warnings]（如「第 2 批（第 5-6 张）识别失败：……」）；
  /// 只有全部批次都失败时才抛出第一个 [AiException]。
  Future<ImageParseResult> parseImages(
    List<AiImageAttachment> images, {
    required int totalWeeks,
    String? extraHint,
  }) async {
    if (images.isEmpty) {
      throw AiException.invalidInput('请至少选择一张课表截图。');
    }
    // 发请求前就拦掉空图片，避免浪费一次昂贵的视觉调用。
    for (var i = 0; i < images.length; i++) {
      if (images[i].isEmpty) {
        throw AiException.invalidInput('第 ${i + 1} 张图片内容为空，请重新选择后再试。');
      }
    }

    final warnings = <String>[];
    final batchCourses = <DraftCourse>[];
    DateTime? detectedDate;
    AiException? firstError;
    Object? firstRawError;
    var succeeded = 0;

    for (var start = 0; start < images.length; start += maxImagesPerRequest) {
      final end = start + maxImagesPerRequest <= images.length
          ? start + maxImagesPerRequest
          : images.length;
      final batch = images.sublist(start, end);
      final label = _batchLabel(start ~/ maxImagesPerRequest + 1, start, end);
      final prompt = buildImageToTimetablePrompt(
        totalWeeks: totalWeeks,
        extraHint: extraHint,
        imageCount: batch.length,
        imageOffset: start,
      );
      try {
        final raw = await _client.chatWithImages(
          images: batch,
          prompt: prompt,
          system: aiSystemPrompt,
        );
        batchCourses.addAll(parseModelOutput(raw, totalWeeks: totalWeeks));
        final batchDate = parseImageDate(raw);
        if (batchDate != null) {
          if (detectedDate == null) {
            detectedDate = batchDate;
          } else if (!_isSameDay(detectedDate, batchDate)) {
            warnings.add('多张图片识别到不同日期，已统一按 ${_formatDate(detectedDate)} 处理。');
          }
        }
        succeeded++;
      } on AiException catch (e) {
        firstError ??= e;
        warnings.add('$label 识别失败：${e.message}');
      } catch (e) {
        firstRawError ??= e;
        warnings.add('$label 识别失败：$e');
      }
    }

    if (succeeded == 0) {
      // 全部批次都失败：把第一个错误抛给 UI，避免用户只看到「没有识别出课程」。
      if (firstError != null) throw firstError;
      throw AiException('识别失败：$firstRawError');
    }

    return ImageParseResult(
      courses: mergeCourses(batchCourses),
      warnings: warnings,
      detectedDate: detectedDate,
    );
  }

  /// 解析单张/单日课表里的顶层 `date` 字段。
  ///
  /// 支持 `YYYY-MM-DD`、`YYYY/MM/DD`、`YYYY年M月D日`、`MM-DD`、`M月D日`；
  /// 没有年份时用当前年份。整周课表一般不返回 date，返回 null。
  static DateTime? parseImageDate(String rawText) {
    final block = extractJsonBlock(rawText.trim());
    if (block == null) return null;
    final decoded = tryDecodeJson(block);
    if (decoded is! Map) return null;
    for (final key in const ['date', '日期', 'imageDate', 'day']) {
      final parsed = _parseDateString(asString(decoded[key]));
      if (parsed != null) return parsed;
    }
    return null;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static DateTime? _parseDateString(String value) {
    final s = value.trim();
    if (s.isEmpty) return null;
    final full = RegExp(r'(\d{4})\s*[年/\-.]\s*(\d{1,2})\s*[月/\-.]\s*(\d{1,2})').firstMatch(s);
    if (full != null) {
      final date = DateTime(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      );
      return _validDate(date) ? date : null;
    }
    final short = RegExp(r'(\d{1,2})\s*[月/\-.]\s*(\d{1,2})').firstMatch(s);
    if (short != null) {
      final date = DateTime(
        DateTime.now().year,
        int.parse(short.group(1)!),
        int.parse(short.group(2)!),
      );
      return _validDate(date) ? date : null;
    }
    return null;
  }

  static bool _validDate(DateTime d) {
    // DateTime 会把 13 月溢出到下一年，这里反查一次避免把明显错的日期当有效。
    return d.month >= 1 && d.month <= 12 && d.day >= 1 && d.day <= 31;
  }

  /// 批次范围的中文描述，如「第 2 批（第 5-8 张）」。
  static String _batchLabel(int batchIndex, int start, int end) {
    final from = start + 1;
    final range = from == end ? '第 $from 张' : '第 $from-$end 张';
    return '第 $batchIndex 批（$range）';
  }

  /// 从模型原始文本解析课程草稿（不发起网络请求，公开便于测试）。
  ///
  /// 能识别三种形态：`{"courses":[...]}`、直接数组 `[...]`、单个课程对象。
  /// 模型明确返回空数组时返回空列表；完全无法识别时抛出 [AiException]。
  static List<DraftCourse> parseModelOutput(
    String rawText, {
    required int totalWeeks,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) {
      throw AiException.parse('模型没有返回任何内容，请重试或换一个模型。');
    }

    final block = extractJsonBlock(text);
    if (block == null) {
      throw AiException.parse(
        '模型输出里找不到可解析的 JSON，可能混入了大段说明文字，请重试。',
        rawOutput: text,
      );
    }

    final decoded = tryDecodeJson(block);
    if (decoded == null) {
      throw AiException.parse(
        '模型输出的 JSON 格式有误（可能存在多余逗号或未转义字符），请重试。',
        rawOutput: block,
      );
    }

    final rawCourses = _extractCourseList(decoded);
    if (rawCourses == null) {
      throw AiException.parse(
        '模型输出的 JSON 结构无法识别：既没有 courses 数组，也不像单门课程对象。',
        rawOutput: block,
      );
    }
    if (rawCourses.isEmpty) {
      // 模型明确表示图中没有课程（如识别出不是课表），返回空列表由 UI 提示。
      return const <DraftCourse>[];
    }

    final weekCount = totalWeeks >= 1 ? totalWeeks : 16;
    final allWeeks = List<int>.generate(weekCount, (i) => i + 1);
    final courses = <DraftCourse>[];

    for (final rawCourse in rawCourses) {
      if (rawCourse is! Map) continue;
      final warnings = <String>[];
      final normalized = _normalizeCourse(
        rawCourse,
        totalWeeks: weekCount,
        warnings: warnings,
      );
      final draft = DraftCourse.fromAiJson(normalized, defaultWeeks: allWeeks);

      // 完全空白的条目（既没名字也没时段）没有展示价值，直接丢弃。
      if (draft.name.trim().isEmpty && draft.sessions.isEmpty) continue;

      var sessions = draft.sessions;
      final mergedSessions = _mergeSessions(sessions);
      if (mergedSessions.length != sessions.length) {
        warnings.add('已合并 ${sessions.length - mergedSessions.length} 个重复的上课时段');
        sessions = mergedSessions;
      }

      courses.add(DraftCourse(
        name: draft.name.trim(),
        teacher: draft.teacher,
        courseCode: draft.courseCode,
        credit: draft.credit,
        note: draft.note,
        sessions: sessions,
        warnings: _dedupeStrings([...warnings, ...draft.warnings]),
      ));
    }

    return _mergeDuplicateCourses(courses);
  }

  // ------------------------------------------------------------ JSON 形态识别

  /// 从任意解码结果里找出「课程对象数组」，找不到返回 null。
  static List<dynamic>? _extractCourseList(dynamic decoded, {int depth = 0}) {
    if (depth > 4) return null;

    if (decoded is List) {
      if (decoded.isEmpty) return const <dynamic>[];
      final maps = decoded.whereType<Map>().map<dynamic>((e) => e).toList();
      return maps.isEmpty ? null : maps;
    }
    if (decoded is! Map) return null;

    final j = Map<String, dynamic>.from(decoded);
    for (final key in const [
      'courses',
      'courseList',
      'data',
      'result',
      'items',
      'list',
      'timetable',
      '课程',
    ]) {
      if (!j.containsKey(key)) continue;
      final value = j[key];
      if (value is List) {
        if (value.isEmpty) return const <dynamic>[];
        final maps = value.whereType<Map>().map<dynamic>((e) => e).toList();
        if (maps.isNotEmpty) return maps;
        continue;
      }
      if (value is String || value is Map) {
        // 有些模型会把内层 JSON 再序列化成字符串
        final inner = value is String ? tryDecodeJson(value) : value;
        final nested = _extractCourseList(inner, depth: depth + 1);
        if (nested != null) return nested;
      }
    }

    // 单门课程：直接是 {"name": "...", "sessions": [...]}
    if (_looksLikeCourse(j)) return <dynamic>[j];
    return null;
  }

  static bool _looksLikeCourse(Map<String, dynamic> j) {
    const nameKeys = ['name', 'courseName', 'course', '课程名', '课程名称'];
    for (final k in nameKeys) {
      final v = asString(j[k]);
      if (v.isNotEmpty) return true;
    }
    return j['sessions'] is List ||
        j['times'] is List ||
        j['时段'] is List ||
        j.containsKey('dayOfWeek') ||
        j.containsKey('星期');
  }

  // -------------------------------------------------------------- 字段归一化

  /// 课程对象的中文/别名键映射。
  static const Map<String, List<String>> _courseAliases = {
    'name': ['courseName', '课程名', '课程名称', '名称'],
    'teacher': ['instructor', '教师', '老师', '任课教师'],
    'courseCode': ['code', '课程编号', '课程号', '编号'],
    'credit': ['credits', '学分'],
    'note': ['remark', '备注', '说明'],
    'location': ['place', 'classroom', '教室', '地点', '上课地点'],
    'sessions': ['times', 'periods', 'schedule', 'slots', 'classes', 'entries', '上课时间', '时段', '课程安排'],
  };

  /// 时段对象的中文/别名键映射。
  static const Map<String, List<String>> _sessionAliases = {
    'dayOfWeek': ['day', 'weekday', '星期', '周几'],
    'startPeriod': ['start', 'periodStart', '开始节次', '起始节', '开始节'],
    'endPeriod': ['end', 'periodEnd', '结束节次', '终止节', '结束节'],
    'weeks': ['周次', '上课周次'],
    'location': ['place', 'classroom', '教室', '地点', '上课地点'],
    'teacher': ['instructor', '教师', '老师'],
  };

  /// 把课程 + 所有时段归一化成 [DraftCourse.fromAiJson] 能吃的结构。
  static Map<String, dynamic> _normalizeCourse(
    Map rawCourse, {
    required int totalWeeks,
    required List<String> warnings,
  }) {
    // 课程级与时段级别名一起补齐：模型可能把「星期/开始节次」直接写在课程对象上。
    final j = _canonicalize(_canonicalize(rawCourse, _courseAliases), _sessionAliases);
    final name = asString(j['name']).trim();
    final label = name.isEmpty ? '（无课程名）' : '「$name」';

    // 课程级周次：有些模型把周次写在课程上，供所有时段复用。
    final courseWeeks = _parseExplicitWeeks(j, totalWeeks);
    final courseLocation = asString(j['location']);

    final sessionMaps = <Map<String, dynamic>>[];
    final rawSessions = j['sessions'];
    if (rawSessions is List) {
      var bad = 0;
      for (final e in rawSessions) {
        if (e is Map) {
          sessionMaps.add(Map<String, dynamic>.from(e));
        } else if (!_isMissing(e)) {
          bad++;
        }
      }
      if (bad > 0) warnings.add('$label 有 $bad 个上课时段格式不正确（不是对象），已忽略');
    } else if (!_isMissing(rawSessions)) {
      warnings.add('$label 的 sessions 字段不是数组，已忽略');
    }

    final normalized = <Map<String, dynamic>>[];
    for (var i = 0; i < sessionMaps.length; i++) {
      final s = _canonicalize(sessionMaps[i], _sessionAliases);
      final sessionLabel = '第 ${i + 1} 个上课时段';
      if (_isMissing(s['dayOfWeek'])) {
        warnings.add('$label $sessionLabel 未标注星期，已默认按周一处理');
      }
      if (_isMissing(s['location']) && courseLocation.isNotEmpty) {
        s['location'] = courseLocation;
      }
      s['weeks'] = _resolveWeeks(
        s,
        totalWeeks: totalWeeks,
        courseLabel: label,
        sessionLabel: sessionLabel,
        courseWeeks: courseWeeks,
        warnings: warnings,
      );
      normalized.add(s);
    }

    if (normalized.isNotEmpty) {
      j['sessions'] = normalized;
      return j;
    }

    // 扁平结构：课程对象本身带 dayOfWeek/节次（模型偷懒只给一门一段课）。
    if (_hasFlatSession(j)) {
      final flat = _canonicalize(Map<String, dynamic>.from(j), _sessionAliases);
      if (_isMissing(flat['dayOfWeek'])) {
        warnings.add('$label 未标注星期，已默认按周一处理');
      }
      if (_isMissing(flat['location']) && courseLocation.isNotEmpty) {
        flat['location'] = courseLocation;
      }
      flat['weeks'] = _resolveWeeks(
        flat,
        totalWeeks: totalWeeks,
        courseLabel: label,
        sessionLabel: '上课时段',
        courseWeeks: courseWeeks,
        warnings: warnings,
      );
      j['sessions'] = <Map<String, dynamic>>[flat];
      return j;
    }

    j.remove('sessions');
    return j;
  }

  /// 是否把课程对象本身当成一个时段。
  ///
  /// 注意：只有 `weeks` 而没有星期/节次时不算（避免凭空造出「周一第 1 节」的假时段）。
  static bool _hasFlatSession(Map<String, dynamic> j) {
    if (!_isMissing(j['dayOfWeek'])) return true;
    if (!_isMissing(j['startPeriod'])) return true;
    if (!_isMissing(j['endPeriod'])) return true;
    return false;
  }

  /// 解析单个时段的周次，缺失时回退并记录警告。
  static List<int> _resolveWeeks(
    Map<String, dynamic> session, {
    required int totalWeeks,
    required String courseLabel,
    required String sessionLabel,
    required List<int>? courseWeeks,
    required List<String> warnings,
  }) {
    final allWeeks = List<int>.generate(totalWeeks, (i) => i + 1);

    final explicit = _parseExplicitWeeks(session, totalWeeks);
    if (explicit != null && explicit.isNotEmpty) {
      return _clampWeeks(
        explicit,
        totalWeeks: totalWeeks,
        courseLabel: courseLabel,
        sessionLabel: sessionLabel,
        warnings: warnings,
      );
    }
    if (explicit != null && explicit.isEmpty) {
      warnings.add('$courseLabel $sessionLabel 的周次无法解析，已按第 1-$totalWeeks 周处理');
      return allWeeks;
    }

    if (courseWeeks != null && courseWeeks.isNotEmpty) {
      return _clampWeeks(
        courseWeeks,
        totalWeeks: totalWeeks,
        courseLabel: courseLabel,
        sessionLabel: sessionLabel,
        warnings: warnings,
      );
    }

    warnings.add('$courseLabel $sessionLabel 未标注周次，已按第 1-$totalWeeks 周处理');
    return allWeeks;
  }

  /// 截断超出学期范围的周次，并记录警告。
  static List<int> _clampWeeks(
    List<int> weeks, {
    required int totalWeeks,
    required String courseLabel,
    required String sessionLabel,
    required List<String> warnings,
  }) {
    final sorted = weeks.where((w) => w > 0).toSet().toList()..sort();
    final over = sorted.where((w) => w > totalWeeks).toList();
    if (over.isEmpty) return sorted;

    warnings.add(
      '$courseLabel $sessionLabel 的周次 ${over.join(',')} 超出学期总周数 $totalWeeks，已截断',
    );
    final kept = sorted.where((w) => w <= totalWeeks).toList();
    if (kept.isEmpty) {
      warnings.add('$courseLabel $sessionLabel 的周次全部超出范围，已按第 1-$totalWeeks 周处理');
      return List<int>.generate(totalWeeks, (i) => i + 1);
    }
    return kept;
  }

  /// 解析显式周次：支持整数数组、整数、字符串（区间/单双周/逗号分隔）。
  ///
  /// 返回 null 表示「没写周次」；返回空列表表示「写了但解析不出来」。
  static List<int>? _parseExplicitWeeks(Map<String, dynamic> j, int totalWeeks) {
    var found = false;
    final raw = j['weeks'];

    if (raw is List) {
      found = true;
      final list = raw
          .map(asInt)
          .whereType<int>()
          .where((w) => w > 0)
          .toSet()
          .toList()
        ..sort();
      if (list.isNotEmpty) return list;
    } else if (raw is num) {
      found = true;
      final w = raw.toInt();
      if (w > 0) return <int>[w];
    } else if (raw is String && raw.trim().isNotEmpty) {
      found = true;
      if (_isEveryWeek(raw)) return List<int>.generate(totalWeeks, (i) => i + 1);
      final parsed = parseWeeks(raw, maxWeek: totalWeeks);
      if (parsed.isNotEmpty) return parsed;
    }

    for (final key in const [
      'weekRange',
      'weekType',
      'weekTypeText',
      'weekText',
      'weeksText',
      '上课周次',
      '周次',
    ]) {
      final s = asString(j[key]);
      if (s.isEmpty) continue;
      found = true;
      if (_isEveryWeek(s)) return List<int>.generate(totalWeeks, (i) => i + 1);
      final parsed = parseWeeks(s, maxWeek: totalWeeks);
      if (parsed.isNotEmpty) return parsed;
    }

    // startWeek/endWeek 这种「起止周」写法
    final sw = asInt(j['startWeek']) ??
        asInt(j['weekStart']) ??
        asInt(j['fromWeek']) ??
        asInt(j['起始周']);
    if (sw != null) {
      found = true;
      final ew = asInt(j['endWeek']) ??
          asInt(j['weekEnd']) ??
          asInt(j['toWeek']) ??
          asInt(j['结束周']) ??
          sw;
      final lo = sw <= ew ? sw : ew;
      final hi = sw <= ew ? ew : sw;
      final list = <int>[];
      for (var w = lo; w <= hi; w++) {
        if (w > 0) list.add(w);
      }
      if (list.isNotEmpty) return list;
    }

    return found ? <int>[] : null;
  }

  /// 「每周 / 全周 / 所有周」这类描述表示全学期上课。
  static bool _isEveryWeek(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (t.contains('每周') || t.contains('全周') || t.contains('所有周') || t.contains('全部周')) {
      return true;
    }
    if (t == '全' || t == '全部') return true;
    // 「1-16周」这类会由 parseWeeks 处理，这里只兜底不含数字的「每…」写法
    return t.contains('每') && !RegExp(r'\d').hasMatch(t);
  }

  // ------------------------------------------------------------------- 小工具

  /// 按别名表补齐 canonical 键（canonical 为空时才使用别名值）。
  static Map<String, dynamic> _canonicalize(
    Map raw,
    Map<String, List<String>> aliases,
  ) {
    final out = Map<String, dynamic>.from(raw);
    aliases.forEach((canonical, alts) {
      if (!_isMissing(out[canonical])) return;
      for (final alt in alts) {
        if (!_isMissing(out[alt])) {
          out[canonical] = out[alt];
          return;
        }
      }
    });
    return out;
  }

  static bool _isMissing(dynamic v) {
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty;
    if (v is List) return v.isEmpty;
    if (v is Map) return v.isEmpty;
    return false;
  }

  static List<String> _dedupeStrings(List<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final v in values) {
      final s = v.trim();
      if (s.isEmpty) continue;
      if (seen.add(s)) out.add(s);
    }
    return out;
  }

  /// 合并「同一时段」的多条上课记录，并把周次取并集。
  ///
  /// 同一时段的判定：星期、起止节次相同，且地点相同（至少一方没写地点也算，
  /// 因为模型有时只在其中一条里写了教室）。单周截图与双周截图各识别出一条
  /// 「周一第 1-2 节」时，就会在这里合并成一条完整周次的记录。
  static List<DraftSession> _mergeSessions(List<DraftSession> sessions) {
    final out = <DraftSession>[];
    for (final s in sessions) {
      final index = out.indexWhere((e) => _isSameSlot(e, s));
      if (index < 0) {
        out.add(s);
        continue;
      }
      final prev = out[index];
      final weeks = <int>{...prev.weeks, ...s.weeks}.toList()..sort();
      final location = pickNonEmpty([prev.location, s.location]);
      final teacher = pickNonEmpty([prev.teacher, s.teacher]);
      out[index] = DraftSession(
        dayOfWeek: prev.dayOfWeek,
        startPeriod: prev.startPeriod,
        endPeriod: prev.endPeriod,
        weeks: weeks,
        location: location.isEmpty ? null : location,
        teacher: teacher.isEmpty ? null : teacher,
      );
    }
    return out;
  }

  /// 两个时段是否是「同一天、同起止节、同地点」。
  static bool _isSameSlot(DraftSession a, DraftSession b) {
    if (a.dayOfWeek != b.dayOfWeek) return false;
    if (a.startPeriod != b.startPeriod) return false;
    if (a.endPeriod != b.endPeriod) return false;
    final la = (a.location ?? '').trim();
    final lb = (b.location ?? '').trim();
    if (la.isEmpty || lb.isEmpty) return true;
    return la == lb;
  }

  /// 跨图/跨批合并课程草稿（公开便于单测）。
  ///
  /// 规则：同名课程合并成一条；同一门课里「同一天 + 同起止节 + 同地点」的时段
  /// 合并成一条并取周次并集——这是「单周截图 + 双周截图」拼成完整周次的关键，
  /// 也能去掉多张图重叠部分带来的重复时段。
  static List<DraftCourse> mergeCourses(List<DraftCourse> courses) =>
      _mergeDuplicateCourses(courses);

  /// 同名课程合并（模型常把同一门课拆成多条）。
  static List<DraftCourse> _mergeDuplicateCourses(List<DraftCourse> courses) {
    final indexByName = <String, int>{};
    final out = <DraftCourse>[];
    for (final c in courses) {
      final key = c.name.trim().toLowerCase();
      if (key.isEmpty) {
        out.add(c);
        continue;
      }
      final existing = indexByName[key];
      if (existing == null) {
        indexByName[key] = out.length;
        out.add(c);
        continue;
      }
      final prev = out[existing];
      final merged = _mergeSessions([...prev.sessions, ...c.sessions]);
      final duplicateCount = prev.sessions.length + c.sessions.length - merged.length;
      final warnings = <String>{...prev.warnings, ...c.warnings}
        ..add('已合并疑似重复的课程条目（同名课程）');
      if (duplicateCount > 0) warnings.add('已合并 $duplicateCount 个重复的上课时段');
      out[existing] = DraftCourse(
        name: prev.name,
        teacher: prev.teacher ?? c.teacher,
        courseCode: prev.courseCode ?? c.courseCode,
        credit: prev.credit ?? c.credit,
        note: prev.note ?? c.note,
        sessions: merged,
        warnings: warnings.toList(),
      );
    }
    return out;
  }
}

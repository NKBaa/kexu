import 'semester.dart';

/// 一套远程作息模板（按学校归组）。
///
/// 模板文件托管在 GitHub 的 `templates/bell_schedules.json`，由 App 按学校
/// 分组展示。这里只描述数据，不依赖网络或 UI，便于单独测试。
class BellScheduleTemplate {
  const BellScheduleTemplate({
    required this.id,
    required this.school,
    required this.name,
    required this.slots,
    this.description = '',
    this.startMonthDay,
    this.endMonthDay,
  });

  /// 模板唯一标识（同一学校内唯一即可）。
  final String id;

  /// 所属学校。
  final String school;

  /// 模板名，如「夏季作息」「标准 12 节」。
  final String name;

  /// 可选的说明。
  final String description;

  /// 每节课的起止时间。
  final List<TimeSlot> slots;

  /// 模板首节的开始时间，用于列表摘要。
  String get firstStart => slots.isEmpty ? '' : slots.first.start;

  /// 模板末节的结束时间，用于列表摘要。
  String get lastEnd => slots.isEmpty ? '' : slots.last.end;

  /// 可选的生效日期范围（`MM-dd` 形式，如春季 `05-01` ~ `10-01`）。
  ///
  /// 学校按季节区分作息时，模板会带这两个字段；应用「全部导入」时
  /// 会转换成具体年份的 [DateTime] 写入 [BellSchedule.startDate/endDate]。
  final String? startMonthDay;
  final String? endMonthDay;

  bool get hasDateRange =>
      (startMonthDay ?? '').isNotEmpty && (endMonthDay ?? '').isNotEmpty;

  String get rangeLabel =>
      hasDateRange ? '$startMonthDay ~ $endMonthDay' : '不限日期';

  factory BellScheduleTemplate.fromJson(
    Map<String, dynamic> j, {
    required String school,
  }) {
    final rawSlots = j['slots'];
    final slots = <TimeSlot>[];
    if (rawSlots is List) {
      for (final item in rawSlots) {
        if (item is Map) {
          slots.add(TimeSlot.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    if (slots.isEmpty) {
      throw const FormatException('作息模板缺少 slots');
    }
    slots.sort((a, b) => a.period.compareTo(b.period));
    final rawName = (j['name'] ?? '').toString().trim();
    final id = (j['id'] ?? rawName).toString().trim();
    if (rawName.isEmpty || id.isEmpty) {
      throw const FormatException('作息模板缺少名称或 id');
    }

    // 兼容两种写法：
    //   "dateRange": {"start":"05-01","end":"10-01"}
    //   "startMonthDay":"05-01","endMonthDay":"10-01"
    String? startMonthDay;
    String? endMonthDay;
    final range = j['dateRange'];
    if (range is Map) {
      startMonthDay = (range['start'] ?? range['startDate'] ?? '').toString().trim();
      endMonthDay = (range['end'] ?? range['endDate'] ?? '').toString().trim();
    } else {
      startMonthDay = (j['startMonthDay'] ?? '').toString().trim();
      endMonthDay = (j['endMonthDay'] ?? '').toString().trim();
    }
    if (!_isMonthDay(startMonthDay) || !_isMonthDay(endMonthDay)) {
      startMonthDay = null;
      endMonthDay = null;
    }

    return BellScheduleTemplate(
      id: id,
      school: school,
      name: rawName,
      description: (j['description'] ?? '').toString().trim(),
      slots: slots,
      startMonthDay: startMonthDay,
      endMonthDay: endMonthDay,
    );
  }

  static bool _isMonthDay(String? value) {
    if (value == null || value.isEmpty) return false;
    final m = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(value);
    if (m == null) return false;
    final month = int.tryParse(m.group(1)!);
    final day = int.tryParse(m.group(2)!);
    return month != null && month >= 1 && month <= 12 && day != null && day >= 1 && day <= 31;
  }
}

/// 一所学校的模板集合。
class SchoolBellTemplates {
  const SchoolBellTemplates({
    required this.school,
    required this.templates,
    this.note = '',
  });

  final String school;
  final String note;
  final List<BellScheduleTemplate> templates;

  factory SchoolBellTemplates.fromJson(Map<String, dynamic> j) {
    final school = (j['school'] ?? j['name'] ?? '').toString().trim();
    if (school.isEmpty) {
      throw const FormatException('模板学校名不能为空');
    }
    final rawTemplates = j['templates'];
    final templates = <BellScheduleTemplate>[];
    if (rawTemplates is List) {
      for (final item in rawTemplates) {
        if (item is Map) {
          templates.add(
            BellScheduleTemplate.fromJson(
              Map<String, dynamic>.from(item),
              school: school,
            ),
          );
        }
      }
    }
    if (templates.isEmpty) {
      throw FormatException('学校「$school」没有模板');
    }
    return SchoolBellTemplates(
      school: school,
      note: (j['note'] ?? '').toString().trim(),
      templates: templates,
    );
  }
}

/// 模板目录（GitHub 上的一个 JSON 文件）。
class BellScheduleTemplateCatalog {
  const BellScheduleTemplateCatalog({
    required this.schools,
    this.version = 1,
    this.updatedAt = '',
  });

  final int version;
  final String updatedAt;
  final List<SchoolBellTemplates> schools;

  bool get isEmpty => schools.isEmpty;

  Iterable<BellScheduleTemplate> get allTemplates =>
      schools.expand((school) => school.templates);

  factory BellScheduleTemplateCatalog.fromJson(Map<String, dynamic> j) {
    final raw = j['schools'];
    if (raw is! List) {
      throw const FormatException('模板文件缺少 schools 数组');
    }
    final schools = <SchoolBellTemplates>[];
    for (final item in raw) {
      if (item is Map) {
        schools.add(SchoolBellTemplates.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    if (schools.isEmpty) {
      throw const FormatException('模板文件里没有学校数据');
    }
    return BellScheduleTemplateCatalog(
      version: (j['version'] is num)
          ? (j['version'] as num).toInt()
          : int.tryParse('${j['version']}') ?? 1,
      updatedAt: (j['updatedAt'] ?? '').toString(),
      schools: schools,
    );
  }
}

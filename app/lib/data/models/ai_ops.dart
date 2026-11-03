import '../../core/utils/json_utils.dart';
import '../../core/utils/week_utils.dart';
import 'draft.dart' show pickNonEmpty, parseDayOfWeek;

/// 自然语言改课表时，大模型输出的「结构化操作」。
///
/// 关键设计：模型**不知道**数据库主键，所以定位一律用「课程名 + 时段特征」，
/// 由仓储层（[TimetableRepository]）负责解析成真实 ID。
/// 所有操作先进入预览列表，用户确认后才落库，避免模型幻觉直接破坏课表。
enum AiOpKind {
  addCourse,
  updateCourse,
  deleteCourse,
  addSession,
  updateSession,
  deleteSession,
  moveSession,

  /// 修改某一节**作息时间**的上下课时间（如「第 3 节改成 10:05 上课」）。
  ///
  /// 注意与 [updateSession] 的区别：这里改的是「第 N 节几点开始」这套
  /// 全校作息（`TimeSlot`），不是某门课的上课安排，因此不需要课程名。
  updatePeriod,

  /// 把整套作息整体平移若干分钟（如「下午的课整体推迟 10 分钟」）。
  shiftSchedule,
  unknown,
}

AiOpKind aiOpKindFromString(String? s) {
  switch ((s ?? '').trim().toLowerCase()) {
    case 'addcourse':
    case 'add_course':
    case '新增课程':
      return AiOpKind.addCourse;
    case 'updatecourse':
    case 'update_course':
    case '修改课程':
      return AiOpKind.updateCourse;
    case 'deletecourse':
    case 'delete_course':
    case 'remove_course':
    case '删除课程':
      return AiOpKind.deleteCourse;
    case 'addsession':
    case 'add_session':
    case '新增时段':
      return AiOpKind.addSession;
    case 'updatesession':
    case 'update_session':
    case '修改时段':
      return AiOpKind.updateSession;
    case 'deletesession':
    case 'delete_session':
    case 'remove_session':
    case '删除时段':
      return AiOpKind.deleteSession;
    case 'movesession':
    case 'move_session':
    case 'swap':
    case '调课':
      return AiOpKind.moveSession;
    case 'updateperiod':
    case 'update_period':
    case 'updateperiodtime':
    case 'update_period_time':
    case '修改作息':
    case '修改作息时间':
    case '修改节次时间':
      return AiOpKind.updatePeriod;
    case 'shiftschedule':
    case 'shift_schedule':
    case 'shifttimes':
    case 'shift_times':
    case '调整作息':
    case '整体平移':
    case '整体调整作息':
      return AiOpKind.shiftSchedule;
    default:
      return AiOpKind.unknown;
  }
}

String aiOpKindLabel(AiOpKind k) {
  switch (k) {
    case AiOpKind.addCourse:
      return '新增课程';
    case AiOpKind.updateCourse:
      return '修改课程';
    case AiOpKind.deleteCourse:
      return '删除课程';
    case AiOpKind.addSession:
      return '新增时段';
    case AiOpKind.updateSession:
      return '修改时段';
    case AiOpKind.deleteSession:
      return '删除时段';
    case AiOpKind.moveSession:
      return '调课';
    case AiOpKind.updatePeriod:
      return '修改作息时间';
    case AiOpKind.shiftSchedule:
      return '整体调整作息';
    case AiOpKind.unknown:
      return '未知操作';
  }
}

/// 一条待执行的课表变更。
class AiOp {
  final AiOpKind kind;

  /// 目标课程名（模型能提供的唯一定位信息）。
  final String courseName;

  /// 操作参数，结构随 [kind] 变化，详见各 op 的约定。
  final Map<String, dynamic> args;

  /// 给用户看的一句话说明，如「把高等数学改为单周上课」。
  final String summary;

  const AiOp({
    required this.kind,
    required this.courseName,
    this.args = const {},
    this.summary = '',
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'courseName': courseName,
        'args': args,
        'summary': summary,
      };

  /// 从模型输出解析。兼容 `kind`/`type`/`action` 与 `courseName`/`course`/`name` 等别名。
  static AiOp fromAiJson(Map<String, dynamic> j) {
    final kind = aiOpKindFromString(
      pickNonEmpty([asString(j['kind']), asString(j['type']), asString(j['action'])]),
    );
    final courseName = pickNonEmpty([
      asString(j['courseName']),
      asString(j['course']),
      asString(j['target']),
      asString(j['name']),
    ]);
    final args = asMap(j['args']).isNotEmpty
        ? asMap(j['args'])
        : asMap(j['params']).isNotEmpty
            ? asMap(j['params'])
            : asMap(j['payload']);
    return AiOp(
      kind: kind,
      courseName: courseName,
      args: args.isNotEmpty ? args : j,
      summary: pickNonEmpty([asString(j['summary']), asString(j['description']), asString(j['reason'])]),
    );
  }

  /// 人类可读描述，用于预览列表。
  String describe() {
    final label = aiOpKindLabel(kind);
    if (summary.isNotEmpty) return summary;
    return courseName.isEmpty ? label : '$label：$courseName';
  }

  // ---------------------------------------------------------------- 参数读取
  int? get dayOfWeek => parseDayOfWeek(args['dayOfWeek'] ?? args['day'] ?? args['weekday']);
  int? get startPeriod => asInt(args['startPeriod']) ?? asInt(args['start']) ?? asInt(args['period']);
  int? get endPeriod => asInt(args['endPeriod']) ?? asInt(args['end']) ?? startPeriod;

  /// 周次：优先显式列表，其次字符串区间，再次单双周标记。
  List<int>? get weeks {
    final raw = args['weeks'];
    if (raw is List) {
      final list = raw.map(asInt).whereType<int>().where((w) => w > 0).toSet().toList()..sort();
      if (list.isNotEmpty) return list;
    }
    final text = pickNonEmpty([
      asString(args['weeks']),
      asString(args['weekRange']),
      asString(args['weekType']),
    ]);
    if (text.isEmpty) return null;
    final parsed = parseWeeks(text);
    return parsed.isEmpty ? null : parsed;
  }

  String? get location {
    final s = pickNonEmpty([asString(args['location']), asString(args['place']), asString(args['classroom'])]);
    return s.isEmpty ? null : s;
  }

  String? get teacher {
    final s = pickNonEmpty([asString(args['teacher']), asString(args['instructor'])]);
    return s.isEmpty ? null : s;
  }

  // ------------------------------------------------- 作息（节次时间）参数读取

  /// 要修改的作息节次（第几节）。兼容 `period` / `section` / `节次`。
  ///
  /// 只用于改作息的操作（[AiOpKind.updatePeriod]）；数值是否合法由应用层校验。
  int? get period => asInt(args['period'] ?? args['section'] ?? args['节次']);

  /// 目标作息方案名（如「夏季作息」）。为空表示由应用层挑选默认方案。
  /// 兼容 `scheduleName` / `schedule` / `scheduleId` / `作息` / `方案`。
  String? get scheduleName {
    final s = pickNonEmpty([
      asString(args['scheduleName']),
      asString(args['schedule']),
      asString(args['scheduleId']),
      asString(args['作息']),
      asString(args['方案']),
    ]);
    return s.isEmpty ? null : s;
  }

  /// 该节改成几点开始（`HH:mm` 或「8点10分」这类口语写法，由应用层规范化）。
  ///
  /// `start` 有两种可能含义：`{"start":3}` 是节次，`{"start":"8:10"}` 是时间，
  /// 因此只在写法明显是时间时才采用。
  String? get startTime {
    for (final key in const ['startTime', '开始时间', 'start']) {
      final s = _timeLike(args[key]);
      if (s != null) return s;
    }
    return null;
  }

  /// 该节改成几点结束（`HH:mm` 或口语写法）。`end` 同样可能是节次，需判断。
  String? get endTime {
    for (final key in const ['endTime', '结束时间', 'end']) {
      final s = _timeLike(args[key]);
      if (s != null) return s;
    }
    return null;
  }

  /// 整体平移的分钟数：正数=推迟，负数=提前。兼容 `minutes` / `shiftMinutes`
  /// / `offsetMinutes` / `分钟` / `偏移分钟`，也识别「提前 10 分钟」这类口语写法。
  int? get shiftMinutes {
    final raw = args['minutes'] ??
        args['shiftMinutes'] ??
        args['offsetMinutes'] ??
        args['分钟'] ??
        args['偏移分钟'];
    final n = _signedInt(raw);
    if (n == null) return null;
    final dir = asString(args['direction'] ?? args['方向']).trim().toLowerCase();
    if (dir == 'earlier' || dir == 'before' || dir == '提前' || dir == '前移') {
      return -n.abs();
    }
    if (dir == 'later' || dir == 'after' || dir == '推迟' || dir == '延后') {
      return n.abs();
    }
    return n;
  }

  /// 整体平移的起始节次（可选）：只平移 [fromPeriod]~[toPeriod] 范围内的节次。
  ///
  /// 「下午的课推迟 10 分钟」这类说法，模型会按作息把「下午」换算成节次范围，
  /// 例如下午是第 5-8 节 → `{"minutes":10,"fromPeriod":5,"toPeriod":8}`；
  /// 不写范围表示整套作息一起平移。
  int? get fromPeriod {
    for (final key in const ['fromPeriod', 'startPeriod', 'from', '起始节次']) {
      final n = asInt(args[key]);
      if (n != null && n > 0) return n;
    }
    return null;
  }

  /// 整体平移的结束节次（可选）。
  int? get toPeriod {
    for (final key in const ['toPeriod', 'endPeriod', 'to', '结束节次']) {
      final n = asInt(args[key]);
      if (n != null && n > 0) return n;
    }
    return null;
  }

  /// `match` / `from` 子对象，用于精确定位要改的时段。
  Map<String, dynamic> get matchSpec {
    for (final key in ['match', 'from', 'target', 'where', 'filter']) {
      final m = asMap(args[key]);
      if (m.isNotEmpty) return m;
    }
    return args;
  }

  /// `patch` / `set` / `to` 子对象，用于描述改成什么。
  Map<String, dynamic> get patchSpec {
    for (final key in ['patch', 'set', 'to', 'changes', 'new']) {
      final m = asMap(args[key]);
      if (m.isNotEmpty) return m;
    }
    return args;
  }
}

/// 不需要课程名也能执行的操作类型。
///
/// 改作息（[AiOpKind.updatePeriod] / [AiOpKind.shiftSchedule]）作用于全校作息，
/// 不针对某门课，因此不能像课程操作那样要求 courseName。
const Set<AiOpKind> _kindsWithoutCourseName = {
  AiOpKind.addCourse,
  AiOpKind.updatePeriod,
  AiOpKind.shiftSchedule,
};

/// 一次自然语言改课表的完整计划。
class AiEditPlan {
  /// 模型对整体意图的复述，如「已将高等数学调整为单周上课」。
  final String summary;

  final List<AiOp> ops;

  /// 解析过程中的告警（无法识别的操作、缺少定位信息等）。
  final List<String> warnings;

  /// 模型对用户的追问（信息不足或简称有歧义时使用，可为空）。
  ///
  /// 「一句话改课表」是对话式的：模型可以先不产出操作，而是反问
  /// 「你说的是哪一门课？」；用户回答后下一轮再生成方案。
  final String question;

  /// 追问的候选答案（供 UI 渲染成快捷回复按钮），可为空。
  final List<String> options;

  const AiEditPlan({
    this.summary = '',
    this.ops = const [],
    this.warnings = const [],
    this.question = '',
    this.options = const [],
  });

  bool get isEmpty => ops.isEmpty;

  /// 是否有需要用户回答的追问。
  bool get hasQuestion => question.trim().isNotEmpty;

  /// 从模型返回的 JSON 构建计划。
  static AiEditPlan fromAiJson(Map<String, dynamic> j) {
    final warnings = <String>[];
    final ops = <AiOp>[];
    for (final raw in asList(j['ops'])) {
      final op = AiOp.fromAiJson(asMap(raw));
      if (op.kind == AiOpKind.unknown) {
        warnings.add('忽略了一条无法识别的操作');
        continue;
      }
      if (op.courseName.isEmpty && !_kindsWithoutCourseName.contains(op.kind)) {
        warnings.add('忽略了一条未指明课程名的操作');
        continue;
      }
      ops.add(op);
    }
    return AiEditPlan(
      summary: pickNonEmpty([asString(j['summary']), asString(j['reply']), asString(j['message'])]),
      ops: ops,
      warnings: warnings,
      question: pickNonEmpty([
        asString(j['ask']),
        asString(j['question']),
        asString(j['clarify']),
        asString(j['needInfo']),
      ]),
      options: parseOptions(j['options'] ?? j['choices'] ?? j['candidates']),
    );
  }

  /// 解析候选答案数组：兼容字符串数组与 `{name/label/value}` 对象数组。
  static List<String> parseOptions(dynamic raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in asList(raw)) {
      String text = '';
      if (item is String) {
        text = item.trim();
      } else if (item is Map) {
        text = pickNonEmpty([
          asString(item['name']),
          asString(item['label']),
          asString(item['value']),
          asString(item['text']),
          asString(item['title']),
        ]);
      }
      if (text.isEmpty) continue;
      if (seen.add(text)) out.add(text);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'ops': ops.map((o) => o.toJson()).toList(),
        'warnings': warnings,
        'question': question,
        'options': options,
      };
}

/// 把可能是「时间」的字段读成字符串。
///
/// 只接受明显是时间的写法（含冒号，或中文「点/时/分」），
/// 这样 `{"start":3}` 这种节次不会被误当成时间。
String? _timeLike(dynamic v) {
  final s = asString(v);
  if (s.isEmpty) return null;
  if (s.contains(':') ||
      s.contains('：') ||
      s.contains('点') ||
      s.contains('时') ||
      s.contains('分')) {
    return s;
  }
  return null;
}

/// 读取带符号的整数：兼容 `-10`、`"-10"`、「提前 10 分钟」等写法。
int? _signedInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  final s = asString(v);
  if (s.isEmpty) return null;
  final m = RegExp(r'([+-]?)\s*(\d+)').firstMatch(s);
  if (m == null) return null;
  final n = int.tryParse(m.group(2)!);
  if (n == null) return null;
  final negative = m.group(1) == '-' || s.contains('提前') || s.contains('前移');
  return negative ? -n : n;
}

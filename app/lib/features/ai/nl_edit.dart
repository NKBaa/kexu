/// 「自然语言 → 课表操作计划」的编排与解析。
///
/// 模型不知道数据库主键，因此所有操作都用「课程名 + 时段特征」定位；
/// 解析结果复用数据层的 [AiEditPlan] / [AiOp] 契约，UI 只负责展示与确认。
/// 解析阶段只做**结构容错与补全**，不会执行任何写库动作。
library;

import '../../core/utils/json_utils.dart';
import '../../data/models/ai_ops.dart';
import '../../data/models/draft.dart' show pickNonEmpty;
import '../../data/models/timetable.dart';
import 'ai_client.dart';
import 'ai_exception.dart';
import 'course_matcher.dart';
import 'now_context.dart';
import 'prompts.dart';

export 'prompts.dart' show buildTimetableContext;

/// 一次「自然语言 → 方案」的完整回合。
///
/// UI 需要 [rawOutput] 把模型回复记入多轮对话历史：否则下一轮模型会忘记
/// 自己上一轮反问过什么，用户回答「高等数学（上）」时它也无从衔接。
class NlEditTurn {
  const NlEditTurn({
    required this.plan,
    required this.rawOutput,
    required this.instruction,
  });

  /// 解析并做过课程名归一后的计划。
  final AiEditPlan plan;

  /// 模型返回的原始文本（可能含 ask / options / ops）。
  final String rawOutput;

  /// 本轮的原始用户指令。
  final String instruction;
}

/// 自然语言改课表服务。
class NlEditService {
  // 命名参数名对外是 client，字段是私有的，无法使用 initializing formal。
  // ignore: prefer_initializing_formals
  NlEditService({required AiClient client}) : _client = client;

  final AiClient _client;

  /// 把用户的自然语言指令翻译成结构化操作计划，并返回模型原始文本。
  ///
  /// 不直接修改课表：返回的 [NlEditTurn.plan] 需要 UI 让用户确认后再交给仓储执行。
  /// [history] 是多轮对话历史（用户原话 + 模型原始回复），会原样带给模型。
  Future<NlEditTurn> planTurn(
    String instruction, {
    required Timetable current,
    DateTime? now,
    List<AiChatMessage> history = const [],
    List<AiImageAttachment> images = const [],
  }) async {
    final text = instruction.trim();
    if (text.isEmpty) {
      throw AiException.invalidInput('请先输入要修改的内容，例如「把高等数学改成单周上课」。');
    }
    final nowContext = NowContext.fromTimetable(current, now: now);
    final prompt = buildNlEditPrompt(
      instruction: text,
      current: current,
      now: nowContext,
      history: history,
    );
    final raw = images.isEmpty
        ? await _client.chatMessages(
            [...history, AiChatMessage.user(prompt)],
            system: aiSystemPrompt,
          )
        : await _client.chatWithImages(
            images: images,
            prompt: prompt,
            system: aiSystemPrompt,
            history: history,
          );
    return NlEditTurn(
      plan: _normalizeCourseNames(parseModelOutput(raw), current),
      rawOutput: raw,
      instruction: text,
    );
  }

  /// 用本地课表把模型给出的课程名归一成**规范全名**。
  ///
  /// 模型知道「高数」就是「高等数学」，但它输出的是用户原话里的简称；
  /// 应用层（[AiApplyService]）是按名称找课程的，简称未必命中。
  /// 因此这里做一次本地校验：
  /// - 唯一命中：把 courseName 改写成课表里的规范全名；
  /// - 零命中 / 多命中：移除该操作，生成 question（多命中时把候选放进 options），
  ///   让 UI 反问用户，而不是把一条注定失败的操作丢给应用层。
  ///
  /// 模型自己已经给了 ask 时保留它的追问（只补充候选/告警）。
  static AiEditPlan _normalizeCourseNames(AiEditPlan plan, Timetable current) {
    if (plan.ops.isEmpty) return plan;

    final kept = <AiOp>[];
    final problems = <String>[];
    final suggestions = <String>[];
    var renamed = false;

    for (final op in plan.ops) {
      // 新增课程的目标是「课表里还没有的课」，不做归一。
      if (op.kind == AiOpKind.addCourse) {
        kept.add(op);
        continue;
      }
      final keyword = op.courseName.trim();
      if (keyword.isEmpty) {
        kept.add(op);
        continue;
      }

      final candidates = CourseMatcher.match(keyword, current.courses);
      if (candidates.length == 1) {
        final canonical = candidates.single.name;
        if (canonical != op.courseName) {
          renamed = true;
          kept.add(AiOp(
            kind: op.kind,
            courseName: canonical,
            args: op.args,
            summary: op.summary,
          ));
        } else {
          kept.add(op);
        }
        continue;
      }

      if (candidates.isEmpty) {
        problems.add('课表里没有找到「$keyword」，请确认课程名，或先把它添加进课表。');
      } else {
        final names = candidates.map((c) => c.name).toList();
        problems.add('「$keyword」可能对应多门课：${names.join('、')}，请说明要改哪一门。');
        suggestions.addAll(names);
      }
    }

    if (problems.isEmpty) {
      // 只有课程名被归一（数量没变）时也要返回新计划，否则改写就丢了。
      if (!renamed) return plan;
      return AiEditPlan(
        summary: plan.summary,
        ops: kept,
        warnings: plan.warnings,
        question: plan.question,
        options: plan.options,
      );
    }

    final warnings = <String>[
      ...plan.warnings,
      for (final p in problems) '已移除无法确定课程的操作：$p',
    ];
    final question = plan.hasQuestion ? plan.question : problems.join('\n');
    final options = plan.options.isNotEmpty ? plan.options : _dedupeStrings(suggestions);

    return AiEditPlan(
      summary: plan.summary,
      ops: kept,
      warnings: _dedupeStrings(warnings),
      question: question,
      options: options,
    );
  }

  /// 从模型原始文本解析操作计划（不发起网络请求，公开便于测试）。
  ///
  /// 兼容三种输出形态：
  /// - 标准 `{"summary":"...","ops":[...]}`；
  /// - 直接输出操作数组 `[...]`；
  /// - 单个操作对象 `{"kind":"deleteCourse","courseName":"..."}`。
  ///
  /// 模型用自然语言澄清/拒绝时（没有 JSON），返回只带 summary 的空计划，
  /// 让 UI 能把模型的话原样告诉用户，而不是直接报错。
  static AiEditPlan parseModelOutput(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) {
      throw AiException.parse('模型没有返回任何内容，请重试或换一个模型。');
    }

    final block = extractJsonBlock(text);
    if (block == null) {
      // 纯文本回复（如「请补充要改哪一门课」）不是错误，交给 UI 展示。
      if (text.contains('{') || text.contains('[')) {
        throw AiException.parse(
          '模型输出里找不到可解析的 JSON，请重试。',
          rawOutput: text,
        );
      }
      return AiEditPlan(
        summary: _oneLine(text),
        warnings: const ['模型没有返回结构化操作，已原样显示它的回复'],
      );
    }

    final decoded = tryDecodeJson(block);
    if (decoded == null) {
      throw AiException.parse(
        '模型输出的 JSON 格式有误（可能存在多余逗号或未转义字符），请重试。',
        rawOutput: block,
      );
    }

    final planJson = _toPlanJson(decoded, block);
    final base = AiEditPlan.fromAiJson(planJson);
    return _postProcess(base);
  }

  /// 把各种可能的 JSON 形态整理成 `{"summary":..., "ops":[...]}`。
  static Map<String, dynamic> _toPlanJson(dynamic decoded, String rawBlock) {
    if (decoded is List) {
      return <String, dynamic>{'ops': decoded};
    }
    if (decoded is! Map) {
      throw AiException.parse('模型输出的 JSON 既不是对象也不是数组，无法识别。', rawOutput: rawBlock);
    }
    final j = Map<String, dynamic>.from(decoded);

    // 有的模型会把结果再包一层：{"data": {"ops": [...]}}
    for (final wrapper in const ['data', 'result', 'plan', 'response', 'output']) {
      final inner = j[wrapper];
      if (inner is Map && _hasOpsKey(Map<String, dynamic>.from(inner))) {
        final merged = Map<String, dynamic>.from(inner);
        final outerSummary = pickNonEmpty([
          asString(j['summary']),
          asString(j['reply']),
          asString(j['message']),
        ]);
        if (outerSummary.isNotEmpty && asString(merged['summary']).isEmpty) {
          merged['summary'] = outerSummary;
        }
        // 追问字段偶尔被放在包裹层，搬运进内层后再递归。
        _carryAskFields(j, merged);
        // 内层可能用 operations/actions 等别名，递归再归一化一次。
        return _toPlanJson(merged, rawBlock);
      }
      if (inner is String) {
        final nested = tryDecodeJson(inner);
        if (nested != null) {
          try {
            return _toPlanJson(nested, rawBlock);
          } on AiException {
            // 内层不是计划就忽略，继续尝试外层
          }
        }
      }
    }

    // 直接把操作列表放在别的键名下
    for (final key in const ['operations', 'actions', 'edits', 'changes', 'list']) {
      final v = j[key];
      if (v is List) {
        final summary = pickNonEmpty([
          asString(j['summary']),
          asString(j['reply']),
          asString(j['message']),
        ]);
        return <String, dynamic>{
          if (summary.isNotEmpty) 'summary': summary,
          'ops': v,
          ..._askFields(j),
        };
      }
    }

    // 统一 ops 键名（operations/actions 等别名在数据层不会被识别）
    if (j['ops'] is! List) {
      for (final key in const ['operations', 'actions', 'edits', 'changes', 'list']) {
        final v = j[key];
        if (v is List) {
          j['ops'] = v;
          break;
        }
      }
    }
    if (j['ops'] is List) {
      final summary = pickNonEmpty([
        asString(j['summary']),
        asString(j['reply']),
        asString(j['message']),
      ]);
      if (summary.isNotEmpty) j['summary'] = summary;
      return j;
    }

    // 单个操作对象
    if (j.containsKey('kind') || j.containsKey('type') || j.containsKey('action')) {
      return <String, dynamic>{
        if (asString(j['summary']).isNotEmpty) 'summary': j['summary'],
        'ops': <dynamic>[j],
        ..._askFields(j),
      };
    }

    // 只有 summary / reply / ask 的「无法执行」回复
    final summary = pickNonEmpty([
      asString(j['summary']),
      asString(j['reply']),
      asString(j['message']),
      asString(j['error']),
    ]);
    final askFields = _askFields(j);
    if (summary.isNotEmpty || askFields.isNotEmpty) {
      return <String, dynamic>{
        'summary': summary,
        'ops': const <dynamic>[],
        ...askFields,
      };
    }

    throw AiException.parse(
      '模型输出的 JSON 里没有 ops 数组，也没有可识别的操作字段。',
      rawOutput: rawBlock,
    );
  }

  static bool _hasOpsKey(Map<String, dynamic> j) =>
      j['ops'] is List || j['operations'] is List || j['actions'] is List;

  /// 从 JSON 里提取追问字段，统一成 `ask` / `options` 两个键。
  static Map<String, dynamic> _askFields(Map<String, dynamic> j) {
    final out = <String, dynamic>{};
    for (final key in const ['ask', 'question', 'clarify', 'needInfo']) {
      if (j[key] != null) {
        out['ask'] = j[key];
        break;
      }
    }
    for (final key in const ['options', 'choices', 'candidates']) {
      if (j[key] != null) {
        out['options'] = j[key];
        break;
      }
    }
    return out;
  }

  /// 把外层包裹里的追问字段搬运到内层（内层已有时不覆盖）。
  static void _carryAskFields(Map<String, dynamic> from, Map<String, dynamic> to) {
    final ask = _askFields(from);
    if (!to.containsKey('ask') &&
        !to.containsKey('question') &&
        !to.containsKey('clarify') &&
        !to.containsKey('needInfo') &&
        ask.containsKey('ask')) {
      to['ask'] = ask['ask'];
    }
    if (!to.containsKey('options') &&
        !to.containsKey('choices') &&
        !to.containsKey('candidates') &&
        ask.containsKey('options')) {
      to['options'] = ask['options'];
    }
  }

  /// 结构解析后的语义校验与补全。
  static AiEditPlan _postProcess(AiEditPlan base) {
    final warnings = <String>[...base.warnings];
    final ops = <AiOp>[];

    const maxOps = 100;
    final limited = base.ops.length > maxOps ? base.ops.sublist(0, maxOps) : base.ops;
    if (base.ops.length > maxOps) {
      warnings.add('操作过多（${base.ops.length} 条），已只保留前 $maxOps 条');
    }

    for (final op in limited) {
      final fixed = _repairOp(op, warnings);
      if (fixed == null) continue;
      // 先用模型原始结构校验（定位信息必须来自 match），再平铺 patch 方便消费方读取。
      if (!_validateOp(fixed, warnings)) continue;
      ops.add(_flattenPatch(fixed));
    }

    if (ops.isEmpty && !base.hasQuestion) {
      warnings.add('模型没有给出任何可执行操作，请确认指令是否明确或补充信息后重试。');
    }

    var summary = base.summary.trim();
    if (summary.isEmpty && ops.isNotEmpty) {
      summary = ops.first.describe();
    }

    return AiEditPlan(
      summary: summary,
      ops: ops,
      warnings: _dedupeStrings(warnings),
      question: base.question,
      options: base.options,
    );
  }

  /// 把 `patch` 子对象里的字段平铺到 args 顶层。
  ///
  /// 数据层的 [AiOp] 提供了 `patchSpec`，但部分消费方（如应用服务）习惯直接用
  /// `op.weeks` / `op.location` 等顶层 getter。这里做一次无损平铺：
  /// `match` / `patch` 原样保留，因此两种读取方式都能拿到正确值。
  static AiOp _flattenPatch(AiOp op) {
    if (op.kind != AiOpKind.updateSession &&
        op.kind != AiOpKind.moveSession &&
        op.kind != AiOpKind.updatePeriod &&
        op.kind != AiOpKind.shiftSchedule) {
      return op;
    }
    final patch = op.patchSpec;
    if (patch.isEmpty || identical(patch, op.args)) return op;
    return AiOp(
      kind: op.kind,
      courseName: op.courseName,
      args: <String, dynamic>{...op.args, ...patch},
      summary: op.summary,
    );
  }

  /// 补全模型常见遗漏：addCourse 忘了 courseName（写在 args.name 里）。
  static AiOp? _repairOp(AiOp op, List<String> warnings) {
    if (op.kind == AiOpKind.addCourse && op.courseName.trim().isEmpty) {
      final name = pickNonEmpty([
        asString(op.args['name']),
        asString(op.args['courseName']),
        asString(op.args['课程名']),
      ]);
      if (name.isEmpty) {
        warnings.add('忽略了一条未指明课程名的新增课程操作');
        return null;
      }
      return AiOp(
        kind: op.kind,
        courseName: name,
        args: op.args,
        summary: op.summary,
      );
    }
    return op;
  }

  /// 校验操作是否带够定位信息；返回 false 表示该操作无法执行，已记入 warnings。
  static bool _validateOp(AiOp op, List<String> warnings) {
    switch (op.kind) {
      case AiOpKind.addCourse:
        return true;
      case AiOpKind.updateCourse:
        if (!_hasPatchValues(op.args)) {
          warnings.add('「${op.courseName}」的修改操作没有说明要改什么，已忽略');
          return false;
        }
        return true;
      case AiOpKind.addSession:
        if (!_hasTimeLocator(op.args) && op.weeks == null && !_hasSessionList(op.args)) {
          warnings.add('「${op.courseName}」的新增时段缺少星期/节次信息，已忽略');
          return false;
        }
        return true;
      case AiOpKind.updateSession:
      case AiOpKind.deleteSession:
      case AiOpKind.moveSession:
        if (!_hasLocator(op.matchSpec)) {
          warnings.add('「${op.courseName}」的时段操作缺少定位信息（星期/节次），已忽略');
          return false;
        }
        if (op.kind != AiOpKind.deleteSession && !_hasPatch(op.args)) {
          warnings.add('「${op.courseName}」的时段操作没有说明要改成什么，已忽略');
          return false;
        }
        return true;
      case AiOpKind.deleteCourse:
        return true;
      case AiOpKind.updatePeriod: {
        // 改作息不针对某门课，只需要「第几节 + 改成什么时间」。
        // 模型可能把新时间写在 patch 里，校验前先平铺一次。
        final flat = _flattenPatch(op);
        final period = flat.period;
        if (period == null || period <= 0) {
          warnings.add('修改作息的操作缺少节次（第几节），已忽略');
          return false;
        }
        if (flat.startTime == null && flat.endTime == null) {
          warnings.add('修改作息的操作没有说明第$period节改成什么时间，已忽略');
          return false;
        }
        return true;
      }
      case AiOpKind.shiftSchedule: {
        final flat = _flattenPatch(op);
        final minutes = flat.shiftMinutes;
        if (minutes == null || minutes == 0) {
          warnings.add('整体调整作息的操作缺少要平移的分钟数，已忽略');
          return false;
        }
        final from = flat.fromPeriod;
        final to = flat.toPeriod;
        if (from != null && to != null && from > to) {
          warnings.add('整体调整作息的节次范围不合法（第$from-$to节），已忽略');
          return false;
        }
        return true;
      }
      case AiOpKind.unknown:
        return false;
    }
  }

  /// 时间定位字段：必须有星期或节次，光有地点不算（新增时段必须能落到格子）。
  static bool _hasTimeLocator(Map<String, dynamic> spec) {
    for (final key in const [
      'dayOfWeek',
      'day',
      'weekday',
      'startPeriod',
      'start',
      'period',
      'endPeriod',
      'end',
    ]) {
      final v = spec[key];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      return true;
    }
    return false;
  }

  /// 定位字段：只要出现星期、节次、周次、地点之一，就认为能定位到某个时段。
  static bool _hasLocator(Map<String, dynamic> spec) {
    for (final key in const [
      'dayOfWeek',
      'day',
      'weekday',
      'startPeriod',
      'start',
      'period',
      'endPeriod',
      'end',
      'weeks',
      'weekRange',
      'weekType',
      'location',
      'place',
      'classroom',
    ]) {
      final v = spec[key];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is List && v.isEmpty) continue;
      return true;
    }
    return false;
  }

  /// 是否描述了「改成什么」：出现 patch/set/to 等子对象；扁平写法下则看是否有具体值字段。
  static bool _hasPatch(Map<String, dynamic> args) {
    for (final key in const ['patch', 'set', 'to', 'changes', 'new']) {
      final v = args[key];
      if (v is Map && v.isNotEmpty) return true;
    }
    // 只给了 match 却没给 patch，说明模型没说改成什么。
    if (args.containsKey('match') || args.containsKey('from')) return false;
    return _hasLocator(args) || _hasPatchValues(args);
  }

  /// 课程/时段属性字段（用于判断「要改成什么」是否为空）。
  static bool _hasPatchValues(Map<String, dynamic> args) {
    for (final key in const ['patch', 'set', 'to', 'changes', 'new']) {
      final v = args[key];
      if (v is Map && v.isNotEmpty) return true;
    }
    for (final key in const [
      'name',
      'teacher',
      'instructor',
      'courseCode',
      'code',
      'credit',
      'credits',
      'note',
      'remark',
      'location',
      'place',
      'classroom',
      'dayOfWeek',
      'day',
      'weekday',
      'startPeriod',
      'start',
      'period',
      'endPeriod',
      'end',
      'weeks',
      'weekRange',
      'weekType',
    ]) {
      final v = args[key];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is List && v.isEmpty) continue;
      if (v is Map && v.isEmpty) continue;
      return true;
    }
    return false;
  }

  /// addSession 是否直接给了 sessions 数组。
  static bool _hasSessionList(Map<String, dynamic> args) {
    final v = args['sessions'] ?? args['times'] ?? args['periods'];
    return v is List && v.isNotEmpty;
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

  static String _oneLine(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// AI 提示词（中文）。
///
/// 所有提示词都遵循同一套约定：
/// 1. 只输出严格 JSON，不要 markdown 代码块与解释文字；
/// 2. 周次一律用显式整数数组（不输出「1-16 周」「单周」这种有损写法）；
/// 3. 信息不足时宁可在 `note` 里说明，也不要编造。
library;

import '../../data/models/timetable.dart';
import 'ai_message.dart';
import 'now_context.dart';

/// 通用系统提示词：约束输出风格。
const String aiSystemPrompt =
    '你是一个严谨的大学课表结构化助手。你的输出必须是严格、可解析的 JSON：'
    '不要使用 markdown 代码块，不要写注释，不要在 JSON 前后添加任何解释文字。'
    '所有周次都必须展开为显式整数数组（例如 [1,3,5,7]），不要输出「1-16周」这类字符串。'
    '所有信息必须以用户提供的内容为依据，不确定或看不清的内容宁可留空并在 note 中说明，'
    '绝对不要编造、猜测或补全不存在的课程、时间、地点。';

/// 「图片 → 课表」提示词。
///
/// [totalWeeks] 是学期总周数，用于把「单周/双周/未标注周次」展开成显式数组。
/// [extraHint] 是用户补充的说明（如「这是 2025 秋季学期，共 18 周」），优先级高于图片推断。
/// [imageCount] 是本次请求一起发送的图片张数，[imageOffset] 是这批图片之前已发送的张数：
/// 一次给多张图时（分页截图、单周/双周两张图）提示词会要求模型合并成一份课表；
/// 分批请求时用 offset 告诉模型这批图在整组图片中的位置。
String buildImageToTimetablePrompt({
  required int totalWeeks,
  String? extraHint,
  int imageCount = 1,
  int imageOffset = 0,
}) {
  final weeks = totalWeeks < 1 ? 16 : totalWeeks;
  final hint = (extraHint ?? '').trim();
  final count = imageCount < 1 ? 1 : imageCount;
  final offset = imageOffset < 0 ? 0 : imageOffset;
  final from = offset + 1;
  final to = offset + count;
  final buffer = StringBuffer()
    ..writeln('你在帮一名中国大学生把「课表截图 / 照片」识别成结构化课程数据。')
    ..writeln()
    ..writeln('图片可能是教务系统网页截图、手机 App 截图、Excel/表格截图，也可能是打印或手写的课表照片。')
    ..writeln();

  if (count > 1) {
    // 多图一次发送：模型能同时看到多张图，让它自己合并比客户端硬拼更准。
    buffer
      ..writeln('本次一次提供了 $count 张图片（第 $from-$to 张），它们属于同一份课表，'
          '请合并成一份课表后再输出：')
      ..writeln('  - 这些图片可能是同一张课表的分页/分屏截图（上下两半、左右两半），'
          '也可能是「单周」「双周」两张截图，或同一门课的不同部分；')
      ..writeln('  - 同一门课在所有图片中只输出一个 course 对象，跨图的时段合并进同一个 sessions 数组，'
          '不要重复输出同名课程；')
      ..writeln('  - 同一门课同一时段在多张图里重复出现时只保留一条，并把周次取并集；')
      ..writeln('  - 如果一张图是单周、另一张是双周：把同一时段的周次合并成完整数组，'
          '例如单周 [1,3,5,...,15] + 双周 [2,4,6,...,16] -> [1,2,3,...,16] 全周；')
      ..writeln('  - 只有明确是不同学期或不同人的课表时，才分开输出多个 course，'
          '并在各自 note 中说明原因。')
      ..writeln();
  } else if (offset > 0) {
    // 分批请求的续批：本批只有一张图，但它是整组图片里的一张。
    buffer
      ..writeln('本次是同一份课表的分批识别之一（第 $from 张图）：请只识别这张图里的课程，'
          '不要推测其他图片的内容，客户端会把多批结果合并。')
      ..writeln();
  }

  buffer
    ..writeln('识别规则：')
    ..writeln('1. 只提取课程信息，忽略表头（星期、节次、时间）、菜单、按钮、水印等非课程文字。')
    ..writeln('2. 如果图片明确是「某一天」的课表（如顶部有 2026-11-02、11月2日、今日课表），'
        '请在 JSON 顶层输出 "date":"YYYY-MM-DD"（没有年份就输出 "MM-DD"），'
        '并且只输出这一天当天的课程；sessions 的 dayOfWeek 按该日期换算，不要补全其他天。')
    ..writeln('   如果图片是整周课表，即使表头带日期，也不要输出 date。')
    ..writeln('3. 每门课输出一个 course 对象；同一门课一周上多次时合并为一个 course，'
        '用多个 sessions 表示（每个时段一个元素）。')
    ..writeln('4. dayOfWeek 用 1~7 表示周一到周日；图中没有写星期时，按时段所在列或图片日期推断'
        '（第一列通常是周一），并在 note 中说明这一推断。')
    ..writeln('5. startPeriod / endPeriod 用整数节次（从 1 开始）；占两格或三格的课按起止节填写，'
        'endPeriod 必须大于等于 startPeriod。')
    ..writeln('6. weeks 必须是显式整数数组，取值范围 1~$weeks：')
    ..writeln('   - 「1-8周」 -> [1,2,3,4,5,6,7,8]')
    ..writeln('   - 「单周」「1-15周(单)」 -> 该范围内的奇数周，如 [1,3,5,7,9,11,13,15]')
    ..writeln('   - 「双周」 -> 该范围内的偶数周，如 [2,4,6,8]')
    ..writeln('   - 「3-5,7-9周」 -> [3,4,5,7,8,9]')
    ..writeln('   - 图片没有标注周次 -> 填满 1~$weeks，并在 note 里写明「图片未标注周次，已按全部周次处理」')
    ..writeln('   - 图片标注了超过 $weeks 的周次 -> 截断到 $weeks')
    ..writeln('7. 信息必须来自图片：')
    ..writeln('   - 看不清或缺失的字段直接省略，不要猜测；')
    ..writeln('   - 绝对不要编造图片里没有的课程、教师、教室或周次；')
    ..writeln('   - 有疑问的地方写进该课程的 note（如「教师姓名模糊，未填写」「截图只显示到第 8 周」）；')
    ..writeln('   - 完全无法识别为课程的文字，直接忽略。')
    ..writeln('8. 不要输出颜色、字体、坐标、像素等样式信息。')
    ..writeln('9. 如果图片明显不是课表（例如聊天截图），返回 {"date":"","courses":[]}，'
        '并在 note 中说明原因。')
    ..writeln();

  if (hint.isNotEmpty) {
    buffer
      ..writeln('用户补充说明（优先级高于图片推断，请优先采纳）：')
      ..writeln(hint)
      ..writeln();
  }

  buffer
    ..writeln('只输出下面这一个 JSON 对象，不要任何多余文字：')
    ..writeln('{"date":"","courses":[{"name":"高等数学","teacher":"张三","courseCode":"MATH101",'
        '"credit":4,"note":"","sessions":[{"dayOfWeek":1,"startPeriod":1,"endPeriod":2,'
        '"weeks":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,$weeks],"location":"A101",'
        '"teacher":"张三"}]}]}')
    ..writeln()
    ..writeln('字段说明：')
    ..writeln('- date：可选；仅当图片是单日课表时输出，格式 YYYY-MM-DD 或 MM-DD；整周课表留空；')
    ..writeln('- courses：课程数组，可以包含 0~n 门课；')
    ..writeln('- name：课程名（必填，保留原始中文，不要翻译）；')
    ..writeln('- teacher：任课教师（可省略；同一门课不同时段的教师不同时，写在对应 session 里）；')
    ..writeln('- courseCode / credit：课程编号与学分（图片有则填，可省略）；')
    ..writeln('- note：不确定或需要提醒用户的信息（可省略）；')
    ..writeln('- sessions：该课程的上课时段数组，每项含 dayOfWeek、startPeriod、endPeriod、weeks，'
        '以及可选的 location、teacher。');
  return buffer.toString();
}

/// 「自然语言 → 结构化改课表操作」提示词。
///
/// [instruction] 是用户原话，[current] 是当前课表（会被压成紧凑文本）。
/// [now] 是「现在」的时间上下文：模型不知道今天几号，必须靠它把
/// 「明天」「下周三」换算成显式的 dayOfWeek + weeks。
/// [history] 是多轮对话历史：历史内容由 `AiClient.chatMessages` 作为独立
/// message 发送，这里只提示「这是多轮对话」，不重复拼接历史正文。
String buildNlEditPrompt({
  required String instruction,
  required Timetable current,
  NowContext? now,
  List<AiChatMessage> history = const [],
}) {
  final context = buildTimetableContext(current);
  final totalWeeks = current.semester.totalWeeks;
  final buffer = StringBuffer()
    ..writeln('你在帮一名大学生用「一句话」改课表。请把用户的自然语言指令翻译成结构化的操作计划。')
    ..writeln('你不能访问数据库，也拿不到课程 ID，因此只能用「课程名 + 时段特征」来定位要修改的对象。')
    ..writeln();

  if (history.isNotEmpty) {
    buffer
      ..writeln('这是一次多轮对话：用户之前的提问和你的回答见对话历史。')
      ..writeln('请结合历史理解下面这条指令；如果上一轮你已经反问过，这一轮用户的话就是对追问的回答。')
      ..writeln();
  }

  if (now != null) {
    buffer
      ..writeln(now.toPromptText())
      ..writeln();
  }

  buffer
    ..writeln('当前课表（这是唯一可依据的数据，用户说的课程名请优先对齐到这里的规范全名）：')
    ..writeln(context)
    ..writeln()
    ..writeln('用户指令：')
    ..writeln(instruction.trim())
    ..writeln()
    ..writeln('理解规则（口语容错）：')
    ..writeln('1. 用户会用很随意的白话、简称、倒装语序、错别字或不精确描述，'
        '只要意图能落到具体操作就执行，不要因为说法不规范而拒绝。')
    ..writeln('   例如「高数」=「高等数学」，「英语」=「大学英语」，「线代」=「线性代数」，'
        '「把高数挪到周三」= 调课时段。')
    ..writeln('2. courseName 优先写上面「当前课表」里的规范全名：用户用简称/别名/错别字时，'
        '先按语义对上课表里的课程再输出全名；课表里确实没有这门课时，不要编造，改用 ask 告诉用户没找到。')
    ..writeln('3. 同一简称可能命中多门课（如「高数」对应「高等数学（上）」「高等数学（下）」）时，'
        '用 ask 反问，并把候选课程名放进 options。')
    ..writeln('4. 不要为了反问而反问：信息足够就直接给出 ops；'
        '只有缺少「改哪门课」「改成什么」这类关键信息时才反问。')
    ..writeln()
    ..writeln('相对时间换算规则（用户说的今天/明天/本周/下周都必须按上面的「时间上下文」换算，不要凭空猜日期）：')
    ..writeln('1. 「今天/明天/后天/大后天」：先换算成具体日期，再写成 dayOfWeek（周一=1 … 周日=7）'
        '+ 该日期所在教学周的 weeks 显式数组。')
    ..writeln('   注意跨周：例如今天是第 9 周周日，「明天」是第 10 周周一，'
        'dayOfWeek 要写 1、weeks 要写第 10 周的编号，不能写第 9 周。')
    ..writeln('2. 「本周X」「这周X」= 当前教学周；「下周X」= 下一教学周；「下下周X」= 再下一周。'
        '周日一律用 7。')
    ..writeln('3. 「每周X」「每周都上」「一直上」：weeks 取 1~$totalWeeks 的完整数组。')
    ..writeln('4. 「上午/下午/晚上」按上面「今天各节次时间」映射到节次：'
        '上午 = 12:00 之前开始的节次，下午 = 12:00~18:00 开始的节次，晚上 = 18:00 之后开始的节次。')
    ..writeln('   用户没说具体节次时，取该时间段的第一节作为 startPeriod（例如「下午」→ 下午第一节），'
        '不要编造作息里不存在的节次。')
    ..writeln('5. 日期或周次超出学期范围（学期还没开始、已结束，或「下下周」超过第 $totalWeeks 周）时，'
        '不要输出该操作，改用 ask 说明超出范围。')
    ..writeln()
    ..writeln('可用的操作类型（kind 只能取以下之一）：')
    ..writeln('1. addCourse：新增一门课程。args 里需要 name，可选 teacher、courseCode、credit、note，')
    ..writeln('   以及 sessions（数组，元素格式同 addSession 的 args）。')
    ..writeln('2. updateCourse：修改课程本身的信息（改名、换教师、改学分、改备注），不涉及具体时段。')
    ..writeln('   args 用 patch 描述要改的字段，如 {"patch":{"teacher":"李四"}}。')
    ..writeln('3. deleteCourse：删除整门课程（连同所有时段）。args 可为空。')
    ..writeln('4. addSession：给已有课程增加一个时段。args 需要 dayOfWeek、startPeriod、endPeriod、weeks，')
    ..writeln('   可选 location、teacher。')
    ..writeln('5. updateSession：修改已有课程某个时段的属性（周次、节次、地点、教师）。')
    ..writeln('   args 用 match 定位旧时段，用 patch 描述新值：')
    ..writeln('   {"match":{"dayOfWeek":1,"startPeriod":1},"patch":{"weeks":[1,3,5,7]}}')
    ..writeln('6. deleteSession：删除某门课的一个时段。args 用 match 定位：')
    ..writeln('   {"match":{"dayOfWeek":1,"startPeriod":1}}')
    ..writeln('7. moveSession：把某个时段整体换到别的时间/地点。')
    ..writeln('   args 用 match 定位原时段，用 patch 写新值：')
    ..writeln('   {"match":{"dayOfWeek":1,"startPeriod":1},"patch":{"dayOfWeek":3,"startPeriod":5,"endPeriod":6}}')
    ..writeln('8. updatePeriod：修改某一节「作息时间」（全校统一的上课/下课时间），不需要 courseName。')
    ..writeln('   args 需要 period（第几节），可选 scheduleName（作息方案名）、startTime、endTime，时间写 HH:mm：')
    ..writeln('   {"period":3,"startTime":"10:05","endTime":"10:50"}')
    ..writeln('9. shiftSchedule：把整套作息、或其中一段节次整体平移若干分钟，不需要 courseName。')
    ..writeln('   args 需要 minutes（正数=推迟，负数=提前），可选 scheduleName、fromPeriod/toPeriod'
        '（只平移该节次范围）：')
    ..writeln('   {"minutes":10} 或 {"minutes":10,"fromPeriod":5,"toPeriod":8} 或 '
        '{"minutes":-5,"scheduleName":"夏季作息"}')
    ..writeln()
    ..writeln('作息时间 vs 课程时间的区分（很容易混淆，按下面的规则判断）：')
    ..writeln('1. 说的是「第 N 节几点上下课」「下午的课推迟 10 分钟」「夏季作息第 5 节改 14:30」'
        '这类「节次时间本身」，属于改作息：输出 updatePeriod / shiftSchedule，不要 courseName。'
        '「上午/下午/晚上的课」这类范围说法，先按上面的作息把范围换算成节次（如下午=第5-8节），'
        '再用 shiftSchedule 的 fromPeriod/toPeriod 限定，不要把所有节次都平移。')
    ..writeln('2. 说的是「把高数改到周三」「高数改成单周」「高数换教室」这类「某门课」的安排，'
        '属于改课程/时段：用上面的 1~7 号 kind，并带上 courseName。')
    ..writeln('3. 一句话里两种都有时（如「第 3 节推迟 5 分钟，并把高数挪到周四」），'
        '拆成多条 op 按执行顺序输出。')
    ..writeln()
    ..writeln('输出格式（只输出这一个 JSON 对象，不要 markdown、不要解释）：')
    ..writeln('{"summary":"把高等数学改成单周上课","ask":"","options":[],'
        '"ops":[{"kind":"updateSession","courseName":"高等数学",'
        '"args":{"match":{"dayOfWeek":1,"startPeriod":1},"patch":{"weeks":[1,3,5,7,9,11,13,15]}},'
        '"summary":"高等数学周一第1-2节改为单周"}]}')
    ..writeln('{"summary":"第3节改为10:05上课","ops":[{"kind":"updatePeriod",'
        '"args":{"period":3,"startTime":"10:05"},"summary":"第3节改为 10:05 上课"}]}')
    ..writeln()
    ..writeln('字段说明：')
    ..writeln('- summary：必填，一句话复述你的理解或方案；')
    ..writeln('- ask：可选，需要用户补充信息时的追问（例如「你说的是哪一门高数？」）；')
    ..writeln('- options：可选，配合 ask 使用，给出 1~4 个可直接点选的候选答案（字符串数组，可为空数组）；')
    ..writeln('- ops：操作数组；反问时可以输出空数组 []。不需要反问时不要输出 ask。')
    ..writeln()
    ..writeln('示例（模糊指令 → 合理操作或反问）：')
    ..writeln('- 用户「把明天的课都挪到下周」：先按时间上下文把「明天」换算成 dayOfWeek 与周次，'
        '再为每个命中的时段输出 moveSession（match 原时段，patch 写新周次）；'
        '明天没有课时 ops 为空，并在 summary 里说明「明天没有课」。')
    ..writeln('- 用户「高数改成单双周都上」：课表里只有「高等数学」一门时，直接输出 updateSession，'
        'weeks 写 1~$totalWeeks 的完整数组；若课表里同时有「高等数学（上）」「高等数学（下）」，'
        '用 ask 反问「你要改哪一门？」，options 放这两门课的全名。')
    ..writeln('- 用户「周三下午的课换到周四上午」：按作息把「下午」映射到下午第一节（如第5节）、'
        '「上午」映射到上午第一节（如第1节），match 周三第5节、patch 改成周四第1节；'
        '若周三下午没有课，ops 为空并用 ask 说明没找到。')
    ..writeln('- 用户「第 3 节改成 10:05 上课」：输出 updatePeriod，args 写 '
        '{"period":3,"startTime":"10:05"}，不需要 courseName。')
    ..writeln('- 用户「下午的课整体推迟 10 分钟」：按作息把「下午」换算成节次范围（如第5-8节），'
        '输出 shiftSchedule，args 写 {"minutes":10,"fromPeriod":5,"toPeriod":8}；'
        '用户说的是「所有课/整套作息」时才省略 fromPeriod/toPeriod；'
        '点名了某套作息（如「夏季作息」）就加 scheduleName。')
    ..writeln('- 用户「夏季作息第 5 节改 14:30」：输出 updatePeriod，args 写 '
        '{"period":5,"startTime":"14:30","scheduleName":"夏季作息"}。')
    ..writeln()
    ..writeln('强制规则：')
    ..writeln('1. 周次一律展开为显式整数数组，取值范围 1~$totalWeeks：')
    ..writeln('   「单周」-> 该范围内奇数周；「双周」-> 偶数周；「1-8,10-16周」-> 展开成具体数字。')
    ..writeln('   用户没说周次时不要输出 weeks 字段（表示沿用原值）。')
    ..writeln('2. 课程名优先使用「当前课表」里的规范全名；用户可以用简称/错别字，'
        '但输出的 courseName 必须是课表里的全名（课表里没有就不要输出该操作，改用 ask）。')
    ..writeln('3. 一条指令涉及多个动作时，把动作按执行顺序放进 ops；不要输出与指令无关的操作。')
    ..writeln('4. 定位不到具体时段时（例如用户只说「高数改成周三」而高数有多个时段），')
    ..writeln('   在 ask 或 summary 里说明歧义并只输出能确定的操作；宁可少改，也不要乱改。')
    ..writeln('5. 用户指令无法对应到任何课表操作时（如与课表无关、信息不足），输出')
    ..writeln('   {"summary":"……向用户说明原因或需补充的信息……","ops":[]}；需要用户回答时用 ask + options。')
    ..writeln('6. 不要编造当前课表里不存在的课程名；不要输出课程 ID、索引、颜色等数据。')
    ..writeln('7. match 里只需要写足以定位的字段：优先 dayOfWeek + startPeriod，必要时加 endPeriod。')
    ..writeln('8. 反问时 ask 要具体到用户能一句话回答（例如「你要改哪一门课？」），'
        '不要泛泛地说「信息不足」。')
    ..writeln('9. updatePeriod / shiftSchedule 是改全校作息，不需要 courseName；'
        '其余操作必须给出课程名。用户说的方案名（如「夏季作息」）写进 args.scheduleName。');
  return buffer.toString();
}

/// 把当前课表压成紧凑文本，供大模型理解。
///
/// 输出包含：学期信息、课程总数/时段总数、每门课的教师/学分/编号/备注、
/// 每个时段的星期/节次/周次/地点，以及一次性调整（调课/停课/补课）。
/// 为空课表时返回明确的「空」说明，避免模型把缺失误当成信息。
String buildTimetableContext(Timetable t) {
  final sem = t.semester;
  final buf = StringBuffer();
  buf.writeln('学期：${sem.name}（共 ${sem.totalWeeks} 周，第 1 周周一：${_formatDate(sem.startMonday)}）');
  buf.writeln(_schedulesContext(t));
  buf.writeln();

  if (t.courses.isEmpty) {
    buf.write('当前课表为空：还没有任何课程。');
    return buf.toString();
  }

  buf.writeln('课程数：${t.courses.length}，时段总数：${t.sessionCount}');
  const maxCourses = 80;
  final shown = t.courses.length > maxCourses ? t.courses.sublist(0, maxCourses) : t.courses;

  for (var i = 0; i < shown.length; i++) {
    final c = shown[i];
    buf.write('${i + 1}. ${c.name}');

    final meta = <String>[];
    if (c.teacher != null && c.teacher!.trim().isNotEmpty) meta.add(c.teacher!.trim());
    if (c.credit != null) meta.add('${_trimNumber(c.credit!)} 学分');
    if (c.courseCode != null && c.courseCode!.trim().isNotEmpty) {
      meta.add('编号 ${c.courseCode!.trim()}');
    }
    if (meta.isNotEmpty) buf.write('（${meta.join('，')}）');

    if (c.sessions.isEmpty) {
      buf.write('：暂无上课时段');
    } else {
      buf.write('：${c.sessions.map((s) => s.describe()).join('；')}');
    }

    if (c.note != null && c.note!.trim().isNotEmpty) {
      buf.write('｜备注：${_oneLine(c.note!)}');
    }
    if (c.adjustments.isNotEmpty) {
      buf.write('｜调整：${c.adjustments.map((a) => a.describe()).join('；')}');
    }
    buf.writeln();
  }

  if (t.courses.length > maxCourses) {
    buf.writeln('（其余 ${t.courses.length - maxCourses} 门课程已省略）');
  }
  return buf.toString().trimRight();
}

/// 把作息方案压成紧凑文本（一套一行）。
///
/// 模型必须知道「第 N 节几点上下课」，才能把「下午的课」「第 3 节」落到具体时间；
/// 多套方案（夏季/冬季作息）都要列出，并标出当前日期生效的那一套。
String _schedulesContext(Timetable t) {
  final active = t.activeSchedule;
  final buf = StringBuffer();
  buf.writeln('作息方案（共 ${t.schedules.length} 套，当前生效：${active.name}）：');
  for (var i = 0; i < t.schedules.length; i++) {
    final s = t.schedules[i];
    final isActive = s.id == active.id;
    buf.write('${i + 1}. ${s.name}${isActive ? '（当前生效）' : ''}（生效区间：${s.rangeLabel}）：');
    if (s.slots.isEmpty) {
      buf.write('暂无节次时间');
    } else {
      buf.write(s.slots.map((sl) => '第${sl.period}节 ${sl.start}-${sl.end}').join('；'));
    }
    buf.writeln();
  }
  return buf.toString().trimRight();
}

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// 把 `4.0` 这类整数显示成 `4`，避免提示词里出现无意义的 `.0`。
String _trimNumber(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// 把多行文本压成一行，防止把提示词结构搞乱。
String _oneLine(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

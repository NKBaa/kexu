import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/utils/week_utils.dart';
import '../../../data/models/course.dart';

/// 在给定背景色上挑选对比度最高的主题色作为前景色。
///
/// 课程卡片底色来自 [CoursePalette]（业务色），文字颜色必须跟随主题，
/// 所以从 [ColorScheme] 的候选色里按对比度挑一个，避免在任何地方硬编码黑/白。
Color _readableOnColor(Color background, ColorScheme scheme) {
  final candidates = <Color>[
    scheme.onSurface,
    scheme.surface,
    scheme.onPrimary,
    scheme.onInverseSurface,
    scheme.onSecondaryContainer,
  ];
  var best = candidates.first;
  var bestRatio = -1.0;
  for (final candidate in candidates) {
    final ratio = _contrastRatio(background, candidate);
    if (ratio > bestRatio) {
      bestRatio = ratio;
      best = candidate;
    }
  }
  return best;
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 课表网格中的课程卡片。
///
/// 尺寸完全由外部给定（网格里是并排列宽 × `rowSpan * rowHeight`），
/// 内部按可用高度/宽度自动降级显示：
/// - 内容优先级：课程名 → 教师 → 教室（地点）→ 周次标签；
/// - 宽度：正常宽度显示「课程名 + 教师 + 教室 + 周次」，小于 [_metaWidth] 时隐藏周次标签，
///   小于 [_compactWidth]（同一格并排了 2~3 门课）时只显示课程名。
///
/// 教师与教室是**默认显示**的（不用点开详情），空间不够时才按上面的优先级舍弃，
/// 舍弃的信息在点开卡片的详情弹层里都能看到。
///
/// 任何一档都**保持可读字号**：窄列不再用 `FittedBox` 等比缩小（那样会缩到
/// 5~6sp，看起来「字太小」），而是换行 + 省略号，最小字号约 11sp。
///
/// [conflicting] 为 true（该时段与同一天其它时段时间冲突）时，
/// 用警告色描边 + 右上角警告图标做高亮，但**保留**课程配色（[CoursePalette]），
/// 以免把「哪门课」的信息丢掉。
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.course,
    required this.session,
    this.onTap,
    this.onLongPress,
    this.conflicting = false,
    this.timeLabel = '',
  });

  /// 该时段的作息时间，如 `08:00-09:40`（可选；窄卡片会自动只显示开始时间）。
  final String timeLabel;

  /// 窄于此宽度（逻辑像素）时进入「紧凑模式」：只显示（换行后的）课程名。
  ///
  /// 典型场景：手机竖屏下同一格并排 2~3 门课，每张卡只有 20~30px 宽。
  /// 手机竖屏单列卡约 40~50px 宽（一屏放 7 天），属于正常模式（课程名 12/14sp 换行），
  /// 阈值若定得过高（如 64）会把整屏课程名都当成窄列，缩放成小字。
  static const double _compactWidth = 34;

  /// 窄于此宽度（逻辑像素）时隐藏周次标签，但课程名 + 教师 + 地点仍然显示。
  static const double _metaWidth = 130;

  final Course course;
  final Session session;

  /// 点击回调，参数为该卡片对应的课程与时段。
  final void Function(Course, Session)? onTap;

  /// 长按回调（打开课程编辑页，手动修改课程信息）。
  final void Function(Course, Session)? onLongPress;

  /// 该时段是否与同一天其它时段时间冲突。
  final bool conflicting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = CoursePalette.of(course.colorIndex);
    final foreground = _readableOnColor(background, scheme);

    final periodText = session.startPeriod == session.endPeriod
        ? '第${session.startPeriod}节'
        : '第${session.startPeriod}-${session.endPeriod}节';
    final location = (session.location ?? '').trim();
    // 教师优先取「这个时段的教师」（调课时可能换老师），没有再用课程默认教师。
    final teacher = (session.teacher ?? course.teacher ?? '').trim();
    final weekText = formatWeeks(session.weeks);

    final warningColor = scheme.error;
    final semanticsText = <String>[
      course.name,
      '$periodText${timeLabel.isEmpty ? '' : ' $timeLabel'}'
          '${location.isEmpty ? '' : '，$location'}',
      if (teacher.isNotEmpty) '教师 $teacher',
      if (conflicting) '时间冲突',
    ].join('，');
    final tooltipText = <String>[
      if (conflicting) '时间冲突',
      course.name,
      '$periodText${timeLabel.isEmpty ? '' : ' $timeLabel'}'
          '${location.isEmpty ? '' : ' · $location'}',
      if (teacher.isNotEmpty) teacher,
      if (weekText.isNotEmpty) weekText,
    ].join(' · ');

    return Semantics(
      container: true,
      label: semanticsText,
      button: onTap != null,
      child: Tooltip(
        message: tooltipText,
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 400),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(course, session),
            onLongPress:
                onLongPress == null ? null : () => onLongPress!(course, session),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final finiteWidth = constraints.maxWidth.isFinite;
                final finiteHeight = constraints.maxHeight.isFinite;
                final width = finiteWidth ? constraints.maxWidth : 140.0;
                final height = finiteHeight ? constraints.maxHeight : 96.0;
                // 降级阈值：
                // - compact（< _compactWidth）：列宽很窄（同一格并排了 2~3 门课），
                //   只保留课程名（换行 + 省略，保持 11sp 可读）；
                // - tight（< _metaWidth）：手机竖屏单列宽度，课程名换行显示，不再显示周次标签。
                final compact = width < _compactWidth;
                final tight = width < _metaWidth;

                // 卡片默认显示：课程名 → 教师 → 教室（地点）→ 周次。
                // 手机竖屏一屏要放下 7 天，单列卡净宽只有 40~50，按这个优先级依次保留，
                // 放不下的信息在点开卡片的详情弹层里都能看到。
                final showTeacher = !compact && teacher.isNotEmpty && height >= 48;
                final showLocation = !compact && location.isNotEmpty && height >= 84;
                final locationLines = height >= 150
                    ? 3
                    : (width < 44
                        ? (height >= 110 ? 3 : (height >= 100 ? 2 : 1))
                        : (height >= 112 ? 2 : 1));
                final showWeeks = !compact &&
                    !tight &&
                    height >= 96 &&
                    weekText.isNotEmpty;

                // 作息时间：卡片够宽时显示完整范围，窄卡只显示开始时间，
                // 避免在手机一屏 7 天的窄列里被省略成无意义的一条线。
                final shortTime =
                    timeLabel.contains('-') ? timeLabel.split('-').first : timeLabel;
                final shownTime = width >= 58 ? timeLabel : shortTime;
                final showTime =
                    !compact && timeLabel.isNotEmpty && height >= 54;

                final maxLines = compact
                    ? (height >= 40 ? 2 : 1)
                    : (height >= 100
                        ? 4
                        : (height >= 84
                            ? 3
                            : (height >= 44 ? 2 : 1)));

                // 字号：正常/紧凑两档都保证可读。
                // - 宽卡（>= 46）：课程名 14sp；
                // - 手机一屏 7 天时单列卡约 40~50 宽：11.5~12sp 才能每行放下 3 个字；
                // - 紧凑档（同格并排 2~3 门课）：11sp，宁可省略也不缩到看不清。
                final nameSize = compact
                    ? 11.0
                    : (width >= 46 ? (maxLines >= 2 ? 14.0 : 12.0) : 11.5);
                final nameStyle = TextStyle(
                  fontSize: nameSize,
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                );
                final metaStyle = theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  color: foreground.withAlpha(225),
                  height: 1.1,
                );

                final name = Text(
                  course.name,
                  maxLines: maxLines,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle,
                );

                final content = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name,
                    if (showTeacher)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          teacher,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ),
                    if (showTime)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          shownTime,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle?.copyWith(
                            fontSize: 10,
                            height: 1.1,
                          ),
                        ),
                      ),
                    if (showLocation)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          location,
                          maxLines: locationLines,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ),
                    if (showWeeks)
                      Text(
                        weekText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                  ],
                );

                // 手机一屏 7 天时卡片很窄，左右内边距收窄到 2，把宽度让给文字。
                final basePadding = compact
                    ? const EdgeInsets.fromLTRB(3, 3, 3, 3)
                    : (width < 64
                        ? const EdgeInsets.fromLTRB(2, 3, 2, 3)
                        : const EdgeInsets.fromLTRB(6, 4, 6, 4));

                final card = SizedBox(
                  width: finiteWidth ? null : width,
                  height: finiteHeight ? null : height,
                  child: Stack(
                    children: [
                      // 冲突卡：警告色描边（2px）。用同一个圆角、往内收 1px，
                      // 这样描边不会被 Material 的 clip 切掉一半，也仍是 2px。
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(1),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: conflicting
                                  ? Border.fromBorderSide(
                                      BorderSide(color: warningColor, width: 2),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          // 宽卡片的冲突图标浮在右上角，正文右侧让出 10px 避免被压住。
                          padding: conflicting && !compact
                              ? const EdgeInsets.only(right: 10)
                              : EdgeInsets.zero,
                          child: Padding(
                            padding: basePadding,
                            // 极端窄高（超大字号 / 极扁卡片）时兜底：宁可裁切也不溢出。
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: content,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                if (!conflicting) return card;

                // 冲突高亮：右上角警告图标，且与正文**互不重叠**：
                // - 卡片够宽（正常单列）或高度约束无界时，图标浮在右上角；
                // - 卡片极窄（同一格好几门课）时，图标单独占顶部一条，课程名整体下移。
                final badgeSize = compact ? 12.0 : 14.0;
                final badge = SizedBox(
                  width: badgeSize,
                  height: badgeSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: warningColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: badgeSize - 3,
                        color: scheme.onError,
                      ),
                    ),
                  ),
                );

                if (!compact || !finiteHeight) {
                  return Stack(
                    children: [
                      Positioned.fill(child: card),
                      Positioned(top: 1, right: 1, child: badge),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: badgeSize,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: badge,
                      ),
                    ),
                    Expanded(child: card),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

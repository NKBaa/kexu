part of 'onboarding_wizard_page.dart';

/// 教程中的一条操作说明。
class _TutorialAction {
  const _TutorialAction({
    required this.icon,
    required this.title,
    required this.description,
    this.path,
  });

  final IconData icon;
  final String title;
  final String description;

  /// 操作入口，例如「更多 → 添加课程」。
  final String? path;
}

/// 使用教程的一节。
class _TutorialChapter {
  const _TutorialChapter({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.tip,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_TutorialAction> actions;
  final String tip;

  static const List<_TutorialChapter> all = <_TutorialChapter>[
    _TutorialChapter(
      icon: Icons.calendar_view_week_outlined,
      title: '认识课表',
      subtitle: '先弄清「第几周」和「第几节」，后面所有操作都围绕这两个坐标。',
      actions: <_TutorialAction>[
        _TutorialAction(
          icon: Icons.swap_horiz,
          title: '切换周次',
          description: '顶部显示当前教学周。点开可以跳到任意周，也可以直接左右滑动课表。',
          path: '点顶部「第 N 周」或左右滑动',
        ),
        _TutorialAction(
          icon: Icons.today_outlined,
          title: '回到本周',
          description: '翻到别的周后，点「回到本周」立即回到当前教学周。',
          path: '顶栏「回到本周」',
        ),
        _TutorialAction(
          icon: Icons.grid_view_outlined,
          title: '看懂课程块',
          description: '每个色块是一节课；颜色区分课程，单双周、断续周次会标在卡片上。',
          path: '课表格子',
        ),
      ],
      tip: '课表按「学期起始日 + 总周数」换算周次。如果周次整体对不上，'
          '先去「设置 → 学期与作息」检查学期起始日。',
    ),
    _TutorialChapter(
      icon: Icons.add_circle_outline,
      title: '添加课程',
      subtitle: '三种方式：长按空白格最快，菜单最完整，图片 / AI 最适合批量导入。',
      actions: <_TutorialAction>[
        _TutorialAction(
          icon: Icons.touch_app_outlined,
          title: '长按空白格',
          description: '从按下的位置开始选节次，继续上下拖动可以选中连续几节；'
              '松开后自动填好星期与节次。',
          path: '课表空白处',
        ),
        _TutorialAction(
          icon: Icons.post_add_outlined,
          title: '从菜单添加',
          description: '手动填写课程名、老师、地点、颜色和周次，适合新课或临时课。',
          path: '更多 → 添加课程',
        ),
        _TutorialAction(
          icon: Icons.auto_awesome_outlined,
          title: '图片或一句话',
          description: '截教务系统课表让 AI 识别，或直接说「周三下午加一门课」；'
              '两种方式都会先给方案，再让你确认。',
          path: '添加面板 / AI',
        ),
      ],
      tip: '长按空白格是最快的方式；一次没选准可以点顶栏撤销，重新再来。',
    ),
    _TutorialChapter(
      icon: Icons.edit_calendar_outlined,
      title: '编辑与调整',
      subtitle: '改时间、换周次、拖动课程，以及一门课多个时段。',
      actions: <_TutorialAction>[
        _TutorialAction(
          icon: Icons.edit_outlined,
          title: '长按卡片编辑',
          description: '打开课程编辑页，改时间、周次、地点、颜色，或删除这门课。',
          path: '长按课程块',
        ),
        _TutorialAction(
          icon: Icons.drag_indicator,
          title: '拖动换时间',
          description: '按住卡片右下角的拖动柄，把课程拖到其它星期或节次；松手即保存。',
          path: '课程卡片右下角',
        ),
        _TutorialAction(
          icon: Icons.layers_outlined,
          title: '一门课多个时段',
          description: '同一门课可以有多段上课时间，每段单独设置星期、节次和周次。',
          path: '编辑页「添加时段」',
        ),
        _TutorialAction(
          icon: Icons.undo,
          title: '撤销 / 重做',
          description: '改错了就撤销；撤销/重做只保留一条时间线，新的编辑会截断重做。',
          path: '顶栏 ↶ ↷',
        ),
      ],
      tip: '拖动只移动当前课程块；要改整门课的所有时段，请进入编辑页。',
    ),
    _TutorialChapter(
      icon: Icons.event_note_outlined,
      title: '日程与提醒',
      subtitle: '考试、作业截止、活动和会议，都可以和课表分开管理。',
      actions: <_TutorialAction>[
        _TutorialAction(
          icon: Icons.calendar_month_outlined,
          title: '打开日程',
          description: '月历上的圆点表示当天有日程；点日期查看当天事项。',
          path: '底部「日程」',
        ),
        _TutorialAction(
          icon: Icons.add,
          title: '新建日程',
          description: '支持全天或指定开始/结束时间，可以写标题和备注。',
          path: '日程页右下角 +',
        ),
        _TutorialAction(
          icon: Icons.auto_awesome,
          title: '用 AI 加日程',
          description: '说「明天下午 3 点交高数作业」，AI 解析日期、时间、标题和备注。',
          path: '日程页右上角 AI',
        ),
        _TutorialAction(
          icon: Icons.notifications_active_outlined,
          title: '上课提醒',
          description: '按作息提前提醒；节假日和停课不会提醒。',
          path: '设置 → 上课提醒',
        ),
      ],
      tip: '日程保存在独立文件里，和课表互不影响；同步课表不会覆盖日程。',
    ),
    _TutorialChapter(
      icon: Icons.auto_awesome_outlined,
      title: 'AI 助手',
      subtitle: '一个窗口同时处理改课表和加日程，不需要在两套 AI 之间切换。',
      actions: <_TutorialAction>[
        _TutorialAction(
          icon: Icons.chat_bubble_outline,
          title: '打开 AI',
          description: '课表右下角的「AI」和日程右上角的「AI」打开的是同一个窗口。',
          path: '课表右下角 / 日程右上角',
        ),
        _TutorialAction(
          icon: Icons.table_chart_outlined,
          title: '改课表',
          description: '例如「把明天的课挪到下周」「高数改成单双周都上」，AI 会先生成操作方案。',
          path: '直接说',
        ),
        _TutorialAction(
          icon: Icons.event_available_outlined,
          title: '加日程',
          description: '例如「下个月 5 号报名截止」，AI 会解析成日期、时间、标题和备注。',
          path: '直接说',
        ),
        _TutorialAction(
          icon: Icons.image_outlined,
          title: '发图片',
          description: '可以附课表截图；有语言模型时直接看图，没有时先用识图模型转述。',
          path: '输入框左侧图片按钮',
        ),
        _TutorialAction(
          icon: Icons.fact_check_outlined,
          title: '先预览再应用',
          description: '逐条核对方案，取消不想要的，再点应用；AI 不会直接改数据。',
          path: '方案卡片',
        ),
      ],
      tip: 'AI 需要先在「设置 → 大模型配置」填 API Key。没有 Key 也能手动添加课程和日程。',
    ),
    _TutorialChapter(
      icon: Icons.settings_outlined,
      title: '设置与数据',
      subtitle: '换设备、备份、主题和更新，都收在设置里。',
      actions: <_TutorialAction>[
        _TutorialAction(
          icon: Icons.school_outlined,
          title: '学期与作息',
          description: '学期起始日、总周数、每节课时间、节假日和作息方案都在这里。',
          path: '设置 → 学期与作息',
        ),
        _TutorialAction(
          icon: Icons.palette_outlined,
          title: '主题中心',
          description: '跟随系统 / 浅色 / 深色，内置主题与自定义主题；显示周末也在这里。',
          path: '设置 → 主题中心',
        ),
        _TutorialAction(
          icon: Icons.cloud_sync_outlined,
          title: '数据管理',
          description: '导出 JSON 备份、导入恢复、WebDAV 同步；换设备前先导出。',
          path: '设置 → 数据管理',
        ),
        _TutorialAction(
          icon: Icons.system_update_outlined,
          title: '检查更新',
          description: '从 GitHub Release 检查新版本，也可以手动下载 APK / Windows 包。',
          path: '设置 → 检查更新',
        ),
      ],
      tip: '换手机或重装前先导出 JSON；课表、日程和设置都可以一起恢复。',
    ),
  ];
}

class _TutorialChapterView extends StatelessWidget {
  const _TutorialChapterView({
    required this.chapter,
    required this.index,
    required this.total,
    required this.isLast,
  });

  final _TutorialChapter chapter;
  final int index;
  final int total;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TutorialHero(
                  chapter: chapter,
                  index: index,
                  total: total,
                ),
                const SizedBox(height: 22),
                Text(
                  '你可以这样做',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < chapter.actions.length; i++) ...[
                  _TutorialActionCard(action: chapter.actions[i]),
                  if (i != chapter.actions.length - 1)
                    const SizedBox(height: 8),
                ],
                const SizedBox(height: 14),
                _TutorialTip(text: chapter.tip),
                if (isLast) ...[
                  const SizedBox(height: 14),
                  const _TutorialFinishCard(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TutorialHero extends StatelessWidget {
  const _TutorialHero({
    required this.chapter,
    required this.index,
    required this.total,
  });

  final _TutorialChapter chapter;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(chapter.icon, size: 28, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第 ${index + 1} 节 · 共 $total 节',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                chapter.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                chapter.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TutorialActionCard extends StatelessWidget {
  const _TutorialActionCard({required this.action});

  final _TutorialAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(action.icon, size: 21, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    action.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  if (action.path != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '入口：${action.path}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialTip extends StatelessWidget {
  const _TutorialTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialFinishCard extends StatelessWidget {
  const _TutorialFinishCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 28, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '教程完成',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '现在去课表试试长按空白格，添加第一门课。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialSidebar extends StatelessWidget {
  const _TutorialSidebar({required this.current, required this.onSelect});

  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      color: scheme.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '教程目录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '第 ${current + 1} 节 / 共 ${_TutorialChapter.all.length} 节 · 约 5 分钟',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _TutorialChapter.all.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: i == current ? scheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: Key('tutorial_chapter_$i'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: i == current
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: i == current
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _TutorialChapter.all[i].title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: i == current
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == current
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

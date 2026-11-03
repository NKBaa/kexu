import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/bell_schedule_template.dart';
import '../settings/pages/ai_settings_page.dart';
import '../settings/pages/holiday_ai_page.dart';
import '../settings/pages/holiday_reminder_page.dart';
import '../settings/pages/silicon_flow_guide_page.dart';
import '../settings/providers/schedule_template_provider.dart';
import '../settings/providers/settings_provider.dart';
import '../settings/schedule_template_apply.dart';
import '../../core/utils/holiday_utils.dart';

/// 首次使用向导：学校作息 → 大模型 API → 节假日 → 添加课程方式。
class OnboardingWizardPage extends ConsumerStatefulWidget {
  const OnboardingWizardPage({super.key, this.replay = false});

  /// 从课表「更多 → 重启教程」进入时为 true：不重复标记完成，完成后返回。
  final bool replay;

  @override
  ConsumerState<OnboardingWizardPage> createState() => _OnboardingWizardPageState();
}

class _OnboardingWizardPageState extends ConsumerState<OnboardingWizardPage> {
  int _step = 0;
  bool _finishing = false;
  bool _applyingSchool = false;
  String? _appliedSchool;
  int _appliedCount = 0;

  static const int _totalSteps = 5;

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    if (widget.replay) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await ref.read(settingsProvider.notifier).completeOnboarding();
    if (mounted) setState(() => _finishing = false);
  }

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  Future<void> _applySchool(SchoolBellTemplates school) async {
    if (_applyingSchool) return;
    setState(() => _applyingSchool = true);
    final count = await applyScheduleTemplates(ref, school.templates);
    if (!mounted) return;
    setState(() {
      _applyingSchool = false;
      _appliedSchool = school.school;
      _appliedCount = count;
    });
    if (count > 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已导入 $count 套作息')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.replay
            ? IconButton(
                tooltip: '关闭教程',
                onPressed: _finish,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(widget.replay ? '使用教程' : '使用向导'),
        actions: [
          TextButton(
            key: const Key('onboarding_skip_all'),
            onPressed: _finish,
            child: Text(widget.replay ? '关闭' : '跳过'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '第 ${_step + 1} 步 / 共 $_totalSteps 步',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < _totalSteps; i++) ...[
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            height: 5,
                            decoration: BoxDecoration(
                              color: i <= _step
                                  ? scheme.primary
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        if (i != 3) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey<int>(_step),
                  child: switch (_step) {
                    0 => widget.replay
                        ? _buildReplaySchoolStep(theme)
                        : _buildSchoolStep(theme),
                    1 => _buildAiStep(theme),
                    2 => _buildHolidayStep(theme),
                    3 => _buildGuideStep(theme),
                    _ => _buildEditingStep(theme),
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('上一步'),
                    ),
                  if (_step < _totalSteps - 1)
                    TextButton(
                      key: const Key('onboarding_skip_step'),
                      onPressed: _finishing ? null : _next,
                      child: const Text('跳过此步'),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('onboarding_next'),
                    onPressed: _finishing ? null : _next,
                    child: Text(
                      _step == _totalSteps - 1
                          ? (widget.replay ? '完成' : '开始使用')
                          : '下一步',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 回看教程时的第一步：不请求 GitHub 模板，避免网络慢时卡在加载中。
  Widget _buildReplaySchoolStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        const _StepHeader(
          icon: Icons.school_outlined,
          title: '学期与作息',
          subtitle: '学期起止、总周数与每节课时间，决定课表的时间骨架。',
        ),
        const SizedBox(height: 14),
        const _GuideCard(
          icon: Icons.calendar_month_outlined,
          title: '设置学期',
          description: '在「设置 → 学期与作息」里填写开学日期、学期名称和总周数；'
              '课表按这些信息换算「第几周」。',
        ),
        const SizedBox(height: 8),
        const _GuideCard(
          icon: Icons.access_time,
          title: '设置作息',
          description: '可以手动编辑每节课的上下课时间，也可以从 GitHub 学校模板导入；'
              '夏季/冬季作息可以建多套方案。',
        ),
        const SizedBox(height: 8),
        const _GuideCard(
          icon: Icons.beach_access_outlined,
          title: '节假日',
          description: '节假日也在「学期与作息」里管理；放假当天不显示课程、不排上课提醒。',
        ),
        const SizedBox(height: 14),
        Text(
          '回看教程不会改动你的设置；点「下一步」继续。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolStep(ThemeData theme) {
    final async = ref.watch(scheduleTemplateCatalogProvider);
    return async.when(
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          const _StepHeader(
            icon: Icons.school_outlined,
            title: '选择学校设置作息',
            subtitle: '正在从 GitHub 加载学校模板；网络慢时可以先跳过，稍后在设置里手动调整。',
          ),
          const SizedBox(height: 40),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(
            '如果一直加载不出来，点右下角「下一步」即可继续。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      error: (e, st) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          _StepHeader(
            icon: Icons.school_outlined,
            title: '选择学校设置作息',
            subtitle: '选择学校后会导入该校的作息模板；也可以稍后在设置里再调整。',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('模板加载失败', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text('$e', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        ref.invalidate(scheduleTemplateCatalogProvider),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('没有网络也没关系：可以先跳过，之后在「学期与作息」里手动设置。'),
        ],
      ),
      data: (catalog) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          _StepHeader(
            icon: Icons.school_outlined,
            title: '选择学校设置作息',
            subtitle: '点击学校会自动导入该校全部作息模板，之后仍可修改。',
          ),
          if (_appliedSchool != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: ListTile(
                leading: Icon(Icons.check_circle,
                    color: theme.colorScheme.onSecondaryContainer),
                title: Text('已设置：$_appliedSchool'),
                subtitle: Text('已应用 $_appliedCount 套作息'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (catalog.schools.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无学校模板，可以先跳过。'),
              ),
            )
          else
            for (final school in catalog.schools) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: Key('onboarding_school_${school.school}'),
                  enabled: !_applyingSchool,
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.account_balance_outlined,
                        size: 21, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: Text(
                    school.school,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${school.templates.length} 套作息'
                    '${school.note.isEmpty ? '' : ' · ${school.note}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _appliedSchool == school.school
                      ? Icon(Icons.check_circle,
                          color: theme.colorScheme.primary)
                      : _applyingSchool
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                  onTap: () => _applySchool(school),
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _buildAiStep(ThemeData theme) {
    final async = ref.watch(aiConfigProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        _StepHeader(
          icon: Icons.auto_awesome_outlined,
          title: '配置大模型 API',
          subtitle: '用于识别课表图片和「一句话改课表」。这一步可以跳过，之后在设置里再配置。',
        ),
        const SizedBox(height: 14),
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: ListTile(
            key: const Key('onboarding_siliconflow'),
            leading: Icon(Icons.bolt_outlined,
                color: theme.colorScheme.onSecondaryContainer),
            title: Text(
              '推荐使用硅基流动（还没有 API Key？）',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            subtitle: Text(
              '注册 / 登录、创建 API Key、充值都在官网完成，课序不接触账号密码。',
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SiliconFlowGuidePage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, st) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('读取 AI 配置失败：$e'),
            ),
          ),
          data: (config) => Column(
            children: [
              _AiStatusCard(
                title: '视觉模型',
                subtitle: '图片转课表',
                icon: Icons.image_outlined,
                configured: config.vision.isConfigured,
                model: config.vision.model,
              ),
              const SizedBox(height: 8),
              _AiStatusCard(
                title: '语言模型',
                subtitle: '一句话改课表',
                icon: Icons.chat_bubble_outline,
                configured: config.text.isConfigured,
                model: config.text.model,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          key: const Key('onboarding_open_ai_settings'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AiSettingsPage()),
          ),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('打开大模型配置'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('onboarding_skip_ai'),
          onPressed: _finishing ? null : _next,
          icon: const Icon(Icons.skip_next_outlined, size: 18),
          label: const Text('跳过 AI 设置，稍后再配'),
        ),
        const SizedBox(height: 10),
        Text(
          '没有 API Key 也没关系，可以直接点「跳过 AI 设置」。'
          '之后可在「设置 → 大模型配置」里随时补上。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildHolidayStep(ThemeData theme) {
    final async = ref.watch(settingsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        const _StepHeader(
          icon: Icons.beach_access_outlined,
          title: '设置节假日（可选）',
          subtitle: '放假当天不显示课程，也不会安排上课提醒；可以稍后再加。',
        ),
        const SizedBox(height: 14),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, st) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('读取节假日失败：$e'),
            ),
          ),
          data: (settings) {
            final holidays = sortHolidays(settings.holidays);
            return Card(
              child: Column(
                children: [
                  if (holidays.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 18, 16, 18),
                      child: Row(
                        children: [
                          Icon(Icons.event_available_outlined, size: 20),
                          SizedBox(width: 10),
                          Expanded(child: Text('还没有添加节假日。')),
                        ],
                      ),
                    )
                  else
                    for (var i = 0; i < holidays.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.beach_access_outlined, size: 20),
                        title: Text(holidays[i].name),
                        subtitle: Text(holidays[i].dateKey),
                      ),
                    ],
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('onboarding_open_holidays'),
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('添加 / 管理节假日'),
                    subtitle: const Text('添加国庆、校运会等放假日期'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HolidayReminderPage(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('onboarding_ai_holidays'),
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('用 AI 设置节假日'),
                    subtitle: const Text('一句话描述放假日期，解析后确认添加'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HolidayAiPage(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          '这一步可以跳过：之后在「设置 → 节假日与提醒」里随时添加。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildGuideStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        const _StepHeader(
          icon: Icons.rocket_launch_outlined,
          title: '开始添加课程',
          subtitle: '三种方式任选一种，之后也可以随时从主界面添加。',
        ),
        const SizedBox(height: 14),
        const _GuideCard(
          icon: Icons.photo_camera_outlined,
          title: '图片转课表',
          description: '上传教务系统截图或课表照片，AI 识别后预览确认。',
        ),
        const SizedBox(height: 8),
        const _GuideCard(
          icon: Icons.auto_awesome_outlined,
          title: '一句话改课表',
          description: '在课表页点「AI」，直接说「高数改成单双周」这类需求。',
        ),
        const SizedBox(height: 8),
        const _GuideCard(
          icon: Icons.add_circle_outline,
          title: '手动添加',
          description: '点顶栏「添加」，逐门填写课程、时间与周次。',
        ),
        const SizedBox(height: 14),
        Text(
          '点击下方「开始使用」进入课表。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildEditingStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        const _StepHeader(
          icon: Icons.edit_calendar_outlined,
          title: '课表编辑与新增',
          subtitle: '记住这几个手势，改课表会快很多。',
        ),
        const SizedBox(height: 14),
        const _GuideCard(
          icon: Icons.touch_app_outlined,
          title: '长按空白处新增',
          description: '长按空白单元格会从点击位置开始选节次；继续上下拖动可选中连续几节，'
              '松开后自动填好星期与节次。',
        ),
        const SizedBox(height: 8),
        const _GuideCard(
          icon: Icons.drag_indicator,
          title: '长按编辑，拖动调整',
          description: '长按课程卡片进入编辑；按住卡片右下角的拖动柄，可把课程拖到其它星期或节次。',
        ),
        const SizedBox(height: 8),
        const _GuideCard(
          icon: Icons.layers_outlined,
          title: '一门课多个时段',
          description: '新增课程页可以添加多个上课时段，每个时段单独选星期、节次与周次。',
        ),
        const SizedBox(height: 8),
        const _GuideCard(
          icon: Icons.undo,
          title: '撤销与重做',
          description: '顶栏可以撤销/重做；「更多」里还有添加课程、分享、导入导出和重启教程。',
        ),
        const SizedBox(height: 14),
        Text(
          '教程可随时从课表「更多 → 重启教程」回看。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiStatusCard extends StatelessWidget {
  const _AiStatusCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.configured,
    required this.model,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool configured;
  final String model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(configured && model.isNotEmpty ? model : subtitle),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: configured
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            configured ? '已配置' : '未配置',
            style: theme.textTheme.labelSmall?.copyWith(
              color: configured
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

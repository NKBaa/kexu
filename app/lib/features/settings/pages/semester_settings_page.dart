import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/hint_icon.dart';
import '../../../data/models/semester.dart';
import '../../../data/models/timetable.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../widgets/holiday_settings_card.dart';
import '../widgets/semester_form.dart';
import 'bell_schedule_editor_page.dart';
import 'schedule_templates_page.dart';

/// 子页面通用脚手架：统一的标题栏 + 居中的窄列内容。
///
/// 设置被拆成多个二级页面后，需要一个一致的容器，
/// 这样后续新增设置分类时只需套这个壳，不需要重复写布局。
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (subtitle != null)
            HintIcon(message: subtitle!, title: '页面说明'),
          ...?actions,
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [child],
          ),
        ),
      ),
    );
  }
}

/// 学期与作息设置页。
///
/// 这两项都直接决定课表的「时间骨架」，放在同一个二级页面里，
/// 用户改学期时顺手就能核对作息。
class SemesterSettingsPage extends ConsumerStatefulWidget {
  const SemesterSettingsPage({super.key});

  @override
  ConsumerState<SemesterSettingsPage> createState() => _SemesterSettingsPageState();
}

class _SemesterSettingsPageState extends ConsumerState<SemesterSettingsPage> {
  Semester? _draft;
  bool _dirty = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(timetableProvider);
    return SettingsSubPage(
      title: '学期与作息',
      subtitle: '决定周次范围、以及每节课的起止时间',
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => Text('读取失败：$e'),
        data: (timetable) => _buildBody(context, timetable),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Timetable timetable) {
    _draft ??= timetable.semester;
    if (_draft!.id != timetable.semester.id) {
      _draft = timetable.semester;
      _dirty = false;
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('学期设置', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    if (_dirty)
                      Text('未保存',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.tertiary)),
                  ],
                ),
                const SizedBox(height: 10),
                SemesterForm(
                  semester: _draft!,
                  onChanged: (next) => setState(() {
                    _draft = next;
                    _dirty = !_sameSemester(next, timetable.semester);
                  }),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _dirty && !_saving
                        ? () => _saveSemester(timetable)
                        : null,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存学期'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('作息方案', style: theme.textTheme.titleSmall),
                    const SizedBox(width: 2),
                    const HintIcon(
                      message: '学校夏季/冬季作息不同？可以建多套方案并设置生效日期，'
                          'App 会按日期自动切换。只有一套时也可以再加一套。',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const BellScheduleList(),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    key: const Key('bell_template_button'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ScheduleTemplatesPage(),
                      ),
                    ),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('从 GitHub 模板导入'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const HolidaySettingsCard(),
      ],
    );
  }

  Future<void> _saveSemester(Timetable timetable) async {
    final draft = _draft;
    if (draft == null || _saving) return;
    if (draft.name.trim().isEmpty) {
      _toast('学期名称不能为空', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(timetableProvider.notifier).setSemester(draft);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      _toast('学期设置已保存');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$e', error: true);
    }
  }

  bool _sameSemester(Semester a, Semester b) =>
      a.id == b.id &&
      a.name == b.name &&
      a.totalWeeks == b.totalWeeks &&
      a.startMonday == b.startMonday;

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }
}

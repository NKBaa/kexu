import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import '../../../core/widgets/hint_icon.dart';
import 'semester_settings_page.dart' show SettingsSubPage;
import 'update_settings_page.dart';

/// 关于页。
class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsSubPage(
      title: '关于',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(Icons.calendar_month,
                            color: theme.colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('课序 · Kexu',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            Text('版本 $fullVersion',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                )),
                            Text('不规律的课表，也有自己的顺序',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                )),
                          ],
                        ),
                      ),
                      const HintIcon(
                        message: '用「显式周次列表」建模，因此单周/双周、3-5+7-9 这种断续周次、'
                            '一门课多个时段、临时调课/停课/补课都能精确表达；'
                            '同一时间排了两门课会并排显示并高亮冲突。\n\n'
                            '快捷键：表单内 Enter 跳到下一项；课程编辑器返回时会提示保存。',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const Key('about_check_update'),
              leading: Icon(Icons.system_update,
                  color: theme.colorScheme.primary),
              title: const Text('检查更新'),
              subtitle: const Text('从 GitHub Releases 获取新版本，支持国内镜像加速'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const UpdateSettingsPage(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

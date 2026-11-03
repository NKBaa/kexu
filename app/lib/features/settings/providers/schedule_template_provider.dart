import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/bell_schedule_template.dart';
import '../../../data/services/schedule_template_service.dart';
import '../../settings/providers/settings_provider.dart';

/// 作息模板服务（测试可 override）。
final scheduleTemplateServiceProvider = Provider<ScheduleTemplateService>((ref) {
  return ScheduleTemplateService();
});

/// 从 GitHub 拉取模板目录；仓库/镜像配置随 [settingsProvider] 变化。
final scheduleTemplateCatalogProvider =
    FutureProvider.autoDispose<BellScheduleTemplateCatalog>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  return ref.read(scheduleTemplateServiceProvider).fetch(
        config: settings.updateConfig,
      );
});

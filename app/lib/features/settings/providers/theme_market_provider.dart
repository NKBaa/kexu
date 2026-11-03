import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/theme_market_service.dart';
import 'settings_provider.dart';

/// 主题市场服务（测试可 override）。
final themeMarketServiceProvider = Provider<ThemeMarketService>((ref) {
  return ThemeMarketService();
});

/// 从 GitHub 拉取主题市场；仓库/镜像沿用检查更新配置。
final themeMarketProvider =
    FutureProvider.autoDispose<ThemeMarketCatalog>((ref) async {
  final config = ref.watch(
    settingsProvider.select((s) => s.valueOrNull?.updateConfig),
  );
  if (config != null) {
    return ref.read(themeMarketServiceProvider).fetch(config: config);
  }
  final settings = await ref.read(settingsProvider.future);
  return ref.read(themeMarketServiceProvider).fetch(
        config: settings.updateConfig,
      );
});

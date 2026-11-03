import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/ai_model_catalog.dart';
import '../../../data/services/ai_model_catalog_service.dart';
import 'settings_provider.dart';

/// 模型名单服务（测试可 override）。
final aiModelCatalogServiceProvider = Provider<AiModelCatalogService>((ref) {
  return AiModelCatalogService();
});

/// 从 GitHub 拉取模型能力名单；失败时依次回退到本地缓存、内置名单。
///
/// 返回的 [AiModelCatalog.source] 会标明 `github` / `cache` / `builtin`，
/// [AiModelCatalog.warning] 在回退时给出原因，UI 可直接展示。
final aiModelCatalogProvider =
    FutureProvider.autoDispose<AiModelCatalog>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  final service = ref.read(aiModelCatalogServiceProvider);
  try {
    final remote = await service.fetch(config: settings.updateConfig);
    await service.saveCache(remote);
    return remote;
  } catch (e) {
    final cached = await service.loadCache();
    if (cached != null) {
      return cached.copyWith(warning: 'GitHub 名单更新失败，已使用本地缓存：$e');
    }
    return AiModelCatalog.builtIn().copyWith(
      warning: 'GitHub 名单更新失败，已使用内置名单：$e',
    );
  }
});

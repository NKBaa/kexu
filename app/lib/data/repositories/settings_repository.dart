import '../local/document_store.dart';
import '../models/ai_config.dart';
import '../models/app_settings.dart';

/// 设置仓储：读写 `settings.json`。
///
/// 单独存一个文件，好处是「清空课表」不会连带把用户填好的 API Key 清掉。
class SettingsRepository {
  SettingsRepository({DocumentStore? store})
      : _store = store ?? DocumentStore('settings.json', backupKeep: 3);

  final DocumentStore _store;

  Future<AppSettings> load() async {
    AppSettings? primary;
    try {
      final json = await _store.readJson();
      if (json != null) primary = AppSettings.fromJson(json);
    } catch (_) {
      primary = null;
    }

    AppSettings? backup;
    try {
      final backupJson = await _store.readLatestBackupJson();
      if (backupJson != null) backup = AppSettings.fromJson(backupJson);
    } catch (_) {
      backup = null;
    }

    if (primary == null) {
      if (backup != null) {
        // 主文件丢失/损坏：把备份恢复成当前设置，避免用户重新填 API Key。
        await _store.writeJson(backup.toJson());
        return backup;
      }
      return const AppSettings();
    }

    // 主文件被重置成默认（例如升级过程写入了空设置）时，
    // 从最近备份把 AI 配置找回来；其它设置仍以主文件为准。
    // 只在 AI 配置整体为空时恢复，避免用户手动清空 Key 后被“复活”。
    if (backup != null && _aiConfigEmpty(primary) && _hasApiKey(backup)) {
      final merged = primary.copyWith(aiConfig: backup.aiConfig);
      await _store.writeJson(merged.toJson());
      return merged;
    }
    return primary;
  }

  bool _hasApiKey(AppSettings settings) =>
      settings.aiConfig.vision.apiKey.trim().isNotEmpty ||
      settings.aiConfig.text.apiKey.trim().isNotEmpty;

  bool _aiConfigEmpty(AppSettings settings) =>
      settings.aiConfig.vision.isEmpty && settings.aiConfig.text.isEmpty;

  Future<void> save(AppSettings settings) async {
    await _store.writeJson(settings.toJson());
  }

  Future<void> saveAiConfig(AiConfig config) async {
    final current = await load();
    await save(current.copyWith(aiConfig: config));
  }
}

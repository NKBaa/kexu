import 'dart:io';

import 'package:course_timetable/data/local/document_store.dart';
import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('settings_repo_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  const keyed = AppSettings(
    aiConfig: AiConfig(
      vision: AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-persisted',
        model: 'vision-model',
      ),
      text: AiModelConfig(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-persisted',
        model: 'text-model',
      ),
    ),
  );

  test('主设置被重置为空时，从备份恢复 API Key', () async {
    final store = DocumentStore('settings.json', baseDirectory: root);
    final repo = SettingsRepository(store: store);

    await repo.save(keyed);
    // 模拟升级过程把设置写回默认值；写之前 DocumentStore 会先备份带 Key 的版本。
    await repo.save(const AppSettings());

    final loaded = await repo.load();
    expect(loaded.aiConfig.vision.apiKey, 'sk-persisted');
    expect(loaded.aiConfig.text.apiKey, 'sk-persisted');
  });

  test('主设置文件被删除时，从备份恢复', () async {
    final store = DocumentStore('settings.json', baseDirectory: root);
    final repo = SettingsRepository(store: store);

    await repo.save(keyed);
    await repo.save(const AppSettings()); // 生成带 Key 的备份
    await store.delete();

    final loaded = await repo.load();
    expect(loaded.aiConfig.vision.apiKey, 'sk-persisted');
  });

  test('用户只清空 API Key 时，不会被旧备份复活', () async {
    final store = DocumentStore('settings.json', baseDirectory: root);
    final repo = SettingsRepository(store: store);

    await repo.save(keyed);
    const noKey = AppSettings(
      aiConfig: AiConfig(
        vision: AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          model: 'vision-model',
        ),
        text: AiModelConfig(
          baseUrl: 'https://api.example.com/v1',
          model: 'text-model',
        ),
      ),
    );
    await repo.save(noKey);

    final loaded = await repo.load();
    expect(loaded.aiConfig.vision.apiKey, isEmpty);
    expect(loaded.aiConfig.text.apiKey, isEmpty);
  });
}

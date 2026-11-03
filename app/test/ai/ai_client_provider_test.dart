import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/repositories/settings_repository.dart';
import 'package:course_timetable/features/ai/ai_client_provider.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(this.current);

  final AppSettings current;

  @override
  Future<AppSettings> load() async => current;
}

void main() {
  test('设置加载后 AI 客户端直接使用已保存的 Key，无需再点保存', () async {
    const settings = AppSettings(
      aiConfig: AiConfig(
        vision: AiModelConfig(
          baseUrl: 'https://vision.example/v1',
          apiKey: 'sk-vision',
          model: 'vision-model',
        ),
        text: AiModelConfig(
          baseUrl: 'https://text.example/v1',
          apiKey: 'sk-text',
          model: 'text-model',
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider
            .overrideWithValue(_FakeSettingsRepository(settings)),
      ],
    );
    addTearDown(container.dispose);

    // 模拟启动时设置已加载，但 aiConfigProvider 尚未被任何页面读取。
    await container.read(settingsProvider.future);

    expect(container.read(visionAiClientProvider).config.apiKey, 'sk-vision');
    expect(container.read(textAiClientProvider).config.apiKey, 'sk-text');
  });
}

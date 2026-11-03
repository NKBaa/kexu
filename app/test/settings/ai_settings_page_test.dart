import 'package:course_timetable/data/models/ai_config.dart';
import 'package:course_timetable/data/models/ai_model_catalog.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/features/settings/pages/ai_settings_page.dart';
import 'package:course_timetable/features/settings/providers/ai_model_catalog_provider.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this.current);

  AppSettings current;

  @override
  Future<AppSettings> build() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    current = settings;
    state = AsyncData(settings);
  }
}

void main() {
  testWidgets('大模型配置页按提供商列出视觉/语言模型，并可进入详情', (tester) async {
    final settings = _FakeSettingsController(
      const AppSettings(
        aiConfig: AiConfig(
          vision: AiModelConfig(
            baseUrl: 'https://a/v1',
            apiKey: 'sk-v',
            model: 'vision-model',
          ),
          text: AiModelConfig(
            baseUrl: 'https://b/v1',
            apiKey: 'sk-t',
            model: 'text-model',
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => settings),
          // 测试不联网：模型名单直接用内置兜底。
          aiModelCatalogProvider.overrideWith((ref) async => AiModelCatalog.builtIn()),
        ],
        child: const MaterialApp(home: AiSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai_provider_vision')), findsOneWidget);
    expect(find.byKey(const Key('ai_provider_text')), findsOneWidget);
    expect(find.text('视觉模型'), findsWidgets);
    expect(find.text('语言模型'), findsWidgets);
    expect(find.text('vision-model'), findsOneWidget);
    expect(find.text('text-model'), findsOneWidget);

    // 两个推荐服务商默认折叠，只显示标题/说明。
    expect(find.byKey(const Key('siliconflow_recommend_card')), findsOneWidget);
    expect(find.byKey(const Key('cotton_recommend_card')), findsOneWidget);
    expect(find.byKey(const Key('siliconflow_register_ai')), findsNothing);
    expect(find.byKey(const Key('cotton_register_ai')), findsNothing);

    // 点开硅基流动：注册/充值/使用指南出现。
    await tester.tap(find.byKey(const Key('siliconflow_recommend_card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('siliconflow_register_ai')), findsOneWidget);
    expect(find.byKey(const Key('siliconflow_recharge_ai')), findsOneWidget);
    expect(find.byKey(const Key('siliconflow_guide_ai')), findsOneWidget);

    await tester.tap(find.byKey(const Key('siliconflow_guide_ai')));
    await tester.pumpAndSettle();
    expect(find.text('硅基流动'), findsWidgets);
    expect(find.byKey(const Key('siliconflow_register_button')), findsOneWidget);
    expect(find.byKey(const Key('siliconflow_recharge_button')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // 点开 CottonAPI：注册/充值入口出现。
    await tester.ensureVisible(find.byKey(const Key('cotton_recommend_card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cotton_recommend_card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cotton_register_ai')), findsOneWidget);
    expect(find.byKey(const Key('cotton_recharge_ai')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai_provider_vision')));
    await tester.pumpAndSettle();
    expect(find.text('服务商预设'), findsOneWidget);
  });
}

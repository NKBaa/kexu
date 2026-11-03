import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/app_theme_spec.dart';
import 'package:course_timetable/data/services/theme_market_service.dart';
import 'package:course_timetable/features/settings/pages/theme_center_page.dart';
import 'package:course_timetable/features/settings/pages/theme_editor_page.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/settings/providers/theme_market_provider.dart';
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
  testWidgets('主题中心展示内置/自定义/市场主题并可应用', (tester) async {
    final settings = _FakeSettingsController(const AppSettings());
    final market = ThemeMarketCatalog(
      themes: [
        AppThemeSpec.fromJson({
          'id': 'market-test',
          'name': '市场主题',
          'light': {
            'seed': '#C45C7C',
            'surface': '#FFF7FA',
            'card': '#FFFFFF',
            'ink': '#2A1B22',
          },
          'dark': {
            'seed': '#E8A2BC',
            'surface': '#1A1216',
            'card': '#241A1F',
            'ink': '#F5E7EC',
          },
        }),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => settings),
          themeMarketProvider.overrideWith((ref) async => market),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ThemeCenterPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主题中心'), findsOneWidget);
    expect(find.text('内置主题'), findsOneWidget);
    expect(find.text('我的主题'), findsOneWidget);
    expect(find.text('主题市场'), findsOneWidget);
    expect(find.text('市场主题'), findsOneWidget);
    expect(find.byKey(const Key('theme_new_button')), findsOneWidget);

    await tester.tap(find.text('樱花'));
    await tester.pumpAndSettle();
    expect(settings.current.activeThemeId, 'sakura');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('主题编辑器可预览并保存 JSON 主题', (tester) async {
    AppThemeSpec? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<AppThemeSpec>(
                    MaterialPageRoute<AppThemeSpec>(
                      builder: (_) => const ThemeEditorPage(),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('主题代码（JSON）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('theme_editor_preview')));
    await tester.pumpAndSettle();
    expect(find.text('预览'), findsWidgets);
    expect(find.text('示例按钮'), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme_editor_save')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.id, 'my-theme');
  });
}

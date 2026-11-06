import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/app_theme_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设置持久化保留当前主题与自定义主题', () {
    final spec = AppThemeSpec.fromCode(AppThemeSpec.template);
    final settings = const AppSettings().copyWith(
      activeThemeId: spec.id,
      customThemes: [spec],
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.activeThemeId, 'my-theme');
    expect(restored.customThemes, hasLength(1));
    expect(restored.customThemes.single.name, '我的主题');
    expect(restored.customThemes.single.light.seed, spec.light.seed);
  });

  test('findTheme 可找到内置与自定义主题', () {
    final custom = AppThemeSpec.fromCode(AppThemeSpec.template);
    expect(findTheme([custom], 'default')?.name, '黑灰牛皮纸（默认）');
    expect(findTheme([custom], 'my-theme')?.name, '我的主题');
    expect(findTheme([custom], 'missing'), isNull);
  });

  test('损坏的自定义主题不会影响整份设置解析', () {
    final restored = AppSettings.fromJson({
      'activeThemeId': 'default',
      'customThemes': [
        {'id': 'bad id', 'name': 'x'},
        {'id': 'ok', 'name': '可用主题'},
      ],
    });
    expect(restored.customThemes, hasLength(1));
    expect(restored.customThemes.single.id, 'ok');
  });
}

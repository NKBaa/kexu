import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/app_theme_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('主题代码', () {
    test('模板可解析并保留色板/圆角', () {
      final spec = AppThemeSpec.fromCode(AppThemeSpec.template);
      expect(spec.id, 'my-theme');
      expect(spec.name, '我的主题');
      expect(spec.radius, 24);
      expect(spec.light.surfaceColor, const Color(0xFFF8F6EE));
      expect(spec.dark.inkColor, const Color(0xFFEDEAE2));
    });

    test('JSON 往返保留主题', () {
      final spec = AppThemeSpec.fromCode(AppThemeSpec.template);
      final decoded = AppThemeSpec.fromJson(spec.toJson());
      expect(decoded.name, spec.name);
      expect(decoded.light.seed, spec.light.seed);
      expect(decoded.dark.surface, spec.dark.surface);
    });

    test('非法 JSON / 缺少 id 会被拒绝', () {
      expect(
        () => AppThemeSpec.fromCode('{not-json'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AppThemeSpec.fromCode('{"name":"x"}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AppThemeSpec.fromCode('{"id":"default","name":"x"}'),
        returnsNormally,
      );
    });

    test('内置主题覆盖默认与几个风格', () {
      expect(AppThemeSpec.builtIns, hasLength(5));
      expect(AppThemeSpec.builtIns.first.id, 'default');
      expect(
        AppThemeSpec.builtIns.map((t) => t.id).toSet(),
        hasLength(AppThemeSpec.builtIns.length),
      );
    });

    test('自定义 ThemeData 使用主题色板与圆角', () {
      final spec = AppThemeSpec.fromJson({
        'id': 'test',
        'name': '测试',
        'radius': 16,
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
      });
      final data = AppTheme.custom(spec, Brightness.light);
      expect(data.colorScheme.surface, const Color(0xFFFFF7FA));
      expect(data.scaffoldBackgroundColor, const Color(0xFFFFF7FA));
      expect(data.cardTheme.color, const Color(0xFFFFFFFF));
    });
  });
}

import 'dart:convert';

import 'package:course_timetable/data/models/update_config.dart';
import 'package:course_timetable/data/services/theme_market_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('主题市场固定从加速镜像拉取并解析', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'ghfast.top');
      expect(request.url.toString(), contains('templates/themes.json'));
      return http.Response(
        jsonEncode({
          'version': 1,
          'updatedAt': '2026-11-03',
          'themes': [
            {
              'id': 'market-test',
              'name': '测试市场主题',
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
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final catalog = await ThemeMarketService(client: client).fetch(
      config: const UpdateConfig(repo: 'owner/repo', mirrorMode: 'direct'),
    );
    expect(catalog.themes, hasLength(1));
    expect(catalog.themes.single.name, '测试市场主题');
    expect(catalog.updatedAt, '2026-11-03');
  });

  test('HTTP 失败时抛可展示的异常', () async {
    final client = MockClient((request) async => http.Response('no', 500));
    await expectLater(
      ThemeMarketService(client: client).fetch(
        config: const UpdateConfig(repo: 'owner/repo', mirrorMode: 'direct'),
      ),
      throwsA(isA<ThemeMarketException>()),
    );
  });
}

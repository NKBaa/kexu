import 'dart:convert';
import 'dart:io';

import 'package:course_timetable/data/models/ai_model_catalog.dart';
import 'package:course_timetable/data/models/update_config.dart';
import 'package:course_timetable/data/services/ai_model_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _catalogJson({String updatedAt = '2026-11-03'}) => {
      'version': 1,
      'updatedAt': updatedAt,
      'models': [
        {
          'providerId': 'siliconflow',
          'providerLabel': '硅基流动',
          'id': 'Qwen/Qwen2.5-VL-72B-Instruct',
          'vision': true,
          'text': true,
          'free': false,
          'context': '128K',
          'note': '测试模型',
        },
      ],
    };

void main() {
  group('AiModelCatalog 解析', () {
    test('从 JSON 解析模型能力', () {
      final catalog = AiModelCatalog.fromJson(_catalogJson());
      expect(catalog.models, hasLength(1));
      final model = catalog.models.single;
      expect(model.providerId, 'siliconflow');
      expect(model.vision, isTrue);
      expect(model.text, isTrue);
      expect(model.context, '128K');
    });

    test('缺少 models 或空名单时抛 FormatException', () {
      expect(
        () => AiModelCatalog.fromJson({'version': 1}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AiModelCatalog.fromJson({'models': <Object>[]}),
        throwsA(isA<FormatException>()),
      );
    });

    test('内置名单可作为离线兜底', () {
      final catalog = AiModelCatalog.builtIn();
      expect(catalog.models, isNotEmpty);
      expect(catalog.source, 'builtin');
      expect(catalog.models.any((m) => m.vision), isTrue);
      expect(catalog.models.any((m) => m.text), isTrue);
    });
  });

  group('AiModelCatalogService', () {
    test('按固定加速镜像拉取并标记来源', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'ghfast.top');
        expect(request.url.toString(), contains('templates/ai_models.json'));
        return http.Response(
          jsonEncode(_catalogJson()),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final catalog = await AiModelCatalogService(client: client).fetch(
        config: const UpdateConfig(repo: 'owner/repo', mirrorMode: 'direct'),
      );
      expect(catalog.source, 'github');
      expect(catalog.models.single.id, 'Qwen/Qwen2.5-VL-72B-Instruct');
    });

    test('HTTP 失败时抛可展示的异常', () async {
      final client = MockClient((request) async => http.Response('no', 500));
      await expectLater(
        AiModelCatalogService(client: client).fetch(
          config: const UpdateConfig(repo: 'owner/repo', mirrorMode: 'direct'),
        ),
        throwsA(isA<AiModelCatalogException>()),
      );
    });

    test('缓存可写入并读取，读取时标记 cache', () async {
      final dir = await Directory.systemTemp.createTemp('kexu_ai_models_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final service = AiModelCatalogService(cacheDirectory: dir);
      await service.saveCache(AiModelCatalog.fromJson(_catalogJson()));
      final cached = await service.loadCache();
      expect(cached, isNotNull);
      expect(cached!.source, 'cache');
      expect(cached.models.single.providerLabel, '硅基流动');
    });
  });
}

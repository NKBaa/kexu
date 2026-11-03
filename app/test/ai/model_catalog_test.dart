import 'package:course_timetable/data/models/ai_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内置模型能力目录', () {
    test('收录足够多的模型，字段完整且能力标签自洽', () {
      expect(builtInModels.length, greaterThanOrEqualTo(30));
      final providers = builtInModels.map((m) => m.providerId).toSet();
      for (final id in ['siliconflow', 'zhipu', 'qwen', 'openai', 'deepseek', 'moonshot']) {
        expect(providers, contains(id), reason: '缺少 $id 的模型');
      }

      final ids = <String>{};
      for (final m in builtInModels) {
        expect(m.id.trim(), isNotEmpty);
        expect(m.providerLabel.trim(), isNotEmpty);
        expect(m.context.trim(), isNotEmpty);
        expect(m.note.trim(), isNotEmpty);
        expect(m.vision || m.text, isTrue, reason: '${m.id} 至少支持一种能力');
        expect(ids.add(m.id), isTrue, reason: '模型 id 重复：${m.id}');
      }
    });

    test('findModelInCatalog 忽略大小写与首尾空白', () {
      final model = findModelInCatalog(
        builtInModels,
        '  qwen/qwen2.5-vl-72b-instruct ',
      );
      expect(model, isNotNull);
      expect(model!.vision, isTrue);
      expect(findModelInCatalog(builtInModels, 'not-a-real-model'), isNull);
      expect(findModelInCatalog(builtInModels, ''), isNull);
    });

    test('findModelInCatalog 可给服务端返回的模型名标注能力', () {
      final model = findModelInCatalog(
        builtInModels,
        'deepseek-ai/deepseek-v3',
      );
      expect(model, isNotNull);
      expect(model!.text, isTrue);
      expect(model.vision, isFalse);
    });

    test('视觉任务只返回支持图片的模型', () {
      final vision = builtInModels.where((m) => m.supports(vision: true)).toList();
      final text = builtInModels.where((m) => m.supports(vision: false)).toList();
      expect(vision, isNotEmpty);
      expect(text, isNotEmpty);
      expect(vision.every((m) => m.vision), isTrue);
      expect(text.every((m) => m.text), isTrue);
      expect(vision.length, lessThan(builtInModels.length));
    });
  });
}

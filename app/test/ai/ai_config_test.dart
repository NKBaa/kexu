import 'package:course_timetable/data/models/ai_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiProviderPreset / aiProviderPresets', () {
    test('包含主流服务商，且字段完整', () {
      expect(aiProviderPresets.length, greaterThanOrEqualTo(5));
      final ids = aiProviderPresets.map((p) => p.id).toList();
      for (final required in [
        'siliconflow',
        'cotton',
        'deepseek',
        'zhipu',
        'qwen',
        'openai',
        'custom',
      ]) {
        expect(ids, contains(required), reason: '缺少预设 $required');
      }
      // 硅基流动：官方 OpenAI 兼容地址，视觉/文本都给出默认模型。
      final silicon = aiProviderPresets.firstWhere((p) => p.id == 'siliconflow');
      expect(silicon.defaultBaseUrl, 'https://api.siliconflow.cn/v1');
      expect(silicon.label, contains('推荐'));
      expect(silicon.visionModel, isNotEmpty);
      expect(silicon.textModel, isNotEmpty);
      expect(silicon.note, contains('官网'));
      // 推荐预设：地址与模型都填好，用户只需填 API Key。
      final cotton = aiProviderPresets.firstWhere((p) => p.id == 'cotton');
      expect(cotton.defaultBaseUrl, 'https://api.cottonapi.cloud/v1');
      expect(cotton.visionModel, isNotEmpty);
      expect(cotton.textModel, isNotEmpty);
      expect(cotton.label, contains('推荐'));
      for (final p in aiProviderPresets) {
        expect(p.id.trim(), isNotEmpty);
        expect(p.label.trim(), isNotEmpty);
        expect(p.note.trim(), isNotEmpty);
        // 「自定义」预设故意留空，让用户自己填
        if (p.id != 'custom') {
          expect(p.textModel.trim(), isNotEmpty, reason: '${p.label} 应给出文本模型');
        }
      }
    });

    test('supportsVision 反映 visionModel 是否为空', () {
      for (final p in aiProviderPresets) {
        expect(p.supportsVision, p.visionModel.trim().isNotEmpty);
      }
    });

    test('同时提供视觉与文本两套默认值（可混搭）', () {
      final zhipu = aiProviderPresets.firstWhere((p) => p.id == 'zhipu');
      expect(zhipu.visionModel, isNotEmpty);
      expect(zhipu.textModel, isNotEmpty);

      final deepseek = aiProviderPresets.firstWhere((p) => p.id == 'deepseek');
      expect(deepseek.visionModel, isEmpty, reason: 'DeepSeek 官方不支持图片');
      expect(deepseek.textModel, isNotEmpty);
    });
  });

  group('AiModelConfig 单模型配置', () {
    test('默认空配置', () {
      const c = AiModelConfig();
      expect(c.isConfigured, isFalse);
      expect(c.isEmpty, isTrue);
      expect(c.hasApiKey, isFalse);
      expect(c.chatCompletionsUrl, isEmpty);
    });

    test('isConfigured 只要求 baseUrl 与 model；hasApiKey 单独判断', () {
      const c = AiModelConfig(baseUrl: 'https://x/v1', model: 'm');
      expect(c.isConfigured, isTrue);
      expect(c.hasApiKey, isFalse);
      expect(const AiModelConfig(baseUrl: 'https://x/v1').isConfigured, isFalse);
      expect(const AiModelConfig(model: 'm').isConfigured, isFalse);
    });

    test('chatCompletionsUrl 处理末尾斜杠与已含路径', () {
      String url(String base) => AiModelConfig(baseUrl: base, model: 'm').chatCompletionsUrl;

      expect(url('https://api.deepseek.com/v1'), 'https://api.deepseek.com/v1/chat/completions');
      expect(url('https://api.deepseek.com/v1/'), 'https://api.deepseek.com/v1/chat/completions');
      expect(
        url('https://x/v1/chat/completions'),
        'https://x/v1/chat/completions',
        reason: '不应重复拼接',
      );
    });

    test('modelsUrl 处理末尾斜杠、已含 /models 与 /chat/completions', () {
      String url(String base) => AiModelConfig(baseUrl: base, model: 'm').modelsUrl;

      expect(url('https://api.deepseek.com/v1'), 'https://api.deepseek.com/v1/models');
      expect(url('https://api.deepseek.com/v1/'), 'https://api.deepseek.com/v1/models');
      expect(url('https://x/v1/models'), 'https://x/v1/models', reason: '不应重复拼接');
      expect(
        url('https://x/v1/chat/completions'),
        'https://x/v1/models',
        reason: '粘贴完整 chat 地址时先剥掉再拼 /models',
      );
      expect(url(''), isEmpty);
    });

    test('isEmpty 判断是否完全没填', () {
      expect(const AiModelConfig(baseUrl: 'x').isEmpty, isFalse);
      expect(const AiModelConfig(apiKey: 'k').isEmpty, isFalse);
    });

    test('JSON 往返', () {
      const c = AiModelConfig(
        baseUrl: 'https://x/v1',
        apiKey: 'sk-1',
        model: 'm1',
        temperature: 0.3,
        timeoutSeconds: 90,
      );
      final back = AiModelConfig.fromJson(c.toJson());
      expect(back.baseUrl, c.baseUrl);
      expect(back.apiKey, c.apiKey);
      expect(back.model, c.model);
      expect(back.temperature, 0.3);
      expect(back.timeoutSeconds, 90);
    });

    test('copyWith', () {
      const c = AiModelConfig(baseUrl: 'a', model: 'm');
      final n = c.copyWith(model: 'm2');
      expect(n.model, 'm2');
      expect(n.baseUrl, 'a');
    });
  });

  group('AiConfig 容器：视觉与文本分开', () {
    test('两类可独立配置，互不影响', () {
      const cfg = AiConfig(
        vision: AiModelConfig(baseUrl: 'https://a/v1', model: 'vl-model', apiKey: 'k1'),
        text: AiModelConfig(baseUrl: 'https://b/v1', model: 'text-model', apiKey: 'k2'),
      );

      expect(cfg.visionConfigured, isTrue);
      expect(cfg.textConfigured, isTrue);
      expect(cfg.isConfigured, isTrue);
      expect(cfg.vision.baseUrl, isNot(cfg.text.baseUrl));
      expect(cfg.vision.model, isNot(cfg.text.model));
    });

    test('只配了文本时，视觉不可用', () {
      const cfg = AiConfig(text: AiModelConfig(baseUrl: 'https://b/v1', model: 'm'));
      expect(cfg.textConfigured, isTrue);
      expect(cfg.visionConfigured, isFalse);
      expect(cfg.isConfigured, isTrue, reason: '至少一项可用');
    });

    test('只配了视觉时，文本不可用', () {
      const cfg = AiConfig(vision: AiModelConfig(baseUrl: 'https://a/v1', model: 'm'));
      expect(cfg.visionConfigured, isTrue);
      expect(cfg.textConfigured, isFalse);
    });

    test('都没配时 isConfigured 为 false', () {
      const cfg = AiConfig();
      expect(cfg.isConfigured, isFalse);
    });

    test('copyWith 只改一侧', () {
      const cfg = AiConfig(
        vision: AiModelConfig(baseUrl: 'a', model: 'v'),
        text: AiModelConfig(baseUrl: 'b', model: 't'),
      );
      final n = cfg.copyWith(text: const AiModelConfig(baseUrl: 'c', model: 't2'));
      expect(n.vision.model, 'v', reason: '视觉侧不应被改动');
      expect(n.text.model, 't2');
    });

    test('JSON 往返保留两侧独立配置', () {
      const cfg = AiConfig(
        vision: AiModelConfig(baseUrl: 'https://a/v1', model: 'v', apiKey: 'k1'),
        text: AiModelConfig(baseUrl: 'https://b/v1', model: 't', apiKey: 'k2'),
      );
      final back = AiConfig.fromJson(cfg.toJson());
      expect(back.vision.baseUrl, 'https://a/v1');
      expect(back.vision.model, 'v');
      expect(back.text.baseUrl, 'https://b/v1');
      expect(back.text.model, 't');
    });

    test('兼容旧版单模型配置：同时用作视觉与文本', () {
      final legacy = {
        'baseUrl': 'https://api.deepseek.com/v1',
        'apiKey': 'sk-old',
        'model': 'deepseek-chat',
        'temperature': 0.2,
        'timeoutSeconds': 120,
      };

      final cfg = AiConfig.fromJson(legacy);
      expect(cfg.vision.model, 'deepseek-chat', reason: '升级后不应丢失配置');
      expect(cfg.text.model, 'deepseek-chat');
      expect(cfg.vision.apiKey, 'sk-old');
      expect(cfg.text.apiKey, 'sk-old');
      expect(cfg.isConfigured, isTrue);
    });

    test('新格式里缺某侧时，该侧为空配置', () {
      final cfg = AiConfig.fromJson({
        'text': {'baseUrl': 'https://b/v1', 'model': 'm'},
      });
      expect(cfg.textConfigured, isTrue);
      expect(cfg.visionConfigured, isFalse);
    });

    test('完全空的 JSON 得到空配置', () {
      final cfg = AiConfig.fromJson(const {});
      expect(cfg.isConfigured, isFalse);
    });
  });
}

import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/update_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateConfig 默认值', () {
    test('默认写死本仓库、自动检查默认开启、镜像默认自动', () {
      const config = UpdateConfig();
      expect(config.repo, defaultUpdateRepo);
      expect(defaultUpdateRepo, 'NKBaa/kexu');
      expect(config.isConfigured, isTrue);
      expect(config.mirrorMode, 'auto');
      expect(config.mirrorPresetId, 'ghfast');
      expect(config.customMirrorPrefix, '');
      expect(config.autoCheck, isTrue);
      expect(config.ignoredVersion, '');
      expect(config.lastCheckedAt, '');
    });

    test('清空 repo 后视为未配置（不发请求）', () {
      expect(const UpdateConfig(repo: '').isConfigured, isFalse);
      expect(const UpdateConfig(repo: '  ').isConfigured, isFalse);
    });

    test('isConfigured 只认 owner/repo（容忍粘贴完整链接与结尾斜杠）', () {
      expect(const UpdateConfig(repo: 'owner/repo').isConfigured, isTrue);
      expect(
        const UpdateConfig(repo: ' https://github.com/owner/repo/ ').isConfigured,
        isTrue,
      );
      expect(
        const UpdateConfig(repo: 'https://github.com/owner/repo').normalizedRepo,
        'owner/repo',
      );
      expect(const UpdateConfig(repo: 'owner').isConfigured, isFalse);
      expect(const UpdateConfig(repo: 'a/b/c').isConfigured, isFalse);
      expect(const UpdateConfig(repo: 'owner/').isConfigured, isFalse);
      expect(const UpdateConfig(repo: '  ').isConfigured, isFalse);
    });
  });

  group('UpdateConfig JSON', () {
    test('roundtrip 保留全部字段', () {
      const config = UpdateConfig(
        repo: 'owner/repo',
        mirrorMode: 'preset',
        mirrorPresetId: 'ghproxy',
        customMirrorPrefix: 'https://ghfast.top/',
        autoCheck: false,
        ignoredVersion: 'v1.2.0',
        lastCheckedAt: '2026-10-01T12:00:00.000',
      );
      final restored = UpdateConfig.fromJson(config.toJson());
      expect(restored.repo, config.repo);
      expect(restored.mirrorMode, config.mirrorMode);
      expect(restored.mirrorPresetId, config.mirrorPresetId);
      expect(restored.customMirrorPrefix, config.customMirrorPrefix);
      expect(restored.autoCheck, config.autoCheck);
      expect(restored.ignoredVersion, config.ignoredVersion);
      expect(restored.lastCheckedAt, config.lastCheckedAt);
    });

    test('旧版 JSON 缺字段时回退默认值', () {
      final restored = UpdateConfig.fromJson(<String, dynamic>{});
      expect(restored.repo, defaultUpdateRepo);
      expect(restored.mirrorMode, 'auto');
      expect(restored.mirrorPresetId, 'ghfast');
      expect(restored.autoCheck, isTrue);
      expect(restored.ignoredVersion, '');
      expect(restored.lastCheckedAt, '');
    });

    test('用户显式清空 repo 时保持为空（不强制回默认）', () {
      final restored = UpdateConfig.fromJson(<String, dynamic>{'repo': ''});
      expect(restored.repo, '');
      expect(restored.isConfigured, isFalse);
    });

    test('非法 mirrorMode / mirrorPresetId 回退到安全默认值', () {
      final restored = UpdateConfig.fromJson(<String, dynamic>{
        'repo': 'owner/repo',
        'mirrorMode': 'something-else',
        'mirrorPresetId': 'unknown-preset',
        'autoCheck': 'yes', // 类型不对也应回退
      });
      expect(restored.mirrorMode, 'auto');
      expect(restored.mirrorPresetId, 'ghfast');
      expect(restored.autoCheck, isTrue);
      expect(restored.isConfigured, isTrue);
    });

    test('AppSettings 旧 JSON 没有 updateConfig 时使用默认配置', () {
      final settings = AppSettings.fromJson(<String, dynamic>{
        'themeMode': 'dark',
      });
      expect(settings.themeMode, 'dark');
      expect(settings.updateConfig.repo, defaultUpdateRepo);
      expect(settings.updateConfig.isConfigured, isTrue);
      expect(settings.updateConfig.autoCheck, isTrue);
    });

    test('AppSettings roundtrip 保留 updateConfig', () {
      const settings = AppSettings(
        updateConfig: UpdateConfig(repo: 'owner/repo', autoCheck: false),
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.updateConfig.repo, 'owner/repo');
      expect(restored.updateConfig.autoCheck, isFalse);
    });
  });

  group('镜像前缀生成', () {
    test('auto：直连优先，再依次尝试国内镜像', () {
      expect(const UpdateConfig().mirrorPrefixes, <String>[
        '',
        'https://ghfast.top/',
        'https://ghproxy.net/',
        'https://gh-proxy.com/',
      ]);
    });

    test('direct：只用直连', () {
      expect(
        const UpdateConfig(mirrorMode: 'direct').mirrorPrefixes,
        <String>[''],
      );
    });

    test('preset：只用选中的预设', () {
      expect(
        const UpdateConfig(mirrorMode: 'preset', mirrorPresetId: 'ghproxy')
            .mirrorPrefixes,
        <String>['https://ghproxy.net/'],
      );
      expect(
        const UpdateConfig(mirrorMode: 'preset', mirrorPresetId: 'ghproxy_com')
            .mirrorPrefixes,
        <String>['https://gh-proxy.com/'],
      );
    });

    test('custom：规范化用户前缀（补协议、补结尾斜杠）', () {
      expect(
        const UpdateConfig(
          mirrorMode: 'custom',
          customMirrorPrefix: 'ghfast.top',
        ).mirrorPrefixes,
        <String>['https://ghfast.top/'],
      );
      expect(
        const UpdateConfig(
          mirrorMode: 'custom',
          customMirrorPrefix: 'https://ghfast.top',
        ).mirrorPrefixes,
        <String>['https://ghfast.top/'],
      );
      // 自定义前缀留空时退化为直连，避免拼出坏地址
      expect(
        const UpdateConfig(mirrorMode: 'custom').mirrorPrefixes,
        <String>[''],
      );
    });

    test('apiPrefixes：API 检查只优先尝试能代理 api.github.com 的镜像', () {
      // auto：直连 → gh-proxy.com（可代理 API）→ 其余只能下载的镜像兜底
      expect(const UpdateConfig().apiPrefixes, <String>[
        '',
        'https://gh-proxy.com/',
        'https://ghfast.top/',
        'https://ghproxy.net/',
      ]);
      // direct：尊重用户选择，只直连
      expect(const UpdateConfig(mirrorMode: 'direct').apiPrefixes, <String>['']);
      // preset ghfast：先试 ghfast（对 API 会 403），再直连，最后 gh-proxy 兜底
      expect(
        const UpdateConfig(mirrorMode: 'preset', mirrorPresetId: 'ghfast')
            .apiPrefixes,
        <String>['https://ghfast.top/', '', 'https://gh-proxy.com/'],
      );
      // preset 本身已是 API 镜像时不重复
      expect(
        const UpdateConfig(mirrorMode: 'preset', mirrorPresetId: 'ghproxy_com')
            .apiPrefixes,
        <String>['https://gh-proxy.com/', ''],
      );
      // custom：自定义前缀 → 直连 → gh-proxy 兜底
      expect(
        const UpdateConfig(
          mirrorMode: 'custom',
          customMirrorPrefix: 'https://ghfast.top/',
        ).apiPrefixes,
        <String>['https://ghfast.top/', '', 'https://gh-proxy.com/'],
      );
    });

    test('镜像预设覆盖 auto / direct / 三个国内镜像 / custom', () {
      final ids = updateMirrorPresets.map((p) => p.id).toSet();
      expect(ids, containsAll(<String>[
        'auto',
        'direct',
        'ghfast',
        'ghproxy',
        'ghproxy_com',
        'custom',
      ]));
      expect(findMirrorPreset('ghfast')?.prefix, 'https://ghfast.top/');
      expect(findMirrorPreset('ghfast')?.mode, 'preset');
      expect(findMirrorPreset('auto')?.mode, 'auto');
      expect(findMirrorPreset('not-exist'), isNull);
    });
  });
}

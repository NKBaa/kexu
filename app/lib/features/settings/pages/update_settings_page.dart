import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/widgets/hint_icon.dart';
import '../../../data/models/update_config.dart';
import '../../../data/services/update_service.dart';
import '../providers/settings_provider.dart';
import 'semester_settings_page.dart' show SettingsSubPage;

/// 更新服务实例（测试可 override 注入假实现，页面不直接 new）。
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

/// 页面内可供测试 / 自动化定位的 Key。
const Key updateRepoFieldKey = Key('update_repo_field');
const Key updateMirrorDropdownKey = Key('update_mirror_dropdown');
const Key updateCustomMirrorFieldKey = Key('update_custom_mirror_field');
const Key updateAutoCheckKey = Key('update_auto_check');
const Key updateCheckButtonKey = Key('update_check_button');
const Key updateResultCardKey = Key('update_result_card');
const Key updateUnconfiguredGuideKey = Key('update_unconfigured_guide');
const Key updateDownloadButtonKey = Key('update_download_button');
const Key updateInstallButtonKey = Key('update_install_button');
const Key updateOpenGithubButtonKey = Key('update_open_github_button');
const Key updateIgnoreButtonKey = Key('update_ignore_button');
const Key updateErrorCardKey = Key('update_error_card');
const Key updateProgressKey = Key('update_progress');

/// 在线更新设置页。
///
/// 交互约定：
/// - 仓库 / 镜像 / 自动检查的改动**即时保存**（下拉与开关立即写回，
///   输入框在提交或离开焦点时写回，避免每敲一个字符就写一次磁盘）；
/// - 检查、下载、安装都通过 [updateServiceProvider] 注入的服务执行，
///   页面本身不持有网络细节，方便 widget 测试用假服务替换；
/// - 未配置仓库时只展示引导，不发任何请求。
class UpdateSettingsPage extends ConsumerStatefulWidget {
  const UpdateSettingsPage({super.key});

  @override
  ConsumerState<UpdateSettingsPage> createState() => _UpdateSettingsPageState();
}

class _UpdateSettingsPageState extends ConsumerState<UpdateSettingsPage> {
  final TextEditingController _repoController = TextEditingController();
  final TextEditingController _customMirrorController = TextEditingController();

  /// 是否已从设置里播种过一次（之后用户的编辑不会被外部更新冲掉）。
  bool _seeded = false;

  // ---- 配置草稿（改动即保存）----
  String _mirrorMode = 'auto';
  String _mirrorPresetId = 'ghfast';
  bool _autoCheck = true;

  // ---- 页面运行态 ----
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  UpdateCheckResult? _result;
  String? _error;
  String? _actionMessage;
  bool _actionMessageIsError = false;
  File? _downloadedFile;
  int _received = 0;
  int? _total;
  double? _progress;

  @override
  void dispose() {
    _repoController.dispose();
    _customMirrorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(settingsProvider);
    return SettingsSubPage(
      title: '检查更新',
      subtitle: '从 GitHub Releases 检查新版本：仓库需发布带 .apk / .exe 的 Release；'
          '国内网络建议保持「自动」镜像，直连失败会自动切换加速线路。',
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('读取设置失败：$e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(settingsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (settings) {
          _seed(settings.updateConfig);
          return _buildBody(context);
        },
      ),
    );
  }

  /// 首次拿到设置时播种草稿；之后只由用户的编辑驱动。
  void _seed(UpdateConfig config) {
    if (_seeded) return;
    _seeded = true;
    _repoController.text = config.repo;
    _customMirrorController.text = config.customMirrorPrefix;
    _mirrorMode = config.mirrorMode;
    _mirrorPresetId = config.mirrorPresetId;
    _autoCheck = config.autoCheck;
  }

  Widget _buildBody(BuildContext context) {
    final config = _composeConfig();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVersionCard(context, config),
        const SizedBox(height: 12),
        _buildConfigCard(context),
        if (!config.isConfigured) ...[
          const SizedBox(height: 12),
          _buildUnconfiguredGuide(context),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _buildErrorCard(context, _error!),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          _buildResultCard(context, _result!),
        ],
        if (_downloadedFile != null) ...[
          const SizedBox(height: 12),
          _buildDownloadedCard(context, _downloadedFile!),
        ],
        if (_actionMessage != null) ...[
          const SizedBox(height: 12),
          _buildMessageCard(context, _actionMessage!),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- 版本卡

  Widget _buildVersionCard(BuildContext context, UpdateConfig config) {
    final theme = Theme.of(context);
    final configured = config.isConfigured;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.system_update,
                  color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前版本 $fullVersion',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _lastCheckedLabel(config),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: updateCheckButtonKey,
              onPressed: (!configured || _checking) ? null : _check,
              icon: _checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(_checking ? '检查中…' : '检查更新'),
            ),
          ],
        ),
      ),
    );
  }

  String _lastCheckedLabel(UpdateConfig config) {
    final raw = config.lastCheckedAt.trim();
    if (raw.isEmpty) return '尚未检查过更新';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '上次检查：$raw';
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '上次检查：${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  // ---------------------------------------------------------------- 配置卡

  Widget _buildConfigCard(BuildContext context) {
    final theme = Theme.of(context);
    final presetId = _selectedPresetId;
    final mirrorDesc = findMirrorPreset(presetId)?.description ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('更新源设置', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: updateRepoFieldKey,
              controller: _repoController,
              decoration: const InputDecoration(
                labelText: 'GitHub 仓库',
                hintText: 'owner/repo，默认 NKBaa/kexu',
                prefixIcon: Icon(Icons.link),
                suffixIcon: HintIcon(
                  message: '默认已指向本仓库；fork 后可改成自己的 owner/repo，'
                      '也可粘贴完整链接。',
                ),
              ),
              onSubmitted: (_) => _persistConfig(),
              onEditingComplete: _persistConfig,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: updateMirrorDropdownKey,
              initialValue: presetId,
              decoration: InputDecoration(
                labelText: '镜像加速',
                prefixIcon: const Icon(Icons.bolt_outlined),
                suffixIcon: mirrorDesc.isEmpty
                    ? null
                    : HintIcon(message: mirrorDesc),
              ),
              items: [
                for (final preset in updateMirrorPresets)
                  DropdownMenuItem<String>(
                    value: preset.id,
                    child: Text(preset.label),
                  ),
              ],
              onChanged: (id) {
                if (id != null) _onMirrorPresetChanged(id);
              },
            ),
            if (_mirrorMode == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                key: updateCustomMirrorFieldKey,
                controller: _customMirrorController,
                decoration: const InputDecoration(
                  labelText: '自定义镜像前缀',
                  hintText: 'https://ghfast.top/',
                  prefixIcon: Icon(Icons.tune),
                  suffixIcon: HintIcon(
                    message: '镜像地址 = 前缀 + 原 GitHub 地址，记得带上结尾的 /。',
                  ),
                ),
                onSubmitted: (_) => _persistConfig(),
                onEditingComplete: _persistConfig,
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              key: updateAutoCheckKey,
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('启动时自动检查更新'),
              subtitle: const Text('发现新版本时在首页底部提示，不打断使用'),
              value: _autoCheck,
              onChanged: (v) {
                setState(() => _autoCheck = v);
                _persistConfig();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 下拉框当前选中的预设 id（把 mirrorMode 映射回某个预设）。
  String get _selectedPresetId {
    if (_mirrorMode == 'auto' ||
        _mirrorMode == 'direct' ||
        _mirrorMode == 'custom') {
      return _mirrorMode;
    }
    final preset = findMirrorPreset(_mirrorPresetId);
    return preset?.mode == 'preset' ? _mirrorPresetId : 'ghfast';
  }

  void _onMirrorPresetChanged(String id) {
    final preset = findMirrorPreset(id);
    if (preset == null) return;
    setState(() {
      _mirrorMode = preset.mode;
      if (preset.mode == 'preset') _mirrorPresetId = preset.id;
    });
    _persistConfig();
  }

  // ---------------------------------------------------------------- 结果卡

  Widget _buildResultCard(BuildContext context, UpdateCheckResult result) {
    final theme = Theme.of(context);
    if (!result.updateAvailable) {
      return Card(
        key: updateResultCardKey,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '已是最新版本（${result.currentVersion}）',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final asset = result.asset;
    final release = result.release;
    return Card(
      key: updateResultCardKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.new_releases_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '发现新版本 ${result.latestVersion}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '当前 ${result.currentVersion} · 发布于 ${release.publishedLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (release.body.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    release.body.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    asset == null
                        ? '这个 Release 没有匹配当前平台的安装包，可在 GitHub 页面手动下载。'
                        : '安装包：${asset.name}（${asset.sizeLabel}）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: asset == null
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: updateDownloadButtonKey,
                  onPressed:
                      (asset == null || _downloading) ? null : _download,
                  icon: _downloading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download, size: 18),
                  label: Text(_downloading ? '下载中…' : '下载并安装'),
                ),
                OutlinedButton.icon(
                  key: updateOpenGithubButtonKey,
                  onPressed: _openReleasePage,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('在 GitHub 打开'),
                ),
                TextButton.icon(
                  key: updateIgnoreButtonKey,
                  onPressed: _ignore,
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: const Text('忽略此版本'),
                ),
              ],
            ),
            if (_downloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                key: updateProgressKey,
                value: _progress,
                minHeight: 4,
              ),
              const SizedBox(height: 4),
              Text(
                _progressLabel(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _progressLabel() {
    final total = _total;
    if (total != null && total > 0) {
      final percent = ((_received / total) * 100).clamp(0, 100).toStringAsFixed(0);
      return '${_formatBytes(_received)} / ${_formatBytes(total)}（$percent%）';
    }
    return '已下载 ${_formatBytes(_received)}';
  }

  // ---------------------------------------------------------------- 下载完成卡

  Widget _buildDownloadedCard(BuildContext context, File file) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download_done, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('下载完成', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              file.path,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: updateInstallButtonKey,
                  onPressed: _installing ? null : _install,
                  icon: _installing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Platform.isAndroid
                              ? Icons.android
                              : Icons.rocket_launch_outlined,
                          size: 18,
                        ),
                  label: Text(
                    Platform.isAndroid ? '安装 APK' : '运行安装包',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _revealDownload,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('打开下载目录'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(BuildContext context, String message) {
    final theme = Theme.of(context);
    final color = _actionMessageIsError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final fg = _actionMessageIsError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _actionMessageIsError
                ? Icons.error_outline
                : Icons.info_outline,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 引导 / 错误

  Widget _buildUnconfiguredGuide(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: updateUnconfiguredGuideKey,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 6),
              Text(
                '仓库地址被清空了',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '默认仓库是 NKBaa/kexu。清空后不会检查更新；'
            '重新填写 owner/repo（或点「恢复默认」）即可。'
            '仓库需要发布 Release，并上传 .apk / .exe 安装包；'
            '没配置时不会发起任何网络请求。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
              height: 1.4,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                _repoController.text = defaultUpdateRepo;
                _persistConfig();
              },
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onTertiaryContainer,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('恢复默认 NKBaa/kexu'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onErrorContainer;
    return Container(
      key: updateErrorCardKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _checking ? null : _check,
              style: TextButton.styleFrom(
                foregroundColor: fg,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 草稿与动作

  UpdateConfig _composeConfig() {
    final base = ref.read(settingsProvider).valueOrNull?.updateConfig ??
        const UpdateConfig();
    return base.copyWith(
      repo: _repoController.text,
      mirrorMode: _mirrorMode,
      mirrorPresetId: _mirrorPresetId,
      customMirrorPrefix: _customMirrorController.text,
      autoCheck: _autoCheck,
    );
  }

  Future<void> _persistConfig({UpdateConfig? override}) async {
    final next = override ?? _composeConfig();
    try {
      await ref.read(settingsProvider.notifier).saveUpdateConfig(next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionMessage = '保存更新设置失败：$e';
        _actionMessageIsError = true;
      });
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    // 先把输入框里的最新内容落库，避免「改了仓库但没提交」导致检查用旧值
    await _persistConfig();
    if (!mounted) return;

    final config = _composeConfig();
    if (!config.isConfigured) {
      setState(() {
        _error = '请先填写 GitHub 仓库（owner/repo），例如 your-name/kexu。';
      });
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
      _result = null;
      _downloadedFile = null;
      _actionMessage = null;
      _progress = null;
      _received = 0;
      _total = null;
    });

    try {
      final result = await ref.read(updateServiceProvider).checkForUpdate(
            config: config,
            currentVersion: fullVersion,
          );
      if (!mounted) return;
      setState(() {
        _checking = false;
        _result = result;
      });
      await _persistConfig(
        override: config.copyWith(
          lastCheckedAt: DateTime.now().toIso8601String(),
        ),
      );
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = '检查更新失败：$e';
      });
    }
  }

  Future<void> _download() async {
    final result = _result;
    final asset = result?.asset;
    if (result == null || asset == null || _downloading) return;

    setState(() {
      _downloading = true;
      _error = null;
      _actionMessage = null;
      _downloadedFile = null;
      _received = 0;
      _total = asset.size > 0 ? asset.size : null;
      _progress = _total == null ? null : 0.0;
    });

    try {
      final file = await ref.read(updateServiceProvider).download(
            release: result.release,
            asset: asset,
            config: _composeConfig(),
            onProgress: (received, total) {
              if (!mounted) return;
              setState(() {
                _received = received;
                _total = total ?? _total;
                final known = _total;
                _progress = (known != null && known > 0)
                    ? (received / known).clamp(0.0, 1.0)
                    : null;
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadedFile = file;
        _progress = 1;
      });
      // 下载完成后直接拉起系统安装界面，不需要用户再点一次「安装 APK」。
      await _install();
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '下载失败：$e';
      });
    }
  }

  Future<void> _install() async {
    final file = _downloadedFile;
    final result = _result;
    if (file == null || result == null || _installing) return;

    setState(() {
      _installing = true;
      _actionMessage = null;
      _actionMessageIsError = false;
    });
    try {
      final installResult = await ref
          .read(updateServiceProvider)
          .install(file, release: result.release);
      if (!mounted) return;
      setState(() {
        _installing = false;
        _actionMessage = installResult.message;
        _actionMessageIsError = !installResult.success;
      });
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _actionMessage = e.toString();
        _actionMessageIsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _actionMessage = '安装失败：$e';
        _actionMessageIsError = true;
      });
    }
  }

  Future<void> _revealDownload() async {
    final file = _downloadedFile;
    if (file == null) return;
    try {
      await ref.read(updateServiceProvider).revealFile(file);
      if (!mounted) return;
      setState(() {
        _actionMessage = '已打开下载目录';
        _actionMessageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionMessage = '打开下载目录失败：$e';
        _actionMessageIsError = true;
      });
    }
  }

  Future<void> _openReleasePage() async {
    final result = _result;
    if (result == null) return;
    final opened = await ref
        .read(updateServiceProvider)
        .openReleasePage(result.release);
    if (!mounted) return;
    setState(() {
      _actionMessage = opened
          ? '已用浏览器打开 GitHub Release 页面。'
          : '无法打开浏览器，请手动访问 ${result.release.htmlUrl}';
      _actionMessageIsError = !opened;
    });
  }

  Future<void> _ignore() async {
    final result = _result;
    if (result == null) return;
    final next = _composeConfig().copyWith(ignoredVersion: result.latestVersion);
    await _persistConfig(override: next);
    if (!mounted) return;
    setState(() {
      _result = null;
      _actionMessage = '已忽略版本 ${result.latestVersion}，之后不再提示';
      _actionMessageIsError = false;
    });
  }
}

/// 把字节数格式化成可读文本（与 [UpdateAsset.sizeLabel] 保持一致的量级）。
String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
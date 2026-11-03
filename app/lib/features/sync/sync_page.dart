import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_config.dart';
import 'providers/sync_controller.dart';
import 'widgets/webdav_form.dart';

/// 页面内可供测试/自动化定位的 Key。
const Key syncProgressKey = Key('sync_progress');
const Key syncDirtyBannerKey = Key('sync_dirty_banner');
const Key syncTestErrorKey = Key('sync_test_error');
const Key syncConflictCardKey = Key('sync_conflict_card');

/// 网盘同步设置页。
///
/// 设计要点：
/// - **草稿式编辑**：开关与表单改动先留在页面里，点「保存配置」才落库
///   （与设置页一致），避免每敲一个字符就写一次 `settings.json`；
/// - **界面只读契约**：配置来自 `syncConfigProvider`，运行状态来自
///   `syncStatusProvider`，动作走 `syncControllerProvider`；
/// - 同步进行中禁用所有动作按钮，避免并发触发多次同步。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final GlobalKey<FormState> _webdavFormKey = GlobalKey<FormState>();

  // ---- 草稿（点「保存配置」才写回 provider）----
  bool _enabled = false;
  bool _autoSync = true;
  WebDavConfig _webdav = const WebDavConfig();

  /// 草稿是否已经从 provider 播种过一次（之后不再被外部更新覆盖）。
  bool _seeded = false;

  // ---- 局部忙碌态 ----
  bool _saving = false;
  bool _testing = false;
  bool _resetting = false;

  /// 测试连接失败的原因（红色卡片展示）。
  String? _testError;
  String? _testDetail;

  @override
  Widget build(BuildContext context) {
    final asyncConfig = ref.watch(syncConfigProvider);
    final status = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('网盘同步')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: asyncConfig.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => _buildLoadError(context, e),
            data: (config) {
              _seedDraft(config);
              return _buildContent(context, config, status);
            },
          ),
        ),
      ),
    );
  }

  /// 首次拿到配置时播种草稿；之后用户的编辑不会被 provider 的更新冲掉。
  void _seedDraft(SyncConfig config) {
    if (_seeded) return;
    _seeded = true;
    _enabled = config.enabled;
    _autoSync = config.autoSync;
    _webdav = config.webdav;
  }

  Widget _buildLoadError(BuildContext context, Object error) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text('读取同步配置失败：$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(syncConfigProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, SyncConfig config, SyncStatus status) {
    final running = status.running;
    final dirty = _isDirty(config);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _buildStatusCard(context, config, status),
        if (status.conflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildConflictCard(context, status.conflicts),
        ],
        const SizedBox(height: 12),
        _buildSwitchCard(context, config, running),
        const SizedBox(height: 12),
        _buildBackendCard(context, config, running),
        const SizedBox(height: 12),
        _buildActionCard(context, config, status, dirty: dirty, running: running),
      ],
    );
  }

  // ---------------------------------------------------------------- 状态卡

  Widget _buildStatusCard(BuildContext context, SyncConfig config, SyncStatus status) {
    final theme = Theme.of(context);
    final running = status.running;
    final failed = !running && status.error != null;
    final succeeded = !running && !failed && status.lastResult != null;

    final Color accent;
    final String stateLabel;
    final IconData stateIcon;
    if (running) {
      accent = theme.colorScheme.primary;
      stateLabel = '同步中…';
      stateIcon = Icons.sync;
    } else if (failed) {
      accent = theme.colorScheme.error;
      stateLabel = '上次同步失败';
      stateIcon = Icons.error_outline;
    } else if (succeeded) {
      accent = theme.colorScheme.primary;
      stateLabel = '同步成功';
      stateIcon = Icons.check_circle_outline;
    } else {
      accent = theme.colorScheme.outline;
      stateLabel = config.enabled ? '已启用' : '未启用';
      stateIcon = Icons.radio_button_unchecked;
    }

    final result = status.lastResult;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    running ? Icons.sync : Icons.cloud_sync_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '同步状态',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${syncBackendLabel(config.backend)} · ${config.lastSyncLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (config.lastSyncAtMs == 0)
                        Text(
                          '尚未同步过，填写网盘信息后先点「测试连接」',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildStateChip(theme, accent, stateIcon, stateLabel, running: running),
              ],
            ),
            if (running) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(key: syncProgressKey, minHeight: 3),
            ],
            if (!running && result != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.history, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '上次结果：${result.summary}'
                      '${result.uploaded ? '（已上传）' : ''}'
                      '${result.downloaded ? '（已拉取）' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (status.error != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${status.error}（可在下方「测试连接」查看详细原因）',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStateChip(
    ThemeData theme,
    Color accent,
    IconData icon,
    String label, {
    required bool running,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: accent),
            )
          else
            Icon(icon, size: 13, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 冲突卡

  Widget _buildConflictCard(BuildContext context, List<String> conflicts) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onTertiaryContainer;
    return Card(
      key: syncConflictCardKey,
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  '同步冲突（${conflicts.length}）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '下列条目两端都改过，已保留本机版本。请核对后按需手动调整，避免另一端的新改动被覆盖。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg.withValues(alpha: 0.92),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            for (final c in conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: theme.textTheme.bodySmall?.copyWith(color: fg)),
                    Expanded(
                      child: Text(
                        c,
                        style: theme.textTheme.bodySmall?.copyWith(color: fg),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 开关卡

  Widget _buildSwitchCard(BuildContext context, SyncConfig config, bool running) {
    final theme = Theme.of(context);
    final draftConfig = _composeConfig(config);
    return _SyncSection(
      icon: Icons.toggle_on_outlined,
      title: '同步开关',
      subtitle: '决定是否上传 / 拉取，以及是否自动同步',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: _enabled,
            onChanged: running ? null : (v) => setState(() => _enabled = v),
            secondary: const Icon(Icons.cloud_outlined),
            contentPadding: EdgeInsets.zero,
            title: const Text('启用网盘同步'),
            subtitle: const Text('关闭后不会上传或拉取课表'),
          ),
          Opacity(
            opacity: _enabled ? 1 : 0.45,
            child: SwitchListTile(
              value: _autoSync,
              onChanged: (!_enabled || running) ? null : (v) => setState(() => _autoSync = v),
              secondary: const Icon(Icons.sync),
              contentPadding: EdgeInsets.zero,
              title: const Text('自动同步'),
              subtitle: const Text('课表改动后自动上传，启动时自动拉取'),
            ),
          ),
          if (!_enabled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '同步未启用：填好下面的网盘信息并保存后，打开上方开关即可生效。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_enabled && !draftConfig.isConfigured)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '网盘信息还不完整，即使启用也不会真正执行同步。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 后端 + 表单

  Widget _buildBackendCard(BuildContext context, SyncConfig config, bool running) {
    final theme = Theme.of(context);
    return _SyncSection(
      icon: Icons.cloud_outlined,
      title: '网盘类型',
      subtitle: 'WebDAV 通用同步（坚果云 / Nextcloud / 群晖 / InfiniCLOUD）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebDavForm(
            formKey: _webdavFormKey,
            initial: _webdav,
            enabled: !running,
            onChanged: (next) => setState(() {
              _webdav = next;
              _testError = null;
              _testDetail = null;
            }),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '同步的是整份课表 JSON：两端都改过的课程会保留本机版本并提示冲突。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 操作区

  Widget _buildActionCard(
    BuildContext context,
    SyncConfig config,
    SyncStatus status, {
    required bool dirty,
    required bool running,
  }) {
    final theme = Theme.of(context);
    final busy = running || _testing || _saving || _resetting;

    return _SyncSection(
      icon: Icons.play_circle_outline,
      title: '同步操作',
      subtitle: '测试连接、立即同步与重置同步状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dirty)
            Container(
              key: syncDirtyBannerKey,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 16,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '有未保存的改动',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (dirty) const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: (running || _testing) ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_testing ? '测试中…' : '测试连接'),
              ),
              FilledButton.tonalIcon(
                onPressed: (running || _testing) ? null : _syncNow,
                icon: running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 18),
                label: Text(running ? '同步中…' : '立即同步'),
              ),
              FilledButton.icon(
                onPressed: (!dirty || busy) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? '保存中…' : '保存配置'),
              ),
              TextButton.icon(
                onPressed: busy ? null : _resetSyncState,
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                icon: _resetting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt, size: 18),
                label: const Text('重置同步状态'),
              ),
            ],
          ),
          if (_testError != null) ...[
            const SizedBox(height: 10),
            _buildTestErrorCard(context),
          ],
          const SizedBox(height: 10),
          Text(
            '「重置同步状态」只清除本机的同步基线，不会删除任何课程；'
            '下次同步会以远端为准重新比对。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestErrorCard(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onErrorContainer;
    return Container(
      key: syncTestErrorKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
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
                  '连接失败：$_testError',
                  style: theme.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ),
            ],
          ),
          if (_testDetail != null && _testDetail!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 22),
              child: SelectableText(
                _testDetail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 11,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _testError = null;
                _testDetail = null;
              }),
              style: TextButton.styleFrom(foregroundColor: fg, visualDensity: VisualDensity.compact),
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 草稿与动作

  SyncConfig _composeConfig(SyncConfig base) => base.copyWith(
        enabled: _enabled,
        autoSync: _autoSync,
        webdav: _webdav,
      );

  bool _isDirty(SyncConfig config) =>
      _enabled != config.enabled ||
      _autoSync != config.autoSync ||
      !_sameWebDav(_webdav, config.webdav);

  static bool _sameWebDav(WebDavConfig a, WebDavConfig b) =>
      a.url.trim() == b.url.trim() &&
      a.username.trim() == b.username.trim() &&
      a.password == b.password &&
      a.remotePath.trim() == b.remotePath.trim();

  bool _validateActiveForm() {
    final form = _webdavFormKey.currentState;
    return form?.validate() ?? false;
  }

  Future<bool> _save() async {
    if (_saving) return false;
    if (!_validateActiveForm()) {
      _toast('请先修正表单里的错误', error: true);
      return false;
    }
    setState(() => _saving = true);
    try {
      final base = await ref.read(syncConfigProvider.future);
      final next = _composeConfig(base);
      await ref.read(syncConfigProvider.notifier).save(next);
      if (!mounted) return false;
      _toast(
        next.enabled && !next.isConfigured
            ? '已保存，但网盘信息还不完整，同步不会执行'
            : '同步配置已保存',
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      _toast('保存失败：$e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    final base = ref.read(syncConfigProvider).valueOrNull ?? const SyncConfig();
    final draft = _composeConfig(base);
    setState(() {
      _testing = true;
      _testError = null;
      _testDetail = null;
    });
    try {
      await ref.read(syncControllerProvider).testConnection(draft);
      if (!mounted) return;
      _toast('连接成功');
    } on SyncException catch (e) {
      if (!mounted) return;
      setState(() {
        _testError = e.message;
        _testDetail = e.detail;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testError = '测试失败：$e';
        _testDetail = null;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _syncNow() async {
    if (ref.read(syncStatusProvider).running || _testing) return;

    final saved = ref.read(syncConfigProvider).valueOrNull ?? const SyncConfig();
    if (_isDirty(saved)) {
      final choice = await _askSaveBeforeSync();
      if (choice == null || !mounted) return;
      if (choice) {
        final ok = await _save();
        if (!ok || !mounted) return;
      }
    }

    try {
      final result = await ref.read(syncControllerProvider).syncNow();
      if (!mounted) return;
      if (result == null) {
        _toast('同步未执行：请先启用同步并填好网盘信息', error: true);
        return;
      }
      _toast(result.summary);
    } on SyncException catch (e) {
      if (!mounted) return;
      _toast('同步失败：${e.message}', error: true);
    } catch (e) {
      if (!mounted) return;
      _toast('同步失败：$e', error: true);
    }
  }

  Future<bool?> _askSaveBeforeSync() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('有未保存的改动'),
        content: const Text('同步会使用已保存的配置。要先保存再同步吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('直接同步'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存并同步'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetSyncState() async {
    final ok = await _confirm(
      title: '重置同步状态？',
      message: '将清除本机保存的同步基线，并把「上次同步时间」清空。\n\n'
          '下次同步会以远端为准重新比对：不会删除任何课程，'
          '但两端不一致时会重新上传 / 下载一次。',
      confirmText: '重置',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _resetting = true);
    try {
      await ref.read(syncControllerProvider).resetSyncState();
      if (!mounted) return;
      _toast('已重置同步状态');
    } catch (e) {
      if (!mounted) return;
      _toast('重置失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  // ---------------------------------------------------------------- 工具

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
          duration: Duration(seconds: error ? 5 : 3),
        ),
      );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// 统一的分组卡片（图标 + 标题 + 副标题 + 内容）。
class _SyncSection extends StatelessWidget {
  const _SyncSection({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}


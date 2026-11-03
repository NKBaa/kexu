import 'package:flutter/material.dart';

import '../../../core/widgets/hint_icon.dart';
import '../../../data/sync/sync_config.dart';

/// 字段 Key：测试与自动化可用它精确定位（避免依赖中文文案）。
const Key webdavUrlFieldKey = Key('webdav_url_field');
const Key webdavUsernameFieldKey = Key('webdav_username_field');
const Key webdavPasswordFieldKey = Key('webdav_password_field');
const Key webdavPasswordToggleKey = Key('webdav_password_toggle');
const Key webdavRemotePathFieldKey = Key('webdav_remote_path_field');
const Key webdavFullUrlTextKey = Key('webdav_full_url_text');
const Key webdavExampleFillKey = Key('webdav_example_fill');

/// 坚果云示例地址。
const String webdavJianguoyunExampleUrl = 'https://dav.jianguoyun.com/dav/';

/// WebDAV 表单：服务器地址 / 用户名 / 密码 / 远端路径。
///
/// 本控件**不持有业务状态**：任意字段变化都会通过 [onChanged] 把完整草稿交给
/// 父级（`SyncPage` 负责「是否保存」与「未保存」标记）。这样切换后端、页面
/// 因同步状态刷新而重建时，用户已输入的内容都不会丢。
///
/// 另外它会实时用 [WebDavConfig.remoteFileUrl] 拼出最终请求的完整 URL ——
/// WebDAV 出错时最常见的原因就是「地址少个斜杠 / 路径拼错」，
/// 让用户直接看到拼好的 URL 能省掉大量排查。
class WebDavForm extends StatefulWidget {
  const WebDavForm({
    super.key,
    required this.initial,
    required this.onChanged,
    this.formKey,
    this.enabled = true,
  });

  /// 初始值（通常是已保存的配置或父级草稿）。
  final WebDavConfig initial;

  /// 任意字段变化时回调完整草稿。
  final ValueChanged<WebDavConfig> onChanged;

  /// 父级用于统一校验的 `Form` key。
  final GlobalKey<FormState>? formKey;

  final bool enabled;

  @override
  State<WebDavForm> createState() => _WebDavFormState();
}

class _WebDavFormState extends State<WebDavForm> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _remotePathCtrl;

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initial.url);
    _usernameCtrl = TextEditingController(text: widget.initial.username);
    _passwordCtrl = TextEditingController(text: widget.initial.password);
    _remotePathCtrl = TextEditingController(text: widget.initial.remotePath);
    for (final c in [_urlCtrl, _usernameCtrl, _passwordCtrl, _remotePathCtrl]) {
      c.addListener(_handleChanged);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _remotePathCtrl.dispose();
    super.dispose();
  }

  /// 当前输入框里的草稿。
  ///
  /// 密码不做 trim：密码里的空格可能是有效字符，改动用户密码比多几个空格更糟。
  WebDavConfig _draft() => WebDavConfig(
        url: _urlCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        remotePath: _remotePathCtrl.text.trim(),
      );

  void _handleChanged() {
    // 先让父级拿到最新草稿（用于脏标记与保存），再刷新本控件的 URL 预览。
    widget.onChanged(_draft());
    setState(() {});
  }

  void _fillJianguoyunExample() {
    _urlCtrl.text = webdavJianguoyunExampleUrl;
    if (_remotePathCtrl.text.trim().isEmpty) {
      _remotePathCtrl.text = const WebDavConfig().remotePath;
    }
    _urlCtrl.selection = TextSelection.collapsed(offset: _urlCtrl.text.length);
  }

  static String? _validateUrl(String? value) {
    final s = (value ?? '').trim();
    if (s.isEmpty) return '请填写 WebDAV 服务器地址';
    final uri = Uri.tryParse(s);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return '地址需以 http:// 或 https:// 开头';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final fullUrl = _draft().remoteFileUrl;

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildJianguoyunHint(context),
          const SizedBox(height: 12),
          TextFormField(
            key: webdavUrlFieldKey,
            controller: _urlCtrl,
            enabled: widget.enabled,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            validator: _validateUrl,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '服务器地址',
              hintText: webdavJianguoyunExampleUrl,
              prefixIcon: Icon(Icons.link, size: 18),
              suffixIcon: HintIcon(
                message: '坚果云示例：$webdavJianguoyunExampleUrl\n'
                    '多数服务要求地址以 / 结尾，末尾没写会自动补上。',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: webdavUsernameFieldKey,
            controller: _usernameCtrl,
            enabled: widget.enabled,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '用户名',
              hintText: '坚果云填账号邮箱',
              prefixIcon: Icon(Icons.person_outline, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: webdavPasswordFieldKey,
            controller: _passwordCtrl,
            enabled: widget.enabled,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              isDense: true,
              labelText: '密码（应用密码）',
              hintText: '不是网盘登录密码',
              prefixIcon: const Icon(Icons.key_outlined, size: 18),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HintIcon(
                    message: '已保存的密码以圆点显示，点右侧眼睛可临时查看。\n'
                        '这里填「应用密码」，不是网盘登录密码。',
                  ),
                  IconButton(
                    key: webdavPasswordToggleKey,
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: webdavRemotePathFieldKey,
            controller: _remotePathCtrl,
            enabled: widget.enabled,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            validator: (v) => (v ?? '').trim().isEmpty ? '请填写远端文件路径' : null,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '远端路径',
              hintText: '/course_timetable/timetable.json',
              prefixIcon: Icon(Icons.folder_outlined, size: 18),
              suffixIcon: HintIcon(
                message: '相对服务器地址的路径；目录不存在会自动创建。',
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildFullUrlPreview(context, fullUrl),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 片段

  Widget _buildJianguoyunHint(BuildContext context) {
    return Row(
      children: [
        const HintIcon(
          message: '坚果云示例：地址 $webdavJianguoyunExampleUrl\n'
              '密码请填「应用密码」而不是登录密码：坚果云 账户信息 → 安全选项 → '
              '添加应用密码，生成后填入下方。',
        ),
        const SizedBox(width: 4),
        TextButton.icon(
          key: webdavExampleFillKey,
          onPressed: widget.enabled ? _fillJianguoyunExample : null,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          icon: const Icon(Icons.auto_fix_high, size: 15),
          label: const Text('填入示例地址'),
        ),
      ],
    );
  }

  Widget _buildFullUrlPreview(BuildContext context, String fullUrl) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.alt_route, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              fullUrl.isEmpty ? '填写服务器地址后，这里会显示拼好的完整远端 URL' : '完整远端 URL：$fullUrl',
              key: webdavFullUrlTextKey,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
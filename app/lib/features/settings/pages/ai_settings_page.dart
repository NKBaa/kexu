import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/ai_config.dart';
import '../../../data/models/ai_model_catalog.dart';
import '../providers/ai_model_catalog_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/ai_config_form.dart';
import 'semester_settings_page.dart' show SettingsSubPage;
import 'silicon_flow_guide_page.dart';

/// 大模型（AI）配置页，采用「提供商」列表：
/// 视觉模型与语言模型各是一张服务商卡片，点进详情再配置。
class AiSettingsPage extends ConsumerWidget {
  const AiSettingsPage({super.key});

  /// 推荐的服务商（OpenAI 兼容网关）。
  static const String cottonApiUrl = 'https://api.cottonapi.cloud';
  static const String cottonWalletUrl = 'https://api.cottonapi.cloud/wallet';

  /// 打开服务商官方网页（课序不接触账号密码/支付信息）。
  Future<void> _openUrl(BuildContext context, String url) async {
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打不开浏览器，请手动访问 $url')),
      );
    }
  }

  Widget _buildSiliconFlowCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ProviderRecommendationCard(
      cardKey: const Key('siliconflow_recommend_card'),
      icon: Icons.bolt_outlined,
      title: '推荐使用硅基流动 SiliconFlow',
      subtitle: '注册 / 登录、充值、API Key 都在官网完成',
      color: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
      children: [
        Text(
          'OpenAI 兼容接口，图片与文本模型都能接；通过邀请链接注册可支持课序开发。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              key: const Key('siliconflow_register_ai'),
              onPressed: () => _openUrl(
                context,
                SiliconFlowGuidePage.registerUrl,
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('注册 / 登录'),
            ),
            OutlinedButton.icon(
              key: const Key('siliconflow_recharge_ai'),
              onPressed: () => _openUrl(
                context,
                SiliconFlowGuidePage.rechargeUrl,
              ),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('充值'),
            ),
            TextButton(
              key: const Key('siliconflow_guide_ai'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SiliconFlowGuidePage(),
                ),
              ),
              child: const Text('使用指南'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '邀请链接可能给邀请人带来平台奖励，你的充值价格不受影响。',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer.withAlpha(180),
              ),
        ),
      ],
    );
  }

  Widget _buildCottonApiCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _ProviderRecommendationCard(
      cardKey: const Key('cotton_recommend_card'),
      icon: Icons.hub_outlined,
      title: '推荐使用 CottonAPI',
      subtitle: 'OpenAI 兼容网关，视觉与文本模型都能接',
      color: scheme.primaryContainer,
      foreground: scheme.onPrimaryContainer,
      children: [
        Text(
          '在模型详情页选择「CottonAPI（推荐）」会自动填好地址与模型；'
          'API Key、注册与充值都在 CottonAPI 官网完成。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              key: const Key('cotton_register_ai'),
              onPressed: () => _openUrl(context, cottonApiUrl),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('打开官网 / 注册'),
            ),
            OutlinedButton.icon(
              key: const Key('cotton_recharge_ai'),
              onPressed: () => _openUrl(context, cottonWalletUrl),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('充值'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '课序不收集账号密码或支付信息，只在本机保存你粘贴的 API Key。',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer.withAlpha(180),
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAi = ref.watch(aiConfigProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SettingsSubPage(
      title: '大模型配置',
      subtitle: '用于「图片转课表」与「一句话改课表」，协议走 OpenAI 兼容接口。\n\n'
          '两类 AI 能力可以分别配置模型，互不影响。',
      child: asyncAi.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => Text(
          '读取 AI 配置失败：$e',
          style: TextStyle(color: scheme.error),
        ),
        data: (config) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSiliconFlowCard(context),
            const SizedBox(height: 8),
            _buildCottonApiCard(context),
            const SizedBox(height: 12),
            _ProviderCard(
              key: const Key('ai_provider_vision'),
              title: '视觉模型',
              subtitle: '图片转课表 · 需要能看图的模型',
              icon: Icons.image_outlined,
              config: config.vision,
              onOpen: () => _openDetail(context, isVision: true),
              onShare: () => _copyConfig(context, config.vision),
            ),
            const SizedBox(height: 12),
            _ProviderCard(
              key: const Key('ai_provider_text'),
              title: '语言模型',
              subtitle: '一句话改课表 · 纯文本任务',
              icon: Icons.chat_bubble_outline,
              config: config.text,
              onOpen: () => _openDetail(context, isVision: false),
              onShare: () => _copyConfig(context, config.text),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, {required bool isVision}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiModelConfigPage(isVision: isVision),
      ),
    );
  }

  Future<void> _copyConfig(BuildContext context, AiModelConfig config) async {
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(config.toJson())),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('模型配置已复制到剪贴板')));
  }
}

/// 推荐服务商折叠卡片：平时只显示标题/一句话，点击后才展开注册、充值等按钮。
class _ProviderRecommendationCard extends StatefulWidget {
  const _ProviderRecommendationCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.foreground,
    required this.children,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color foreground;
  final List<Widget> children;

  @override
  State<_ProviderRecommendationCard> createState() =>
      _ProviderRecommendationCardState();
}

class _ProviderRecommendationCardState
    extends State<_ProviderRecommendationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: widget.color,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: widget.cardKey,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Icon(widget.icon, size: 20, color: widget.foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: widget.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: widget.foreground.withAlpha(200),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: widget.foreground,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: widget.foreground.withAlpha(40)),
                  ...widget.children,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.config,
    required this.onOpen,
    required this.onShare,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AiModelConfig config;
  final VoidCallback onOpen;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final configured = config.isConfigured;
    final model = config.model.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, size: 26, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _Pill(
                              text: configured ? '已配置' : '未配置',
                              color: configured
                                  ? scheme.secondaryContainer
                                  : scheme.surfaceContainerHighest,
                              textColor: configured
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                            if (model.isNotEmpty)
                              _Pill(
                                text: model,
                                color: scheme.primaryContainer,
                                textColor: scheme.onPrimaryContainer,
                                maxWidth: 240,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('分享'),
                  ),
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.view_list_outlined, size: 18),
                    label: const Text('模型'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('配置'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.color,
    required this.textColor,
    this.maxWidth,
  });

  final String text;
  final Color color;
  final Color textColor;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth!),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 单个模型的详细配置页。
class AiModelConfigPage extends ConsumerWidget {
  const AiModelConfigPage({super.key, required this.isVision});

  final bool isVision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAi = ref.watch(aiConfigProvider);
    final catalog = ref.watch(aiModelCatalogProvider).valueOrNull;
    final catalogModels =
        (catalog != null && catalog.models.isNotEmpty) ? catalog.models : builtInModels;
    final title = isVision ? '视觉模型' : '语言模型';
    return SettingsSubPage(
      title: title,
      subtitle: isVision
          ? '图片转课表使用。选择服务商预设，填写 API Key 与模型名，支持测试连接。'
          : '一句话改课表使用。纯文本任务可选择更便宜的文本模型。',
      child: asyncAi.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => Text('读取配置失败：$e'),
        data: (config) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: AiModelSectionForm(
              isVision: isVision,
              initial: isVision ? config.vision : config.text,
              showHeader: false,
              catalogModels: catalogModels,
              onSave: (next) {
                return ref.read(aiConfigProvider.notifier).save(
                      isVision
                          ? config.copyWith(vision: next)
                          : config.copyWith(text: next),
                    );
              },
            ),
          ),
        ),
      ),
    );
  }
}

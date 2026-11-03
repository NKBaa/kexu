import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/hint_icon.dart';
import 'semester_settings_page.dart' show SettingsSubPage;

/// 硅基流动（SiliconFlow）接入引导。
///
/// 为什么不是「应用内登录」：
/// 硅基流动没有面向第三方 App 的公开 OAuth / 登录 SDK，账号密码与短信验证码
/// 必须由用户在官方页面完成。课序不收集、不代理账号密码，只引导用户到官方
/// 注册/登录页，拿到 API Key 后填回本机配置。充值同理，跳官方控制台完成。
class SiliconFlowGuidePage extends StatelessWidget {
  const SiliconFlowGuidePage({super.key});

  /// 邀请注册链接（用户明确要求使用该邀请码）。
  static const String registerUrl = 'https://cloud.siliconflow.cn/i/DnX87B1j';

  /// 控制台 API Key 页面。
  static const String apiKeyUrl =
      'https://cloud.siliconflow.cn/me/account/ak';

  /// 控制台充值页面（未登录会先跳登录）。
  static const String rechargeUrl =
      'https://cloud.siliconflow.cn/me/account/charge';

  /// API 根地址（与 [aiProviderPresets] 中的 SiliconFlow 预设一致）。
  static const String apiBaseUrl = 'https://api.siliconflow.cn/v1';

  Future<void> _open(BuildContext context, String url) async {
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('打不开浏览器，请手动访问 $url')),
        );
    }
  }

  Future<void> _copyInviteLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: registerUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('邀请链接已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SettingsSubPage(
      title: '硅基流动',
      subtitle: '注册/登录、创建 API Key、充值都在硅基流动官网完成；'
          '课序只保存你填写的 API Key。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.hub_outlined,
                      size: 28, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '一个 API，接入图片与文本模型',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '硅基流动提供 OpenAI 兼容接口，适合课序的「图片转课表」与'
                          '「一句话改课表」。按量计费，注册后创建 API Key 即可使用。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _StepCard(
            index: 1,
            title: '注册 / 登录',
            body: '通过邀请链接打开硅基流动，用手机号注册或登录。'
                '邀请链接由课序开发者提供，注册后邀请人可能获得平台奖励；'
                '你的充值价格不受影响。',
            action: FilledButton.icon(
              key: const Key('siliconflow_register_button'),
              onPressed: () => _open(context, registerUrl),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('打开注册 / 登录'),
            ),
            extra: TextButton(
              onPressed: () => _copyInviteLink(context),
              child: const Text('复制邀请链接'),
            ),
          ),
          const SizedBox(height: 10),
          _StepCard(
            index: 2,
            title: '创建 API Key',
            body: '登录后进入「API 密钥」页面，新建一个 Key 并复制。'
                'Key 只保存在本机设置里，不会上传到课序服务器。',
            action: OutlinedButton.icon(
              key: const Key('siliconflow_apikey_button'),
              onPressed: () => _open(context, apiKeyUrl),
              icon: const Icon(Icons.key_outlined, size: 18),
              label: const Text('打开 API 密钥页面'),
            ),
          ),
          const SizedBox(height: 10),
          _StepCard(
            index: 3,
            title: '充值',
            body: '硅基流动按量计费。新用户可能有平台赠送额度；'
                '余额不足时在控制台充值，课序不参与支付，也不会保存支付信息。',
            action: OutlinedButton.icon(
              key: const Key('siliconflow_recharge_button'),
              onPressed: () => _open(context, rechargeUrl),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('打开充值页面'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings_suggest_outlined,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '4. 回到课序配置',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const HintIcon(
                        message: '在「大模型配置 → 视觉模型 / 语言模型」里选择'
                            '「硅基流动 SiliconFlow」，粘贴 API Key，'
                            '点「获取模型列表」选择可用模型后保存。',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '服务地址：$apiBaseUrl\n'
                    '推荐视觉模型：Qwen/Qwen2.5-VL-72B-Instruct\n'
                    '推荐文本模型：deepseek-ai/DeepSeek-V3',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '模型名会随平台更新，若不可用请在模型详情页点「获取模型列表」'
                    '选择账号当前可用的模型。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '说明：课序不提供应用内账号登录或支付，也不会收集硅基流动账号密码、'
                '短信验证码或支付信息。所有注册、登录、充值与 Key 管理都在官方页面完成；'
                '课序只在本机保存你粘贴的 API Key。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.body,
    required this.action,
    this.extra,
  });

  final int index;
  final String title;
  final String body;
  final Widget action;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$index',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [action, ?extra],
            ),
          ],
        ),
      ),
    );
  }
}

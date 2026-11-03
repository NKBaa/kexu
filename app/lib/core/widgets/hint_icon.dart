import 'package:flutter/material.dart';

/// 灰色感叹号提示按钮：替代页面上常驻的说明文字。
///
/// 点击后弹窗显示 [message]，让界面保持清爽，需要时再看详细说明。
class HintIcon extends StatelessWidget {
  const HintIcon({
    super.key,
    required this.message,
    this.title = '提示',
    this.size = 18,
    this.color,
  });

  /// 弹窗正文。
  final String message;

  /// 弹窗标题。
  final String title;

  /// 图标大小。
  final double size;

  /// 图标颜色，默认使用 `onSurfaceVariant` 灰色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: '查看提示',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        Icons.error_outline,
        size: size,
        color: color ?? scheme.onSurfaceVariant,
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }
}

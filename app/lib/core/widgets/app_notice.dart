import 'dart:async';

import 'package:flutter/material.dart';

OverlayEntry? _currentNotice;
Timer? _noticeTimer;

/// 统一的轻量提示：显示在顶部星期表头下方，而不是盖在课程上。
///
/// 这样做在课表页正好落在「周一~周日」表头下面；其他页面也保持在
/// AppBar 下方的位置，不会遮挡底部 AI 按钮。
void showAppNotice(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _noticeTimer?.cancel();
  _currentNotice?.remove();
  _currentNotice = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final top = MediaQuery.paddingOf(ctx).top + kToolbarHeight + 44 + 6;
      return Positioned(
        top: top,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Material(
              key: const ValueKey('app_notice'),
              color: scheme.inverseSurface,
              elevation: 2,
              borderRadius: BorderRadius.circular(18),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(ctx).width - 32,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 16, color: scheme.onInverseSurface),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onInverseSurface,
                            fontSize: 12,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  _currentNotice = entry;
  _noticeTimer = Timer(const Duration(seconds: 2), () {
    if (entry.mounted) entry.remove();
    if (_currentNotice == entry) _currentNotice = null;
  });
}

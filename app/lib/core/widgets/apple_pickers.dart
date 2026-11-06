import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 苹果风格时间选择器：底部滚轮 + 取消/完成。
///
/// 全 App 的时间设置统一走这里，避免 Android 的 Material 时钟弹窗
/// 与 Windows 上的 Material 控件混用。
Future<TimeOfDay?> showAppleTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
  String title = '选择时间',
}) {
  var picked = DateTime(2000, 1, 1, initial.hour, initial.minute);
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ApplePickerSheet(
      title: title,
      height: 320,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        use24hFormat: true,
        initialDateTime: picked,
        onDateTimeChanged: (value) => picked = value,
      ),
      onDone: () => Navigator.of(ctx).pop(
        TimeOfDay(hour: picked.hour, minute: picked.minute),
      ),
    ),
  );
}

/// 苹果风格日期选择器。
Future<DateTime?> showAppleDatePicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期',
}) {
  var picked = DateTime(initial.year, initial.month, initial.day);
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ApplePickerSheet(
      title: title,
      height: 320,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: picked,
        minimumDate: firstDate,
        maximumDate: lastDate,
        onDateTimeChanged: (value) => picked = value,
      ),
      onDone: () => Navigator.of(ctx).pop(
        DateTime(picked.year, picked.month, picked.day),
      ),
    ),
  );
}

class _ApplePickerSheet extends StatelessWidget {
  const _ApplePickerSheet({
    required this.title,
    required this.height,
    required this.child,
    required this.onDone,
  });

  final String title;
  final double height;
  final Widget child;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onDone,
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: theme.brightness,
                  primaryColor: scheme.primary,
                  textTheme: const CupertinoTextThemeData(),
                ),
                child: child,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

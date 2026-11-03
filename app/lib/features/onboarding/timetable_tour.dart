import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showcaseview/showcaseview.dart';

/// 首次向导完成后请求打开交互教程。
final timetableTourRequestProvider = StateProvider<bool>((ref) => false);

/// 课表交互教程的锚点。
class TimetableTutorialKeys {
  TimetableTutorialKeys._();

  static final GlobalKey weekTitle = GlobalKey();
  static final GlobalKey moreButton = GlobalKey();
  static final GlobalKey aiButton = GlobalKey();
  static final GlobalKey grid = GlobalKey();
}

/// 启动覆盖在真实界面上的交互教程。
///
/// 教程会高亮真实控件，用户可以直接点这些控件，也可以点「下一步」。
Future<void> startTimetableTour() async {
  try {
    ShowcaseView.get().startShowCase([
      TimetableTutorialKeys.weekTitle,
      TimetableTutorialKeys.moreButton,
      TimetableTutorialKeys.aiButton,
      TimetableTutorialKeys.grid,
    ]);
  } catch (_) {
    // 尚未注册（例如极端情况下页面还没挂载）时静默失败，不影响主流程。
  }
}

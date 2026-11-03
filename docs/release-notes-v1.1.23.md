# 课序 v1.1.23

本轮做了一次全量代码审查并删除无用代码，不改变功能行为。

## 审查与清理

- 删除 `conflict_utils.dart` 中无人调用的 `entriesConflict` 便捷函数（实际冲突判定统一走
  `sessionsConflict` / `findConflicts` / `conflictedSessionIds`），并移除对应测试。
- `TimetableHistoryRepository.defaultMaxEntries` 接入构造默认值，常量不再只给测试使用。
- 全量确认：
  - `flutter analyze` 0 issue；
  - `lib/` 下 64 个 Dart 文件全部可从 `main.dart` 到达，无孤立文件；
  - 无 TODO/FIXME、无注释掉的代码、无 `print` 调试残留；
  - 依赖全部有使用，无未使用 import / 私有成员。
- 测试 565 个用例（559 通过 / 6 默认跳过）。
- 版本 1.1.23+25（Android versionCode 25）。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.23-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.23.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

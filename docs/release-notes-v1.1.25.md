# 课序 v1.1.25

继续全量审查并删除无用代码，不改变功能行为。

## 审查与清理

- 删除仅测试使用、生产代码不再调用的公共 API：
  - `Course.isActiveAt`
  - `AiConfig.isBlank`
  - `AiClient.isDisposed`
  - `ConflictPair.sessionIds`
  - `DocumentStore.isUsingFallback`（同时移除内部 `_usingFallback` 状态）
- 原有测试改为直接使用公开数据或已有行为断言，不再依赖上述 API。
- 全量确认：
  - `flutter analyze` 0 issue；
  - `lib/` 全部 Dart 文件可从 `main.dart` 到达，无孤立文件；
  - 无 TODO/FIXME、无注释掉代码、无 `print` 调试残留；
  - 无未使用 import / 私有成员；公共成员均有生产调用（`main` 除外）。
- 测试 567 用例（561 通过 / 6 默认跳过）。
- 版本 1.1.25+27（Android versionCode 27）。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.25-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.25.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

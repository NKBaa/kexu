# 课序 v1.1.10

本次为一次**全量代码审查与清理**版本：不改变功能行为，删除无用代码、补齐健壮性处理，并重新构建发布。

## 更新内容

### 代码审查与清理
- 删除无引用的公开常量 `AppRadius.small` / `AppRadius.tiny` / `AppRadius.smallBorder`。
- 删除未使用的仓储 API：`TimetableRepository.importFromFile` / `clear` / `store`、
  `SettingsRepository.store`、`TimetableHistoryRepository.clear`。
- 删除两个已过时、无引用的开发脚本 `tooling/e2e-hpu.ps1`、`tooling/e2e-ui.ps1`；
  `tooling/e2e-conflict.ps1` 保留并补进 README 脚本表。
- `.gitignore` 增加 `/.e2e-*/`，避免 e2e 脚本生成的临时数据目录污染工作区。
- 全量确认：`lib/` 下 63 个 Dart 文件均可从 `main.dart` 到达，无孤立文件；
  无 TODO/FIXME、无注释掉的代码、无 `print` 调试残留。

### 健壮性
- 「修改历史」回退/恢复增加异常兜底：历史文件不可写或读取失败时返回失败并记录日志，
  不再让异常冒到界面（底部提示「回退失败」）。

### 其他
- 版本 1.1.10+12（Android versionCode 12）。
- 测试保持 563 个用例（557 通过 / 6 默认跳过），`flutter analyze` 0 issue。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.10-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.10.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

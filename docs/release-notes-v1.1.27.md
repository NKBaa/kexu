# 课序 v1.1.27

修复「每次更新后 API Key 需要重新保存」的问题。

## 更新内容

- `SettingsRepository` 在读取主设置文件时增加备份恢复：
  - `settings.json` 丢失、损坏或被写成默认空设置时，自动从最近的
    `settings.json` 备份恢复 AI 配置（含 API Key）；
  - 仅在 AI 配置整体为空时恢复，**用户主动清空 Key 不会被旧备份复活**；
  - 恢复后把内容写回主设置文件，后续启动直接读取。
- `DocumentStore` 新增 `readLatestBackupJson()`，复用已有的本地备份机制。
- 新增设置仓储测试：设置被重置、文件被删除时能恢复 Key；主动清空 Key 时不复活。
- 测试 570 用例（564 通过 / 6 默认跳过），`flutter analyze` 0 issue。
- 版本 1.1.27+29（Android versionCode 29）。

> 说明：升级到本版本后，请先重新保存一次 API Key；以后更新会优先保留，
> 只有设置文件异常时才会从备份自动恢复。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.27-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.27.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

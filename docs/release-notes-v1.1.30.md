# 课序 v1.1.30

撤回「午休 / 晚休时间」功能。

## 更新内容

- 移除作息方案中的午休 / 晚休设置界面与校验逻辑。
- 移除 `BellSchedule` 的 `lunchBreak` / `dinnerBreak` 字段、`BreakTime` 模型、
  摘要文字与 JSON 序列化字段。
- 旧版本保存的 `lunchBreak` / `dinnerBreak` 数据会被忽略，不影响课表加载。
- 删除对应的模型与设置页测试。
- 测试 569 用例（563 通过 / 6 默认跳过），`flutter analyze` 0 issue。
- 版本 1.1.30+32（Android versionCode 32）。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.30-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.30.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

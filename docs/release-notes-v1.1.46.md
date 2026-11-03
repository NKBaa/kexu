# 课序 v1.1.46

修复更新后必须先打开大模型配置点一次保存才能使用 AI 的问题。

## 原因

AI 客户端之前从 `aiConfigProvider` 读取配置。首次打开 AI 页面时该 provider 可能仍处于加载中，客户端会先拿到空配置并缓存；用户去大模型配置页保存一次后 provider 才刷新，所以表现为“更新后必须点一次保存”。

## 修复

- `visionAiClientProvider` / `textAiClientProvider` 改为直接读取已加载的 `settingsProvider.aiConfig`；
- 图片转课表识别前等待设置加载完成再校验视觉模型；
- 新增回归测试：设置已加载但未打开过大模型配置页时，AI 客户端也能直接拿到已保存的 API Key。

## 验证

- 测试 **585 用例（579 通过 / 6 默认跳过）**
- `flutter analyze` 0 issue
- 版本 1.1.46+48（Android versionCode 48）

## 下载与安装

- **Windows**：下载 `kexu-v1.1.46-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.46.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

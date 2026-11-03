# 课序 v1.1.40

代码审查并删除无用代码。

## 清理内容

- 删除仅测试使用的旧 `AiConfigForm` 双模型表单（生产页面已由 提供商卡片列表 + 单模型详情页替代），测试改为直接覆盖 `AiModelSectionForm`。
- 删除未使用的 `AppRadius.cardShape`。
- `flutter analyze`：0 issue；无 TODO/FIXME 调试残留。
- 测试保持 581 用例（575 通过 / 6 默认跳过）。
- 版本 1.1.40+42（Android versionCode 42）。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.40-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.40.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

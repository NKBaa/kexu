# 课序 v1.2.26

作息模板、模型名单与主题市场统一使用内置加速镜像。

## 更新内容

- `templates/bell_schedules.json`（学校作息模板）固定走内置加速镜像；
- `templates/ai_models.json`（模型能力名单）固定走内置加速镜像；
- `templates/themes.json`（主题市场）固定走内置加速镜像；
- 加速顺序写死在代码里：先尝试镜像节点，最后 GitHub 直连兜底；
- 模板下载不再受「检查更新」里镜像设置影响，用户不需要额外配置；
- 仓库地址仍沿用「设置 → 检查更新」的配置，方便 fork 后维护模板；
- 测试 690 用例（684 通过 / 6 默认跳过），`flutter analyze` 0 issue；
- 版本 1.2.26+82（Android versionCode 82）。

## 下载与安装

- **Windows**：下载 `kexu-v1.2.26-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.2.26.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

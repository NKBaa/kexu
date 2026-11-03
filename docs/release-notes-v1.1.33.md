# 课序 v1.1.33

修复底部 SnackBar 提示过大、遮挡课表视野的问题。

## 更新内容

- SnackBar 改为**固定 320px 宽的浮动提示**，不再铺满屏幕宽度。
- 提示文字缩小到 13px，行高收紧，减少多行提示的高度。
- 背景沿用深色反色、圆角 16px，短暂显示后自动消失。
- 版本 1.1.33+35（Android versionCode 35）。
- 测试保持 577 用例（571 通过 / 6 默认跳过），`flutter analyze` 0 issue。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.33-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.33.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

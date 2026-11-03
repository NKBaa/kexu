# 课序 v1.1.37

重新设计应用图标。

## 更新内容

- 图标从原来的高饱和紫蓝渐变 + 彩色日历，改为与 App 新 UI 一致的风格：
  - **暖白渐变底**；
  - **深墨色课表卡片**；
  - **雾蓝 / 杏色课程条**，小尺寸下仍清晰可辨。
- 同步更新：
  - `docs/app-icon-1024.png`（母版）
  - Android `mipmap-* / ic_launcher.png`
  - Windows `app_icon.ico`
- 版本 1.1.37+39（Android versionCode 39）。
- 测试保持 580 用例（574 通过 / 6 默认跳过），`flutter analyze` 0 issue。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.37-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.37.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

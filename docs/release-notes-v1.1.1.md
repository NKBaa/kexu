# 课序 v1.1.1

本次更新把在线更新的仓库地址**默认写死为本仓库 `NKBaa/kexu`**：装好即用，
不用再手动填写 `owner/repo` 就能收到后续版本。

## 更新内容

- **在线更新开箱即用**：`UpdateConfig` 默认 `repo = NKBaa/kexu`，
  启动时自动检查、设置页默认已填好；清空后不再检查，可点「恢复默认」还原。
  fork 后仍可在设置里改成自己的仓库。
- **版本号**：1.1.1+3（Android versionCode 3）。
- **发布资产命名统一为 ASCII**：`kexu-v<version>.apk` / `kexu-v<version>-windows.zip`，
  避免 gh CLI 在 Windows 上传中文文件名时把字符吃掉。
- 其余功能与 v1.1.0 一致：对话式一句话改课表（当前时间/教学周上下文、白话容错、
  AI 反问、多轮对话）、图片转课表多图识别与跨图合并、GitHub Releases 在线更新。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.1-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.1.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已是 `NKBaa/kexu`，旧版本（v1.1.0 及更早）打开「设置 → 检查更新」
即可检测到本版本并直接下载安装。

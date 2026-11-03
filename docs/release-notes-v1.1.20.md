# 课序 v1.1.20

修复「检查更新」报 `FormatException: Invalid HTTP header field value` 的问题。

## 更新内容

- 原因：请求 GitHub API 时，`User-Agent` 使用了中文应用名 `课序/版本号`；
  dart:io 的 HTTP 头只允许 ASCII/Latin-1 字符，直接在本地抛出
  `Invalid HTTP header field value: "课序/1.1.18+20"`，请求根本没发出去。
- 修复：`User-Agent` 改为 ASCII 的 `Kexu/<版本号>`（检查更新与下载两条链路共用）。
- 增加回归测试：断言 `User-Agent` 以 `Kexu/` 开头且全部字符为 ASCII。
- 版本 1.1.20+22（Android versionCode 22）。
- 测试保持 563 个用例（557 通过 / 6 默认跳过），`flutter analyze` 0 issue。

> 注意：v1.1.18 及更早版本的「检查更新」因该头错误无法联网，需要手动安装本版本；
> 之后的应用内更新即可正常使用。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.20-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.20.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

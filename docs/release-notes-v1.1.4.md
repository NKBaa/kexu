# 课序 v1.1.4

本次更新修复「大模型配置」页在手机窄屏下预设下拉文字顶出边框的问题，并新增 **CottonAPI** 推荐。

## 更新内容

### 大模型配置
- **修复预设下拉溢出**：「自定义（任意 OpenAI 兼容服务）」等长预设名在手机上不再顶出输入框，
  选中后自动省略号显示（`isExpanded: true` + `selectedItemBuilder`）。
- **新增推荐：CottonAPI（`https://api.cottonapi.cloud`）**：
  - 配置页顶部新增推荐卡片，说明用途并提供「打开官网」按钮；
  - 预设列表新增「CottonAPI（推荐）」，选中后自动填好
    `https://api.cottonapi.cloud/v1` 与 `gemini-3.8-flash`（视觉/文本各一套），只需再填 API Key；
  - 模型名可改成自己账号支持的其它模型。
- README「大模型配置」补充推荐说明与预设表。

### 其他
- 版本 1.1.4+6（Android versionCode 6）。
- 测试增至 531 个用例（525 通过 / 6 默认跳过），新增窄屏下拉布局回归测试。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.4-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.4.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

# 课序 v1.2.8

硅基流动与 CottonAPI 推荐卡改为默认折叠，点击展开注册/充值入口。

## 更新内容

- 「大模型配置」顶部两张推荐卡：
  - **推荐使用硅基流动 SiliconFlow**；
  - **推荐使用 CottonAPI**；
  - 平时只显示标题与一句话说明，点击卡片才展开详情，避免配置页过长。
- 硅基流动展开后：注册/登录、充值、使用指南（邀请链接不变）。
- CottonAPI 展开后：
  - 「打开官网 / 注册」→ `https://api.cottonapi.cloud`
  - 「充值」→ `https://api.cottonapi.cloud/wallet`
  - 注册、充值与 API Key 都在官网完成，课序只保存本机 API Key。
- 测试保持 662 用例（656 通过 / 6 默认跳过），`flutter analyze` 0 issue；
- 版本 1.2.8+64（Android versionCode 64）。

## 下载与安装

- **Windows**：下载 `kexu-v1.2.8-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.2.8.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

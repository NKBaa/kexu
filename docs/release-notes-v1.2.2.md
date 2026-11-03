# 课序 v1.2.2

新增硅基流动 SiliconFlow 接入引导：注册 / 登录、创建 API Key、充值。

## 更新内容

- 「大模型配置」顶部新增硅基流动卡片：
  - **注册 / 登录**：打开硅基流动官方邀请链接；
  - **充值**：打开官方控制台充值页；
  - **使用指南**：分步说明注册、创建 API Key、充值与回填配置；
  - 邀请链接：`https://cloud.siliconflow.cn/i/DnX87B1j`。
- 新增「硅基流动 SiliconFlow」模型预设：
  - API 地址：`https://api.siliconflow.cn/v1`
  - 视觉默认模型：`Qwen/Qwen2.5-VL-72B-Instruct`
  - 文本默认模型：`deepseek-ai/DeepSeek-V3`
  - 模型名可在详情页点「获取模型列表」按账号可用模型调整。
- 首次使用向导的大模型步骤新增硅基流动入口。
- 说明：硅基流动没有面向第三方 App 的公开登录/OAuth SDK，因此课序不提供
  应用内账号登录或支付；注册、登录、充值与 Key 管理都在官方网页完成。
  课序不接触账号密码、短信验证码或支付信息，只在本机保存用户粘贴的 API Key。
- 测试保持 651 用例（645 通过 / 6 默认跳过），`flutter analyze` 0 issue。
- 版本 1.2.2+58（Android versionCode 58）。

## 下载与安装

- **Windows**：下载 `kexu-v1.2.2-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.2.2.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

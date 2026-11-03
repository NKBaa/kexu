# 课序 v1.2.13

模型能力名单改为只在「获取模型列表」时标注能力，移除「课表推荐」和独立选择入口。

## 更新内容

- 删除「大模型配置」里的「课表推荐」标记、筛选和推荐字段；
- 删除「按能力选内置模型」独立入口，避免和「获取模型列表」重复；
- 模型能力名单现在只做一件事：
  - 填好 baseUrl / API Key 后点「获取模型列表」；
  - 返回的模型名如果命中名单，列表中标注「图片 + 文本 / 仅文本、上下文、免费、
    选型建议」；
  - 未命中名单的模型照常显示，不影响选择。
- 名单仍从 GitHub `templates/ai_models.json` 自动拉取并缓存；
  远程 JSON 已移除 `recommendedVision` / `recommendedText` 字段。
- 测试保持 667 用例（661 通过 / 6 默认跳过），`flutter analyze` 0 issue；
- 版本 1.2.13+69（Android versionCode 69）。

## 下载与安装

- **Windows**：下载 `kexu-v1.2.13-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.2.13.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

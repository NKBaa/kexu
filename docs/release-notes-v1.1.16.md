# 课序 v1.1.16

新增应用图标，并把设置页剩余的小字说明全部收进「灰色感叹号」弹窗。

## 更新内容

### 新应用图标
- 紫蓝渐变圆角底 + 白色日历卡片 + 彩色课程块，小尺寸下也能看出「课表」。
- Android：`mipmap-mdpi` ~ `mipmap-xxxhdpi` 五档 `ic_launcher.png`。
- Windows：`windows/runner/resources/app_icon.ico`（16/24/32/48/64/128/256 多尺寸）。
- 母版 `docs/app-icon-1024.png`，README 顶部展示；新增 `tooling/make_icon.py` 可一键重建。

### 小字说明改为灰色感叹号
- AI 配置页：
  - 「两类 AI 能力可以分别配置模型…」移入页面标题栏的灰色感叹号弹窗；
  - 各模型区标题下的说明、服务商预设说明（含「OpenAI 兼容网关…」）合并进标题旁感叹号；
  - 服务地址、API Key、模型名的 helper 文字改为输入框右侧灰色感叹号；
  - 温度、超时的建议文字同样改为标签旁灰色感叹号。
- 学期与作息：常用周数快捷 Chip 删除；日期/周数/按今天定位/作息说明改为灰色感叹号。
- 设置二级页顶部副标题、更新页/关于页/作息列表的底部说明也统一改为灰色感叹号弹窗。

### 其他
- 版本 1.1.16+18（Android versionCode 18）。
- 测试保持 563 个用例（557 通过 / 6 默认跳过），`flutter analyze` 0 issue。

## 下载与安装

- **Windows**：下载 `kexu-v1.1.16-windows.zip`，解压后双击 `course_timetable.exe`（免安装）。
- **Android**：下载 `kexu-v1.1.16.apk` 传到手机安装（debug 签名，需允许安装未知来源应用）。

## 应用内更新

默认仓库已写死为 `NKBaa/kexu`，旧版本在「设置 → 检查更新」里即可检测到本版本。

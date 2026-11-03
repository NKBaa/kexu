# 远程数据文件

## 作息模板 `bell_schedules.json`

`bell_schedules.json` 由 App 的「设置 → 学期与作息 → 从 GitHub 模板导入」读取。

- 仓库沿用 App 的「设置 → 检查更新」配置，默认是 `NKBaa/kexu` 的 `main` 分支；
  下载固定走内置加速镜像，无需额外配置。
- 模板按 `schools` 分组，每所学校可有多套作息模板。
- 增加学校模板时，复制一个学校对象并修改 `school` / `note` / `templates` 即可；
  每套模板必须有 `id`、`name` 和 `slots`（`period` + `start` + `end`）。
- 分季节作息可以加可选的 `dateRange`：
  `"dateRange": {"start": "05-01", "end": "10-01"}`（`MM-dd`，可跨年）。
  学校详情页的「全部导入」会把这些模板一起导入，并按当前学期自动换算年份。
- 时间使用 `HH:mm` 24 小时制，`period` 从 1 开始。

### 当前收录学校

通用、河南理工大学、郑州大学、清华大学、北京大学、浙江大学、武汉大学、
四川大学、中山大学、西安交通大学、华中科技大学。

数据来自各校教务处公开的作息时间表 / 上课时间表，仅做整理方便导入；
不同校区、院系和学期可能有微调，请以学校最新通知为准。

## 模型能力名单 `ai_models.json`

`ai_models.json` 由 App 的「设置 → 大模型配置 → 视觉/语言模型」打开时
自动从 GitHub 拉取，并缓存到本地；填好 API 信息点「获取模型列表」后用于标注同名模型能力。

- 仓库同样沿用「设置 → 检查更新」的配置，默认 `NKBaa/kexu` 的 `main` 分支；
  下载固定走内置加速镜像。
- 顶层字段：`version`、`updatedAt`、`models`。
- 每个模型字段：
  - `providerId`：模型开发者 id（如 `google`、`anthropic`、`openai`、`zhipu`、`alibaba`、`nvidia`）；
    同一开发者经不同中转站/网关提供时仍归到开发者，不写中转站名称；
  - `providerLabel`：开发者展示名（如 `Google`、`NVIDIA`、`智谱`）；
  - `id`：网关实际模型名，必须与「获取模型列表」返回的模型名逐字符一致（含 `openrouter/` 前缀、`:free` 后缀）；
  - `vision` / `text`：是否支持图片/文本；
  - `free`：是否免费；
  - `context`：上下文长度描述；
  - `note`：选型建议。
- 名单只用于给「获取模型列表」里同名模型标注能力，不作为独立模型选择器。
- 修改后提交到 `main`，App 在模型详情页打开/点刷新即可更新，不需要发新版。

修改后提交到 `main` 分支，App 下次打开模板页或点刷新即可看到。

## 主题市场 `themes.json`

`themes.json` 由「设置 → 主题中心 → 主题市场」自动拉取，用户点「安装」后写入本地设置。

- 顶层字段：`version`、`updatedAt`、`themes`。
- 每个主题字段：
  - `id`：唯一 id，只能包含字母、数字、下划线、短横线；
  - `name` / `author` / `description`：展示信息；
  - `radius`：卡片/弹窗圆角（0~40）；
  - `light` / `dark`：浅色/深色色板，各含 `seed`、`surface`、`card`、`ink`，
    颜色可写 `#RRGGBB` 或 `#AARRGGBB`。
- 修改后提交到 `main`，App 在主题中心点刷新即可看到，不需要发新版。

```json
{
  "id": "market-ocean",
  "name": "海盐",
  "author": "课序主题市场",
  "description": "清透的海蓝背景",
  "radius": 24,
  "light": {"seed": "#2B7A9B", "surface": "#F3FAFD", "card": "#FFFFFF", "ink": "#10222A"},
  "dark": {"seed": "#7EC8E3", "surface": "#0B151A", "card": "#13242C", "ink": "#E4F3F8"}
}
```

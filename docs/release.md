# 发布检查清单（GitHub Release）

配套脚本：`tooling/build-all.ps1`（构建 + 归档到 `dist/`）、`tooling/release.ps1`（发布）。
命令都在项目根执行；**不要**用 ASCII 联接路径跑这两个脚本（脚本内部会自己处理）。

## 0. 一次性准备

- [ ] 安装 Flutter stable、JDK 17、Android SDK（见 README「环境要求」）。
- [ ] `gh`（GitHub CLI）已安装并登录：`gh auth login`。
- [ ] 项目已是 git 仓库且配好远端：当前仓库为 `https://github.com/NKBaa/kexu`（`main` 分支）。
      新机器克隆后确认 `git remote -v` 指向正确仓库即可；`release.ps1` 检测不到 `.git` 时会给出中文提示并退出，不会自动初始化。

## 1. 改版本号（两处必须一起改）

- [ ] `app/pubspec.yaml`：`version: <X.Y.Z>+<build>`
- [ ] `app/lib/core/app_info.dart`：`appVersion = '<X.Y.Z>'`、`appBuildNumber = <build>`

> `app/test/core/app_info_test.dart` 会校验两者一致；只改一处 `flutter test` 会失败。
> 文件名的版本号取 `+` 之前的 `X.Y.Z`，构建号只体现在 Android versionCode 与「关于页」。

## 2. 验证

- [ ] `cd C:\dev\kt; flutter analyze` → `No issues found!`
- [ ] `cd C:\dev\kt; flutter test` → 全部通过
- [ ] Windows 手工冒烟：`flutter run -d windows`，确认主界面 / AI 入口 / 设置页正常
- [ ] Android 手工冒烟（有设备时）：安装 release APK，确认能启动

## 3. 构建并归档

```powershell
pwsh -File tooling\build-all.ps1
```

- [ ] 日志末尾是 `SUMMARY ... apk=True zip=True` 与 `BUILD OK`（否则看 `WINDOWS_EXIT` / `ANDROID_EXIT`）
- [ ] `dist/android/kexu-v<X.Y.Z>.apk` 存在
- [ ] `dist/windows/kexu-v<X.Y.Z>-windows.zip` 存在（解压后能直接双击 `course_timetable.exe`）

## 4. 写发布说明

- [ ] 新建 `docs/release-notes-v<X.Y.Z>.md`，内容建议：
      `## 更新内容`（按条目列改动）、`## 下载与安装`、`## 应用内更新`。
- [ ] 说明里不要写「修复若干问题」这类空话，用户要靠它判断值不值得更新。

## 5. 发布

```powershell
# 先预览：只检查版本号/环境/资产，打印将要执行的 gh 命令，不构建不发布
pwsh -File tooling\release.ps1 -DryRun

# 正式发布（默认会先构建；已有 dist 资产时可加 -SkipBuild）
pwsh -File tooling\release.ps1 -NotesFile docs\release-notes-v<X.Y.Z>.md
```

- [ ] tag 为 `v<X.Y.Z>`，标题为 `课序 v<X.Y.Z>`
- [ ] 两个资产都上传成功（`gh release view v<X.Y.Z>` 可查看）
- [ ] **不要**把 Release 存成 draft / prerelease：App 内更新走 `/releases/latest`，只认最新正式版
- [ ] 同名 Release 已存在时脚本会直接报错退出（避免把新构建覆盖到旧 Release）；
      确认要重发就先 `gh release delete v<X.Y.Z>` 再重跑

## 6. 发布后验证（关键）

- [ ] 在旧版本的 App 里：`设置 → 检查更新` → 填 `owner/repo` → 点「检查更新」，
      应看到新版本号、发布时间、说明与安装包大小。
- [ ] Windows：下载 `.zip` → 打开所在文件夹 → 解压 → 运行，确认是新版本。
- [ ] Android：下载 `.apk` → 调起系统安装界面；无「安装未知应用」权限时应回退浏览器下载页。
- [ ] 国内网络：把「镜像加速」保持「自动」，确认直连失败后能切到镜像完成检查/下载。
- [ ] 点「忽略此版本」后不再提示；重新打开 App（开着自动检查）只在新版本时轻提示一次。

## 7. 回滚

- 应用内更新只看「最新正式版」，因此**回滚 = 发一个版本号更高的修复版**（例如 `1.1.1`）。
- 若必须撤下某个 Release：`gh release delete v<X.Y.Z>`（同时删 tag：加 `--cleanup-tag`）。
- 已发布的 tag 不要复用给不同内容，否则用户装到的版本会与 tag 不符。

## 附：资产命名与匹配规则

| 平台 | 资产命名 | 应用内匹配规则 |
|---|---|---|
| Android | `kexu-v<X.Y.Z>.apk` | 只认 `.apk`；多个时优先含 `android` / `arm64` / `universal` |
| Windows | `kexu-v<X.Y.Z>-windows.zip` | `.exe` 优先、其次 `.zip`；优先含 `windows` / `win` / `setup` / `x64` |

- 版本比较用 tag（`v1.2.33`）与 App 内 `1.2.33+89` 比较，**相等不算更新**。
- 镜像规则：**镜像地址 = 前缀 + 原始 GitHub 地址**（API 与资产下载都一样），
  所以发布时不需要为国内镜像做任何额外准备。

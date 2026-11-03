#Requires -Version 7.0
<#
.SYNOPSIS
    发布课序（Kexu）新版本到 GitHub Releases。

.DESCRIPTION
    流程：读版本号 → 校验 git / gh 环境 → 构建并归档到 dist/ → 用 gh CLI 创建 Release 并上传资产。

    版本号以 app/pubspec.yaml 的 `version:` 为准（当前 1.2.28+84），tag 取语义化版本 v1.2.28；
    app/lib/core/app_info.dart 必须与之同步（app/test/core/app_info_test.dart 会校验）。
    本脚本**只创建** Release，不会删除/覆盖已有 Release，也不会改动任何源码或 dist 之外的文件。

.PARAMETER Version
    要发布的版本（如 1.1.0 或 v1.1.0），默认从 app/pubspec.yaml 读取。
    传入值必须与 pubspec 一致，否则直接退出（防止 tag 与 App 内版本号漂移）。

.PARAMETER SkipBuild
    跳过构建，直接用 dist/ 里已有的资产发布（资产缺失会报错）。

.PARAMETER NotesFile
    发布说明 Markdown 文件路径（相对项目根或绝对路径）。省略时用脚本生成的中文模板。

.PARAMETER DryRun
    只做参数/环境检查并打印将要执行的命令，不构建、不发布。

.PARAMETER Repo
    GitHub 仓库 owner/repo。省略时由 gh 从 git 远端推断。

.EXAMPLE
    pwsh -File tooling\release.ps1 -DryRun
    pwsh -File tooling\release.ps1 -NotesFile docs\release-notes-v1.2.28.md
    pwsh -File tooling\release.ps1 -SkipBuild -Repo your-name/kexu
#>
[CmdletBinding()]
param(
  [string]$Version = '',
  [switch]$SkipBuild,
  [string]$NotesFile = '',
  [switch]$DryRun,
  [string]$Repo = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 路径：全部相对脚本位置推导（项目根 = tooling 的上一级），不依赖当前目录。
# ---------------------------------------------------------------------------
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AppDir = Join-Path $ProjectRoot 'app'
$DistRoot = Join-Path $ProjectRoot 'dist'
$Pubspec = Join-Path $AppDir 'pubspec.yaml'
$BuildScript = Join-Path $PSScriptRoot 'build-all.ps1'
$GitDir = Join-Path $ProjectRoot '.git'

# 展示用应用名（与 app/lib/core/app_info.dart 的 appName 一致）。
$AppName = '课序'

function Write-Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Warn([string]$Message) { Write-Host "警告：$Message" -ForegroundColor Yellow }
function Fail([string]$Message) {
  Write-Host "错误：$Message" -ForegroundColor Red
  exit 1
}

# 把命令渲染成可直接复制执行的字符串（-DryRun 与错误提示共用）。
function Format-Command([string]$Exe, [string[]]$Arguments) {
  $parts = @($Exe)
  foreach ($arg in $Arguments) {
    if ($null -eq $arg) { continue }
    if ($arg -eq '' -or $arg -match '[\s"]') {
      $parts += '"' + ($arg -replace '"', '\"') + '"'
    } else {
      $parts += $arg
    }
  }
  return ($parts -join ' ')
}

# ---------------------------------------------------------------------------
# 1. 版本号：以 pubspec.yaml 为准，-Version 只用于确认，不能改出别的版本。
# ---------------------------------------------------------------------------
Write-Step '读取版本号'

if (-not (Test-Path $Pubspec)) { Fail "找不到 $Pubspec（脚本应放在 <项目根>\tooling 下）" }

$versionMatch = Select-String -Path $Pubspec -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
if (-not $versionMatch) { Fail "$Pubspec 里没有 version 行" }

$PubspecFullVersion = $versionMatch.Matches[0].Groups[1].Value
$PubspecVersion = ($PubspecFullVersion -split '\+')[0]
if ($PubspecVersion -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
  Fail "app/pubspec.yaml 的 version 不是合法语义化版本：$PubspecFullVersion"
}

$Semver = $PubspecVersion
if ($Version -and $Version.Trim() -ne '') {
  $requested = $Version.Trim()
  if ($requested -match '^[vV]') { $requested = $requested.Substring(1) }
  if ($requested.Contains('+')) {
    $buildPart = ($requested -split '\+')[1]
    $requested = ($requested -split '\+')[0]
    Write-Warn "忽略 -Version 里的构建号 +$buildPart：GitHub tag 只用语义化版本 v$requested，构建号以 pubspec.yaml 为准。"
  }
  if ($requested -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    Fail "-Version '$Version' 不是合法版本号（形如 1.1.0 或 v1.1.0）。"
  }
  if ($requested -ne $PubspecVersion) {
    Fail @"
传入的 -Version $requested 与 app/pubspec.yaml 的 version $PubspecFullVersion 不一致。
  发版请先**同时**修改这两处，再运行本脚本：
    1) app/pubspec.yaml        version: $requested+<构建号>
    2) app/lib/core/app_info.dart  appVersion / appBuildNumber
  （app/test/core/app_info_test.dart 会校验两者一致，改漏了测试会失败。）
"@
  }
  $Semver = $requested
}

$Tag = "v$Semver"
$Title = "$AppName $Tag"
Write-Host "版本：$Semver（pubspec: $PubspecFullVersion）   Tag：$Tag"

# ---------------------------------------------------------------------------
# 2. 环境检查：git 仓库、gh CLI、登录状态。
#    没有 .git 是当前项目很可能遇到的情况：只提示怎么补，绝不自动初始化/改动仓库。
# ---------------------------------------------------------------------------
Write-Step '检查发布环境'

$hasGitRepo = Test-Path $GitDir
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
$hasGh = $null -ne $ghCommand
$hasGitCli = $null -ne $gitCommand

if (-not $hasGitRepo) {
  $hint = @"
当前项目还不是 git 仓库（缺少 $GitDir），无法确定发布到哪个 GitHub 仓库。
  请先完成（本脚本不会自动执行，也不会删除或改写任何文件）：
    git init
    git remote add origin https://github.com/<owner>/<repo>.git
    git add -A; git commit -m "init"
    gh auth login
  然后再运行：pwsh -File tooling\release.ps1
"@
  if ($DryRun) {
    Write-Warn $hint
  } else {
    Fail $hint
  }
}

if (-not $hasGitCli) {
  if ($DryRun) { Write-Warn '找不到 git 命令；正式发布前请安装 Git。' } else { Fail '找不到 git 命令，请先安装 Git。' }
}

if (-not $hasGh) {
  $ghHint = @'
找不到 gh（GitHub CLI）。请安装后登录再发布：
  winget install --id GitHub.cli
  gh auth login
'@
  if ($DryRun) { Write-Warn $ghHint } else { Fail $ghHint }
}

if ($Repo -and $Repo.Trim() -ne '') {
  if ($Repo.Trim() -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    Fail "-Repo '$Repo' 不是 owner/repo 形式，例如 your-name/kexu。"
  }
  $Repo = $Repo.Trim()
}

# 只做展示：gh 自己会从 git 远端推断仓库。
$remoteUrl = ''
if ($hasGitRepo -and $hasGitCli) {
  $remoteUrl = (& git -C $ProjectRoot remote get-url origin 2>$null | Select-Object -First 1)
  if ($remoteUrl) { Write-Host "git 远端：$remoteUrl" }
}

if (-not $DryRun -and $hasGh) {
  & gh auth status 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Fail 'gh 还没有登录 GitHub。请先运行 gh auth login（或设置 GH_TOKEN 环境变量）。'
  }
}

# ---------------------------------------------------------------------------
# 3. 构建（默认执行；-SkipBuild 跳过）。
# ---------------------------------------------------------------------------
Write-Step '构建并归档产物'

if ($SkipBuild) {
  Write-Host '已指定 -SkipBuild：跳过构建，直接使用 dist\ 里已有的资产。'
} else {
  if (-not (Test-Path $BuildScript)) { Fail "找不到构建脚本：$BuildScript" }
  $buildCmd = Format-Command 'pwsh' @('-NoProfile', '-File', $BuildScript)
  if ($DryRun) {
    Write-Host "将执行：$buildCmd"
  } else {
    Write-Host "执行：$buildCmd"
    & $BuildScript
    if ($LASTEXITCODE -ne 0) {
      Fail '构建失败（见 tooling\build-all.ps1 的输出）。修好后再发布，避免上传半成品。'
    }
  }
}

# ---------------------------------------------------------------------------
# 4. 校验资产：命名约定必须与 tooling\build-all.ps1 完全一致。
# ---------------------------------------------------------------------------
Write-Step '校验 dist 资产'

$ApkPath = Join-Path $DistRoot "android\kexu-v$Semver.apk"
$ZipPath = Join-Path $DistRoot "windows\kexu-v$Semver-windows.zip"
$Assets = @($ApkPath, $ZipPath)

$missing = @()
foreach ($asset in $Assets) {
  if (-not (Test-Path $asset)) { $missing += $asset }
}
if ($missing.Count -gt 0) {
  $missingList = ($missing | ForEach-Object { "  - $_" }) -join "`n"
  if ($DryRun) {
    Write-Warn "以下资产还不存在（-DryRun 不中断，正式发布会失败）：`n$missingList`n  请先运行：pwsh -File tooling\build-all.ps1"
  } else {
    Fail @"
缺少发布资产：
$missingList
  请先运行 pwsh -File tooling\build-all.ps1（或去掉 -SkipBuild），
  并确认 app/pubspec.yaml 的 version 与要发布的版本一致。
"@
  }
} else {
  foreach ($asset in $Assets) {
    Write-Host ("  {0}  ({1:N1} MB)" -f $asset, ((Get-Item $asset).Length / 1MB))
  }
}

# ---------------------------------------------------------------------------
# 5. 发布说明：-NotesFile 优先，否则生成中文模板。
# ---------------------------------------------------------------------------
Write-Step '准备发布说明'

$notesArgs = @()
$notesText = ''
if ($NotesFile -and $NotesFile.Trim() -ne '') {
  $notesPath = if ([System.IO.Path]::IsPathRooted($NotesFile)) {
    $NotesFile
  } else {
    Join-Path $ProjectRoot $NotesFile
  }
  if (-not (Test-Path $notesPath)) { Fail "找不到发布说明文件：$notesPath" }
  $notesArgs = @('--notes-file', $notesPath)
  $notesText = Get-Content -LiteralPath $notesPath -Raw
  Write-Host "使用发布说明文件：$notesPath"
} else {
  $notesText = @"
## 更新内容

- 请补充本次改动；也可以准备一个 Markdown 文件用 ``-NotesFile`` 指定。

## 下载与安装

- **Windows**：下载 ``kexu-$Tag-windows.zip``，解压后运行 ``course_timetable.exe``（免安装）。
- **Android**：下载 ``课表-$Tag.apk``，传到手机安装（需允许安装未知来源应用）。

## 应用内更新

在「设置 → 检查更新」里填写本仓库的 ``owner/repo`` 后即可检测到 $Tag；
国内网络可在同一页把「镜像加速」保持为「自动」，直连失败会自动切换国内镜像。
"@
  $notesArgs = @('--notes', $notesText)
  Write-Host '使用脚本内置的中文发布说明模板（可用 -NotesFile 覆盖）。'
}

# ---------------------------------------------------------------------------
# 6. 组装 gh 命令。
# ---------------------------------------------------------------------------
$repoArgs = @()
if ($Repo) { $repoArgs = @('--repo', $Repo) }

$viewArgs = @('release', 'view', $Tag) + $repoArgs
$createArgs = @('release', 'create', $Tag, '--title', $Title) + $notesArgs + $repoArgs + $Assets
$viewCmd = Format-Command 'gh' $viewArgs
$createCmd = Format-Command 'gh' $createArgs

if ($DryRun) {
  Write-Step 'Dry-Run 汇总（未构建、未发布）'
  Write-Host "项目根：$ProjectRoot"
  Write-Host "版本：$Semver（pubspec: $PubspecFullVersion）"
  Write-Host "Tag：$Tag"
  Write-Host '资产：'
  foreach ($asset in $Assets) {
    $exists = if (Test-Path $asset) { '存在' } else { '缺失' }
    Write-Host "  - $asset [$exists]"
  }
  Write-Host '将先检查同名 Release 是否存在：'
  Write-Host "  $viewCmd"
  Write-Host '将执行发布：'
  Write-Host "  $createCmd"
  Write-Host '发布说明：'
  Write-Host '----'
  Write-Host $notesText
  Write-Host '----'
  exit 0
}

# 已存在同名 Release 时直接退出：覆盖资产容易让用户下到错版本，交给人决定。
Write-Host "检查 Release $Tag 是否已存在…"
& gh @viewArgs 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  Fail @"
Release $Tag 已经存在。为避免把新构建的资产覆盖到旧 Release（应用内更新只认 /releases/latest），
  请先删除旧 Release 或提升版本号，再重新发布：
    gh release delete $Tag
  确认无误后重跑：pwsh -File tooling\release.ps1
"@
}

Write-Step "创建 GitHub Release $Tag 并上传资产"
Write-Host "执行：$createCmd"
& gh @createArgs
if ($LASTEXITCODE -ne 0) {
  Fail "gh release create 失败（退出码 $LASTEXITCODE）。可用 -DryRun 查看完整命令后手动执行。"
}

Write-Host "`n发布完成：$Tag" -ForegroundColor Green
if ($Repo) {
  Write-Host "https://github.com/$Repo/releases/tag/$Tag"
} else {
  Write-Host "可用 gh release view $Tag --web 在浏览器里确认。"
}
Write-Host '提示：应用内「设置 → 检查更新」依赖 GitHub 的 /releases/latest，草稿（draft）与预发布（prerelease）不会被自动更新检测到。'
exit 0

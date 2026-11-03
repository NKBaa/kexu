# 一键构建 Windows Release 与 Android Release APK，并把带版本号的产物归档到 dist/。
#
# 用法：
#   pwsh -File tooling\build-all.ps1
#
# 归档结果（<version> 取 app/pubspec.yaml 里 `version:` 中 + 之前的部分，如 1.1.0）：
#   dist\android\kexu-v<version>.apk
#   dist\windows\kexu-v<version>-windows.zip
#
# 退出码：0 = 两个平台都构建并归档成功；1 = 有构建或归档失败（看日志里的 *_EXIT 行）。
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# 路径一律从脚本位置推导，避免在别的目录下执行时构建到别的项目。
# ---------------------------------------------------------------------------
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AppDir = Join-Path $ProjectRoot 'app'
$DistRoot = Join-Path $ProjectRoot 'dist'
$DistAndroid = Join-Path $DistRoot 'android'
$DistWindows = Join-Path $DistRoot 'windows'
$Pubspec = Join-Path $AppDir 'pubspec.yaml'

if (-not (Test-Path $Pubspec)) {
  Write-Host "FATAL: 找不到 $Pubspec（脚本应放在 <项目根>\tooling 下）"
  exit 1
}

# ---------------------------------------------------------------------------
# 版本号：文件名与 GitHub Release tag 只用 + 之前的语义化版本（v1.1.0），
# 构建号（+2）只体现在 Android versionCode 与「关于页」里。
# ---------------------------------------------------------------------------
$versionMatch = Select-String -Path $Pubspec -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
if (-not $versionMatch) {
  Write-Host "FATAL: $Pubspec 里没有 version 行"
  exit 1
}
$FullVersion = $versionMatch.Matches[0].Groups[1].Value
$Version = ($FullVersion -split '\+')[0]
Write-Host "Version: $FullVersion（归档文件名使用 v$Version）"

$env:PATH = "C:\dev\jdk17\bin;C:\dev\android-sdk\platform-tools;C:\dev\flutter\bin;$env:PATH"
$env:JAVA_HOME = 'C:\dev\jdk17'
$env:ANDROID_HOME = 'C:\dev\android-sdk'
$env:ANDROID_SDK_ROOT = 'C:\dev\android-sdk'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

# ---------------------------------------------------------------------------
# 关键：Android Gradle 明确拒绝非 ASCII 项目路径，Windows MSBuild 也会被
# 中文路径的编码搞坏。因此所有构建都在 ASCII 联接路径 C:\dev\kt 下进行
# （junction 指向真实项目，文件是同一份，不需要管理员权限）。
# ---------------------------------------------------------------------------
$Ascii = 'C:\dev\kt'

if (-not (Test-Path $Ascii)) {
  cmd /c mklink /J "$Ascii" "$AppDir" | Out-Null
} elseif ((Get-Item $Ascii -Force).LinkType -eq 'Junction') {
  # 项目目录可能被移动/改名过：联接还指向旧位置时必须重建，否则会构建到别的项目。
  $junctionTarget = @((Get-Item $Ascii -Force).Target)[0]
  if ($junctionTarget) {
    $normalizedTarget = $junctionTarget.TrimEnd('\')
    if ($normalizedTarget -ne $AppDir.TrimEnd('\')) {
      Write-Host "Rebuilding stale junction: $Ascii -> $normalizedTarget (expected $AppDir)"
      cmd /c rmdir "$Ascii" | Out-Null
      cmd /c mklink /J "$Ascii" "$AppDir" | Out-Null
    }
  }
}
if (-not (Test-Path "$Ascii\pubspec.yaml")) {
  Write-Host "FATAL: ASCII junction not usable at $Ascii"
  exit 1
}
Write-Host "Building via ASCII path: $Ascii"
Set-Location $Ascii

# 先解析依赖：新增插件后 .flutter-plugins-dependencies 才会更新，
# 之后才能为它建 junction。顺序反了会漏掉新插件。
#
# 注意：本机没有开启 Windows 开发者模式时，`flutter pub get` 在重建
# windows\flutter\ephemeral\.plugin_symlinks 这一步会失败（ERROR_PRIVILEGE_NOT_HELD），
# 但依赖解析与 package_config 已经写好；因此下面的 build 一律加 --no-pub，
# 避免 flutter 再次隐式执行 pub get 把 junction 删掉。
& 'C:\dev\flutter\bin\flutter.bat' pub get 2>&1 | Select-Object -Last 3

# 插件符号链接（无开发者模式时用 junction 兜底）
$links = Join-Path $Ascii 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $links | Out-Null
if (Test-Path '.flutter-plugins-dependencies') {
  $j = Get-Content '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
  foreach ($p in $j.plugins.windows) {
    $target = $p.path.TrimEnd('\')
    $link = Join-Path $links $p.name
    if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$target" 2>&1 | Out-Null }
  }
  Write-Host 'plugin junctions ensured'
}

Write-Host "`n========== WINDOWS RELEASE BUILD =========="
& 'C:\dev\flutter\bin\flutter.bat' build windows --release --no-pub 2>&1 | Select-Object -Last 12
$winCode = $LASTEXITCODE
Write-Host "WINDOWS_EXIT=$winCode"

Write-Host "`n========== ANDROID RELEASE APK =========="
& 'C:\dev\flutter\bin\flutter.bat' build apk --release --no-pub 2>&1 | Select-Object -Last 25
$apkCode = $LASTEXITCODE
Write-Host "ANDROID_EXIT=$apkCode"

Write-Host "`n========== ARTIFACTS =========="
Get-ChildItem -Recurse -File -Include *.exe,*.apk -Path 'build' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch 'intermediates|CMakeFiles' } |
  ForEach-Object { "{0,10:N1} MB  {1}" -f ($_.Length/1MB), $_.FullName }

# ---------------------------------------------------------------------------
# 归档：按版本号复制/压缩到 dist/，供 tooling\release.ps1 直接上传。
# 命名约定必须与 release.ps1、README「发布新版本」章节保持一致。
# ---------------------------------------------------------------------------
Write-Host "`n========== PACKAGE TO dist/ =========="

$distRootFull = [System.IO.Path]::GetFullPath($DistRoot).TrimEnd('\') + '\'

# 写 dist 之前先校验目标确实在项目 dist/ 下，避免脚本被改坏时误覆盖别处文件。
function Assert-UnderDist([string]$Path, [string]$What) {
  $full = [System.IO.Path]::GetFullPath($Path)
  if (-not $full.StartsWith($distRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝写入 dist 之外的目标（$What）：$full"
  }
  return $full
}

# 归档文件名统一用 ASCII：gh CLI 在 Windows 上传带中文的文件名时会把非 ASCII
# 字符吃掉（实测「课表-v1.1.0.apk」变成「-v1.1.0.apk」），Release 资产名必须稳定。
$apkOut = Join-Path $DistAndroid "kexu-v$Version.apk"
$zipOut = Join-Path $DistWindows "kexu-v$Version-windows.zip"

New-Item -ItemType Directory -Force -Path $DistAndroid, $DistWindows | Out-Null

# --- Android APK ---
$apkSrc = Join-Path $Ascii 'build\app\outputs\flutter-apk\app-release.apk'
if ($apkCode -eq 0 -and (Test-Path $apkSrc)) {
  Assert-UnderDist $apkOut 'Android APK' | Out-Null
  Copy-Item -LiteralPath $apkSrc -Destination $apkOut -Force
  Write-Host ("APK  -> {0} ({1:N1} MB)" -f $apkOut, ((Get-Item $apkOut).Length / 1MB))
} else {
  Write-Host "WARN: 没有可归档的 Android 产物（$apkSrc）"
}

# --- Windows：把整个 runner\Release 目录压缩成一个 zip ---
$winExe = Get-ChildItem -Path (Join-Path $Ascii 'build\windows') -Recurse -File -Filter '*.exe' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\runner\\Release\\' -and $_.FullName -notmatch 'intermediates|CMakeFiles' } |
  Select-Object -First 1
if ($winCode -eq 0 -and $winExe) {
  $winReleaseDir = $winExe.Directory.FullName
  Assert-UnderDist $zipOut 'Windows zip' | Out-Null
  if (Test-Path $zipOut) { Remove-Item -LiteralPath $zipOut -Force }
  Compress-Archive -Path (Join-Path $winReleaseDir '*') -DestinationPath $zipOut -CompressionLevel Optimal
  Write-Host ("ZIP  -> {0} ({1:N1} MB)" -f $zipOut, ((Get-Item $zipOut).Length / 1MB))
} else {
  Write-Host "WARN: 没有可归档的 Windows 产物（build\windows\**\runner\Release）"
}

$apkOk = Test-Path $apkOut
$zipOk = Test-Path $zipOut

# dist\windows 下可能还有手工解包的 Release 目录（course_timetable.exe + data\），
# 只提示不删除：zip 是正式分发产物，解包目录方便本机直接运行。
$staleExe = Get-ChildItem -Path $DistWindows -File -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($staleExe) {
  Write-Host "NOTE: dist\windows 下还有解包目录（$($staleExe.Name) 等），zip 是正式分发产物；不需要可直接运行解包目录，或手动清理。"
}

Write-Host "`n========== DIST =========="
Get-ChildItem -Path $DistRoot -Recurse -File -ErrorAction SilentlyContinue |
  ForEach-Object { "{0,10:N1} MB  {1}" -f ($_.Length/1MB), $_.FullName }

Write-Host "`nSUMMARY windows=$winCode android=$apkCode version=$FullVersion apk=$apkOk zip=$zipOk"
if ($winCode -ne 0 -or $apkCode -ne 0 -or -not $apkOk -or -not $zipOk) {
  Write-Host "BUILD FAILED（看上方 WINDOWS_EXIT / ANDROID_EXIT 与 WARN 行）"
  exit 1
}
Write-Host "BUILD OK"
exit 0

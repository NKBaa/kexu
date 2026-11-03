param(
  [string]$Root = 'C:\dev'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Dl  = Join-Path $Root '_dl'
$Log = Join-Path $Root 'bootstrap.log'
New-Item -ItemType Directory -Force -Path $Root, $Dl | Out-Null

function Log([string]$m) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Write-Output $line
  Add-Content -Path $Log -Value $line -Encoding utf8
}

function Download([string]$url, [string]$dest) {
  if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 1MB)) {
    Log "cached $dest"
    return
  }
  Log "GET $url"
  & curl.exe -L --fail --retry 3 --retry-delay 3 --silent --show-error -o $dest $url
  if ($LASTEXITCODE -ne 0) { throw "curl failed ($LASTEXITCODE) for $url" }
  Log ("  -> {0:N1} MB" -f ((Get-Item $dest).Length / 1MB))
}

function Unzip([string]$zip, [string]$dest) {
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  & tar.exe -xf $zip -C $dest
  if ($LASTEXITCODE -ne 0) { throw "tar failed for $zip" }
}

Log "=== bootstrap start (root=$Root) ==="

# ---------------------------------------------------------------- 1. Flutter
$flutterDir = Join-Path $Root 'flutter'
$flutterBin = Join-Path $flutterDir 'bin\flutter.bat'
if (Test-Path $flutterBin) {
  Log "Flutter already present at $flutterDir"
} else {
  $manifest = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
  $rel = $manifest.releases | Where-Object { $_.channel -eq 'stable' } | Select-Object -First 1
  $url = $manifest.base_url + '/' + $rel.archive
  Log "Flutter stable target: $($rel.version) (dart $($rel.dart_sdk_version))"
  $zip = Join-Path $Dl 'flutter.zip'
  Download $url $zip
  Log 'extracting flutter (several minutes)...'
  Unzip $zip $Root
  Remove-Item $zip -Force
  Log 'flutter extracted'
}

# -------------------------------------------------------------------- 2. JDK
$jdkDir = Join-Path $Root 'jdk17'
if (Test-Path (Join-Path $jdkDir 'bin\java.exe')) {
  Log "JDK already present at $jdkDir"
} else {
  $jdkZip = Join-Path $Dl 'jdk17.zip'
  Download 'https://aka.ms/download-jdk/microsoft-jdk-17.0.13-windows-x64.zip' $jdkZip
  $tmp = Join-Path $Dl 'jdk17_tmp'
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Unzip $jdkZip $tmp
  $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
  if (-not $inner) { throw 'JDK zip layout unexpected' }
  Move-Item $inner.FullName $jdkDir
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $jdkZip -Force -ErrorAction SilentlyContinue
  Log "JDK installed at $jdkDir"
}

# ------------------------------------------------------------- 3. Android SDK
$Sdk = Join-Path $Root 'android-sdk'
$sdkManager = Join-Path $Sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path $sdkManager)) {
  $cmdZip = Join-Path $Dl 'cmdline-tools.zip'
  Download 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' $cmdZip
  $tmp = Join-Path $Dl 'cmdtools_tmp'
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Unzip $cmdZip $tmp
  $latest = Join-Path $Sdk 'cmdline-tools\latest'
  New-Item -ItemType Directory -Force -Path (Split-Path $latest) | Out-Null
  if (Test-Path $latest) { Remove-Item $latest -Recurse -Force }
  Move-Item (Join-Path $tmp 'cmdline-tools') $latest
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $cmdZip -Force -ErrorAction SilentlyContinue
  Log "cmdline-tools installed"
}

$env:JAVA_HOME = $jdkDir
$env:ANDROID_HOME = $Sdk
$env:ANDROID_SDK_ROOT = $Sdk
$env:PATH = "$jdkDir\bin;$Sdk\platform-tools;$Sdk\cmdline-tools\latest\bin;$flutterDir\bin;$env:PATH"
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

Log 'accepting Android licenses...'
$yes = (1..80 | ForEach-Object { 'y' }) -join "`n"
$yes | & $sdkManager --sdk_root=$Sdk --licenses 2>&1 | Out-Null
Log 'licenses done'

$pkgs = @(
  'platform-tools',
  'platforms;android-35',
  'build-tools;35.0.0'
)
Log "installing SDK packages: $($pkgs -join ', ')"
& $sdkManager --sdk_root=$Sdk @pkgs 2>&1 | ForEach-Object { if ($_ -match 'Fetch|Install|Unzip|done') { Log "  sdk: $_" } }
Log 'sdk packages done'

# --------------------------------------------------------- 4. persist env vars
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkDir, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $Sdk, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $Sdk, 'User')
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
foreach ($p in @("$jdkDir\bin", "$Sdk\platform-tools", "$Sdk\cmdline-tools\latest\bin", "$flutterDir\bin")) {
  if ($userPath -notlike "*$p*") { $userPath = "$p;$userPath" }
}
[Environment]::SetEnvironmentVariable('PATH', $userPath, 'User')
Log 'user environment variables persisted'

# ------------------------------------------------------------ 5. warm flutter
Log 'flutter config / precache ...'
& $flutterBin config --no-analytics 2>&1 | Out-Null
& $flutterBin precache --windows --android 2>&1 | ForEach-Object { if ($_ -match 'Downloading|artifacts|done') { Log "  fl: $_" } }
Log 'precache done'

Log '=== flutter doctor ==='
& $flutterBin doctor -v 2>&1 | ForEach-Object { Log "  $_" }

Log '=== bootstrap COMPLETE ==='

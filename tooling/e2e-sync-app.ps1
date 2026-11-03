$ErrorActionPreference = 'Stop'

# 用真实数据目录启动打包后的 App，验证「启动自动同步」会真的把课表推到 WebDAV 服务器
#
# 注意：数据目录必须放在**工作区内**。DSH 沙箱允许子进程写入工作区，
# 但会拒绝写入工作区之外的路径（如 %APPDATA%），
# 那样会测不出真实行为（不过 App 对此有容错，不会崩）。
$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root '.e2e-sync-data'
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

# 远端目录先清空，确保是「首次同步 → 应上传」的场景
$davRoot = 'C:\dev\davroot\appsync'
Remove-Item $davRoot -Recurse -Force -ErrorAction SilentlyContinue

# 1) 预置课表
$timetable = @'
{
  "version": 1,
  "semester": {"id":"sem1","name":"2026 春季学期","startMonday":"2026-02-23T00:00:00.000","totalWeeks":16},
  "timeSlots": [
    {"period":1,"start":"08:00","end":"08:45"},{"period":2,"start":"08:55","end":"09:40"},
    {"period":3,"start":"10:00","end":"10:45"},{"period":4,"start":"10:55","end":"11:40"},
    {"period":5,"start":"14:00","end":"14:45"},{"period":6,"start":"14:55","end":"15:40"},
    {"period":7,"start":"16:00","end":"16:45"},{"period":8,"start":"16:55","end":"17:40"},
    {"period":9,"start":"19:00","end":"19:45"},{"period":10,"start":"19:55","end":"20:40"},
    {"period":11,"start":"20:50","end":"21:35"},{"period":12,"start":"21:45","end":"22:30"}
  ],
  "courses": [
    {"id":"c1","semesterId":"sem1","name":"高等数学","teacher":"张老师","colorIndex":0,"credit":5,
     "sessions":[{"id":"s1","dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1,3,5,7,9,11,13,15],"location":"A101"}],"adjustments":[]},
    {"id":"c2","semesterId":"sem1","name":"大学英语","teacher":"王老师","colorIndex":2,"credit":2,
     "sessions":[{"id":"s2","dayOfWeek":2,"startPeriod":3,"endPeriod":4,"weeks":[1,2,3,4,5,6,7,8],"location":"C305"}],"adjustments":[]}
  ]
}
'@
Set-Content -Path (Join-Path $dataDir 'timetable.json') -Value $timetable -Encoding UTF8

# 2) 预置设置：开启同步 + 自动同步，指向本地 WebDAV
$settings = @'
{
  "aiConfig": {"baseUrl":"","apiKey":"","model":"","temperature":0.2,"timeoutSeconds":120},
  "syncConfig": {
    "enabled": true,
    "autoSync": true,
    "backend": "webdav",
    "deviceId": "e2e-device",
    "webdav": {
      "url": "http://127.0.0.1:8765/",
      "username": "",
      "password": "",
      "remotePath": "/appsync/timetable.json"
    },
    "lastSyncAtMs": 0
  },
  "themeMode": "system",
  "showWeekend": true,
  "autoJumpToCurrentWeek": true
}
'@
Set-Content -Path (Join-Path $dataDir 'settings.json') -Value $settings -Encoding UTF8
Write-Host "seeded data dir: $dataDir"

$rel = Join-Path $root 'app\build\windows\x64\runner\Release'
Get-Process course_timetable -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $rel 'course_timetable.exe'
$psi.WorkingDirectory = $rel
$psi.UseShellExecute = $false
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['COURSE_TIMETABLE_DATA_DIR'] = $dataDir

$p = New-Object System.Diagnostics.Process; $p.StartInfo = $psi
$null = $p.Start()
Write-Host "started pid=$($p.Id)  (等待启动自动同步…)"
Start-Sleep -Seconds 18

$p.Refresh()
if ($p.HasExited) { Write-Host "APP EXITED code=$($p.ExitCode)" } else { Write-Host "app running" }
$p.Kill()

Write-Host "`n=== WebDAV 服务器上的 appsync 目录 ==="
if (Test-Path $davRoot) {
  Get-ChildItem $davRoot -Recurse -File | Select-Object @{n='File';e={$_.FullName.Replace($davRoot,'')}},Bytes,LastWriteTime | Format-Table -AutoSize
} else {
  Write-Host "（不存在 —— 同步没有发生）"
}

Write-Host "=== 本地数据目录（应有 sync_state.json 基线） ==="
Get-ChildItem $dataDir -Recurse -File | Select-Object @{n='File';e={$_.Name}},Bytes,LastWriteTime | Format-Table -AutoSize

$se = $p.StandardError.ReadToEnd()
Write-Host "=== app stderr ==="
if ($se.Trim()) { $se } else { '(clean)' }

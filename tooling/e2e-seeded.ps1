$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr d, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int Left, Top, Right, Bottom; }
}
'@

$dataDir = 'C:\dev\ktdata'
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

# 预置一份「不规律课表」：单周课 + 断续周次课，覆盖多天
$timetable = @'
{
  "version": 1,
  "semester": {
    "id": "sem1",
    "name": "2026 春季学期",
    "startMonday": "2026-02-23T00:00:00.000",
    "totalWeeks": 16
  },
  "timeSlots": [
    {"period":1,"start":"08:00","end":"08:45"},
    {"period":2,"start":"08:55","end":"09:40"},
    {"period":3,"start":"10:00","end":"10:45"},
    {"period":4,"start":"10:55","end":"11:40"},
    {"period":5,"start":"14:00","end":"14:45"},
    {"period":6,"start":"14:55","end":"15:40"},
    {"period":7,"start":"16:00","end":"16:45"},
    {"period":8,"start":"16:55","end":"17:40"},
    {"period":9,"start":"19:00","end":"19:45"},
    {"period":10,"start":"19:55","end":"20:40"},
    {"period":11,"start":"20:50","end":"21:35"},
    {"period":12,"start":"21:45","end":"22:30"}
  ],
  "courses": [
    {"id":"c1","semesterId":"sem1","name":"高等数学","teacher":"张老师","colorIndex":0,"credit":5,
     "sessions":[{"id":"s1","dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1,3,5,7,9,11,13,15],"location":"A101"}],
     "adjustments":[]},
    {"id":"c2","semesterId":"sem1","name":"数据结构","teacher":"李老师","colorIndex":1,"credit":4,
     "sessions":[{"id":"s2","dayOfWeek":3,"startPeriod":5,"endPeriod":6,"weeks":[3,4,5,7,8,9],"location":"B203"}],
     "adjustments":[]},
    {"id":"c3","semesterId":"sem1","name":"大学英语","teacher":"王老师","colorIndex":2,"credit":2,
     "sessions":[{"id":"s3","dayOfWeek":2,"startPeriod":3,"endPeriod":4,"weeks":[1,2,3,4,5,6,7,8],"location":"C305"}],
     "adjustments":[]},
    {"id":"c4","semesterId":"sem1","name":"物理实验","teacher":"赵老师","colorIndex":3,"credit":1,
     "sessions":[{"id":"s4","dayOfWeek":5,"startPeriod":7,"endPeriod":8,"weeks":[2,4,6,8],"location":"实验楼201"}],
     "adjustments":[]}
  ]
}
'@
Set-Content -Path (Join-Path $dataDir 'timetable.json') -Value $timetable -Encoding UTF8
Write-Host "seeded: $dataDir\timetable.json"

$root = Split-Path -Parent $PSScriptRoot
$rel = Join-Path $root 'app\build\windows\x64\runner\Release'
Get-Process course_timetable -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $rel 'course_timetable.exe'
$psi.WorkingDirectory = $rel
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
# 让数据落到可写目录（沙箱内 AppData 不可写）
$psi.EnvironmentVariables['COURSE_TIMETABLE_DATA_DIR'] = $dataDir

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
$null = $p.Start()
Write-Host "started pid=$($p.Id)"
Start-Sleep -Seconds 16
$p.Refresh()

if ($p.HasExited) { Write-Host "FAIL exited=$($p.ExitCode)"; exit 1 }

$hwnd = $p.MainWindowHandle
$r = New-Object W+R
[void][W]::GetWindowRect($hwnd, [ref]$r)
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
Write-Host "window ${w}x${h} visible=$([W]::IsWindowVisible($hwnd))"

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[void][W]::PrintWindow($hwnd, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = 'C:\dev\shot_seeded.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Host "screenshot: $out"

$p.Kill()
$se = $p.StandardError.ReadToEnd()
Write-Host "`n--- stderr ---"; if ($se.Trim()) { $se } else { '(clean)' }

Write-Host "`n--- data dir after run ---"
Get-ChildItem $dataDir -Recurse -File | Select-Object @{n='Rel';e={$_.FullName.Replace($dataDir+'\','')}},@{n='KB';e={[math]::Round($_.Length/1KB,1)}} | Format-Table -AutoSize

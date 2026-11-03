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

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root '.e2e-conflict'
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

# 关键：两门课在同一时间（周一 1-2 节，周次完全重叠）—— 应并排显示且高亮冲突
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
     "sessions":[{"id":"s1","dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],"location":"A101"}],"adjustments":[]},
    {"id":"c2","semesterId":"sem1","name":"大学英语","teacher":"王老师","colorIndex":1,"credit":2,
     "sessions":[{"id":"s2","dayOfWeek":1,"startPeriod":1,"endPeriod":2,"weeks":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],"location":"B203"}],"adjustments":[]},
    {"id":"c3","semesterId":"sem1","name":"数据结构","teacher":"李老师","colorIndex":2,"credit":4,
     "sessions":[{"id":"s3","dayOfWeek":3,"startPeriod":5,"endPeriod":6,"weeks":[1,3,5,7,9,11,13,15],"location":"C305"}],"adjustments":[]}
  ]
}
'@
Set-Content -Path (Join-Path $dataDir 'timetable.json') -Value $timetable -Encoding UTF8

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
Start-Sleep -Seconds 15
$p.Refresh()
if ($p.HasExited) { Write-Host "APP EXITED code=$($p.ExitCode)"; exit 1 }

$hwnd = $p.MainWindowHandle
$r = New-Object W+R
[void][W]::GetWindowRect($hwnd, [ref]$r)
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
Write-Host "window ${w}x${h}"

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[void][W]::PrintWindow($hwnd, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
$out = Join-Path $root 'docs\screenshot-conflict.png'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Host "screenshot: $out"
$p.Kill()

$se = $p.StandardError.ReadToEnd()
Write-Host "stderr: $(if ($se.Trim()) { $se } else { '(clean)' })"
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue

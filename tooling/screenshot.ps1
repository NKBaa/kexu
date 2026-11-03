$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sig = @'
using System;
using System.Runtime.InteropServices;
public class WinCap {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
'@
Add-Type -TypeDefinition $sig

$root = Split-Path -Parent $PSScriptRoot
$rel = Join-Path $root 'app\build\windows\x64\runner\Release'
Get-Process course_timetable -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$exe = Join-Path $rel 'course_timetable.exe'
$p = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo -Property @{
  FileName = $exe; WorkingDirectory = $rel; UseShellExecute = $false
}))
Write-Host "started pid=$($p.Id)"
Start-Sleep -Seconds 15

$p.Refresh()
if ($p.HasExited) { Write-Host "FAIL: exited code=$($p.ExitCode)"; exit 1 }

$hwnd = $p.MainWindowHandle
Write-Host "hwnd=$hwnd visible=$([WinCap]::IsWindowVisible($hwnd)) title='$($p.MainWindowTitle)'"
if ($hwnd -eq [IntPtr]::Zero) { Write-Host 'FAIL: no main window'; $p.Kill(); exit 1 }

$r = New-Object WinCap+RECT
[void][WinCap]::GetWindowRect($hwnd, [ref]$r)
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
Write-Host "size=${w}x${h}"

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
# flags=2 => PW_RENDERFULLCONTENT (works for GPU-composited windows)
$ok = [WinCap]::PrintWindow($hwnd, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
Write-Host "PrintWindow=$ok"

$out = 'C:\dev\screenshot_main.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "saved: $out  ($([math]::Round((Get-Item $out).Length/1KB,1)) KB)"

$p.Kill()
Write-Host 'done'

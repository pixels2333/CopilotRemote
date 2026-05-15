﻿# Plays completion audio at session end via winmm.dll (no WPF/COM)
# Separated from auto-deploy.ps1 for independent reuse

$ErrorActionPreference = "Continue"

$audioFile = "C:\Users\Administrator\Music\任务完成.mp3"
if (-not (Test-Path $audioFile)) {
    Write-Host "⚠️  Hook: Audio file not found at $audioFile" -ForegroundColor Yellow
    exit 0
}

Write-Host "🔊 Hook: Playing completion audio..." -ForegroundColor Cyan

try {
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class WinMM {
    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    public static extern int mciSendString(string cmd, System.Text.StringBuilder ret, int len, System.IntPtr hwnd);
}
'@ -ErrorAction Stop

    $alias = "completionAudio"
    [WinMM]::mciSendString("open `"$audioFile`" type mpegvideo alias $alias", $null, 0, [System.IntPtr]::Zero) | Out-Null
    [WinMM]::mciSendString("play $alias wait", $null, 0, [System.IntPtr]::Zero) | Out-Null
    [WinMM]::mciSendString("close $alias", $null, 0, [System.IntPtr]::Zero) | Out-Null
}
catch {
    Write-Host "⚠️  Hook: Could not play audio - $($_.Exception.Message)" -ForegroundColor Yellow
}

exit 0

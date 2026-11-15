# Removes AutoInputPS5: switches back to the PC if needed, stops the listener,
# deletes the shortcuts and %LOCALAPPDATA%\AutoInputPS5.
$dest = Join-Path $env:LOCALAPPDATA 'AutoInputPS5'
$ps   = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

if (Test-Path (Join-Path $dest 'fence.txt')) {
    Write-Host "Switching back to the PC first..."
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'AutoInputPS5.ps1') -To PC
}

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'HotkeyListener\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'AutoInputPS5 Hotkey.lnk') -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'AutoInputPS5.lnk') -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "AutoInputPS5 removed."

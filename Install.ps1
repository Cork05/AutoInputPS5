# Installs AutoInputPS5 for the current user (no admin needed).
#  - copies the scripts to %LOCALAPPDATA%\AutoInputPS5
#  - creates settings.json (only if you don't have one yet)
#  - starts the hotkey listener now and at every login
#  - adds a "AutoInputPS5" shortcut to the desktop
$ErrorActionPreference = 'Stop'
$src  = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'AutoInputPS5'
$ps   = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

Write-Host "Installing AutoInputPS5 to $dest"

# Stop a listener that's already running so its files can be replaced.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'HotkeyListener\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Force $dest | Out-Null
foreach ($f in 'AutoInputPS5.ps1', 'HotkeyListener.ps1') {
    Copy-Item (Join-Path $src $f) $dest -Force
}
$settings = Join-Path $dest 'settings.json'
if (-not (Test-Path $settings)) {
    Copy-Item (Join-Path $src 'settings.example.json') $settings
    Write-Host "Created default settings.json"
} else {
    Write-Host "Kept your existing settings.json"
}
# Files downloaded from the internet are marked as blocked; clear that.
Get-ChildItem $dest | Unblock-File

$ws = New-Object -ComObject WScript.Shell

# Start the listener at login.
$startup = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'AutoInputPS5 Hotkey.lnk'))
$startup.TargetPath  = $ps
$startup.Arguments   = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\HotkeyListener.ps1`""
$startup.WindowStyle = 7
$startup.Description = 'AutoInputPS5 hotkey listener'
$startup.Save()

# Desktop shortcut for switching with a double-click.
$desk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'AutoInputPS5.lnk'))
$desk.TargetPath   = $ps
$desk.Arguments    = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\AutoInputPS5.ps1`" -To Toggle"
$desk.WindowStyle  = 7
$desk.IconLocation = "$env:WINDIR\System32\imageres.dll,-27"
$desk.Description  = 'Switch the shared monitor between PC and PS5'
$desk.Hotkey       = ''
$desk.Save()

# Start the listener now.
Start-Process $ps -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dest\HotkeyListener.ps1`""
Start-Sleep -Seconds 3
$log = Join-Path $dest 'listener.log'
if (Test-Path $log) { Write-Host ("Listener: " + (Get-Content $log -Tail 1)) }

Write-Host ""
Write-Host "Your monitors:"
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'AutoInputPS5.ps1') -To Info
Write-Host ""
Write-Host "Done. If the PS5 isn't on the screen marked '<- shared with PS5', or uses a"
Write-Host "different input, edit $settings (see README)."

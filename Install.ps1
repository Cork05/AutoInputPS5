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
    # v1.0 stored a 0-based monitor index and raw input codes; switch those to names.
    $cfg = Get-Content -Raw $settings | ConvertFrom-Json
    if ($cfg.SharedMonitor -is [int]) {
        $names = @{ 1 = 'VGA 1'; 2 = 'VGA 2'; 3 = 'DVI 1'; 4 = 'DVI 2'; 15 = 'DisplayPort 1'; 16 = 'DisplayPort 2'; 17 = 'HDMI 1'; 18 = 'HDMI 2'; 27 = 'USB-C' }
        $shared = "$([int]$cfg.SharedMonitor + 1)"
        $pc  = if ($names.ContainsKey([int]$cfg.PcInput))  { $names[[int]$cfg.PcInput] }  else { [int]$cfg.PcInput }
        $ps5 = if ($names.ContainsKey([int]$cfg.Ps5Input)) { $names[[int]$cfg.Ps5Input] } else { [int]$cfg.Ps5Input }
        $hk  = if ($cfg.Hotkey) { $cfg.Hotkey } else { 'Ctrl+Alt+P' }
        $json = "{`r`n    `"SharedMonitor`": $(ConvertTo-Json $shared),`r`n    `"PcInput`": $(ConvertTo-Json $pc),`r`n    `"Ps5Input`": $(ConvertTo-Json $ps5),`r`n    `"Hotkey`": $(ConvertTo-Json $hk)`r`n}`r`n"
        [IO.File]::WriteAllText($settings, $json)
        Write-Host "Upgraded settings.json to the new input names"
    }
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
Write-Host "The wizard learns which monitor and ports you use, so you don't have to edit settings."
$ans = Read-Host "Run the setup wizard to detect your monitor and inputs automatically? [Y/n]"
if ($ans -notmatch '^\s*n') {
    Write-Host ""
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'AutoInputPS5.ps1') -To Detect
}
Write-Host ""
Write-Host "All set. Press Ctrl+Alt+P to switch (or the hotkey in settings.json)."
Write-Host "Run the wizard again any time: double-click Detect.bat"

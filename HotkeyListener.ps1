# Runs hidden in the background:
#  - listens for the hotkey (default Ctrl+Alt+P) and runs AutoInputPS5.ps1 -To Toggle
#  - while in PS5 mode (fence.txt exists), keeps the mouse fenced into the other screen
$ErrorActionPreference = 'Stop'
$dir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$log    = Join-Path $dir 'listener.log'
$switch = Join-Path $dir 'AutoInputPS5.ps1'
$fence  = Join-Path $dir 'fence.txt'

# Hotkey from settings.json, e.g. "Ctrl+Alt+P", "Ctrl+Shift+F9", "Win+Alt+G"
$hotkey = 'Ctrl+Alt+P'
$settings = Join-Path $dir 'settings.json'
if (Test-Path $settings) {
    $cfg = Get-Content -Raw $settings | ConvertFrom-Json
    if ($cfg.Hotkey) { $hotkey = [string]$cfg.Hotkey }
}
$mods = 0; $vk = 0
foreach ($part in $hotkey.Split('+') | ForEach-Object { $_.Trim().ToUpper() }) {
    switch -Regex ($part) {
        '^(CTRL|CONTROL)$' { $mods = $mods -bor 2; break }
        '^ALT$'            { $mods = $mods -bor 1; break }
        '^SHIFT$'          { $mods = $mods -bor 4; break }
        '^WIN$'            { $mods = $mods -bor 8; break }
        '^F([1-9]|1[0-9]|2[0-4])$' { $vk = 0x6F + [int]$Matches[1]; break }
        '^[A-Z0-9]$'       { $vk = [int][char]$part; break }
        default { "$(Get-Date -Format s) Unknown hotkey part '$part' in '$hotkey'" | Add-Content $log; exit 1 }
    }
}
if ($vk -eq 0) { "$(Get-Date -Format s) Hotkey '$hotkey' has no key" | Add-Content $log; exit 1 }

# Only one listener at a time.
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\AutoInputPS5Hotkey', [ref]$created)
if (-not $created) { exit }

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HotkeyWindow : NativeWindow, IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] static extern bool ClipCursor(ref RECT r);
    [DllImport("user32.dll", EntryPoint = "ClipCursor")] static extern bool ClipCursorOff(IntPtr none);

    public event EventHandler Pressed;
    public bool Ok;
    public int Error;

    Timer fenceTimer;
    string fencePath;
    DateTime fenceStamp;
    RECT fenceRect;
    bool haveRect, clipped;

    public HotkeyWindow(uint mods, uint vk) {
        SetProcessDpiAwarenessContext(new IntPtr(-4));   // same pixel coordinates as AutoInputPS5.ps1
        CreateHandle(new CreateParams());
        Ok = RegisterHotKey(Handle, 1, mods | 0x4000 /* no repeat */, vk);
        if (!Ok) Error = Marshal.GetLastWin32Error();
    }

    // Windows (and some apps) silently drop a cursor clip on focus changes, UAC prompts etc.,
    // so re-apply it every 100 ms while the fence file exists.
    public void StartFence(string path) {
        fencePath = path;
        fenceTimer = new Timer();
        fenceTimer.Interval = 100;
        fenceTimer.Tick += delegate { FenceTick(); };
        fenceTimer.Start();
    }

    void FenceTick() {
        try {
            if (File.Exists(fencePath)) {
                var stamp = File.GetLastWriteTimeUtc(fencePath);
                if (!haveRect || stamp != fenceStamp) {
                    var p = File.ReadAllText(fencePath).Trim().Split(',');
                    fenceRect = new RECT { Left = int.Parse(p[0]), Top = int.Parse(p[1]), Right = int.Parse(p[2]), Bottom = int.Parse(p[3]) };
                    fenceStamp = stamp; haveRect = true;
                }
                ClipCursor(ref fenceRect);
                clipped = true;
            } else if (clipped) {
                ClipCursorOff(IntPtr.Zero);
                clipped = false; haveRect = false;
            }
        } catch { /* file mid-write; try again next tick */ }
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty);
        base.WndProc(ref m);
    }
    public void Dispose() { UnregisterHotKey(Handle, 1); ClipCursorOff(IntPtr.Zero); DestroyHandle(); }
}
"@

$hk = New-Object HotkeyWindow([uint32]$mods, [uint32]$vk)
if (-not $hk.Ok) {
    "$(Get-Date -Format s) $hotkey could not be registered (error $($hk.Error)) - another app is probably using it. Pick another Hotkey in settings.json." | Add-Content $log
    exit 1
}
"$(Get-Date -Format s) Listening for $hotkey, mouse fence on" | Add-Content $log

$hk.add_Pressed({
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$switch`"", '-To', 'Toggle')
})
$hk.StartFence($fence)
[System.Windows.Forms.Application]::Run()

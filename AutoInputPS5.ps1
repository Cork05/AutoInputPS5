# AutoInputPS5 - flips the shared monitor between the PC and the PS5,
# moving your windows out of the way and back again.
#
#   -To PS5     move windows to the other screen, then switch monitor to the PS5
#   -To PC      switch monitor back to the PC, then put windows back
#   -To Toggle  whichever of the two applies right now (default)
#   -To Info    list monitors only, change nothing
#   -To Detect  wizard: you switch the monitor to the PS5 by hand, it learns the setup
param(
    [ValidateSet('PS5', 'PC', 'Toggle', 'Info', 'Detect')] [string]$To = 'Toggle'
)

# ---- input names ------------------------------------------------------------
# Monitors talk in numbered input codes (MCCS VCP 0x60). People talk in port names.
$InputNames = [ordered]@{
    'VGA 1' = 1; 'VGA 2' = 2; 'DVI 1' = 3; 'DVI 2' = 4
    'Composite 1' = 5; 'Composite 2' = 6; 'S-Video 1' = 7; 'S-Video 2' = 8
    'Component 1' = 12; 'Component 2' = 13; 'Component 3' = 14
    'DisplayPort 1' = 15; 'DisplayPort 2' = 16; 'HDMI 1' = 17; 'HDMI 2' = 18
    'USB-C' = 27
}
$InputAliases = @{     # extra spellings people use -> canonical name
    'VGA' = 'VGA 1'; 'DVI' = 'DVI 1'; 'DP' = 'DisplayPort 1'; 'DP1' = 'DisplayPort 1'; 'DP2' = 'DisplayPort 2'
    'DISPLAYPORT' = 'DisplayPort 1'; 'HDMI' = 'HDMI 1'; 'USBC' = 'USB-C'; 'TYPEC' = 'USB-C'; 'USBC1' = 'USB-C'
    'THUNDERBOLT' = 'USB-C'; 'COMPONENT' = 'Component 1'; 'COMPOSITE' = 'Composite 1'; 'SVIDEO' = 'S-Video 1'
}
function Get-InputCode([object]$value) {
    if ($value -is [int] -or "$value" -match '^\d+$') { return [int]"$value" }   # learned by -To Detect on unusual monitors
    $key = ("$value" -replace '[\s_\-]', '').ToUpper()
    if ($InputAliases.ContainsKey($key)) { $key = ($InputAliases[$key] -replace '[\s_\-]', '').ToUpper() }
    foreach ($n in $InputNames.Keys) { if (($n -replace '[\s_\-]', '').ToUpper() -eq $key) { return $InputNames[$n] } }
    throw "Unknown input '$value'. Use one of: $($InputNames.Keys -join ', ') - or run the Detect wizard."
}
function Get-InputName([int]$code) {
    foreach ($n in $InputNames.Keys) { if ($InputNames[$n] -eq $code) { return $n } }
    return "input #$code"
}

# ---- settings (override them in settings.json next to this script) ----------
$SharedMonitor = 'main'           # 'main', 'second', or the monitor's number from -To Info
$PcInput       = 'DisplayPort 1'
$Ps5Input      = 'HDMI 2'
$Hotkey        = 'Ctrl+Alt+P'     # only used by HotkeyListener.ps1, kept here so Detect preserves it
$Settings = Join-Path $PSScriptRoot 'settings.json'
if (Test-Path $Settings) {
    $cfg = Get-Content -Raw $Settings | ConvertFrom-Json
    if ($null -ne $cfg.SharedMonitor) { $SharedMonitor = $cfg.SharedMonitor }
    if ($null -ne $cfg.PcInput)       { $PcInput       = $cfg.PcInput }
    if ($null -ne $cfg.Ps5Input)      { $Ps5Input      = $cfg.Ps5Input }
    if ($null -ne $cfg.Hotkey)        { $Hotkey        = $cfg.Hotkey }
}
$ConfigError = $null
try { $PcCode = Get-InputCode $PcInput; $Ps5Code = Get-InputCode $Ps5Input } catch { $ConfigError = $_.Exception.Message }
$StateFile = Join-Path $PSScriptRoot 'windows.json'
$FenceFile = Join-Path $PSScriptRoot 'fence.txt'   # read by HotkeyListener.ps1 to keep the mouse off the PS5 screen
$MouseFile = Join-Path $PSScriptRoot 'mouse.txt'   # where the mouse was before switching to the PS5

function Save-Settings($shared, $pc, $ps5) {
    $json = "{`r`n    `"SharedMonitor`": $(ConvertTo-Json $shared),`r`n    `"PcInput`": $(ConvertTo-Json $pc),`r`n    `"Ps5Input`": $(ConvertTo-Json $ps5),`r`n    `"Hotkey`": $(ConvertTo-Json $Hotkey)`r`n}`r`n"
    [IO.File]::WriteAllText($Settings, $json)
}
# -----------------------------------------------------------------------------

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class AutoInputPS5 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT { public int length; public int flags; public int showCmd; public POINT ptMin; public POINT ptMax; public RECT rcNormal; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PHYSICAL_MONITOR { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string d; }

    public delegate bool MonProc(IntPtr hMon, IntPtr hdc, IntPtr rect, IntPtr data);
    public delegate bool WinProc(IntPtr hWnd, IntPtr data);

    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonProc cb, IntPtr data);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr hMon, ref MONITORINFO mi);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromRect(ref RECT r, uint flags);
    [DllImport("user32.dll")] static extern bool EnumWindows(WinProc cb, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int idx);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT wp);
    [DllImport("user32.dll")] static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT wp);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int val, int size);
    [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
    [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PHYSICAL_MONITOR[] arr);
    [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, IntPtr type, out uint cur, out uint max);
    [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint val);

    public class Mon { public IntPtr HMon; public IntPtr Phys; public RECT Bounds; public RECT Work; public bool Primary; }
    public class Win { public long Handle; public string Title; public int ShowCmd; public bool RestoreMax; public int L, T, R, B; }

    public static void InitDpi() { SetProcessDpiAwarenessContext(new IntPtr(-4)); } // per-monitor v2

    public static List<Mon> Monitors() {
        var list = new List<Mon>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (h, d, r, p) => {
            var mi = new MONITORINFO(); mi.cbSize = Marshal.SizeOf(mi); GetMonitorInfo(h, ref mi);
            uint n; IntPtr phys = IntPtr.Zero;
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(h, out n) && n > 0) {
                var arr = new PHYSICAL_MONITOR[n];
                if (GetPhysicalMonitorsFromHMONITOR(h, n, arr)) phys = arr[0].h;
            }
            list.Add(new Mon { HMon = h, Phys = phys, Bounds = mi.rcMonitor, Work = mi.rcWork, Primary = (mi.dwFlags & 1) != 0 });
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static int GetInput(Mon m) { uint c, x; return GetVCPFeatureAndVCPFeatureReply(m.Phys, 0x60, IntPtr.Zero, out c, out x) ? (int)c : -1; }
    public static bool SetInput(Mon m, int v) { return SetVCPFeature(m.Phys, 0x60, (uint)v); }

    static readonly string[] SkipClasses = { "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd" };

    // Normal app windows (what you'd see in alt-tab) currently on the given monitor.
    public static List<Win> WindowsOn(Mon m) {
        var list = new List<Win>();
        EnumWindows((h, p) => {
            if (!IsWindowVisible(h)) return true;
            if (GetWindow(h, 4) != IntPtr.Zero) return true;                 // owned popup
            if ((GetWindowLong(h, -20) & 0x80) != 0) return true;            // WS_EX_TOOLWINDOW
            int cloaked; if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
            var cls = new StringBuilder(256); GetClassName(h, cls, 256);
            if (Array.IndexOf(SkipClasses, cls.ToString()) >= 0) return true;
            var title = new StringBuilder(512); GetWindowText(h, title, 512);
            if (title.Length == 0) return true;
            var wp = new WINDOWPLACEMENT(); wp.length = Marshal.SizeOf(wp); GetWindowPlacement(h, ref wp);
            // Minimized windows report a parking spot, so judge them by where they'll restore to.
            IntPtr on = wp.showCmd == 2 ? MonitorFromRect(ref wp.rcNormal, 2) : MonitorFromWindow(h, 2);
            if (on != m.HMon) return true;
            list.Add(new Win { Handle = h.ToInt64(), Title = title.ToString(), ShowCmd = wp.showCmd, RestoreMax = (wp.flags & 2) != 0,
                L = wp.rcNormal.Left, T = wp.rcNormal.Top, R = wp.rcNormal.Right, B = wp.rcNormal.Bottom });
            return true;
        }, IntPtr.Zero);
        return list;
    }

    // Put a window at a saved normal rect, shifted by (dx, dy), keeping max/min state.
    public static bool Place(Win w, int dx, int dy) {
        var h = new IntPtr(w.Handle);
        if (!IsWindow(h)) return false;
        bool minimized = w.ShowCmd == 2;
        bool maximized = w.ShowCmd == 3 || (minimized && w.RestoreMax);
        if (minimized) {
            // Many apps (Spotify, Discord, browsers - anything Chromium/Electron) ignore the restore
            // spot Windows keeps and reopen wherever they last were. So briefly un-minimize without
            // taking focus, move it for real, then minimize again.
            ShowWindow(h, 4);   // SW_SHOWNOACTIVATE
            System.Threading.Thread.Sleep(150);
        }
        var wp = new WINDOWPLACEMENT(); wp.length = Marshal.SizeOf(wp); GetWindowPlacement(h, ref wp);
        wp.rcNormal.Left = w.L + dx; wp.rcNormal.Top = w.T + dy; wp.rcNormal.Right = w.R + dx; wp.rcNormal.Bottom = w.B + dy;
        wp.flags = 0;
        if (maximized) {
            // Restore in place first so Windows re-maximizes on the new screen.
            var tmp = wp; tmp.showCmd = 4; SetWindowPlacement(h, ref tmp);
            wp.showCmd = 3;
        } else {
            wp.showCmd = 4;
        }
        bool ok = SetWindowPlacement(h, ref wp);
        if (minimized) {
            System.Threading.Thread.Sleep(150);
            ShowWindow(h, 7);   // SW_SHOWMINNOACTIVE
        }
        return ok;
    }
}
"@

[AutoInputPS5]::InitDpi()
$mons = [AutoInputPS5]::Monitors()

function Resolve-Monitor($value) {
    $v = "$value".Trim().ToLower()
    if ($v -eq 'main' -or $v -eq 'primary') { for ($i = 0; $i -lt $mons.Count; $i++) { if ($mons[$i].Primary) { return $i } } }
    if ($v -eq 'second' -or $v -eq 'secondary') { for ($i = 0; $i -lt $mons.Count; $i++) { if (-not $mons[$i].Primary) { return $i } } }
    if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le $mons.Count) { return [int]$v - 1 }
    return -1
}
function Describe-Monitor([int]$i) {
    $label = if ($mons[$i].Primary) { 'main' } else { 'second' }
    if ($mons.Count -gt 2 -and -not $mons[$i].Primary) { $label = 'other' }
    return "monitor $($i + 1) ($label)"
}
$SharedIndex = Resolve-Monitor $SharedMonitor
if ($mons.Count -eq 1) { $SharedIndex = 0 }   # single monitor: it's always the shared one

if ($To -eq 'Info') {
    Write-Host "Settings: PS5 shares '$SharedMonitor', PC on '$PcInput', PS5 on '$Ps5Input', hotkey $Hotkey"
    Write-Host ""
    for ($i = 0; $i -lt $mons.Count; $i++) {
        $m = $mons[$i]; $b = $m.Bounds
        $wins = [AutoInputPS5]::WindowsOn($m)
        $code = [AutoInputPS5]::GetInput($m)
        $tag = if ($i -eq $SharedIndex) { '  <- shared with PS5' } else { '' }
        $now = if ($code -lt 0) { 'DDC/CI not responding' } else { "showing $(Get-InputName $code)" }
        Write-Host ("{0}: {1}x{2}, {3}, {4} window(s){5}" -f (Describe-Monitor $i), ($b.Right - $b.Left), ($b.Bottom - $b.Top), $now, $wins.Count, $tag)
        foreach ($w in $wins) { Write-Host "      - $($w.Title)" }
    }
    exit
}

if ($To -eq 'Detect') {
    Write-Host "=== AutoInputPS5 setup wizard ==="
    Write-Host ""
    $before = @(); foreach ($m in $mons) { $before += [AutoInputPS5]::GetInput($m) }
    if (@($before | Where-Object { $_ -ge 0 }).Count -eq 0) {
        Write-Host "None of your monitors answer DDC/CI. Turn on DDC/CI in the monitor's on-screen menu and run this again."
        exit 1
    }
    Write-Host "1. Make sure the PS5 is ON (not in rest mode)."
    Write-Host "2. Use the buttons on your monitor to switch it to the PS5."
    Write-Host ""
    if ($mons.Count -eq 1) {
        Write-Host "   Single monitor: you'll see the PS5 for a few seconds, then AutoInputPS5"
        Write-Host "   switches you back here automatically. No need to touch anything else."
        Write-Host ""
    }
    Write-Host "Waiting up to 2 minutes for a monitor to change input..."
    $found = -1; $ps5 = -1
    for ($t = 0; $t -lt 120 -and $found -lt 0; $t++) {
        Start-Sleep -Seconds 1
        for ($i = 0; $i -lt $mons.Count; $i++) {
            $now = [AutoInputPS5]::GetInput($mons[$i])
            if ($before[$i] -ge 0 -and $now -ge 0 -and $now -ne $before[$i]) { $found = $i; $ps5 = $now; break }
        }
    }
    if ($found -lt 0) { Write-Host "No input change seen. Nothing was saved."; exit 1 }
    $pc = $before[$found]
    Start-Sleep -Seconds 2                                   # let the monitor settle, then switch back for you
    [void][AutoInputPS5]::SetInput($mons[$found], $pc)

    $sharedSetting = if ($mons[$found].Primary) { 'main' } elseif ($mons.Count -eq 2) { 'second' } else { "$($found + 1)" }
    $pcName = Get-InputName $pc;  $ps5Name = Get-InputName $ps5
    $pcSave  = if ($pcName  -like 'input #*') { $pc }  else { $pcName }    # unusual monitor: keep the number it reported
    $ps5Save = if ($ps5Name -like 'input #*') { $ps5 } else { $ps5Name }
    Save-Settings $sharedSetting $pcSave $ps5Save
    Write-Host ""
    Write-Host "Got it! Switched you back to the PC."
    Write-Host "  PS5 shares: $(Describe-Monitor $found)"
    Write-Host "  PC input:   $pcName"
    Write-Host "  PS5 input:  $ps5Name"
    Write-Host "Saved to $Settings"
    exit
}

if ($ConfigError) { Write-Host "settings.json: $ConfigError"; exit 1 }
if ($SharedIndex -lt 0) { Write-Host "SharedMonitor '$SharedMonitor' doesn't match a monitor. Use 'main', 'second' or a number from -To Info."; exit 1 }
$shared = $mons[$SharedIndex]
$other  = $mons | Where-Object { $_.HMon -ne $shared.HMon } | Select-Object -First 1   # $null on a single-monitor setup

if ($To -eq 'Toggle') { $To = if ([AutoInputPS5]::GetInput($shared) -eq $Ps5Code) { 'PC' } else { 'PS5' } }

if ($To -eq 'PS5') {
    $p = New-Object AutoInputPS5+POINT; [void][AutoInputPS5]::GetCursorPos([ref]$p)
    Set-Content -Encoding ASCII $MouseFile "$($p.X),$($p.Y)"
    if ($other) {
        # Two+ monitors: slide this screen's windows onto the other one and fence the mouse there.
        $dx = $other.Work.Left - $shared.Work.Left
        $dy = $other.Work.Top  - $shared.Work.Top
        $wins = [AutoInputPS5]::WindowsOn($shared)
        ConvertTo-Json -InputObject @($wins) -Depth 3 | Set-Content -Encoding UTF8 $StateFile
        foreach ($w in $wins) { [void][AutoInputPS5]::Place($w, $dx, $dy) }
        [void][AutoInputPS5]::SetCursorPos([int](($other.Work.Left + $other.Work.Right) / 2), [int](($other.Work.Top + $other.Work.Bottom) / 2))
        $b = $other.Bounds
        Set-Content -Encoding ASCII $FenceFile ("{0},{1},{2},{3}" -f $b.Left, $b.Top, $b.Right, $b.Bottom)
        $done = "Moved $($wins.Count) window(s) to the other screen"
    } else {
        # Single monitor: windows stay put (they're just behind the PS5 picture). Park the mouse in
        # the bottom-right corner pixel so a bumped mouse can't click anything you can't see.
        $b = $shared.Bounds
        [void][AutoInputPS5]::SetCursorPos($b.Right - 1, $b.Bottom - 1)
        Set-Content -Encoding ASCII $FenceFile ("{0},{1},{2},{3}" -f ($b.Right - 1), ($b.Bottom - 1), $b.Right, $b.Bottom)
        $done = "Parked the mouse"
    }
    [void][AutoInputPS5]::SetInput($shared, $Ps5Code)
    Write-Host "$done, switched to PS5."
}
else {
    Remove-Item $FenceFile -ErrorAction SilentlyContinue
    [void][AutoInputPS5]::SetInput($shared, $PcCode)
    $back = 0
    if (Test-Path $StateFile) {
        $saved = Get-Content -Raw $StateFile | ConvertFrom-Json   # assign first: PS 5.1 won't unroll a piped array
        foreach ($s in $saved) {
            $w = New-Object AutoInputPS5+Win
            $w.Handle = [long]$s.Handle; $w.ShowCmd = $s.ShowCmd; $w.RestoreMax = [bool]$s.RestoreMax; $w.L = $s.L; $w.T = $s.T; $w.R = $s.R; $w.B = $s.B
            if ([AutoInputPS5]::Place($w, 0, 0)) { $back++ }
        }
        Remove-Item $StateFile
    }
    if (Test-Path $MouseFile) {
        # Give the listener a moment to drop the fence, then put the mouse back where it was.
        Start-Sleep -Milliseconds 250
        $xy = (Get-Content $MouseFile).Split(',')
        [void][AutoInputPS5]::SetCursorPos([int]$xy[0], [int]$xy[1])
        Remove-Item $MouseFile
    }
    Write-Host "Switched to PC, put $back window(s) back."
}

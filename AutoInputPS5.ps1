# AutoInputPS5 - flips the shared monitor between the PC and the PS5,
# moving your windows out of the way and back again.
#
#   -To PS5     move windows to the other screen, then switch monitor to the PS5
#   -To PC      switch monitor back to the PC, then put windows back
#   -To Toggle  whichever of the two applies right now (default)
#   -To Info    list monitors only, change nothing
param(
    [ValidateSet('PS5', 'PC', 'Toggle', 'Info')] [string]$To = 'Toggle'
)

# ---- settings (override them in settings.json next to this script) ----------
$SharedMonitor = 0     # monitor index (see -To Info) that the PS5 is plugged into
$PcInput       = 15    # input code for the PC     (15 = DisplayPort 1)
$Ps5Input      = 18    # input code for the PS5    (18 = HDMI 2)
$Settings = Join-Path $PSScriptRoot 'settings.json'
if (Test-Path $Settings) {
    $cfg = Get-Content -Raw $Settings | ConvertFrom-Json
    if ($null -ne $cfg.SharedMonitor) { $SharedMonitor = [int]$cfg.SharedMonitor }
    if ($null -ne $cfg.PcInput)       { $PcInput       = [int]$cfg.PcInput }
    if ($null -ne $cfg.Ps5Input)      { $Ps5Input      = [int]$cfg.Ps5Input }
}
$StateFile = Join-Path $PSScriptRoot 'windows.json'
$FenceFile = Join-Path $PSScriptRoot 'fence.txt'   # read by HotkeyListener.ps1 to keep the mouse off the PS5 screen
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

if ($To -eq 'Info') {
    Write-Host "Settings: SharedMonitor=$SharedMonitor PcInput=$PcInput Ps5Input=$Ps5Input"
    Write-Host ""
    for ($i = 0; $i -lt $mons.Count; $i++) {
        $m = $mons[$i]; $b = $m.Bounds
        $wins = [AutoInputPS5]::WindowsOn($m)
        $code = [AutoInputPS5]::GetInput($m)
        $tag = if ($i -eq $SharedMonitor) { '  <- shared with PS5' } else { '' }
        $ddc = if ($code -lt 0) { 'DDC/CI not responding' } else { "input=$code" }
        Write-Host ("[{0}] {1}x{2} at ({3},{4}) primary={5} {6} windows={7}{8}" -f $i, ($b.Right - $b.Left), ($b.Bottom - $b.Top), $b.Left, $b.Top, $m.Primary, $ddc, $wins.Count, $tag)
        foreach ($w in $wins) { Write-Host "      - $($w.Title)" }
    }
    exit
}

if ($mons.Count -lt 2) { Write-Host "Need two monitors."; exit 1 }
if ($SharedMonitor -ge $mons.Count) { Write-Host "SharedMonitor=$SharedMonitor but only $($mons.Count) monitors found. Fix settings.json."; exit 1 }
$shared = $mons[$SharedMonitor]
$other  = $mons | Where-Object { $_.HMon -ne $shared.HMon } | Select-Object -First 1
$dx = $other.Work.Left - $shared.Work.Left
$dy = $other.Work.Top  - $shared.Work.Top

if ($To -eq 'Toggle') { $To = if ([AutoInputPS5]::GetInput($shared) -eq $Ps5Input) { 'PC' } else { 'PS5' } }

if ($To -eq 'PS5') {
    $wins = [AutoInputPS5]::WindowsOn($shared)
    New-Item -ItemType Directory -Force (Split-Path $StateFile) | Out-Null
    ConvertTo-Json -InputObject @($wins) -Depth 3 | Set-Content -Encoding UTF8 $StateFile
    foreach ($w in $wins) { [void][AutoInputPS5]::Place($w, $dx, $dy) }
    $cx = [int](($other.Work.Left + $other.Work.Right) / 2); $cy = [int](($other.Work.Top + $other.Work.Bottom) / 2)
    [void][AutoInputPS5]::SetCursorPos($cx, $cy)
    $b = $other.Bounds
    Set-Content -Encoding ASCII $FenceFile ("{0},{1},{2},{3}" -f $b.Left, $b.Top, $b.Right, $b.Bottom)
    [void][AutoInputPS5]::SetInput($shared, $Ps5Input)
    Write-Host "Moved $($wins.Count) window(s), switched to PS5."
}
else {
    Remove-Item $FenceFile -ErrorAction SilentlyContinue
    [void][AutoInputPS5]::SetInput($shared, $PcInput)
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
    Write-Host "Switched to PC, put $back window(s) back."
}

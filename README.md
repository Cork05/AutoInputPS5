# AutoInputPS5

**One hotkey. Your monitor flips to the PS5, and your PC desktop gets out of the way and comes back exactly as you left it.**

If your PS5 and your PC share a monitor, you know the drill: dig for the monitor's input button, lose your mouse on a screen you can't see, then drag every window back afterwards. AutoInputPS5 does all of that for you in about a second.

Press **`Ctrl` + `Alt` + `P`**:

| | Going to the PS5 | Coming back to the PC |
|---|---|---|
| 🖥️ **Monitor input** | Switches to the PS5's HDMI port | Switches back to the PC |
| 🪟 **Your windows** | Every window on that screen slides over to your other monitor | Every window returns to the **exact** spot and size it was in |
| 📐 **Maximized windows** | Stay maximized, now on the other screen | Re-maximize on the original screen |
| ➖ **Minimized windows** | Moved too, so they open on the screen you can see | Restored to where they used to open |
| 🖱️ **Mouse** | Jumps to the other screen and is **fenced in**, so it can't wander onto the PS5 screen | Free to roam both screens again |

No capture card, no lag, no extra hardware. The PS5 picture goes straight into the monitor as usual. AutoInputPS5 just tells the monitor which input to show, using the DDC/CI control channel built into almost every modern monitor's cable.

---

## ✨ Features

### ⌨️ Global hotkey
- **`Ctrl` + `Alt` + `P`** toggles between PC and PS5 from anywhere, even mid-game or with a fullscreen app open.
- Works while the PS5 is on screen. Your PC is still running and listening, so the same keys bring you straight back.
- Pick any hotkey you like (`Ctrl+Shift+F9`, `Win+Alt+G`, ...) in `settings.json`.
- Starts automatically when you log in and runs silently in the background. No window, no tray clutter.
- Prefer clicking? There's also an **AutoInputPS5** shortcut on your desktop.

### 🪟 Smart window moving
- Moves only real app windows, the same ones you'd see in Alt+Tab. Popups, tool windows and the taskbar are left alone.
- Keeps each window's exact position relative to the screen, so your layout looks the same on the other monitor.
- **Maximized** windows stay maximized. **Minimized** windows are moved too.
- Handles stubborn apps like Spotify, Discord and Chromium browsers. These ignore Windows' saved restore position and reopen wherever they last were, so AutoInputPS5 briefly un-minimizes them (without stealing focus), moves them for real, and minimizes them again.
- Moves windows without activating them, so nothing jumps in front of you.
- Remembers where everything was, and puts it all back when you return to the PC.

### 🖱️ Mouse fence
- In PS5 mode your cursor is confined to the screen you can actually see.
- Windows sometimes drops a mouse fence on its own (focus changes, permission prompts), so the fence is re-applied 10 times a second.

---

## 📋 Requirements

- Windows 10 or 11
- **Two monitors**: one shared with the PS5, one that's PC-only (that's where your windows go)
- **DDC/CI turned on** in the shared monitor's on-screen menu. It's on by default on most monitors.
- Nothing to install: it uses the PowerShell that comes with Windows. No admin rights needed.

---

## 📥 Download

**[⬇️ Download the latest AutoInputPS5.zip](https://github.com/Cork05/AutoInputPS5/releases/latest/download/AutoInputPS5.zip)**

Or see all versions on the [Releases page](https://github.com/Cork05/AutoInputPS5/releases), or clone it:

```bash
git clone https://github.com/Cork05/AutoInputPS5.git
```

## 🛠️ Setup

1. **Extract** the zip anywhere (Downloads is fine).
2. **Double-click `Install.bat`.**
   - If Windows SmartScreen says "Windows protected your PC", click **More info → Run anyway**. The scripts are plain text, so you can read every line first.
3. The installer:
   - copies AutoInputPS5 to `%LOCALAPPDATA%\AutoInputPS5`
   - starts the hotkey listener now, and every time you log in
   - adds an **AutoInputPS5** shortcut to your desktop
   - lists your monitors so you can check the setup
4. **Press `Ctrl` + `Alt` + `P`.** 🎮

You can delete the extracted folder afterwards. Everything runs from `%LOCALAPPDATA%\AutoInputPS5`.

### ⚙️ Configure (if needed)

The defaults are: the PS5 shares your **main** monitor, the PC uses **DisplayPort**, and the PS5 uses **HDMI 2**. If your setup is different, open `%LOCALAPPDATA%\AutoInputPS5\settings.json`:

```json
{
    "SharedMonitor": 0,
    "PcInput": 15,
    "Ps5Input": 18,
    "Hotkey": "Ctrl+Alt+P"
}
```

| Setting | What it is |
|---|---|
| `SharedMonitor` | Which monitor the PS5 is plugged into. The installer lists them and marks the current choice with `<- shared with PS5`. |
| `PcInput` | The input code the PC is on. |
| `Ps5Input` | The input code the PS5 is on. |
| `Hotkey` | Any combination of `Ctrl`, `Alt`, `Shift`, `Win` plus a letter, digit or `F1` to `F24`. |

Common input codes:

| Input | Code |
|---|---|
| DisplayPort 1 | `15` |
| DisplayPort 2 | `16` |
| HDMI 1 | `17` |
| HDMI 2 | `18` |

**Not sure of your codes?** Some monitors use their own numbers. To find them, run this in PowerShell while the monitor is showing the PC:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AutoInputPS5\AutoInputPS5.ps1" -To Info
```

That's the PC's code. Then switch the monitor to the PS5 with its own buttons and run it again to get the PS5's code.

After changing the **hotkey**, sign out and back in (or run `Install.bat` again) so the listener picks it up. Other settings take effect immediately.

---

## 🧰 Command line

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AutoInputPS5\AutoInputPS5.ps1" -To Toggle
```

| `-To` | Does |
|---|---|
| `Toggle` | Whichever applies right now (default) |
| `PS5` | Move windows away, fence the mouse, switch to the PS5 |
| `PC` | Switch to the PC, put windows back, free the mouse |
| `Info` | List monitors, their current input and their windows. Changes nothing |

Handy if you want to trigger it from a Stream Deck, a macro keyboard or a scheduled task.

---

## ❓ Troubleshooting

| Problem | Fix |
|---|---|
| Hotkey does nothing | Check `%LOCALAPPDATA%\AutoInputPS5\listener.log`. If it says the hotkey couldn't be registered, another app is using it, so pick a different `Hotkey`. |
| `-To Info` says "DDC/CI not responding" | Turn on **DDC/CI** in the monitor's on-screen menu. Some monitors only answer over DisplayPort or HDMI, not through docks or adapters. |
| Monitor switches to the wrong input | Your monitor uses different codes. See *Not sure of your codes?* above. |
| The wrong monitor switches | Change `SharedMonitor` in `settings.json`. |
| A window didn't move | Apps running **as administrator** can't be moved by a normal app. Apps hidden in the **system tray** (not the taskbar) aren't moved either. |
| Mouse feels stuck on one screen | You're in PS5 mode. Press the hotkey to come back to the PC. |

## 🗑️ Uninstall

Double-click **`Uninstall.bat`** (from the zip). It switches you back to the PC if needed, stops the listener, and removes the shortcuts and `%LOCALAPPDATA%\AutoInputPS5`.

---

## 🔍 How it works

- **Input switching** uses DDC/CI VCP code `0x60` (Input Source) through Windows' built-in `dxva2.dll` monitor-configuration API.
- **Window moving** enumerates top-level windows, saves each one's placement (`GetWindowPlacement`) to `windows.json`, shifts it onto the other monitor, and restores it from that file on the way back.
- **The hotkey** is a system-wide `RegisterHotKey` held by a small hidden PowerShell process, which also runs the **mouse fence** (`ClipCursor`) while `fence.txt` exists.

No telemetry, no network access, no admin rights. Just two PowerShell scripts you can read.

## 📄 License

[MIT](LICENSE)

# Windows Update Warrior

Prevents Windows from restarting your PC for updates by continuously pushing Active Hours to the maximum 18-hour window starting from the current time.

## What it does

1. **Sets Active Hours** to start 1 hour before now and span 18 hours forward (the Windows maximum), so Windows won't force a restart for as long as possible.
2. **Re-runs every 16 hours** via a self-scheduling task, refreshing active hours before they expire — creating a continuous protection chain.
3. **Shows a toast notification** each time it updates active hours.
4. **Sets the update policy to notify-only, no auto-restart** (`AUOptions = 2`, `NoAutoRebootWithLoggedOnUsers = 1`), so nothing installs or reboots without you.
5. **Keeps the Windows Update service (`wuauserv`) disabled.** Windows turns it back on by itself, so every run checks it and stops + disables it again if needed, and a separate hourly task (`-ServiceGuard`) repeats that check between runs. To update manually, run `Uninstall.bat` (it re-enables the service), update, then reinstall.
6. **Warns with a dialog box** if Windows has a pending forced reboot that can no longer be postponed, so you can save your work and reboot on your own terms.

## Install (recommended)

1. Download `WindowsUpdateWarriorSetup.exe` from the [`Installer/`](Installer/) folder.
2. Run it as Administrator.
3. Done — the script runs immediately and will re-run at every logon and every 16 hours.

To uninstall, use **Add or Remove Programs** in Windows Settings.

## Manual install

If you prefer not to use the installer:

1. Copy `WindowsUpdateWarrior.ps1` somewhere permanent (e.g. `C:\Tools\`).
2. Run `Install.bat` as Administrator — this creates a scheduled task that runs the script at every logon.
3. Alternatively, create the task yourself:
   ```
   schtasks /Create /TN "WindowsUpdateWarrior" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File 'C:\Tools\WindowsUpdateWarrior.ps1'" /SC ONLOGON /RL HIGHEST /F
   ```

### Manual run

Run the script directly in an elevated PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WindowsUpdateWarrior.ps1
```

Or use the batch launcher:

```
WindowsUpdateWarrior.bat
```

### Manual uninstall

Run `Uninstall.bat` as Administrator, or:

```
schtasks /Delete /TN "WindowsUpdateWarrior" /F
schtasks /Delete /TN "WindowsUpdateWarriorRenewal" /F
schtasks /Delete /TN "WindowsUpdateWarriorServiceGuard" /F
sc config wuauserv start= demand
```

Then delete the script files.

## Development

### Prerequisites

- Windows 10/11
- PowerShell 5.1+ (included with Windows)
- [Inno Setup 6](https://jrsoftware.org/isdownload.php) (to build the installer)

### Building the installer

```
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" WindowsUpdateWarrior.iss
```

The compiled installer is output to `Installer/WindowsUpdateWarriorSetup.exe`.

### Project structure

```
WindowsUpdateWarrior.ps1   # Main script — active hours, update policy, wuauserv, reboot detection
WindowsUpdateWarrior.iss   # Inno Setup installer script
WindowsUpdateWarrior.bat   # Batch launcher for the PS1 script
Install.bat                # Creates the scheduled task manually
Uninstall.bat              # Removes the scheduled tasks
Installer/                 # Compiled installer output
```

### How active hours are calculated

```
Start = (current hour - 1) mod 24
End   = (current hour + 17) mod 24
```

Example: if you boot at 22:00 (10 PM), active hours are set to 21:00–15:00 — Windows cannot restart until 3 PM the next day. The script then re-runs at 14:00 (16 hours later) and pushes the window forward again.

### Registry keys modified

All under `HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings`:

| Key | Value | Purpose |
|-----|-------|---------|
| `ActiveHoursStart` | 0–23 | Start of active hours |
| `ActiveHoursEnd` | 0–23 | End of active hours |
| `IsActiveHoursEnabled` | 1 | Enable manual active hours |
| `SmartActiveHoursState` | 0 | Disable automatic active hours |

Under `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU` (same as Group Policy *Configure Automatic Updates*):

| Key | Value | Purpose |
|-----|-------|---------|
| `NoAutoUpdate` | 0 | Keep the update policy active |
| `AUOptions` | 2 | Notify before download; never install on its own |
| `NoAutoRebootWithLoggedOnUsers` | 1 | No auto-restart while someone is logged on |

The `wuauserv` service is set to **Disabled** and stopped. Uninstalling sets it back to **Manual** (the Windows default) and removes the three policy values above.

### Scheduled tasks created

| Task name | Trigger | Purpose |
|-----------|---------|---------|
| `WindowsUpdateWarrior` | At logon | Main trigger — runs script on every login |
| `WindowsUpdateWarriorRenewal` | Once (16h from last run) | Refreshes active hours before they expire |
| `WindowsUpdateWarriorServiceGuard` | Hourly (as SYSTEM) | Runs the script with `-ServiceGuard`: only re-disables `wuauserv`, no toast or dialog |

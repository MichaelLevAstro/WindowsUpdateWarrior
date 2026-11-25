#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Update Warrior - Maximizes Active Hours starting from now.
.DESCRIPTION
    1. Sets Active Hours to start 1 hour before now and span the full 18 hours,
       so Windows won't restart for as long as possible from this point.
    2. Sets the Windows Update policy to notify-only with no auto-restart, and
       stops + disables the wuauserv service if Windows has turned it back on.
    3. Checks if Windows has a pending forced reboot (update postponed too long)
       and shows a warning dialog if so.
    Designed to run at startup via Task Scheduler (as SYSTEM / elevated).
.PARAMETER ServiceGuard
    Only re-disable wuauserv, then exit. Used by the hourly guard task.
#>
param([switch]$ServiceGuard)

# Stops + disables the Windows Update service (wuauserv) if it is running or
# enabled. Windows (WaaSMedicSvc) re-enables it on its own, so this runs on
# every full run and hourly via the guard task.
function Disable-WindowsUpdateService {
    try {
        $wu = Get-Service -Name "wuauserv" -ErrorAction Stop
        if ($wu.StartType -ne 'Disabled' -or $wu.Status -ne 'Stopped') {
            # Disable first so nothing can restart it between stop and disable.
            Set-Service  -Name "wuauserv" -StartupType Disabled -ErrorAction Stop
            Stop-Service -Name "wuauserv" -Force -ErrorAction Stop
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] wuauserv was $($wu.Status)/$($wu.StartType) - stopped and disabled."
        } else {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] wuauserv already stopped and disabled."
        }
    } catch {
        Write-Warning "Failed to disable wuauserv: $_"
    }
}

if ($ServiceGuard) {
    Disable-WindowsUpdateService
    exit
}

# ── 1. Calculate and set optimal Active Hours ────────────────────────────

$now         = Get-Date
$currentHour = $now.Hour
$maxSpan     = 18  # Windows maximum active-hours range

# Start 1 hour before now, end 17 hours after now (full 18 h span).
$start = ($currentHour - 1 + 24) % 24
$end   = ($currentHour + 17) % 24

# Write to registry
$regPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

try {
    Set-ItemProperty -Path $regPath -Name "ActiveHoursStart"          -Value $start -Type DWord -Force
    Set-ItemProperty -Path $regPath -Name "ActiveHoursEnd"            -Value $end   -Type DWord -Force
    # Tell Windows we're manually managing active hours (disable smart/automatic)
    Set-ItemProperty -Path $regPath -Name "IsActiveHoursEnabled"      -Value 1      -Type DWord -Force
    Set-ItemProperty -Path $regPath -Name "SmartActiveHoursState"     -Value 0      -Type DWord -Force

    $startFmt = "{0}:00" -f $start
    $endFmt   = "{0}:00" -f $end
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] Active Hours set to $startFmt - $endFmt (current hour: $currentHour`:00)"

    # Show a Windows toast notification
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null

    $toastXml = [Windows.Data.Xml.Dom.XmlDocument]::new()
    $toastXml.LoadXml(@"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>Windows Update Warrior</text>
      <text>Active Hours updated: $startFmt - $endFmt</text>
    </binding>
  </visual>
</toast>
"@)

    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    $toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
} catch {
    Write-Warning "Failed to set Active Hours: $_"
}

# ── 1b. Schedule a re-run in 16 hours to refresh before active hours expire ──

$renewalTaskName = "WindowsUpdateWarriorRenewal"
$scriptPath      = $MyInvocation.MyCommand.Path
$renewalAt       = $now.AddHours(16)

try {
    # Register-ScheduledTask takes a real DateTime, so no locale-dependent
    # date string (schtasks /SD rejected ToShortDateString on some systems).
    # SYSTEM so task fires even when no user is logged on;
    # otherwise a missed one-time trigger breaks the renewal chain.
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At $renewalAt
    Register-ScheduledTask -TaskName $renewalTaskName -Action $action -Trigger $trigger `
        -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -Force -ErrorAction Stop | Out-Null

    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] Renewal scheduled for $($renewalAt.ToString('yyyy-MM-dd HH:mm')) (in 16 hours)."
} catch {
    Write-Warning "Failed to schedule renewal task: $_"
}

# ── 1c. Update policy: notify only, never auto-restart ───────────────────

$auPolicyKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

try {
    if (-not (Test-Path $auPolicyKey)) { New-Item -Path $auPolicyKey -Force | Out-Null }
    # AUOptions 2 = notify before download; nothing installs or reboots on its own.
    Set-ItemProperty -Path $auPolicyKey -Name "NoAutoUpdate"                  -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $auPolicyKey -Name "AUOptions"                     -Value 2 -Type DWord -Force
    Set-ItemProperty -Path $auPolicyKey -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] Update policy set: notify only, no auto-restart."
} catch {
    Write-Warning "Failed to set Windows Update policy: $_"
}

# ── 1d. Keep the Windows Update service (wuauserv) disabled ──────────────

Disable-WindowsUpdateService

# ── 1e. Hourly guard task: re-disable wuauserv between full runs ─────────

$guardTaskName = "WindowsUpdateWarriorServiceGuard"

try {
    # /F overwrites, so re-running keeps the task pointing at this script.
    schtasks /Create `
        /TN $guardTaskName `
        /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \`"$scriptPath\`" -ServiceGuard" `
        /SC HOURLY `
        /MO 1 `
        /RU "SYSTEM" `
        /RL HIGHEST `
        /F | Out-Null

    if ($LASTEXITCODE -ne 0) { throw "schtasks exit code $LASTEXITCODE" }
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] Hourly wuauserv guard task registered."
} catch {
    Write-Warning "Failed to register guard task: $_"
}

# ── 2. Check for pending forced-reboot and warn the user ─────────────────

$forceReboot = $false
$reasons     = @()

# Check RebootRequired flag
$rebootKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Auto Update\RebootRequired"
if (Test-Path $rebootKey) {
    $forceReboot = $true
    $reasons += "Windows Update has flagged a required reboot."
}

# Check for pending reboot timestamps in UX settings
try {
    $pendingTime = Get-ItemProperty -Path $regPath -Name "PendingRebootStartTime" -ErrorAction Stop
    $forceReboot = $true
    $reasons += "A reboot deadline has been scheduled (PendingRebootStartTime present)."
} catch { }

# Check USOShared reboot-pending state
$usoKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\StateVariables"
try {
    $usoState = Get-ItemProperty -Path $usoKey -Name "RebootRequired" -ErrorAction SilentlyContinue
    if ($usoState -and $usoState.RebootRequired -eq 1) {
        $forceReboot = $true
        $reasons += "UX StateVariables indicates a reboot is required."
    }
} catch { }

# Check engaged restart deadline (the "we'll restart by..." date)
try {
    $engagedKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    $deadline   = Get-ItemProperty -Path $engagedKey -Name "EngagedRestartDeadline" -ErrorAction Stop
    $forceReboot = $true
    $reasons += "An engaged restart deadline is set: $($deadline.EngagedRestartDeadline)"
} catch { }

# Also check the orchestrator
$orchestratorKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\RebootRequired"
if (Test-Path $orchestratorKey) {
    $forceReboot = $true
    $reasons += "Update Orchestrator has queued a mandatory reboot."
}

if ($forceReboot) {
    $detailText = ($reasons | ForEach-Object { "  - $_" }) -join "`n"
    $message = @"
WARNING: Windows is about to force a restart for updates!

Your updates have been postponed for too long and Windows will
forcibly reboot your machine soon.

Detected signals:
$detailText

Save all your work NOW and reboot at your convenience
to avoid an unexpected forced restart.
"@

    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] FORCED UPDATE REBOOT PENDING - showing warning dialog."

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "Windows Update Warrior - Reboot Warning",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
} else {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] No pending forced reboot detected."
}

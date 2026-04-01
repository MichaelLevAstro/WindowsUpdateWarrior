#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Update Warrior - Maximizes Active Hours starting from now.
.DESCRIPTION
    1. Sets Active Hours to start 1 hour before now and span the full 18 hours,
       so Windows won't restart for as long as possible from this point.
    2. Checks if Windows has a pending forced reboot (update postponed too long)
       and shows a warning dialog if so.
    Designed to run at startup via Task Scheduler (as SYSTEM / elevated).
#>

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
$renewalTime     = $now.AddHours(16).ToString("HH:mm")
$renewalDate     = $now.AddHours(16).ToString("MM/dd/yyyy")

try {
    # Remove previous renewal task if it exists
    schtasks /Delete /TN $renewalTaskName /F 2>$null

    schtasks /Create `
        /TN $renewalTaskName `
        /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" `
        /SC ONCE `
        /ST $renewalTime `
        /SD $renewalDate `
        /RL HIGHEST `
        /F | Out-Null

    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] Renewal scheduled for $renewalDate $renewalTime (in 16 hours)."
} catch {
    Write-Warning "Failed to schedule renewal task: $_"
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

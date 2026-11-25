@echo off
setlocal
:: Removes all WindowsUpdateWarrior scheduled tasks. Run as Administrator.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Must be run as Administrator.
    pause
    exit /b 1
)

set "TASK_NAME=WindowsUpdateWarrior"
set "RENEWAL_TASK=WindowsUpdateWarriorRenewal"
set "GUARD_TASK=WindowsUpdateWarriorServiceGuard"
set "ANY_REMOVED=0"

call :RemoveTask "%TASK_NAME%"
call :RemoveTask "%RENEWAL_TASK%"
call :RemoveTask "%GUARD_TASK%"

:: Undo what the script changed: re-enable Windows Update (default: Manual) and
:: remove the policy values it wrote.
set "AU_KEY=HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
sc config wuauserv start= demand >nul 2>&1 && echo [ok]   Windows Update service re-enabled.
reg delete "%AU_KEY%" /v NoAutoUpdate /f >nul 2>&1
reg delete "%AU_KEY%" /v AUOptions /f >nul 2>&1
reg delete "%AU_KEY%" /v NoAutoRebootWithLoggedOnUsers /f >nul 2>&1
echo [ok]   Windows Update policy values removed.

echo.
if "%ANY_REMOVED%"=="1" (
    echo All WindowsUpdateWarrior tasks removed.
) else (
    echo No WindowsUpdateWarrior tasks were found.
)

pause
endlocal
exit /b 0

:RemoveTask
schtasks /Query /TN %~1 >nul 2>&1
if %errorlevel% neq 0 (
    echo [skip] Task %~1 not found.
    exit /b 0
)
schtasks /End    /TN %~1 >nul 2>&1
schtasks /Delete /TN %~1 /F >nul 2>&1
if %errorlevel% equ 0 (
    echo [ok]   Task %~1 removed.
    set "ANY_REMOVED=1"
) else (
    echo [fail] Could not remove task %~1.
)
exit /b 0

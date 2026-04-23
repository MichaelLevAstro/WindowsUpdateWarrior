@echo off
setlocal
:: Registers WindowsUpdateWarrior as a scheduled task that runs at every logon (elevated).
:: Run this script once as Administrator.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: This installer must be run as Administrator.
    echo Right-click and select "Run as administrator".
    pause
    exit /b 1
)

set "SCRIPT_DIR=%~dp0"
set "TASK_NAME=WindowsUpdateWarrior"
set "RENEWAL_TASK=WindowsUpdateWarriorRenewal"
set "PS_PATH=%SCRIPT_DIR%WindowsUpdateWarrior.ps1"

if not exist "%PS_PATH%" (
    echo ERROR: Cannot find "%PS_PATH%".
    pause
    exit /b 1
)

:: Stop and remove any existing tasks (main + renewal) so we can recreate cleanly.
echo Cleaning up any existing tasks...
schtasks /End    /TN "%TASK_NAME%"    >nul 2>&1
schtasks /Delete /TN "%TASK_NAME%"    /F >nul 2>&1
schtasks /End    /TN "%RENEWAL_TASK%" >nul 2>&1
schtasks /Delete /TN "%RENEWAL_TASK%" /F >nul 2>&1

:: Create task: runs at logon of any user, with highest privileges
schtasks /Create ^
    /TN "%TASK_NAME%" ^
    /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_PATH%\"" ^
    /SC ONLOGON ^
    /RL HIGHEST ^
    /F
set "RC=%errorlevel%"

echo.
if "%RC%"=="0" (
    echo Success! "%TASK_NAME%" will run at every logon.
    echo It will set optimal Active Hours and warn you about forced reboots.
) else (
    echo Failed to create the scheduled task (exit code %RC%). Check the error above.
)

pause
endlocal
exit /b %RC%

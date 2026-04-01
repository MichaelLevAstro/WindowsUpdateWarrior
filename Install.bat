@echo off
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
set "PS_PATH=%SCRIPT_DIR%WindowsUpdateWarrior.ps1"

:: Remove existing task if present
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1

:: Create task: runs at logon of any user, with highest privileges
schtasks /Create ^
    /TN "%TASK_NAME%" ^
    /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_PATH%\"" ^
    /SC ONLOGON ^
    /RL HIGHEST ^
    /F

if %errorlevel% equ 0 (
    echo.
    echo Success! "%TASK_NAME%" will run at every logon.
    echo It will set optimal Active Hours and warn you about forced reboots.
) else (
    echo.
    echo Failed to create the scheduled task. Check the error above.
)

pause

@echo off
:: Removes the WindowsUpdateWarrior scheduled task. Run as Administrator.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Must be run as Administrator.
    pause
    exit /b 1
)

schtasks /Delete /TN "WindowsUpdateWarrior" /F

if %errorlevel% equ 0 (
    echo Task removed successfully.
) else (
    echo Task not found or could not be removed.
)

pause

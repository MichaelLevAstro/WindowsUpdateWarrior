@echo off
:: Launcher for WindowsUpdateWarrior.ps1 — runs elevated via PowerShell.
:: Place this alongside the .ps1 file or adjust the path below.

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%WindowsUpdateWarrior.ps1"

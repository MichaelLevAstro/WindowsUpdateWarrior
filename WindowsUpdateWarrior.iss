[Setup]
AppName=Windows Update Warrior
AppVersion=1.0
AppPublisher=WindowsUpdateWarrior
DefaultDirName={autopf}\WindowsUpdateWarrior
DefaultGroupName=Windows Update Warrior
OutputDir=Installer
OutputBaseFilename=WindowsUpdateWarriorSetup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
DisableProgramGroupPage=yes
DisableDirPage=yes
UninstallDisplayName=Windows Update Warrior
SetupIconFile=compiler:SetupClassicIcon.ico

[Files]
Source: "WindowsUpdateWarrior.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Run]
; Create the scheduled task on install
Filename: "schtasks.exe"; Parameters: "/Create /TN ""WindowsUpdateWarrior"" /TR ""powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File '{app}\WindowsUpdateWarrior.ps1'"" /SC ONLOGON /RL HIGHEST /F"; Flags: runhidden waituntilterminated; StatusMsg: "Creating startup scheduled task..."
; Run it immediately so active hours are set right now
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\WindowsUpdateWarrior.ps1"""; Flags: runhidden waituntilterminated; StatusMsg: "Setting active hours..."

[UninstallRun]
; Remove the scheduled tasks on uninstall
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""WindowsUpdateWarrior"" /F"; Flags: runhidden waituntilterminated
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""WindowsUpdateWarriorRenewal"" /F"; Flags: runhidden waituntilterminated

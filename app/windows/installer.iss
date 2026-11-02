; Koyun Windows 安装包（Inno Setup 6）
; CI 中执行：iscc /DAppVersion=1.0.0 /DSrcDir=<Release目录> windows\installer.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6E0C3D52-7A1B-4E2B-9C4B-6B1F2A9E7C01}
AppName=Koyun
AppVersion={#AppVersion}
AppPublisher=Koyun
AppPublisherURL=https://ss.koyun520.com
DefaultDirName={autopf}\Koyun
DefaultGroupName=Koyun
DisableProgramGroupPage=yes
OutputBaseFilename=Koyun-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Koyun.exe
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern
CloseApplications=force

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "开机自动启动 / Start with Windows"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Koyun"; Filename: "{app}\Koyun.exe"
Name: "{autodesktop}\Koyun"; Filename: "{app}\Koyun.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Koyun"; ValueData: """{app}\Koyun.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\Koyun.exe"; Description: "{cm:LaunchProgram,Koyun}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 卸载前结束内核并关闭系统代理，防止卸载后上不了网
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM sing-box.exe"; Flags: runhidden; RunOnceId: "KillCore"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM Koyun.exe"; Flags: runhidden; RunOnceId: "KillApp"
Filename: "{sys}\reg.exe"; Parameters: "add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"" /v ProxyEnable /t REG_DWORD /d 0 /f"; Flags: runhidden; RunOnceId: "ResetProxy"

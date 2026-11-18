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
; 官网地址不写入公开仓库
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
; 1.1.7 起以管理员身份安装到 Program Files，并注册 Koyun 后台服务（TUN 模式不再每次弹管理员确认）。
; 1.1.6 及以前装在用户目录，升级时会先静默卸载旧位置（见 [Code]）
PrivilegesRequired=admin
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
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Koyun"; ValueData: """{app}\Koyun.exe"" --autostart"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
; 以安装前的普通用户身份打开 App（安装程序本身是管理员身份，App 不能跟着以管理员运行）
Filename: "{app}\Koyun.exe"; Description: "{cm:LaunchProgram,Koyun}"; Flags: nowait postinstall skipifsilent runasoriginaluser
; App 内自动更新（静默安装）完成后自动重新打开
Filename: "{app}\Koyun.exe"; Flags: nowait runasoriginaluser; Check: WizardSilent

[UninstallRun]
; 先停止并删除后台服务（它会顺带结束由它启动的内核）
Filename: "{app}\koyun-service.exe"; Parameters: "uninstall"; Flags: runhidden; RunOnceId: "RemoveService"
; 卸载前结束内核并关闭系统代理，防止卸载后上不了网
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM sing-box.exe"; Flags: runhidden; RunOnceId: "KillCore"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM Koyun.exe"; Flags: runhidden; RunOnceId: "KillApp"
Filename: "{sys}\reg.exe"; Parameters: "add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"" /v ProxyEnable /t REG_DWORD /d 0 /f"; Flags: runhidden; RunOnceId: "ResetProxy"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\service-data"

[Code]
const
  UninstKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{6E0C3D52-7A1B-4E2B-9C4B-6B1F2A9E7C01}_is1';
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';

var
  HadAutostart: Boolean;

function RunHidden(const FileName, Params: String): Integer;
var
  Code: Integer;
begin
  if not Exec(FileName, Params, '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;
  Result := Code;
end;

{ 1.1.6 及以前是“仅当前用户”安装（用户目录 + HKCU）。先静默卸载，避免电脑上出现两个 Koyun。
  卸载会删掉开机自启动项，所以先记下来，装完再按新路径加回去 }
procedure RemovePerUserInstall();
var
  Uninst, Dummy: String;
begin
  HadAutostart := RegQueryStringValue(HKCU, RunKey, 'Koyun', Dummy);
  if RegQueryStringValue(HKCU, UninstKey, 'UninstallString', Uninst) then
  begin
    Uninst := RemoveQuotes(Uninst);
    if FileExists(Uninst) then
    begin
      Log('Removing per-user install: ' + Uninst);
      RunHidden(Uninst, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART');
    end;
  end;
end;

{ 后台服务只接受“安装 Koyun 的那个用户”的指令。管理员确认时可能换成了别的账号，
  所以用 ExecAsOriginalUser 以安装前的用户身份取 SID }
function OwnerSid(const Svc: String): String;
var
  SidFile: String;
  Sid: AnsiString;
  Code: Integer;
begin
  Result := '';
  SidFile := ExpandConstant('{commonappdata}\koyun-owner-') + GetDateTimeString('yyyymmddhhnnsszzz', #0, #0) + '.sid';
  if ExecAsOriginalUser(ExpandConstant('{cmd}'), '/C ""' + Svc + '" sid > "' + SidFile + '""', '', SW_HIDE, ewWaitUntilTerminated, Code)
     and (Code = 0) and LoadStringFromFile(SidFile, Sid) then
    Result := Trim(String(Sid));
  DeleteFile(SidFile);
end;

procedure InstallService();
var
  Svc, Sid: String;
begin
  Svc := ExpandConstant('{app}\koyun-service.exe');
  if not FileExists(Svc) then exit;
  Sid := OwnerSid(Svc);
  if (Sid = '') or (RunHidden(Svc, 'install --owner ' + Sid) <> 0) then
  begin
    Log('Koyun service install failed, TUN will fall back to "run as administrator"');
    SuppressibleMsgBox('Koyun 后台服务安装失败，TUN 模式将改为“以管理员身份运行”。' + #13#10 +
      'Koyun service could not be installed; TUN mode will ask for administrator rights instead.',
      mbInformation, MB_OK, IDOK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    RemovePerUserInstall();
    { 升级：先停掉旧服务，否则 koyun-service.exe / sing-box.exe 被占用无法覆盖 }
    if FileExists(ExpandConstant('{app}\koyun-service.exe')) then
      RunHidden(ExpandConstant('{app}\koyun-service.exe'), 'uninstall');
    RunHidden(ExpandConstant('{sys}\taskkill.exe'), '/F /IM sing-box.exe');
  end
  else if CurStep = ssPostInstall then
  begin
    InstallService();
    if HadAutostart and not WizardIsTaskSelected('autostart') then
      RegWriteStringValue(HKCU, RunKey, 'Koyun', '"' + ExpandConstant('{app}\Koyun.exe') + '" --autostart');
  end;
end;

; ──────────────────────────────────────────────────────────────────────────────
;  ZPlay — Windows Installer (Inno Setup 6)
;  Built by CI from: build\windows\x64\runner\Release\
; ──────────────────────────────────────────────────────────────────────────────

#define MyAppName      "ZPlay"
#ifndef MyAppVersion
#define MyAppVersion   "1.1.6"
#endif
#define MyAppPublisher "tzero86"
#define MyAppExeName   "zplay.exe"
#define MyAppURL       "https://github.com/tzero86/ZPlay"

[Setup]
; ZPlay's own identity. Until 1.6.24 this was PlayTorrio's AppId, inherited
; with the upstream script, so Windows treated every ZPlay install as an update
; of PlayTorrio: it reused PlayTorrio's install folder and took over its entry
; in Apps & features. See [Code] for the one-time move off the old identity.
AppId={{E34FEE6A-97CF-45A7-B061-20FB0695943B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
OutputDir=Output
OutputBaseFilename=ZPlay-Windows-Setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequired=lowest
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Clean up old files that might conflict with new version
Type: filesandordirs; Name: "{app}\data\flutter_assets\*"
Type: files; Name: "{app}\*.dll.old"

[Icons]
Name: "{group}\{#MyAppName}";    Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  LegacyUninstallKey =
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{9B8C7D6E-5F4E-3D2C-1B0A-9F8E7D6C5B4A}_is1';

{ Finds the uninstall entry registered under the AppId ZPlay used to share
  with PlayTorrio. True only when that entry belongs to ZPlay. }
function FindLegacyZPlay(var Uninstaller, Location: String): Boolean;
var
  Name: String;
  Root: Integer;
begin
  Result := False;
  Root := HKCU;
  if not RegQueryStringValue(Root, LegacyUninstallKey, 'DisplayName', Name) then
  begin
    Root := HKLM;
    if not RegQueryStringValue(Root, LegacyUninstallKey, 'DisplayName', Name) then
      Exit;
  end;
  if Pos('zplay', Lowercase(Name)) <> 1 then
    Exit; { A genuine PlayTorrio install: not ours to touch. }
  if not RegQueryStringValue(Root, LegacyUninstallKey, 'UninstallString', Uninstaller) then
    Exit;
  RegQueryStringValue(Root, LegacyUninstallKey, 'InstallLocation', Location);
  Result := True;
end;

{ Before installing, retire a ZPlay that was installed under the old shared
  AppId - usually into a PlayTorrio folder - so the user is left with one ZPlay,
  in the ZPlay folder. Skipped when that folder also holds PlayTorrio itself:
  the old entry's uninstall log covers PlayTorrio's files too, and removing the
  user's PlayTorrio is not this installer's call. Settings live in AppData and
  are untouched either way. }
procedure CurStepChanged(CurStep: TSetupStep);
var
  Uninstaller, Location: String;
  Code: Integer;
begin
  if CurStep <> ssInstall then
    Exit;
  if not FindLegacyZPlay(Uninstaller, Location) then
    Exit;
  if (Location <> '') and FileExists(AddBackslash(Location) + 'playtorrio.exe') then
  begin
    Log('Legacy ZPlay entry shares a folder with PlayTorrio; leaving it in place.');
    Exit;
  end;
  Log('Removing legacy ZPlay install: ' + Uninstaller);
  Exec(RemoveQuotes(Uninstaller), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

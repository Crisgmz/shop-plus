; ============================================================================
;  Shop+ — Inno Setup script (Windows installer)
;
;  Build the Flutter release first, then compile this script:
;     flutter build windows --release
;     ISCC.exe installer\shop_plus.iss
;
;  Or just run installer\build.ps1 which does both end-to-end.
;
;  The app version is injected by build.ps1 via /DMyAppVersion=... ; if you
;  compile by hand it falls back to the default below.
; ============================================================================

#ifndef MyAppVersion
  #define MyAppVersion "1.0.5"
#endif

#define MyAppName "Shop+"
#define MyAppPublisher "Shop+"
#define MyAppExeName "flutter_app.exe"
#define MyAppId "{{8F3A1C2E-5B7D-4E9A-9C1F-2A6B4D8E0F31}"

; Carpeta con el build de Flutter (relativa a este .iss).
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir=Output
OutputBaseFilename=ShopPlus-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
PrivilegesRequired=admin

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
; Empaqueta todo el contenido del build de Flutter (exe, DLLs, data\).
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

; Installateur Windows de C411 Remote (Inno Setup 6), à partir de la version
; compilée par `flutter build windows --release`.
;
;   iscc /DAppVersion=1.0.0 windows\packaging\c411_remote.iss
;   → build\installer\C411_Remote-Setup-x64.exe
;
; Installation pour l'utilisateur seul, sans droits d'administrateur (on peut
; choisir « pour tous » au lancement) ; raccourci dans le menu Démarrer,
; désinstallation depuis les Paramètres de Windows.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "C411 Remote"
#define AppExe "c411_remote.exe"
#define Release "..\..\build\windows\x64\runner\Release"

[Setup]
; Identifiant fixe : les mises à jour remplacent l'installation existante.
AppId={{477B7B30-782D-4FA6-8346-383D27B74BF4}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=C411_Remote-Setup-x64
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; L'application doit être fermée pour être mise à jour.
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

#ifndef SourceExecutable
  #error SourceExecutable must identify the published application.
#endif

#ifndef OutputDirectory
  #error OutputDirectory must identify the artifact directory.
#endif

#ifndef ArtifactBaseName
  #define ArtifactBaseName "Cytisus-Trading-1.1.1-win11-x64"
#endif

[Setup]
AppId={{A69B1E9B-BD48-4E79-830B-12B60EB45104}
AppName=Cytisus-Trading
AppVersion=1.1.1
AppPublisher=Cytisus-Trading contributors
AppPublisherURL=https://github.com/KDTikkly/Cytisus-Trading
DefaultDirName={autopf}\Cytisus-Trading
DefaultGroupName=Cytisus-Trading
DisableProgramGroupPage=yes
OutputDir={#OutputDirectory}
OutputBaseFilename={#ArtifactBaseName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\CytisusTrading.exe
SetupIconFile=..\..\Resources\ProductIcon.ico
VersionInfoVersion=1.1.1.0
VersionInfoProductName=Cytisus-Trading
VersionInfoDescription=Cytisus-Trading Windows 11 installer
VersionInfoCompany=Cytisus-Trading contributors

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceExecutable}"; DestDir: "{app}"; DestName: "CytisusTrading.exe"; Flags: "ignoreversion"
Source: "..\..\PRIVACY.md"; DestDir: "{app}"; Flags: "ignoreversion"
Source: "..\..\SANITIZATION.json"; DestDir: "{app}"; Flags: "ignoreversion"

[Icons]
Name: "{autoprograms}\Cytisus-Trading"; Filename: "{app}\CytisusTrading.exe"
Name: "{autodesktop}\Cytisus-Trading"; Filename: "{app}\CytisusTrading.exe"; Tasks: "desktopicon"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: "unchecked"

[Run]
Filename: "{app}\CytisusTrading.exe"; Description: "Launch Cytisus-Trading"; Flags: "nowait postinstall skipifsilent"

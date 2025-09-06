[Setup]
AppName=TPhotos
AppVersion={#AppVersion}
DefaultDirName={pf}\TPhotos
DefaultGroupName=TPhotos
OutputDir=Output
OutputBaseFilename=TPhotos-{#AppVersion}-setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\TPhotos"; Filename: "{app}\tphotos.exe"
Name: "{commondesktop}\TPhotos"; Filename: "{app}\tphotos.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\tphotos.exe"; Description: "{cm:LaunchProgram,TPhotos}"; Flags: nowait postinstall skipifsilent

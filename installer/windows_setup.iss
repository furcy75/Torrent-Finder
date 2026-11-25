; Inno Setup script to package SafeTorrent Windows into a single `.exe` installer
[Setup]
AppId={{8D6B4A7E-9A51-4D8C-B9B5-4C7D29D7A101}
AppName=SafeTorrent
AppVersion=1.3.0
AppPublisher=SafeTorrent
DefaultDirName={autopf}\SafeTorrent
DefaultGroupName=SafeTorrent
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..
OutputBaseFilename=SafeTorrent-Windows-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\SafeTorrent"; Filename: "{app}\safetorrent.exe"
Name: "{autodesktop}\SafeTorrent"; Filename: "{app}\safetorrent.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\safetorrent.exe"; Description: "{cm:LaunchProgram,SafeTorrent}"; Flags: nowait postinstall skipifsilent

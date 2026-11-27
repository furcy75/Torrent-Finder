; Inno Setup script to package Torrent Seeder Windows into a single `.exe` installer
[Setup]
AppId={{8D6B4A7E-9A51-4D8C-B9B5-4C7D29D7A101}
AppName=Torrent Seeder
AppVersion=2.1.0
AppPublisher=Torrent Seeder
DefaultDirName={autopf}\Torrent Seeder
DefaultGroupName=Torrent Seeder
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..
OutputBaseFilename=TorrentSeeder-Windows-Setup
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\safetorrent.exe
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
Name: "{autoprograms}\Torrent Seeder"; Filename: "{app}\safetorrent.exe"
Name: "{autodesktop}\Torrent Seeder"; Filename: "{app}\safetorrent.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\safetorrent.exe"; Description: "{cm:LaunchProgram,Torrent Seeder}"; Flags: nowait postinstall skipifsilent

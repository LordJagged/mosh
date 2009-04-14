; Script generated by the Inno Setup Script Wizard.
; SEE THE DOCUMENTATION FOR DETAILS ON CREATING INNO SETUP SCRIPT FILES!

[Setup]
AppName=mosh-scheme
AppVerName=mosh 0.8.0
AppPublisher=higepon
AppPublisherURL=http://code.google.com/p/mosh-scheme/
AppSupportURL=http://code.google.com/p/mosh-scheme/
AppUpdatesURL=http://code.google.com/p/mosh-scheme/
DefaultDirName={pf}\mosh
DefaultGroupName=mosh-scheme
AllowNoIcons=yes
LicenseFile=..\..\COPYING
OutputBaseFilename=setup_mosh
Compression=lzma
SolidCompression=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\mosh.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\lib\*"; DestDir: "{app}\lib"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{group}\mosh-scheme"; Filename: "{app}\mosh.exe"
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\mosh-scheme"; Filename: "{app}\mosh.exe"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\mosh.exe"; Description: "{cm:LaunchProgram,mosh-scheme}"; Flags: nowait postinstall skipifsilent

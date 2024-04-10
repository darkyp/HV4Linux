program HV4L;

{$mode DELPHI}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Windows,
  Dialogs,
  SysUtils,
  Forms, Main, JSON, Common, HCS, VMFrame, ConsoleFrame, pcap, CircularList,
  Streams, ttyframe, commoncontrols, EditDiskForm, NewVHDForm, ProgressForm,
  VHD
  { you can add units after this };

{$R *.res}

var
  i: Integer;


begin
  IsMultiThread := True;
  RequireDerivedFormResource := True;
  for i := 1 to ParamCount do
  begin
    if ParamStr(i) = 'debug' then
    begin
      AllocConsole;
      IsConsole := True;
      SysInitStdIO;
    end;
  end;
  checkConsole();

  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.CreateForm(TfrmCommon, frmCommon);
  Application.CreateForm(TfrmEditDisk, frmEditDisk);
  Application.Run;
end.


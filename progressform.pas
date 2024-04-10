unit ProgressForm;

{$mode Delphi}

interface

uses
  Windows, Messages, Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, StdCtrls,
  Common;

const
  WM_DONE = WM_USER + 1;

type

  { TfrmProgress }

  TfrmProgress = class;
  TProgressProc = function(frm: TfrmProgress): Boolean of object;
  TfrmProgress = class(TForm)
    btnCancel: TButton;
    lblWorking: TLabel;
    ProgressBar1: TProgressBar;
    procedure btnCancelClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    bResult: Boolean;
    szError: string;
    tp: TProgressProc;
    function run(): Integer; stdcall;
    procedure doneMessage(var msg: TMessage); message WM_DONE;
  public
    bCancel: Boolean;
    class function Execute(AOwner: TComponent; tp: TProgressProc): Boolean;
  end;

implementation

{$R *.lfm}

{ TfrmProgress }

procedure TfrmProgress.btnCancelClick(Sender: TObject);
begin
  if not Confirm(Self, 'Stop the operation?') then Exit;
  bCancel := True;
end;

procedure TfrmProgress.doneMessage(var msg: TMessage);
begin
  if not bResult then
  begin
    MessageDlg('Error', 'An error occurred: ' + szError, mtError, [mbOK], 0);
    ModalResult := mrCancel;
    Exit;
  end;
  ModalResult := mrOK;
end;

function TfrmProgress.run(): Integer;
begin
  Result := 0;
  try
    bResult := tp(Self);
  except
    on E: Exception do
    begin
      szError := E.Message;
    end;
  end;
  PostMessage(Handle, WM_DONE, 0, 0);
end;

procedure TfrmProgress.FormShow(Sender: TObject);
begin
  szError := '(unknown)';
  CloseHandle(CreateThread(run));
end;

class function TfrmProgress.Execute(AOwner: TComponent; tp: TProgressProc): Boolean;
var
  frm: TfrmProgress;
begin
  frm := TfrmProgress.Create(AOwner);
  try
    frm.tp := tp;
    Result := frm.ShowModal = mrOK;
  finally
    frm.Free;
  end;
end;

end.


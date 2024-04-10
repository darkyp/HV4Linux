unit NewVHDForm;

{$mode Delphi}

interface

uses
  Windows, Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  Common, ProgressForm, VHD;

type

  { TfrmNewVHD }

  TfrmNewVHD = class(TForm)
    btnCancel: TButton;
    btnOK: TButton;
    btnSelPath: TButton;
    edtSize: TEdit;
    edtPath: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    procedure btnCancelClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure btnSelPathClick(Sender: TObject);
  private
    ready: Boolean;
    cancel: Boolean;
    szPath: string;
    nMB: DWord;
    function createVHD(frm: TfrmProgress): Boolean;
  public
    class function Execute(AOwner: TComponent; var szPath: string): Boolean;
  end;

implementation

{$R *.lfm}

{ TfrmNewVHD }

class function TfrmNewVHD.Execute(AOwner: TComponent; var szPath: string): Boolean;
var
  frm: TfrmNewVHD;
begin
  frm := TfrmNewVHD.Create(AOwner);
  try
    frm.edtPath.Text := szPath;
    Result := frm.ShowModal = mrOK;
    if (Result) then
      szPath := frm.edtPath.Text;
  finally
    frm.Free;
  end;
end;

function TfrmNewVHD.createVHD(frm: TfrmProgress): Boolean;
var
  f: TFileStream;
  b: array of Byte;
  i: Cardinal;
  vhdFooter: TVHDFooter;
begin
  Result := False;
  try
    f := TFileStream.Create(szPath, fmCreate);
    try
      SetLength(b, 1024 * 1024);
      for i := 0 to nMB - 1 do
      begin
        f.Write(b[0], Length(b));
      end;
      vhdFooter := TVHD.getFooter(nMB * 1024 * 1024);
      f.Write(vhdFooter, SizeOf(vhdFooter));
      Result := True;
    finally
      f.Free;
    end;
  except
    on E: Exception do
    begin
      DeleteFile(szPath);
      raise;
    end;
  end;
end;

procedure TfrmNewVHD.btnOKClick(Sender: TObject);
begin
  nMB := StrToInt(edtSize.Text);
  if nMB <= 0 then raise UserException.Create('Size must be greater than 0');
  szPath := Trim(edtPath.Text);
  if Length(szPath) = 0 then raise UserException.Create('Path MUST be specified');
  if FileExists(szPath) then raise UserException.Create('File already exists');
  if TfrmProgress.Execute(Self, createVHD) then
    ModalResult := mrOK;
end;

procedure TfrmNewVHD.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TfrmNewVHD.btnSelPathClick(Sender: TObject);
var
  sd: TSaveDialog;
begin
  sd := TSaveDialog.Create(Self);
  try
    sd.Filter := 'All supported|*.vhd';
    sd.InitialDir := ExtractFilePath(edtPath.Text);
    sd.FileName := ExtractFileName(edtPath.Text);
    if not sd.Execute then Exit;
    if FileExists(sd.FileName) then raise UserException.Create('File already exists');
    edtPath.Text := sd.FileName;
  finally
    sd.Free;
  end;
end;

end.


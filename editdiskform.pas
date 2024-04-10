unit EditDiskForm;

{$mode Delphi}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  Common, HCS, NewVHDForm, VHD;

type

  { TfrmEditDisk }

  TfrmEditDisk = class(TForm)
    btnCancel: TButton;
    btnOK: TButton;
    btnSelPath: TButton;
    btnNew: TButton;
    btnRawToVHD: TButton;
    chkUse: TCheckBox;
    chkReadonly: TCheckBox;
    edtID: TEdit;
    edtName: TEdit;
    edtPath: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    procedure btnNewClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure btnRawToVHDClick(Sender: TObject);
    procedure btnSelPathClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    disk: TVMDisk;
  public
    class function Execute(AOwner: TComponent; disk: TVMDisk): Boolean;
  end;

var
  frmEditDisk: TfrmEditDisk;

implementation

{$R *.lfm}

procedure TfrmEditDisk.btnOKClick(Sender: TObject);
begin
  disk.nId := StrToInt(edtID.Text);
  disk.szPath := Trim(edtPath.Text);
  disk.szName := Trim(edtName.Text);
  disk.bReadonly := chkReadonly.Checked;
  disk.bUse := chkUse.Checked;
  if (disk.nID < 0) then raise UserException.Create('ID must be a non-negative number');
  if (Length(disk.szName) = 0) then raise UserException.Create('Name MUST not be empty');
  if (Length(disk.szPath) = 0) then raise UserException.Create('Path MUST not be empty');
  ModalResult := mrOK;
end;

procedure TfrmEditDisk.btnRawToVHDClick(Sender: TObject);
var
  od: TOpenDialog;
  f: TFileStream;
  vhdFooter: TVHDFooter;
  size: Int64;
begin
  od := TOpenDialog.Create(Self);
  try
    od.Filter := 'All files|*.img;*.raw;*.hdd';
    if not od.Execute then Exit;
    f := TFileStream.Create(od.FileName, fmOpenWrite);
    try
      size := f.Seek(0, soEnd);
      vhdFooter := TVHD.getFooter(size);
      f.Write(vhdFooter, SizeOf(vhdFooter));
    finally
      f.Free;
    end;
  finally
    od.Free;
  end;
end;

procedure TfrmEditDisk.btnNewClick(Sender: TObject);
var
  szPath: string;
begin
  szPath := edtPath.Text;
  if TfrmNewVHD.Execute(Self, szPath) then
  begin
    edtPath.Text := szPath;
  end;
end;

procedure TfrmEditDisk.btnSelPathClick(Sender: TObject);
begin
  EditSelectFile(Self, edtPath, 'All supported|*.vhd;*.vhdx;*.iso');
end;

procedure TfrmEditDisk.FormShow(Sender: TObject);
begin
  edtName.Text := disk.szName;
  edtID.Text := IntToStr(disk.nID);
  edtPath.Text := disk.szPath;
  chkReadonly.Checked := disk.bReadonly;
  chkUse.Checked := disk.bUse;
end;

class function TfrmEditDisk.Execute(AOwner: TComponent; disk: TVMDisk): Boolean;
var
  frm: TfrmEditDisk;
begin
  frm := TfrmEditDisk.Create(AOwner);
  try
    frm.disk := TVMDisk.Create();
    frm.disk.AddRef();
    try
      frm.disk.copyFrom(disk);
      Result := frm.ShowModal() = mrOK;
      if not Result then Exit;
      disk.copyFrom(frm.disk);
    finally
      frm.disk.Release();
    end;
  finally
    frm.Free;
  end;
end;

end.


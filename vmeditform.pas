unit vmeditform;

{$mode Delphi}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  Menus, Common, Hcs, EditDiskForm;

type

  { TfrmVMEdit }

  TfrmVMEdit = class(TForm)
    btnSelKernel: TButton;
    btnOK: TButton;
    btnSelInit: TButton;
    btnCancel: TButton;
    edtCPU: TEdit;
    edtName: TEdit;
    edtID: TEdit;
    edtRAM: TEdit;
    edtKernel: TEdit;
    edtInit: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    lvDisks: TListView;
    lvNetworks: TListView;
    mmoStartup: TMemo;
    miEnabled: TMenuItem;
    miEdit: TMenuItem;
    miDelete: TMenuItem;
    miAdd: TMenuItem;
    pc: TPageControl;
    pmDisk: TPopupMenu;
    pmDisks: TPopupMenu;
    tsStartup: TTabSheet;
    tsDisks: TTabSheet;
    tsNetworks: TTabSheet;
    procedure btnOKClick(Sender: TObject);
    procedure btnSelInitClick(Sender: TObject);
    procedure btnSelKernelClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure lvDisksData(Sender: TObject; Item: TListItem);
    procedure lvDisksSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure miAddClick(Sender: TObject);
    procedure miDeleteClick(Sender: TObject);
    procedure miEditClick(Sender: TObject);
    procedure miEnabledClick(Sender: TObject);
    procedure pmDiskPopup(Sender: TObject);
  private
    vm: TVM;
  public
    class function Execute(AOwner: TComponent; vm: TVM): Boolean;
  end;

implementation

{$R *.lfm}

procedure TfrmVMEdit.btnSelKernelClick(Sender: TObject);
begin
  EditSelectFile(Self, edtKernel, 'Any|*.*');
end;

procedure TfrmVMEdit.FormCreate(Sender: TObject);
begin
  pc.ActivePage := tsDisks;
end;

procedure TfrmVMEdit.FormShow(Sender: TObject);
begin
  edtName.Text := vm.szName;
  edtKernel.Text := vm.szKernelPath;
  edtInit.Text := vm.szInitRDPath;
  edtCPU.Text := IntToStr(vm.nCPU);
  edtRAM.Text := IntToStr(vm.nMemorySize);
  edtID.Text := vm.szId;
  lvDisks.Items.Count := vm.disks.Count;
  mmoStartup.Text := vm.szStartup;
end;

procedure TfrmVMEdit.lvDisksData(Sender: TObject; Item: TListItem);
var
  disk: TVMDisk;
begin
  disk := vm.disks[Item.Index];
  Item.Data := disk;
  Item.Caption := disk.szName;
  Item.SubItems.Add(IntToStr(disk.nID));
  Item.SubItems.Add('TODO');
  if disk.bReadonly then
    Item.SubItems.Add('Yes') else
    Item.SubItems.Add('No');
  if disk.bUse then
  Item.SubItems.Add('Yes') else
  Item.SubItems.Add('No');
end;

procedure TfrmVMEdit.btnSelInitClick(Sender: TObject);
begin
  EditSelectFile(Self, edtInit, 'Any|*.*');
end;

procedure TfrmVMEdit.btnOKClick(Sender: TObject);
begin
  vm.szName := Trim(edtName.Text);
  vm.szKernelPath := Trim(edtKernel.Text);
  vm.szInitRDPath := Trim(edtInit.Text);
  vm.nCPU := StrToInt(edtCPU.Text);
  vm.nMemorySize := StrToInt(edtRAM.Text);
  if Length(vm.szName) = 0 then raise Exception.Create('Name MUST not be empty');
  if Length(vm.szKernelPath) = 0 then raise Exception.Create('Kernel MUST not be empty');
  if Length(vm.szInitRDPath) = 0 then raise Exception.Create('Init MUST be empty');
  vm.szStartUp := Trim(mmoStartup.Text);
  ModalResult := mrOK;
end;

procedure TfrmVMEdit.lvDisksSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  if not Selected then lvDisks.PopupMenu := pmDisks else
    lvDisks.PopupMenu := pmDisk;
end;

procedure TfrmVMEdit.miAddClick(Sender: TObject);
var
  disk: TVMDisk;
begin
  disk := TVMDisk.Create;
  disk.AddRef();
  try
    if TfrmEditDisk.Execute(Self, disk) then
    begin
      vm.disks.Add(disk);
      lvDisks.Items.Count := vm.disks.Count;
    end;
  finally
    disk.Release;
  end;
end;

procedure TfrmVMEdit.miDeleteClick(Sender: TObject);
var
  li: TListItem;
begin
  li := lvDisks.Selected;
  if li = nil then Exit;
  if not Confirm(Self, 'Confirm removing disk [' + vm.disks[li.Index].szName + ']?') then Exit;
  vm.disks.Delete(li.Index);
  lvDisks.Items.Count := vm.disks.Count;
end;

procedure TfrmVMEdit.miEditClick(Sender: TObject);
var
  li: TListItem;
begin
  li := lvDisks.Selected;
  if li = nil then Exit;
  if TfrmEditDisk.Execute(Self, TVMDisk(li.Data)) then
    lvDisks.Repaint;
end;

procedure TfrmVMEdit.miEnabledClick(Sender: TObject);
var
  li: TListItem;
begin
  li := lvDisks.Selected;
  if li = nil then Exit;
  TVMDisk(li.Data).bUse := not TVMDisk(li.Data).bUse;
  lvDisks.Repaint;
end;

procedure TfrmVMEdit.pmDiskPopup(Sender: TObject);
var
  li: TListItem;
  disk: TVMDisk;
begin
  li := lvDisks.Selected;
  if li = nil then Exit;
  disk := li.Data;
  if disk.bUse then miEnabled.Checked := True else
    miEnabled.Checked := False;
end;

class function TfrmVMEdit.Execute(AOwner: TComponent; vm: TVM): Boolean;
var
  frm: TfrmVMEdit;
begin
  frm := TfrmVMEdit.Create(AOwner);
  try
    frm.vm := TVM.Create(nil, True);
    frm.vm.AddRef();
    try
      frm.vm.copyFrom(vm);
      Result := frm.ShowModal() = mrOK;
      if not Result then Exit;
      vm.copyFrom(frm.vm);
    finally
      frm.vm.Release();
    end;
  finally
    frm.Free;
  end;
end;

end.


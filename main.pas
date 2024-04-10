unit Main;

{$mode DELPHI}
interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls,
  ExtCtrls, Menus, Windows, Winsock, JSON, Common, HCS, VMFrame,
  Pcap, Registry, CircularList, VMEditForm;

const
  AF_HYPERV = 34;
  HV_PROTOCOL_RAW = 1;

  // Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\GuestCommunicationServices
  SvcGuid: TGUID = '{00000064-facb-11e6-bd58-64006a7986d3}';

  HV_GUID_ZERO: TGUID = '{00000000-0000-0000-0000-000000000000}';

type
  sockaddr_hv = record
    family: Word;
    reserved: Word;
    vmId: TGUID;
    serviceId: TGUID;
  end;

const
  WM_FREECOMP = WM_USER + 1;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    edtPath: TEdit;
    Label1: TLabel;
    lvLog: TListView;
    lvNet: TListView;
    lvVM: TListView;
    miShow: TMenuItem;
    miExit: TMenuItem;
    miEdit: TMenuItem;
    miRefresh: TMenuItem;
    miDelete: TMenuItem;
    miAdd: TMenuItem;
    miStart: TMenuItem;
    miKill: TMenuItem;
    miShutdown: TMenuItem;
    Panel2: TPanel;
    pcMain: TPageControl;
    pmVM: TPopupMenu;
    pmVMs: TPopupMenu;
    pnlDetail: TPanel;
    pnlLog: TPanel;
    pmTray: TPopupMenu;
    Separator1: TMenuItem;
    spl: TSplitter;
    tmr: TTimer;
    trayIcon: TTrayIcon;
    tsNetworks: TTabSheet;
    tsVMs: TTabSheet;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure lvLogData(Sender: TObject; Item: TListItem);
    procedure lvLogResize(Sender: TObject);
    procedure lvNetSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
    procedure lvVMData(Sender: TObject; Item: TListItem);
    procedure lvVMKeyPress(Sender: TObject; var Key: char);
    procedure lvVMSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean
      );
    procedure miAddClick(Sender: TObject);
    procedure miDeleteClick(Sender: TObject);
    procedure miEditClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure miKillClick(Sender: TObject);
    procedure miRefreshClick(Sender: TObject);
    procedure miShutdownClick(Sender: TObject);
    procedure miStartClick(Sender: TObject);
    procedure tmrTimer(Sender: TObject);
    procedure trayIconClick(Sender: TObject);
    procedure onWMClose(Sender: TObject);
    procedure onAppActivate(Sender: TObject);
    procedure onAppDeactivate(Sender: TObject);
    procedure onAppException(Sender: TObject; e: Exception);
  private
    closeAction: TCloseAction;
    log: TCircularStringList;
    procedure enumVMs();
    procedure enumNets();
    procedure logMessage(var msg: TMessage); message 9999;
    procedure freeComp(var msg: TMessage); message WM_FREECOMP;
  public

  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

procedure WinsockError(szDesc: string);
begin
  raise Exception.Create(szDesc + ' ' + SysErrorMessage(WSAGetLastError));
end;

procedure WinsockCheck(szDesc: string; r: Integer);
begin
  if r = SOCKET_ERROR then WinsockError(szDesc);
end;

{ TfrmMain }

procedure TfrmMain.Button1Click(Sender: TObject);
begin
end;

procedure TfrmMain.Button2Click(Sender: TObject);
begin
end;

procedure TfrmMain.enumNets();
var
  devs: Ppcap_if;
  dev: Ppcap_if;
  li: TListItem;
  reg: TRegistry;
  sl: TStringList;
  i: Integer;
  szPath: string;
  szName: string;
  slNames: TStringList;
  psz: PString;
  lst: TList;
  pcap_errbuf: array[0..PCAP_ERRBUF_SIZE - 1] of Char;
  adapter: TAdapter;
begin
  reg := TRegistry.Create(KEY_READ or KEY_QUERY_VALUE	or KEY_ENUMERATE_SUB_KEYS);
  reg.RootKey := HKEY_LOCAL_MACHINE;
  szPath := '\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}';
  if not reg.OpenKey(szPath, False) then raise Exception.Create('Open failed');
  sl := TStringList.Create;
  reg.GetKeyNames(sl);
  slNames := TStringList.Create;
  for i := 0 to sl.Count - 1 do
  begin
    if not reg.OpenKey(szPath + '\' + sl[i] + '\Connection', False) then Continue;
    szName := reg.ReadString('Name');
    New(psz);
    psz^ := szName;
    slNames.AddObject('\Device\NPF_' + sl[i], Pointer(psz));
  end;
  sl.Free;
  reg.Free;

  if pcap_init(PCAP_CHAR_ENC_LOCAL, @pcap_errbuf[0]) <> 0 then
    raise Exception.Create(pcap_errbuf);
  if pcap_findalldevs(devs, @pcap_errbuf[0]) <> 0 then
    raise Exception.Create(pcap_errbuf);
  dev := devs;
  lvNet.Items.Clear;
  lst := adapters.LockList;
  try
    for i := 0 to lst.Count - 1 do
    begin
      TAdapter(lst[i]).Free;
    end;
    lst.Clear;
  finally
    adapters.UnlockList;
  end;
  while dev <> nil do
  begin
    li := lvNet.Items.Add();
    szName := dev.description;
    i := slNames.IndexOf(dev.name);
    if i >= 0 then
    begin
      szName := PString(slNames.Objects[i])^;
    end;
    li.Caption := szName;
    adapter := TAdapter.Create(szName, dev.description, dev.name);
    adapters.Add(adapter);
    li.Data := adapter;
    dev := dev.next;
  end;
  pcap_freealldevs(devs);
end;

procedure TfrmMain.enumVMs();
begin
  if vms.Refresh() then
  begin
    lvVM.Items.Count := vms.Count;
    lvVM.Repaint;
  end else
  begin
    lvVM.Items.Count := vms.Count;
  end;
end;

procedure TfrmMain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  trayIcon.Visible := True;
  CloseAction := Self.closeAction;
  vms.saveToJSON('vms.json');
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  if (FileExists('vms.json')) then vms.loadFromJSON('vms.json');
  tmr.OnTimer(tmr);
  enumNets();
  pcMain.ActivePageIndex := 0;
  log := TCircularStringList.Create(1000);
  hwndLog := Handle;
  Application.OnActivate := onAppActivate;
  Application.OnDeactivate := onAppDeactivate;
  Application.OnException := onAppException;
  trayIcon.Icon := Application.Icon;
  tmr.Enabled := True;
  closeAction := caHide;
end;

procedure TfrmMain.lvLogData(Sender: TObject; Item: TListItem);
begin
  Item.Caption := log.get(Item.Index);
end;

procedure TfrmMain.lvLogResize(Sender: TObject);
begin
  lvLog.Columns[0].Width := lvLog.ClientWidth;
end;

procedure TfrmMain.lvNetSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
var
  adapter: TAdapter;
begin
  edtPath.Text := '';
  if (Item = nil) or (not Selected) then Exit;
  adapter := Item.Data;
  edtPath.Text := adapter.szPath;
end;

procedure TfrmMain.lvVMData(Sender: TObject; Item: TListItem);
var
  vm: TVM;
begin
  vm := vms[Item.Index];
  Item.Data := vm;
  if Length(vm.szName) > 0 then
    Item.Caption := vm.szName else
    Item.Caption := vm.szId;
  Item.SubItems.Add(vm.szSystemType);
  Item.SubItems.Add(vm.szOwner);
  Item.SubItems.Add(vm.szRuntimeId);
  Item.SubItems.Add(vm.szState);
end;

procedure TfrmMain.onAppActivate(Sender: TObject);
var
  c: TWinControl;
  frm: TForm;
begin
  if Sender is TForm then frm := TForm(Sender) else
    frm := Screen.ActiveForm;
  if frm = nil then Exit;
  c := frm.ActiveControl;
  if (c <> nil) and (Assigned(c.OnEnter)) then c.OnEnter(Sender);
end;

procedure TfrmMain.onAppDeactivate(Sender: TObject);
var
  c: TWinControl;
  frm: TForm;
begin
  if Sender is TForm then frm := TForm(Sender) else
    frm := Screen.ActiveForm;
  if frm = nil then Exit;
  c := frm.ActiveControl;
  if (c <> nil) and (Assigned(c.OnExit)) then c.OnExit(Sender);
end;

procedure TfrmMain.onAppException(Sender: TObject; e: Exception);
var
  frm: TForm;
  parent: TForm;
begin
  if (e is UserException) then
  begin
    parent := Screen.ActiveForm;
    if parent = nil then parent := Self;
    MessageDlg(parent, 'Error', E.Message, mtError, [mbOK]);
  end else
    Application.ShowException(e);
end;

procedure TfrmMain.tmrTimer(Sender: TObject);
begin
  enumVMs();
end;

procedure TfrmMain.trayIconClick(Sender: TObject);
begin
  if Visible then Hide() else Show();
end;

procedure TfrmMain.lvVMKeyPress(Sender: TObject; var Key: char);
begin
  if Key = #$0D then
  begin
    if Assigned(lvVM.OnDblClick) then lvVM.OnDblClick(lvVM);
    Key := #$00;
  end;
end;

procedure TfrmMain.lvVMSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  if not Selected then lvVM.PopupMenu := pmVMs else
    lvVM.PopupMenu := pmVM;
end;

procedure TfrmMain.miAddClick(Sender: TObject);
var
  vm: TVM;
begin
  vm := TVM.Create(nil, True);
  vm.AddRef();
  try
    if TfrmVMEdit.Execute(Self, vm) then
    begin
      vms.Add(vm);
      lvVM.Items.Count := vms.Count;
    end;
  finally
    vm.Release();
  end;
end;

procedure TfrmMain.miDeleteClick(Sender: TObject);
var
  li: TListItem;
  vm: TVM;
begin
  li := lvVM.Selected;
  if li = nil then Exit;
  vm := li.Data;
  if not vm.bIsPersistant then UserError('[' + vm.szName + '] cannot be removed. Not ours.');
  if vm.szState <> 'Not running' then UserError('[' + vm.szName + '] is currently in [' + vm.szState + ']');
  if not Confirm(Self, 'Confirm removing VM [' + vm.szName + ']?') then Exit;
  vms.Delete(li.Index);
end;

procedure TfrmMain.miEditClick(Sender: TObject);
var
  li: TListItem;
begin
  li := lvVM.Selected;
  if li = nil then Exit;
  if TfrmVMEdit.Execute(Self, TVM(li.Data)) then lvVM.Refresh;
end;

procedure TfrmMain.miExitClick(Sender: TObject);
begin
  closeAction := caFree;
  Close;
end;

procedure TfrmMain.miKillClick(Sender: TObject);
var
  op: HCS_OPERATION;
  cs: HCS_SYSTEM;
  r: PWideChar;
  li: TListItem;
begin
  li := lvVM.Selected;
  if li = nil then Exit;

  HCSCheck('HcsOpenComputeSystem', HcsOpenComputeSystem(PWideChar(WideString(TVM(li.Data).getMachineId())), GENERIC_ALL, cs));
  try
    op := HcsCreateOperation(nil, nil);
    if op = nil then raise Exception.Create('HcsCreateOperation failed');
    HcsCheck('HcsTerminateComputeSystem', HcsTerminateComputeSystem(
      cs, op, nil));
    HcsCheck('HcsWaitForOperationResult', HcsWaitForOperationResult(op, INFINITE, r));
    if (r <> nil) then LocalFree(QWord(r));
  finally
    HcsCloseComputeSystem(cs);
  end;
end;

procedure TfrmMain.miRefreshClick(Sender: TObject);
begin
  enumVMs();
end;

procedure TfrmMain.miShutdownClick(Sender: TObject);
var
  op: HCS_OPERATION;
  cs: HCS_SYSTEM;
  r: PWideChar;
  li: TListItem;
begin
  li := lvVM.Selected;
  if li = nil then Exit;

  HCSCheck('HcsOpenComputeSystem', HcsOpenComputeSystem(PWideChar(WideString(li.Caption)), GENERIC_ALL, cs));
  try
    op := HcsCreateOperation(nil, nil);
    if op = nil then raise Exception.Create('HcsCreateOperation failed');
    HcsCheck('HcsShutDownComputeSystem', HcsShutDownComputeSystem(
      cs, op, nil));
    HcsCheck('HcsWaitForOperationResult', HcsWaitForOperationResult(op, INFINITE, r));
    if (r <> nil) then LocalFree(QWord(r));
  finally
    HcsCloseComputeSystem(cs);
  end;
end;

procedure TfrmMain.onWMClose(Sender: TObject);
var
  ts: TTabSheet;
  i: Integer;
  vm: TVM;
begin
  vm := (Sender as TfrmVM).getVM();
  for i := 0 to pcMain.PageCount - 1 do
  begin
    ts := pcMain.Pages[i];
    if ts.Tag = IntPtr(vm) then
    begin
      ts.Free;
      Break;
    end;
    ts := nil;
  end;
  if ts <> nil then
  begin
    PostMessage(Handle, WM_FREECOMP, 0, IntPtr(Sender));
  end;
end;

procedure TfrmMain.miStartClick(Sender: TObject);
var
  ts: TTabSheet;
  frm: TfrmVM;
  li: TListItem;
  vm: TVM;
  i: Integer;
begin
  li := lvVM.Selected;
  if li = nil then Exit;
  vm := li.Data;
  for i := 0 to pcMain.PageCount - 1 do
  begin
    ts := pcMain.Pages[i];
    if ts.Tag = IntPtr(vm) then
    begin
      pcMain.ActivePage := ts;
      Exit;
    end;
  end;
  ts := TTabSheet.Create(Self);
  ts.Tag := IntPtr(vm);
  ts.PageControl := pcMain;
  ts.Caption := vm.szName;
  pcMain.ActivePage := ts;
  frm := TfrmVM.Create(Self);
  frm.onClose := onWMClose;
  frm.setVM(vm);
  frm.Parent := ts;
  frm.Align := alClient;
  frm.startVM();
end;

procedure TfrmMain.freeComp(var msg: TMessage);
begin
  TComponent(PtrInt(msg.LParam)).Free;
end;

procedure TfrmMain.logMessage(var msg: TMessage);
begin
  log.add(Pointer(msg.lParam));
  lvLog.Items.Count := log.usedSize;
  lvLog.Invalidate;
end;

var
  wsd: TWSAData;

initialization
  WSAStartup($0101, wsd);

end.


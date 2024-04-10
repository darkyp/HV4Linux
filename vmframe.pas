unit VMFrame;

{$mode DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ComCtrls, ExtCtrls, StdCtrls, Menus,
  Buttons, PopupNotifier, ConsoleFrame, Windows, HCS, Common, Winsock, Pcap,
  Streams, ttyframe, CommonControls;

const
  AF_HYPERV = 34;
  HV_PROTOCOL_RAW = 1;
  HV_GUID: TGUID = '{00000000-facb-11e6-bd58-64006a7986d3}';


type
  sockaddr_hv = record
    family: Word;
    reserved: Word;
    vmId: TGUID;
    serviceId: TGUID;
  end;

type
  TPcapWorker = class
    pcap: Tpcap;
    szDevice: string;
    s: THandle;
    bMac: Boolean;
    mac: Int64;
    mac4: PDWord;
    mac2: PWord;
    pcap_errbuf: array[0..PCAP_ERRBUF_SIZE - 1] of Char;
    function execute(): Integer; stdcall;
    constructor Create(szDevice: string; s: THandle);
    destructor Destroy(); override;
  end;

  TVMNetClient = class
    s: THandle;
    wnd: HWND;
    bIsClient: Boolean;
    addr: sockaddr_hv;
    szName: string;
    procedure Log(sz: string);
    function read(var b; len: Integer): Integer;
    function readLine(): string;
    procedure write(var b; len: Integer);
    procedure writeString(sz: string);
    procedure writeLine(sz: string);
    function execute(): Integer; stdcall;
    constructor Create(s: THandle; szName: string; wnd: HWND); overload;
    constructor Create(port: DWord; szId: string; szName: string; wnd: HWND); overload;
    procedure stop();
    destructor Destroy(); override;
  end;

  TVMNetService = class
    s: THandle;
    szName: string;
    wnd: HWND;
    procedure Log(sz: string);
    function execute(): Integer; stdcall;
    constructor Create(port: DWord; szId: string; szName: string; wnd: HWND);
    procedure Stop();
  end;

const
  WM_VMCONNECTED = WM_USER + 1;
  WM_VMNEWTTY = WM_USER + 2;
  WM_VMENDTTY = WM_USER + 3;
  WM_FREECOMP = WM_USER + 4;

type
  TTTYNotify = class
    s: TSocket;
    a: array of string;
    constructor Create(s: TSocket; a: array of string);
  end;

type
  TShellCookie = class
    szCommand: string;
  end;

  { TfrmVM }

  TfrmVM = class(TFrame)
    btnNewShell: TButton;
    btnStart: TButton;
    btnShutdown: TButton;
    btnClose: TButton;
    miPopout: TMenuItem;
    Panel1: TPanel;
    pc: TPageControl;
    pmPC: TPopupMenu;
    procedure btnCloseClick(Sender: TObject);
    procedure btnNewShellClick(Sender: TObject);
    procedure btnShutdownClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure miPopoutClick(Sender: TObject);
    procedure pcChange(Sender: TObject);
  private
    console: TfrmConsole;
    ctrl: TSocketStream;
    bPinned: Boolean;
    vm: TVM;
    bAutoStart: Boolean;
    cookies: TList;
    ns: TVMNetService;
    nc: TVMNetClient;
    forms: TList; // popped out forms
    procedure btnCloseTtyClick(Sender: TObject);
    procedure controlConnected(var msg: TMessage); message WM_VMCONNECTED;
    procedure ttyCreate(var msg: TMessage); message WM_VMNEWTTY;
    procedure ttyEnd(var msg: TMessage); message WM_VMENDTTY;
    procedure freeComp(var msg: TMessage); message WM_FREECOMP;
    procedure conClosed(Sender: TObject);
    procedure screenTitle(Sender: TObject);
    procedure onStateChanged(Sender: TObject);
    procedure closeDetached(Sender: TObject; var CloseAction: TCloseAction);
    procedure popIn(Sender: TObject);
  protected
    procedure BeforeDestruction(); override;
  public
    onClose: TNotifyEvent;
    constructor Create(AOwner: TComponent); override;
    procedure startVM();
    procedure setVM(vm: TVM);
    function getVM(): TVM;
  end;

implementation

{$R *.lfm}

constructor TTTYNotify.Create(s: TSocket; a: array of string);
var
  i: Integer;
begin
  inherited Create();
  Self.s := s;
  SetLength(Self.a, Length(a));
  for i := 0 to Length(a) - 1 do Self.a[i] := a[i];
end;

function TPCapWorker.execute(): Integer;
var
  r: Integer;
  pkt_header: PPcap_pkthdr;
  pkt_data: PChar;
  pkt: PByteArray;
begin
  try
    while True do
    begin
      r := pcap_next_ex(pcap, pkt_header, pkt_data);
      if r = 0 then Continue;
      if r <> 1 then Break;
      pkt := Pointer(pkt_data);
      if pkt = nil then
      begin
        if pkt_header = nil then
          raise Exception.Create('no pkt_header');
        Continue;
      end;
      if pkt_header.len <> pkt_header.caplen then
        raise Exception.Create('failed to read entire packet');
      if bMac then
      begin
        if (PDWord(@pkt[6])^ = mac4^) and (PWord(@pkt[10])^ = mac2^) then
          // Do not loop back injected packets
          Continue;
        if (PDWord(@pkt[0])^ = $FFFFFFFF) and (PWord(@pkt[4])^ = $FFFF) then
        begin
          // Send broadcasts
        end else
        if (PDWord(@pkt[0])^ <> mac4^) or (PWord(@pkt[4])^ <> mac2^) then
          // Do not send packets not for us
          Continue;
      end else
      begin
        // Only forward broadcasts
        if (PDWord(@pkt[0])^ <> $FFFFFFFF) and (PWord(@pkt[4])^ <> $FFFF) then
          Continue;
      end;
      if send(s, pkt_header.len, 4, 0) <> 4 then WinsockError('send');
      if send(s, pkt_data^, pkt_header.len, 0) <> pkt_header.len then WinsockError('send');
    end;
  except
    on E: Exception do
    begin
      Log('pcap: ' + E.Message);
    end;
  end;
  Free;
end;

constructor TPCapWorker.Create(szDevice: string; s: THandle);
var
  r: Integer;
begin
  inherited Create;
  Self.szDevice := szDevice;
  Self.s := s;
  Self.szDevice := szDevice;
  pcap := pcap_create(PChar(szDevice), @pcap_errbuf[0]);
  if pcap = nil then raise Exception.Create(pcap_errbuf);
  pcap_set_promisc(pcap, 1);
  pcap_set_timeout(pcap, 10);
  pcap_set_immediate_mode(pcap, 1);
  r := pcap_activate(pcap);
  if r <> 0 then raise Exception.Create('activate failed');

  CreateThread(execute);
end;

destructor TPcapWorker.Destroy;
begin
  if s <> 0 then closesocket(s);
  if pcap <> nil then
    pcap_close(pcap);
  inherited Destroy();
end;

constructor TfrmVM.Create(AOwner: TComponent);
var
  ts: TTabSheet;
begin
  inherited Create(AOwner);
  cookies := TList.Create;
  Name := 'vm_' + IntToStr(QWord(Self));
  btnNewShell.Enabled := False;
  btnShutdown.Enabled := False;
  forms := TList.Create;
  //TServerPipeStream.Create('test');
end;

procedure TfrmVM.pcChange(Sender: TObject);
begin
  if pc.ActivePage.Tag = 0 then Exit;
  if not Application.MainForm.Visible then Exit;
  TfrmConsole(pc.ActivePage.Tag).pbClick(Sender);
end;

procedure TfrmVM.btnNewShellClick(Sender: TObject);
begin
  if ctrl = nil then Exit;
  ctrl.writeLine('newshell');
end;

procedure TfrmVM.btnShutdownClick(Sender: TObject);
begin
  if ctrl = nil then Exit;
  ctrl.writeLine('shutdown');
end;

procedure TfrmVM.btnStartClick(Sender: TObject);
begin
  startVM();
end;

procedure TfrmVM.popIn(Sender: TObject);
var
  wc: TWinControl;
begin
  wc := TWinControl(Sender);
  if (not (wc is TWinControl)) then Exit;
  while wc <> nil do
  begin
    if (wc is TForm) then Break;
    wc := wc.Parent;
  end;
  if wc = nil then Exit;
  (wc as TForm).Close();
end;

procedure TfrmVM.btnCloseClick(Sender: TObject);
begin
  if Assigned(onClose) then onClose(Self);
end;

procedure TfrmVM.btnCloseTtyClick(Sender: TObject);
var
  frm: TfrmTTY;
begin
  frm := pc.ActivePage.Controls[0] as TfrmTTY;
  pc.ActivePage.Free;
  PostMessage(Handle, WM_FREECOMP, 0, IntPtr(frm));
end;

procedure TfrmVM.controlConnected(var msg: TMessage);
var
  c: TSocketStream;
  sl: TStringList;
  i: Integer;
  cookie: TShellCookie;
  sz: string;
begin
  if (msg.WParam = 1) then
  begin
    c := TSocketStream.Create(TSocket(msg.lParam));
    if ctrl <> nil then
    begin
      c.writeLine('command channel already assigned');
      c.Free;
      Exit;
    end;
    ctrl := c;
    ctrl.writeLine('OK');
    if bAutoStart then
    begin
      sl := TStringList.Create;
      try
        sl.Text := vm.szStartup;
        for i := 0 to sl.Count - 1 do
        begin
          sz := Trim(sl[i]);
          if (Length(sz) = 0) or (sz[1] = '#') then Continue;
          cookie := TShellCookie.Create;
          cookie.szCommand := sl[i];
          cookies.Add(cookie);
          ctrl.writeLine('newshell as_' + IntToStr(IntPtr(cookie)));
        end;
      finally
        sl.Free;
      end;
    end;
    btnNewShell.Enabled := True;
    btnShutdown.Enabled := True;
  end else
  if msg.wParam = 0 then
  begin
    if ctrl = nil then Exit;
    if ctrl.s = TSocket(msg.lParam) then
    begin
      ctrl.s := 0;
      ctrl.Free;
      ctrl := nil;
    end;
    btnNewShell.Enabled := False;
    btnShutdown.Enabled := False;
    if ns <> nil then
    begin
      ns.Stop();
      ns := nil;
    end;
  end;
end;

procedure TfrmVM.onStateChanged(Sender: TObject);
var
  i: Integer;
  frm: TfrmTTY;
  ts: TTabSheet;
  form: TForm;
  imageIndex: Integer;
begin
  frm := Pointer(Sender);
  if not frm.bConnected then
    ImageIndex := 1 else
  if frm.bPinned then
    ImageIndex := 2 else
    ImageIndex := 0;
  ts := nil;
  for i := 0 to pc.PageCount - 1 do
  begin
    ts := pc.Pages[i];
    if ts.Controls[0] = frm then
    begin
      ts.ImageIndex := imageIndex;
      Break;
    end;
    ts := nil;
  end;
  if (ts = nil) then
  begin
    for i := 0 to forms.Count - 1 do
    begin
      form := forms[i];
      if form.Controls[0] = frm then
      begin
        frmCommon.il.GetIcon(ImageIndex, form.Icon);
        Break;
      end;
      form := nil;
    end;
  end;
end;

procedure TfrmVM.screenTitle(Sender: TObject);
var
  con: TfrmConsole;
  i: Integer;
  sz: string;
  ts: TTabSheet;
begin
  con := TfrmConsole(Sender);
  for i := 0 to pc.PageCount - 1 do
  begin
    ts := pc.Pages[i];
    if ts.Tag = IntPtr(con) then
    begin
      sz := con.getScreenTitle();
      if sz = '' then sz:= 'TTY (' + IntToStr(con.id) + ')';
      ts.Caption := sz;
      Break;
    end;
  end;
end;

procedure TfrmVM.conClosed(Sender: TObject);
var
  con: TfrmConsole;
  frm: TfrmTTY;
begin
  con := TfrmConsole(Sender);
  if con = console then
  begin
    btnStart.Enabled := True;
  end else
  if con.Parent is TfrmTTY then
  begin
    frm := TfrmTTY(con.Parent);
    frm.setConnected(False);
  end;
end;

procedure TfrmVM.freeComp(var msg: TMessage);
begin
  TComponent(PtrInt(msg.LParam)).Free;
end;

procedure TfrmVM.ttyEnd(var msg: TMessage);
var
  i: Integer;
  pid: Integer;
  reason: Integer;
  status: Integer;
  ttyInfo: TTTYNotify;
  c: TfrmConsole;
  ts: TTabSheet;
  form: TForm;
begin
  ttyInfo := TTTYNotify(msg.LParam);
  pid := StrToInt(ttyInfo.a[1]);
  status := StrToInt(ttyInfo.a[2]);
  reason := status and $ff;
  status := status shr 8;
  ttyInfo.Free;
  if reason <> 0 then Exit;
  if status <> 2 then Exit;
  ts := nil;
  for i := 0 to pc.PageCount - 1 do
  begin
    ts := pc.Pages[i];
    if ts.Tag = 0 then
    begin
      ts := nil;
      Continue;
    end;
    c := TfrmConsole(ts.Tag);
    if c.id = pid then
    begin
      ts.Controls[0].Free;
      ts.Free;
      Break;
    end;
    ts := nil;
  end;
  if ts = nil then
  begin
    for i := 0 to forms.Count - 1 do
    begin
      form := forms[i];
      if (form.Controls[0] as TfrmTTY).getConsole().id = pid then
      begin
        (form.Controls[0] as TfrmTTY).Free;
        form.Free;
        Break;
      end;
      form := nil;
    end;
  end;
end;

procedure TfrmVM.miPopoutClick(Sender: TObject);
var
  frm: TForm;
  frmTTY: TfrmTTY;
  ts: TTabSheet;
begin
  ts := pc.ActivePage;
  if ts = nil then Exit;
  if ts.ControlCount = 0 then Exit;
  frm := TForm.Create(Self);
  frm.OnActivate := Application.OnActivate;
  frm.OnDeactivate := Application.OnDeactivate;
  frm.ShowInTaskBar := stAlways;;
  frm.Name := 'frm_' + IntToStr(IntPtr(frm));
  frmTTY := TfrmTTY(pc.ActivePage.Controls[0]);
  if not (frmTTY is TfrmTTY) then Exit;
  frmTTY.Parent := frm;
  frmTTY.btnClose.OnClick := popIn;
  frm.OnClose := closeDetached;
  frm.Caption := ts.Caption;
  frmCommon.il.GetIcon(ts.ImageIndex, frm.Icon);
  frm.BorderWidth := 3;
  frm.Width := 600;
  frm.Height := 480;
  frm.Show;
  forms.Add(frm);
  ts.Free;
end;

procedure TfrmVM.closeDetached(Sender: TObject; var CloseAction: TCloseAction);
var
  frm: TfrmTTY;
  ts: TTabSheet;
begin
  frm := (Sender as TForm).Controls[0] as TfrmTTY;
  ts := TTabSheet.Create(Self);
  ts.Caption := (Sender as TForm).Caption;
  ts.PageControl := pc;
  frm.Parent := ts;
  frm.btnClose.OnClick := btnCloseTtyClick;
  ts.Tag := IntPtr(frm.getConsole());
  pc.ActivePage := ts;
  onStateChanged(frm);
  forms.Remove(Sender);
  CloseAction := caFree;
end;

procedure TfrmVM.ttyCreate(var msg: TMessage);
var
  ts: TTabSheet;
  frm: TfrmTTY;
  tty: TfrmConsole;
  ttyInfo: TTTYNotify;
  pid: Integer;
  cookie: TShellCookie;
  a: array of string;
  pos: Integer;
begin
  ttyInfo := TTTYNotify(msg.lParam);
  ts := TTabSheet.Create(Self);
  pid := StrToInt(ttyInfo.a[1]);
  ts.Caption := 'TTY (' + IntToStr(pid) + ')';
  ts.PageControl := pc;

  frm := TfrmTTY.Create(Self);
  frm.onScreenTitle := screenTitle;
  frm.Parent := ts;
  frm.Align := alClient;
  frm.setPinned(StrToInt(ttyInfo.a[2]) <> 0);
  frm.onStateChanged := onStateChanged;
  frm.setConnected(True);
  frm.btnClose.OnClick := btnCloseTtyClick;
  tty := TfrmConsole.Create(frm, TTerminalStream.Create(ttyInfo.s), True);
  tty.id := pid;
  tty.onConClosed := conClosed;
  ts.Tag := IntPtr(tty);

  if Length(ttyInfo.a) >= 3 then
  begin
    a := split(ttyInfo.a[3], '_');
    if (Length(a) = 2) then
    begin
      if a[0] = 'as' then
      begin
        cookie := Pointer(StrToInt64(a[1]));
        pos := cookies.IndexOf(cookie);
        if pos >= 0 then
        begin
          tty.szAutoStart := cookie.szCommand;
          cookies.Delete(pos);
        end;
      end;
    end;
  end;

  frm.setConsole(tty);
  if Length(tty.szAutoStart) > 0 then
    frm.btnPin.Click;
  pc.ActivePage := ts;
  ttyInfo.Free;
  //tty.pbClick(Self);
end;

procedure TfrmVM.setVM(vm: TVM);
begin
  Self.vm := vm;
end;

function TfrmVM.getVM(): TVM;
begin
  Result := vm;
end;

procedure TfrmVM.BeforeDestruction();
begin
  if ns <> nil then
  begin
    ns.Stop();
    ns := nil;
  end;
  if nc <> nil then
  begin
    nc.Stop();
    nc := nil;
  end;
  inherited BeforeDestruction();
end;

procedure TfrmVM.startVM();
var
  configuration: string;
  op: HCS_OPERATION;
  cs: HCS_SYSTEM;
  r: PWideChar;
  ts: TTabSheet;
  i: Integer;
  disk: TVMDisk;
  token: THandle;
  user: ^TOKEN_USER;
  br: Cardinal;
  szSid: string;
  n: Integer;
  s: TRefStream;
begin
  bAutoStart := True;
  if vm.szState = 'Running' then
  begin
    bAutoStart := False;
    ns := TVMNetService.Create(130, vm.szId, vm.szName, Handle);
    nc := TVMNetClient.Create(130, vm.szId, vm.szName, Handle);
    btnStart.Enabled := False;
    if console = nil then
    begin
      ts := TTabSheet.Create(pc);
      ts.PageControl := pc;
      ts.Caption := 'Console';
      console := TfrmConsole.Create(ts, TClientPipeStream.Create('ttyS0_' + vm.szId), False);
      console.Parent := ts;
      console.Align := alClient;
      console.onConClosed := conClosed;
    end else
    begin
      console.setStream(TClientPipeStream.Create('ttyS0_' + vm.szId));
    end;
    Exit;
  end;

  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, token) then
    WinError('OpenProcessToken');
  user := GetMem(1024);
  if not GetTokenInformation(token, TokenUser, user, 1024, br) then
    WinError('GetTokenInformation');
  szSid := SidToString(user.User.Sid);

  op := HcsCreateOperation(nil, nil);
  if op = nil then raise Exception.Create('HcsCreateOperation failed');
  configuration :=
    '{'#$0A +
	  '  "Owner":"HV4L",'#$0A +
	  '  "SchemaVersion":{"Major":2,"Minor":3},'#$0A +
	  '  "VirtualMachine":{'#$0A +
		'   "StopOnReset":false,'#$0A +
		'   "Chipset":{'#$0A +
		'    "UseUtc":true,'#$0A +
		'    "LinuxKernelDirect":{'#$0A +
		'	    "KernelFilePath":"' + StringReplace(vm.szKernelPath, '\', '\\', [rfReplaceAll]) + '",'#$0A +
		'	    "InitRdPath":"' + StringReplace(vm.szInitRDPath, '\', '\\', [rfReplaceAll]) + '",'#$0A +
		'	    "KernelCmdLine":"' +
    'initrd=\\initrd.img ' +
    'TERM=xterm HOME=/root ' +
    'panic=-1 ' +
    //'nr_cpus=4 ' +
    'bonding.max_bonds=0 dummy.numdummies=0 fb_tunnels=none swiotlb=force ' +
    'console=ttyS0_' + vm.szId + ' debug pty.legacy_count=0' +
    '"'#$0A +
		'    }'#$0A +
	  '   },'#$0A +
	  '   "ComputeTopology":{'#$0A +
		'    "Memory":{'#$0A +
		'     "SizeInMB":' + IntToStr(vm.nMemorySize) + ','#$0A +
		'     "AllowOvercommit":true,'#$0A +
		'     "EnableColdDiscardHint":true,'#$0A +
		'     "EnableDeferredCommit":true,'#$0A +
		'     "HighMmioBaseInMB":40958,'#$0A +
		'     "HighMmioGapInMB":24578'#$0A +
    '    },'#$0A +
		'    "Processor":{'#$0A +
		'     "Count":' + IntToStr(vm.nCPU) + ','#$0A +
		'     "EnablePerfmonPmu":true,'#$0A +
		'     "EnablePerfmonLbr":true'#$0A +
    '    }'#$0A +
    '   },'#$0A +
		'   "Devices":{'#$0A +
    '    "ComPorts":{'#$0A +
    '     "0":{'#$0A +
    '      "NamedPipe":"\\\\.\\pipe\\ttyS0_' + vm.szId + '"'#$0A +
    '     }'#$0A +
    '    },'#$0A +
    (*
    '	   "VirtioSerial":{'#$0A +
		'		  "Ports":{'#$0A +
		'		   "0":{'#$0A +
		'		   "NamedPipe":"\\\\.\\pipe\\test",'#$0A +
		'			 "Name":"hvc0",'#$0A +
		'      "ConsoleSupport":true'#$0A +
		'     },'#$0A +
		'			"1":{'#$0A +
		'      "NamedPipe":"\\\\.\\pipe\\test1",'#$0A +
		'       "Name":"hvc1",'#$0A +
		'        "ConsoleSupport":true'#$0A +
		'      }'#$0A +
		'     }'#$0A +
		'    },'#$0A +
    *)
    '';
  if vm.disks.Count > 0 then
		configuration := configuration +
    '    "Scsi":{'#$0A +
    '     "0":{'#$0A +
	  '      "Attachments":{'#$0A;

  n := 0;
  for i := 0 to vm.disks.Count - 1 do
  begin
    disk := vm.disks[i];
    if not disk.bUse then Continue;
    n := n + 1;
    if n > 1 then configuration := configuration + ',';
    configuration := configuration +
      '       "' + IntToStr(disk.nID) + '": {'#$0A +
      '        "Type":"VirtualDisk",'#$0A +
      '        "Path":"' + StringReplace(disk.szPath, '\', '\\', [rfReplaceAll]) + '",'#$0A +
      //'        "SupportCompressedVolumes":true,'#$0A + // 2.3
      //'        "AlwaysAllowSparseFiles":true,'#$0A + // 2.6
      //'        "SupportEncryptedFiles":true,'#$0A + // 2.6
      '        "ReadOnly":';
    if (disk.bReadonly) then configuration := configuration + 'true' else
      configuration := configuration + 'false';
    configuration := configuration + #$0A +
      '       }'#$0A;
  end;
  if vm.disks.Count > 0 then
		configuration := configuration +
      '      }'#$0A +
      '     }'#$0A +
		  '    },'#$0A;
  configuration := configuration +
		'	   "HvSocket":{'#$0A +
		'		    "HvSocketConfig":{'#$0A +
		'			    "DefaultBindSecurityDescriptor":"D:P(A;;FA;;;SY)(A;;FA;;;' + szSid + ')",'#$0A +
		'			    "DefaultConnectSecurityDescriptor":"D:P(A;;FA;;;SY)(A;;FA;;;' + szSid + ')"'#$0A +
		'		    }'#$0A +
		'	   }'#$0A +
		//'	   "Plan9":{},'#$0A +
		//'	   "Battery":{}'#$0A +
		'   },'#$0A +
		'   "RunInSilo":{'#$0A +
		'	   "NotifySiloJobCreated":true'#$0A +
		'   }'#$0A +
	  '  },'#$0A +
	  '  "ShouldTerminateOnLastHandleClosed":false'#$0A +
	  //'  "ShouldTerminateOnLastHandleClosed":true'#$0A +
    '}';
  Writeln('Using configuration:');
  Writeln(configuration);
  HcsCheck('HcsCreateComputeSystem', HcsCreateComputeSystem(
    PWideChar(WideString(vm.getMachineId())),
    PWideChar(WideString(configuration)), op, nil, cs));
  HcsCheck('HcsWaitForOperationResult', HcsWaitForOperationResult(op, INFINITE, r));

  if console = nil then
  begin
    ts := TTabSheet.Create(pc);
    ts.PageControl := pc;
    ts.Caption := 'Console';
    console := TfrmConsole.Create(ts, nil, False);
    console.Parent := ts;
    console.Align := alClient;
    console.onConClosed := conClosed;
  end else
  begin
  end;

  ns := TVMNetService.Create(130, vm.szId, vm.szName, Handle);
  s := TClientPipeStream.Create('ttyS0_' + vm.szId);
  try
    HcsCheck('HcsStartComputeSystem', HcsStartComputeSystem(cs, op, nil));
    HcsCheck('HcsWaitForOperationResult', HcsWaitForOperationResult(op, INFINITE, r));
    console.setStream(s);
    btnStart.Enabled := False;
  except
    on E: Exception do
    begin
      s.Release();
      ns.Stop();
      ns := nil;
      HcsTerminateComputeSystem(cs, op, nil);
      HcsWaitForOperationResult(op, INFINITE, r);
      if (r <> nil) then LocalFree(QWord(r));
      raise;
    end;
  end;
end;

procedure TVMNetClient.Log(sz: string);
begin
  Common.Log('VMC [' + szName + ']: ' + sz);
end;

procedure TVMNetService.Log(sz: string);
begin
  Common.Log('VMS [' + szName + ']: ' + sz);
end;

function TVMNetService.execute(): Integer;
var
  caddr: sockaddr_hv;
  len: Integer;
  cs: THandle;
begin
  try
    Log('started');
    while True do
    begin
      len := SizeOf(caddr);
      cs := accept(s, @caddr, @len);
      WinsockCheck('accept', cs);
      Log('client connected');
      TVMNetClient.Create(cs, szName, wnd);
    end;
  except
    on E: Exception do
    begin
      Log(E.Message);
    end;
  end;
  stop();
end;

constructor TVMNetService.Create(port: DWord; szId: string; szName: string; wnd: HWND);
var
  addr: sockaddr_hv;
  SvcGuid: TGUID;
begin
  inherited Create();
  Self.wnd := wnd;
  SvcGuid := HV_GUID;
  SvcGuid.Data1 := port;
  Self.szName := szName;
  s := socket(AF_HYPERV, SOCK_STREAM, HV_PROTOCOL_RAW);
  if s = INVALID_SOCKET then WinsockError('socket');
  FillChar(addr, SizeOf(addr), 0);
  addr.family := AF_HYPERV;
  addr.reserved := 0;
  addr.vmId := StringToGUID(szId);
  addr.serviceId := SvcGuid;

  WinsockCheck('bind', bind(s, PSockAddrIn(@addr)^, SizeOf(addr)));
  WinsockCheck('listen', listen(s, 10));
  CreateThread(execute);
end;

procedure TVMNetService.Stop();
var
  os: TSocket;
begin
  os := 0;
  os := InterlockedExchange64(s, os);
  if (os <> 0) then
  begin
    closesocket(os);
  end else
    Free;
end;

function TVMNetClient.read(var b; len: Integer): Integer;
var
  p: PByte;
  r: Integer;
  rlen: Integer;
begin
  p := @b;
  Result := 0;
  rlen := len;
  if rlen = -1 then rlen := 1024;
  while (rlen > 0) do
  begin
    r := recv(s, p^, rlen, 0);
    if r = 0 then
    begin
      if (len = -1) then Break;
      raise Exception.Create('connection closed');
    end;
    if r < 0 then WinsockError('recv');
    Inc(Result, r);
    if (len = -1) then Break;
    Dec(rlen, r);
    Inc(p, r);
  end;
end;

function TVMNetClient.readLine(): string;
var
  c: Char;
begin
  Result := '';
  while True do
  begin
    read(c, 1);
    if c = #13 then Continue;
    if c = #10 then Break;
    Result := Result + c;
  end;
end;

procedure TVMNetClient.write(var b; len: Integer);
var
  p: PByte;
  r: Integer;
begin
  p := @b;
  while len > 0 do
  begin
    r := send(s, p^, len, 0);
    if r = 0 then raise Exception.Create('disconnected');
    if r < 0 then WinsockError('send');
    Dec(len, r);
    Inc(p, r);
  end;
end;

procedure TVMNetClient.writeString(sz: string);
begin
  write(sz[1], Length(sz));
end;

procedure TVMNetClient.writeLine(sz: string);
begin
  writeString(sz);
  writeString(#10);
end;

function TVMNetClient.execute(): Integer;
var
  buf: array of Byte;
  r: Integer;
  len: Integer;
  sz: string;
  lst: TList;
  adapter: TAdapter;
  i: Integer;
  a: TStringArray;
  pcap: TPcapWorker;
  szCmd: string;
  f: TFileStream;
  bIsCMD: Boolean;
begin
  bIsCMD := False;
  SetLength(buf, 65536);
  try
    if (bIsClient) then
    begin
      Log('connecting');
      WinsockCheck('connect', connect(s, PSockAddrIn(@addr)^, SizeOf(addr)));
      Log('connected');
    end;
    while True do
    begin
      szCmd := readLine();
      a := split(szCmd, ' ');
      if a[0] = 'command' then
      begin
        PostMessage(wnd, WM_VMCONNECTED, 1, s);
        bIsCMD := True;
      end else
      if a[0] = 'sendfile' then
      begin
        f := TFileStream.Create(AppPath + '\shared\' + a[1], fmCreate);
        try
          writeLine('OK');
          while True do
          begin
            i := read(buf[0], -1);
            if i = 0 then Break;
            f.Write(buf[0], i);
          end;
        finally
          f.Free;
        end;
        Break;
      end else
      if a[0] = 'endtty' then
      begin
        PostMessage(wnd, WM_VMENDTTY, 0, LParam(TTTYNotify.Create(0, a)));
      end else
      if a[0] = 'quit' then
      begin
        writeLine('goodbye');
        Break;
      end else
      if a[0] = 'newtty' then
      begin
        PostMessage(wnd, WM_VMNEWTTY, 0, LParam(TTTYNotify.Create(s, a)));
        writeLine('OK');
        s := 0;
        Break;
      end else
      if a[0] = 'list' then
      begin
        lst := adapters.LockList;
        try
          for i := 0 to lst.Count - 1 do
          begin
            adapter := lst[i];
            writeLine(adapter.szName + #9 + adapter.szDesc + #9 + adapter.szPath);
          end;
        finally
          adapters.UnlockList;
        end;
        writeLine('eof');
      end else
      if a[0] = 'connect' then
      begin
        if Length(a) < 2 then
        begin
          writeLine('missing argument');
          Break;
        end;
        if Length(a) <> 2 then
        begin
          writeLine('too many arguments');
          Break;
        end;
        adapter := nil;
        lst := adapters.LockList;
        try
          for i := 0 to lst.Count - 1 do
          begin
            adapter := lst[i];
            if adapter.szName = a[1] then Break;
            adapter := nil;
          end;
        finally
          adapters.UnlockList;
        end;
        if adapter = nil then
        begin
          writeLine('unknown adapter');
          Break;
        end;

        pcap := TPcapWorker.Create(adapter.szPath, s);

        writeLine('OK');
        while True do
        begin
          r := recv(s, len, 4, 0);
          if r <> 4 then WinsockError('recv');
          if len > 65536 then raise Exception.Create('Invalid len');
          r := recv(s, buf[0], len, 0);
          if r <> len then WinsockError('recv');
          //Writeln('Read ', len);
          if not pcap.bMac then
          begin
            Move(buf[6], pcap.mac, 6);
            pcap.mac4 := @pcap.mac;
            pcap.mac2 := Pointer(Cardinal(pcap.mac4) + 4);
            pcap.bMac := True;
            Log('MAC set to ' + Dump(pcap.mac, 6, ':'));
          end;
          if pcap_inject(pcap.pcap, buf[0], len) <> len then
            raise Exception.Create('pcap inject failed');
        end;
        Break;
      end else
      begin
        Log('Bad command ' + szCmd);
        writeLine('bad command ' + a[0]);
      end;
    end;
  except
    on E: Exception do
    begin
      Log(E.Message);
    end;
  end;
  if (bIsCMD) then PostMessage(wnd, WM_VMCONNECTED, 0, s);
  Log('done');
  Free;
end;

constructor TVMNetClient.Create(port: DWord; szId: string; szName: string; wnd: HWND);
var
  SvcGuid: TGUID;
begin
  SvcGuid := HV_GUID;
  SvcGuid.Data1 := port;
  Self.szName := szName;
  s := socket(AF_HYPERV, SOCK_STREAM, HV_PROTOCOL_RAW);
  if s = INVALID_SOCKET then WinsockError('socket');
  FillChar(addr, SizeOf(addr), 0);
  addr.family := AF_HYPERV;
  addr.reserved := 0;
  addr.vmId := StringToGUID(szId);
  addr.serviceId := SvcGuid;
  Self.wnd := wnd;
  bIsClient := True;
  CreateThread(execute);
end;

constructor TVMNetClient.Create(s: THandle; szName: string; wnd: HWND);
begin
  inherited Create();
  Self.s := s;
  Self.wnd := wnd;
  Self.szName := szName;
  CreateThread(execute);
end;

procedure TVMNetClient.stop();
begin
  if s <> 0 then closesocket(s);
end;

destructor TVMNetClient.Destroy();
begin
  Stop();
  inherited Destroy();
end;

end.


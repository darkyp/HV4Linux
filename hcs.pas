unit HCS;

{$mode DELPHI}

interface

uses
  Windows, Classes, SysUtils, Common, JSON;

const
  computecore = 'computecore.dll';

type
  HCSException = class(UserException)

  end;

type
  TVMNet = class(TJSONRefObject)
    szId: string; // GUID
    szName: string; // as views in VM
    szMAC: string; // MAC address
  end;

  TVMDisk = class(TJSONRefObject)
    nID: Integer; // 0 - sda, 1 - sdb, etc
    szPath: string; // File path
    szName: string; // User/display name
    bReadonly: Boolean;
    bUse: Boolean;
    constructor Create();
    procedure copyFrom(from: TVMDisk);
    function toJSON(): TJSONValue; override;
    class function fromJSON(j: TJSONValue): TJSONRefObject; override;
  end;

  TVM = class(TRefObject)
    bIsPersistant: Boolean; // Whether it was autofound from enum or created by the user
    bPresent: Boolean;
    bUpdated: Boolean;

    szId: string;
    szName: string;
    szKernelPath: string;
    szInitRDPath: string;
    szStartup: string;
    nMemorySize: DWord; // In MB
    nCPU: DWord; // Number of CPUs
    disks: TJSONList<TVMDisk>;
    nets: TJSONList<TVMNet>;

    szSystemType: string;
    szOwner: string;
    szRuntimeId: string;
    szState: string;

    constructor Create(js: TJSON; bFromStore: Boolean);
    function toJSON(): TJSON;
    procedure copyFrom(from: TVM);
    procedure Update(fromVM: TVM);
    procedure resetState();
    function getMachineId(): string;
  end;

  TVMList = class(TRefList<TVM>)
    procedure Add(vm: TVM); override;
    function Refresh(): Boolean;
    function toJSON(): TJSONArray;
    procedure saveToJSON(szFile: string);
    procedure loadFromJSON(szFile: string);
  end;

type
  HCS_OPERATION = Pointer;
  HCS_SYSTEM = Pointer;
  HCS_PROCESS = Pointer;
  HCS_OPERATION_COMPLETION = procedure(operation: HCS_OPERATION; context: Pointer); stdcall;

function HcsCreateOperation(context: Pointer; callback: HCS_OPERATION_COMPLETION): HCS_OPERATION; stdcall; external computecore;
function HcsWaitForOperationResult(operation: HCS_OPERATION; timeoutMs: DWORD; var resultDocument: PWideChar): Integer; external computecore;
function HcsWaitForOperationResultAndProcessInfo(operation: HCS_OPERATION; timeoutMs: DWORD; processInformation: Pointer; var resultDocument: PWideChar): Integer; external computecore;
function HcsEnumerateComputeSystems(query: PWideChar; operation: HCS_OPERATION): Integer; stdcall; external computecore;
procedure HcsCloseOperation(operation: HCS_OPERATION); stdcall; external computecore;
function HcsOpenComputeSystem(id: PWideChar; requestedAccess: DWORD; var computeSystem: HCS_SYSTEM): Integer; stdcall; external computecore;
procedure HcsCloseComputeSystem(computeSystem: HCS_SYSTEM); stdcall; external computecore;
function HcsGetComputeSystemProperties(computeSystem: HCS_SYSTEM; operation: HCS_OPERATION; propertyQuery: PWideChar): Integer; stdcall; external computecore;
function HcsCreateComputeSystem(
  id: PWideChar; configuration: PWideChar;
  operation: HCS_OPERATION;
  securityDescriptor: Pointer; // Currently unused
  var computeSystem: HCS_SYSTEM
): Integer; stdcall; external computecore;
function HcsStartComputeSystem(
  computeSystem: HCS_SYSTEM;
  operation: HCS_OPERATION;
  options: PWideChar // Must be NULL
): Integer; stdcall; external computecore;
function HcsShutDownComputeSystem(
  computeSystem: HCS_SYSTEM;
  operation: HCS_OPERATION;
  options: PWideChar // Reserved for future use. Must be NULL.
): Integer; stdcall; external computecore;
function HcsTerminateComputeSystem(
  computeSystem: HCS_SYSTEM;
  operation: HCS_OPERATION;
  options: PWideChar // Reserved for future use. Must be NULL.
): Integer; stdcall; external computecore;

function HcsCreateProcess(computeSystem: HCS_SYSTEM; processParameters: PWideChar;
  operation: HCS_OPERATION; securityDescriptor: Pointer; var process: HCS_PROCESS): Integer; stdcall; external computecore;

procedure HCSCheck(szDesc: string; r: Integer);

var
  vms: TVMList;

implementation

procedure HCSCheck(szDesc: string; r: Integer);
begin
  if r <> S_OK then raise HCSException.Create(szDesc + ': ' + Format('%.8X', [r]) + ' ' + SysErrorMessage(r));
end;

procedure TVM.resetState();
begin
  if (bIsPersistant) then
  begin
    if szState = 'Not running' then
    begin
      Exit;
    end;
    bUpdated := True;
    szState := 'Not running'
  end else
    szState := '';
  szRuntimeId := '';
  szOwner := '';
  szRuntimeId := '';
  szSystemType := '';
end;

procedure TVM.Update(fromVM: TVM);
begin
  bPresent := True;
  bUpdated := False;
  if szState <> fromVM.szState then
  begin
    bUpdated := True;
    szState := fromVM.szState;
  end;
  if szRuntimeId <> fromVM.szRuntimeId then
  begin
    bUpdated := True;
    szRuntimeId := fromVM.szRuntimeId;
  end;
  if szSystemType <> fromVM.szSystemType then
  begin
    bUpdated := True;
    szSystemType := fromVM.szSystemType;
  end;
  if szOwner <> fromVM.szOwner then
  begin
    bUpdated := True;
    szOwner := fromVM.szOwner;
  end;
end;

function TVM.getMachineId(): string;
begin
  Result := Copy(szId, 2, Length(szId) - 2);
end;

class function TVMDisk.fromJSON(j: TJSONValue): TJSONRefObject;
var
  d: TVMDisk;
  js: TJSON;
begin
  js := j as TJSON;
  d := TVMDisk.Create();
  Result := d;
  d.nID := js.getInt('id');
  d.szName := js.getString('name');
  d.szPath := js.getString('path');
  d.bReadonly := js.getBool('readonly');
  d.bUse := js.optBool('use', True);
end;

function TVMDisk.toJSON(): TJSONValue;
var
  js: TJSON;
begin
  js := TJSON.Create('');
  js.add('name', szName);
  js.add('id', nID);
  js.add('path', szPath);
  js.add('readonly', bReadonly);
  js.add('use', bUse);
  Result := js;
end;

constructor TVMDisk.Create();
begin
  inherited Create();
  bUse := True;
end;

procedure TVMDisk.copyFrom(from: TVMDisk);
begin
  nID := from.nID;
  szPath := from.szPath;
  bReadonly := from.bReadonly;
  szName := from.szName;
  bUse := from.bUse;
end;

procedure TVM.copyFrom(from: TVM);
begin
  szId := from.szId;
  szName := from.szName;;
  szKernelPath := from.szKernelPath;
  szInitRDPath := from.szInitRDPath;
  nMemorySize := from.nMemorySize;
  nCPU := from.nCPU;
  szStartup := from.szStartup;
  disks.copyFrom(from.disks);
end;


function TVM.toJSON(): TJSON;
begin
  Result := TJSON.Create('');

  Result.add('Id', szId);
  Result.add('Name', szName);
  Result.add('KernelPath', szKernelPath);
  Result.add('InitRDPath', szInitRDPath);
  Result.add('MemorySize', nMemorySize);
  Result.add('CPUCount', nCPU);
  Result.add('disks', disks.toJSON());
  Result.add('startup', szStartup);
end;

constructor TVM.Create(js: TJSON; bFromStore: Boolean);
var
  guid: TGUID;
begin
  inherited Create();
  Self.bIsPersistant := bFromStore;
  if js <> nil then szId := js.getString('Id');
  bPresent := True;
  if (bIsPersistant) then
  begin
    disks := TJSONList<TVMDisk>.Create();
    if (Length(szId) = 0) then
    begin
      CreateGUID(guid);
      szId := GUIDToString(guid);
    end;
  end else
  begin
    szId := '{' + szId + '}';
  end;
  if js = nil then Exit;
  if bFromStore then
  begin
    szState := 'Not running';
    szId := js.getString('Id');
    szName := js.getString('Name');
    szKernelPath := js.get('KernelPath');
    szInitRDPath := js.get('InitRDPath');
    nMemorySize := js.getInt('MemorySize');
    nCPU := js.getInt('CPUCount');
    disks.fromJSON(js.getArray('disks'));
    szStartup := js.optString('startup', '');
  end else
  begin
    szSystemType := js.getString('SystemType');
    szOwner := js.optString('Owner', '');
    szRuntimeId := js.getString('RuntimeId');
    szState := js.optString('State', 'Created');
  end;
end;

procedure TVMList.Add(vm: TVM);
var
  i: Integer;
begin
  vm.AddRef;
  try
    for i := 0 to Count - 1 do
    begin
      if Items[i].szId = vm.szId then
      begin
        Items[i].Update(vm);
        Exit;
      end;
    end;
    inherited Add(vm);
  finally
    vm.Release();
  end;
end;

function TVMList.Refresh(): Boolean;
var
  op: HCS_OPERATION;
  r: PWideChar;
  ja: TJSONArray;
  js: TJSON;
  s: TStream;
  c: Char;
  sz: string;
  i: Integer;
begin
  Result := False;
  for i := 0 to vms.Count - 1 do
  begin
    vms[i].bPresent := False;
    vms[i].bUpdated := False;
  end;
  op := HcsCreateOperation(nil, nil);
  if op = nil then raise Exception.Create('HcsCreateOperation failed');
  HcsCheck('HcsEnumerateComputeSystems', HcsEnumerateComputeSystems(nil, op));
  HcsCheck('HcsWaitForOperationResult', HcsWaitForOperationResult(op, INFINITE, r));
  sz := r;
  s := TExtMemoryStream.Create(@sz[1], Length(sz));
  c := #0;
  s.Read(c, 1);
  if c <> '[' then raise Exception.Create('Bad char at 0');
  ja := TJSONArray.Create(s);
  s.Free;
  LocalFree(QWord(r));
  HcsCloseOperation(op);
  for i := 0 to ja.Count - 1 do
  begin
    js := ja.getObj(i);
    Add(TVM.Create(js, False));
  end;
  i := 0;
  while i < vms.Count do
  begin
    if not (vms[i].bPresent) then
    begin
      if (vms[i].bIsPersistant) then
      begin
        vms[i].resetState();
      end else
      begin
        vms.Delete(i);
        Result := True;
        Continue;
      end;
    end;
    if (vms[i].bUpdated) then Result := True;
    Inc(i);
  end;
  ja.Free;
end;

procedure TVMList.loadFromJSON(szFile: string);
var
  f: TFileStream;
  j: TJSONArray;
  i: Integer;
begin
  f := TFileStream.Create(szFile, fmOpenRead or fmShareDenyNone);
  try
    j := TJSON.readValue('', f) as TJSONArray;
    for i := 0 to j.Count() - 1 do
    begin
      Add(TVM.Create(j.getObj(i), True));
    end;
  finally
    f.Free;
  end;
end;

procedure TVMList.saveToJSON(szFile: string);
var
  f: TFileStream;
  j: TJSONArray;
begin
  j := toJSON();
  try
    f := TFileStream.Create(szFile, fmCreate);
    try
      j.toJSON(f, '', ' ');
    finally
      f.Free;
    end;
  finally
    j.Free();
  end;
end;

function TVMList.toJSON(): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create();
  for i := 0 to Count - 1 do
  begin
    if not Items[i].bIsPersistant then Continue;
    Result.add(Items[i].toJSON());
  end;
end;


initialization
  vms := TVMList.Create();

end.


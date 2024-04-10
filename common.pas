unit Common;

{$mode DELPHI}

interface

uses
  Forms, Controls, Classes, Messages, SysUtils, Windows, Winsock, StdCtrls, Dialogs;

type
  UserException = class(Exception)

  end;

type
  TRefObject = class
    refCount: Integer;
    procedure AddRef();
    function Release(): Boolean;
  end;

  TRefList<T: TRefObject> = class(TList)
    procedure Add(o: T); virtual;
    procedure Delete(Index: Integer);
    function Get(Index: Integer): T;
    procedure Put(Index: Integer; Item: T);
    property Items[Index: Integer]: T read Get write Put; default;
  end;

const
  FILE_FLAG_FIRST_PIPE_INSTANCE = $00080000;

type
  TStringArray = array of string;

type
  TThreadProc = function: Integer of object; stdcall;
  TThreadProcRec = record
    proc: Pointer;
    obj: Pointer;
  end;

type
  TExtMemoryStream = class(TMemoryStream)
    constructor Create(mem: Pointer; size: Integer);
  end;

procedure EditSelectFile(AOwner: TComponent; edt: TEdit; szFilter: string);
procedure WinError(szDesc: string);
procedure UserError(sz: string);
procedure Log(sz: string);
procedure WinsockError(szDesc: string);
procedure WinsockCheck(szDesc: string; r: Integer);
function split(sz: string; szSep: string): TStringArray;
function CreateThread(const tp: TThreadProc): THandle;
function Dump(var p; len: Integer; szSep: string = ' '): string;
function MessageDlg(AOwner: TForm; const aCaption, aMsg: string; DlgType: TMsgDlgType;
  Buttons: TMsgDlgButtons): TModalResult; overload;
procedure Reverse(var dst; var src; n: Integer);
function SidToString(sid: Pointer): string;
function Confirm(AOwner: TForm; sz: string): Boolean;
procedure checkConsole();

var
  hwndLog: HWND;
  AppPath: string;

implementation

procedure UserError(sz: string);
begin
  raise UserException.Create(sz);
end;

function Confirm(AOwner: TForm; sz: string): Boolean;
begin
  Result := MessageDlg(AOwner, 'Confirm', sz, mtConfirmation, [mbYes, mbNo]) = mrYes;
end;

function ConvertSidToStringSidA(Sid: Pointer; var StringSid: PChar): LongBool; stdcall; external 'advapi32.dll';
function SidToString(sid: Pointer): string;
var
  pszSid: PChar;
begin
  if not ConvertSidToStringSidA(sid, pszSid) then
    WinError('sid to string');
  Result := pszSid;
  LocalFree(Cardinal(pszSid));
end;

procedure Reverse(var dst; var src; n: Integer);
var
  s: PByte;
  d: PByte;
begin
  d := @dst;
  s := (@src + n - 1);
  while n > 0 do
  begin
    d^ := s^;
    Dec(n);
    Inc(d);
    Dec(s);
  end;
end;

function MessageDlg(AOwner: TForm; const aCaption, aMsg: string; DlgType: TMsgDlgType;
  Buttons: TMsgDlgButtons): TModalResult; overload;
var
  frm: TForm;
begin
  frm := CreateMessageDialog(aCaption, aMsg, DlgType, Buttons);
  try
    frm.Position := poDesigned;
    frm.Left := AOwner.Left + (AOwner.Width - frm.Width) div 2;
    frm.Top := AOwner.Top + (AOwner.Height - frm.Height) div 2;
    Result := frm.ShowModal;
  finally
    frm.Free;
  end;
end;

procedure TRefList<T>.Add(o: T);
begin
  o.AddRef();
  inherited Add(Pointer(o));
end;

procedure TRefList<T>.Delete(Index: Integer);
begin
  Items[Index].Release();
  inherited Delete(Index);
end;

function TRefList<T>.Get(Index: Integer): T;
begin
  Result := T(inherited Get(Index));
end;

procedure TRefList<T>.Put(Index: Integer; Item: T);
begin
  inherited Put(Index, Pointer(Item));
end;

procedure TRefObject.AddRef();
begin
  InterLockedIncrement(RefCount);
end;

function TRefObject.Release(): Boolean;
begin
  Result := False;
  if InterLockedDecrement(RefCount) = 0 then
  begin
    Free;
    Result := True;
  end;
end;

procedure nullFunc(var t:TextRec);
begin
  // noop
  t.BufPos:=0;
end;

procedure checkConsole();
begin
  if IsConsole then Exit;
  Assign(output, '');
  TextRec(output).Mode := fmOutput;
  TextRec(output).inoutfunc := @nullFunc;
  TextRec(output).flushfunc := @nullFunc;
  TextRec(output).closefunc := @nullFunc;
end;

function execThread(a: PByte): Integer; stdcall;
var
  tp: TThreadProc;
begin
  checkConsole();
  Move(a^, tp, SizeOf(tp));
  FreeMem(a);
  Result := tp();
end;

function CreateThread(const tp: TThreadProc): THandle;
var
  tid: Cardinal;
  a: PByte;
begin
  a := GetMem(SizeOf(tp));
  Move(tp, a^, SizeOf(tp));
  Result := Windows.CreateThread(nil, 0, @execThread, a, 0, tid);
end;

function Dump(var p; len: Integer; szSep: string = ' '): string;
var
  p1: PByte;
begin
  p1 := @p;
  Result := '';
  while len > 0 do
  begin
    if Length(Result) > 0 then Result := Result + szSep;
    Result := Result + Format('%.2X', [p1^]);
    Inc(p1);
    Dec(len);
  end;
end;

function split(sz: string; szSep: string): TStringArray;
var
  szPart: string;
  szSearch: string;
  c: Char;
  i: Integer;
begin
  SetLength(Result, 0);
  for i := 1 to Length(sz) do
  begin
    c := sz[i];
    szSearch := szSearch + c;
    if szSearch = szSep then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[Length(Result) - 1] := szPart;
      szPart := '';
    end else
    begin
      szPart := szPart + c;
      szSearch := '';
    end;
  end;
  if (szSearch = szSep) or (Length(szPart) > 0) or (Length(Result) = 0) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[Length(Result) - 1] := szPart;
    szPart := '';
  end;
end;

procedure WinsockError(szDesc: string);
begin
  raise Exception.Create(szDesc + ' ' + SysErrorMessage(WSAGetLastError));
end;

procedure WinsockCheck(szDesc: string; r: Integer);
begin
  if r = SOCKET_ERROR then WinsockError(szDesc);
end;

procedure Log(sz: string);
var
  psz: PString;
begin
  Writeln(sz);
  New(psz);
  psz^ := sz;
  PostMessage(hwndLog, 9999, 0, LParam(psz));
end;

procedure WinError(szDesc: string);
var
  r: Integer;
begin
  r := GetLastError;
  raise Exception.Create(szDesc + ': ' + Format('%.8X', [r]) + ' ' + SysErrorMessage(r));
end;

constructor TExtMemoryStream.Create(mem: Pointer; size: Integer);
begin
  inherited Create;
  SetPointer(mem, Size);
end;

procedure EditSelectFile(AOwner: TComponent; edt: TEdit; szFilter: string);
var
  od: TOpenDialog;
begin
  od := TOpenDialog.Create(AOwner);
  try
    od.Name := AOwner.Name + '_' + edt.Name;
    od.Filter := szFilter;
    od.InitialDir := ExtractFileDir(edt.Text);
    od.FileName := ExtractFileName(edt.Text);
    if not od.Execute then Exit;
    edt.Text := od.FileName;
  finally
    od.Free;
  end;
end;

initialization
  AppPath := ExtractFilePath(ParamStr(0));

end.


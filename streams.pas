unit Streams;

{$mode DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Windows, Winsock, Common;

type
  TRefStream = class(TRefObject)
    function Read(var Buffer; Count: Longint): Longint; virtual; abstract;
    function Write(const Buffer; Count: Longint): Longint; virtual; abstract; overload;
    procedure write(sz: string); overload;
    procedure writeLine(sz: string);
    procedure close(); virtual;
  end;

  TPipeStream = class(TRefStream)
    pipeName: string;
    bConnected: Boolean;
    ovRead: TOverlapped;
    ovWrite: TOverlapped;
    h: THandle;
    procedure waitConnect();
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    constructor Create(h: THandle);
    destructor Destroy; override;
    procedure close(); override;
  end;

  TServerPipeStream = class(TPipeStream)
    constructor Create(pipeName: string);
  end;

  TClientPipeStream = class(TPipeStream)
    constructor Create(pipeName: string);
  end;

  TSocketStream = class(TRefStream)
    s: TSocket;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    constructor Create(s: TSocket);
    destructor Destroy(); override;
    procedure close(); override;
  end;

const
  TIOCSWINSZ = $5414;

type
  TTerminalStream = class(TSocketStream)
    screenWidth: Integer;
    screenHeight: Integer;
    function Write(const Buffer; Count: Longint): Longint; override;
    procedure setWinSize(rows: Word; cols: Word);
    procedure setPinned(bPinned: Boolean);
  end;

implementation

procedure TPipeStream.waitConnect(); inline;
var
  br: DWord;
begin
  if bConnected then Exit;
  if not GetOverlappedResult(h, ovRead, br, True) then WinError('GetOverlappedResult');
  bConnected := True;
end;

function TPipeStream.Read(var Buffer; Count: Longint): Longint;
begin
  waitConnect();
  if not ReadFile(h, Buffer, Count, DWord(Result), @ovRead) then
  begin
    Result := GetLastError;
    if (Result = ERROR_IO_PENDING) then
    begin
      if not GetOverlappedResult(h, ovRead, DWord(Result), True) then WinError('GetOverlappedResult');
    end else
      WinError('ReadFile (pipe)');
  end;
end;

function TPipeStream.Write(const Buffer; Count: Longint): Longint;
begin
  waitConnect();
  if not WriteFile(h, Buffer, Count, DWord(Result), @ovWrite) then
  begin
    Result := GetLastError;
    if (Result = ERROR_IO_PENDING) then
    begin
      if not GetOverlappedResult(h, ovWrite, DWord(Result), True) then WinError('GetOverlappedResult');
    end else
      WinError('WriteFile (pipe)');
  end;
end;

procedure TRefStream.write(sz: string);
begin
  Write(sz[1], Length(sz));
end;

procedure TRefStream.writeLine(sz: string);
begin
  Write(sz);
  Write(#$0A);
end;

constructor TPipeStream.Create(h: THandle);
begin
  inherited Create();
  FillChar(ovRead, SizeOf(ovRead), 0);
  ovRead.hEvent := CreateEvent(nil, False, False, nil);
  FillChar(ovWrite, SizeOf(ovWrite), 0);
  ovWrite.hEvent := CreateEvent(nil, False, False, nil);
  Self.h := h;;
end;

constructor TServerPipeStream.Create(pipeName: string);
var
  r: Integer;
begin
  Self.pipeName := pipeName;
  h := CreateNamedPipe(PChar('\\.\pipe\' + pipeName),
    PIPE_ACCESS_DUPLEX or FILE_FLAG_FIRST_PIPE_INSTANCE or FILE_FLAG_OVERLAPPED,
    PIPE_TYPE_BYTE, 1, 4096, 4096, 0, nil);
  if h = INVALID_HANDLE_VALUE then WinError('CreateNamedPipe');

  inherited Create(h);

  if not ConnectNamedPipe(h, @ovRead) then
  begin
    r := GetLastError;
    if (r <> ERROR_IO_PENDING) then
    begin
      WinError('ConnectNamedPipe');
    end;
  end else bConnected := True;
end;

constructor TClientPipeStream.Create(pipeName: string);
var
  r: Integer;
begin
  Self.pipeName := pipeName;
  h := CreateFile(PChar('\\.\pipe\' + pipeName),
    GENERIC_READ or GENERIC_WRITE,
    0, nil, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, 0);
  if h = INVALID_HANDLE_VALUE then WinError('CreateFile pipe');

  inherited Create(h);

  bConnected := True;
end;

destructor TPipeStream.Destroy;
begin
  close();
  CloseHandle(ovRead.hEvent);
  CloseHandle(ovWrite.hEvent);
  inherited Destroy;
end;

procedure TPipeStream.close();
begin
  if h = 0 then Exit;
  CloseHandle(h);
  h := 0;
  Exit;
end;

function TSocketStream.Read(var Buffer; Count: Longint): Longint;
var
  r: Integer;
begin
  r := recv(s, Buffer, Count, 0);
  if r = 0 then raise Exception.Create('connection closed');
  if r < 0 then WinsockError('send');
  Result := r;
end;

function TSocketStream.Write(const Buffer; Count: Longint): Longint;
var
  r: Integer;
begin
  r := send(s, Buffer, Count, 0);
  if r = 0 then raise Exception.Create('connection closed');
  if r < 0 then WinsockError('send');
  Result := r;
end;

constructor TSocketStream.Create(s: TSocket);
begin
  inherited Create();
  Self.s := s;
end;

destructor TSocketStream.Destroy();
begin
  close();
  inherited Destroy();
end;

procedure TSocketStream.close();
begin
  if s = 0 then Exit;
  closesocket(s);
  s := 0;
end;

function TTerminalStream.Write(const Buffer; Count: Longint): Longint;
begin
  inherited Write(Count, 4);
  Result := inherited Write(Buffer, Count);
end;

procedure TTerminalStream.setWinSize(rows: Word; cols: Word);
type
  Twinsize = packed record
    ws_row: Word;
    ws_col: Word;
    ws_xpixel: Word;
    ws_ypixel: Word;
  end;
var
  ws: Twinsize;
  n: DWord;
begin
  if (screenHeight = rows) and (screenWidth = cols) then Exit;
  ws.ws_row := rows;
  ws.ws_col := cols;
  n := $80000000 + SizeOf(ws);
  inherited Write(n, 4);
  n := TIOCSWINSZ;
  inherited Write(n, 4);
  inherited Write(ws, SizeOf(ws));
  screenHeight := rows;
  screenWidth := cols;
end;

procedure TTerminalStream.setPinned(bPinned: Boolean);
var
  cmd: DWord;
begin
  cmd := $40000000;
  if bPinned then cmd := cmd or 1 else
    cmd := cmd or 2;
  inherited Write(cmd, 4);
end;

procedure TRefStream.close();
begin

end;

end.


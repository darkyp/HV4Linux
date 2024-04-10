unit Console;

{$mode Delphi}

interface

uses
  Windows, Classes, SysUtils, Common;

type
  TConsole = class
    hIn: THandle;
    hOut: THandle;
    hOld: THandle;
    function run(): Integer; stdcall;
    constructor Create();
  end;

implementation

constructor TConsole.Create();
begin
  inherited Create();
  IsConsole := True;
  hOld := GetStdHandle(STD_OUTPUT_HANDLE);
  CreatePipe(hIn, hOut, nil, 1024);
  SetStdHandle(STD_OUTPUT_HANDLE, hOut);
  SetStdHandle(STD_ERROR_HANDLE, hOut);
  SetStdHandle(STD_INPUT_HANDLE, CreateFile('nul', GENERIC_READ,
    FILE_SHARE_WRITE or FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0));
  CreateThread(run);
end;

function TConsole.run(): Integer;
var
  sz: string;
  br: Cardinal;
begin
  try
    SetLength(sz, 1024);
    while True do
    begin
      if not ReadFile(hIn, sz[1], Length(sz), br, nil) then
        Break;
      WriteFile(hOld, sz[1], br, br, nil);
    end;
  except
  end;
end;

end.


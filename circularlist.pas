unit CircularList;

{$mode DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

type
  TCircularList = class
    lst: array of Pointer;
    pos: Integer;
    usedSize: Integer;
    size: Integer;
    avail: Integer;
    startPos: Integer;
    constructor Create(size: Integer);
    procedure dispose(p: Pointer); virtual;
    procedure add(p: Pointer);
    function get(Index: Integer): Pointer;
  end;

  TCircularStringList = class(TCircularList)
    procedure dispose(p: Pointer); override;
    procedure addString(sz: string);
    function get(Index: Integer): string;
  end;

implementation

constructor TCircularList.Create(size: Integer);
begin
  inherited Create();
  SetLength(lst, size);
  Self.size := size;
  Self.avail := size;
end;

procedure TCircularList.dispose(p: Pointer);
begin

end;

function TCircularList.get(Index: Integer): Pointer;
begin
  Result := lst[(startPos + Index) mod size];
end;

procedure TCircularList.add(p: Pointer);
begin
  if avail = 0 then
  begin
    dispose(lst[pos]);
    Inc(startPos);
    if startPos = size then startPos := 0;
  end else
  begin
    Dec(avail);
    Inc(usedSize);
  end;
  lst[pos] := p;
  pos := (pos + 1) mod size;
end;

procedure TCircularStringList.dispose(p: Pointer);
begin
  System.Dispose(PString(p));
end;

procedure TCircularStringList.addString(sz: string);
var
  psz: PString;
begin
  New(psz);
  psz^ := sz;
  inherited add(psz);
end;

function TCircularStringList.get(Index: Integer): string;
begin
  Result := PString(inherited get(Index))^;
end;

end.


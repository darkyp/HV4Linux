unit JSON;
{$mode DELPHI}
interface

uses SysUtils, Classes, StrUtils, Common;

type
  NotFoundException = class(Exception)
  end;

  TJSONValue = class
  public
    function get(path: string): string; virtual; abstract;
    function toString(): string; virtual; abstract;
    procedure toJSON(s: TStream; const currentindent: string; const indent: string); virtual; abstract;
  end;

  TJSONPair = class
    name: string;
    value: TJSONValue;
    constructor Create(name: string; value: TJSONValue);
    destructor Destroy; override;
  end;

  TJSONString = class(TJSONValue)
    Fvalue: string;
  public
    constructor Create(value: string);
    function toString(): string; override;
    procedure toJSON(s: TStream; const currentindent: string; const indent: string); override;
  end;

  TJSONBool = class(TJSONValue)
    Fvalue: Boolean;
  public
    constructor Create(value: Boolean);
    function toString(): string; override;
    procedure toJSON(s: TStream; const currentindent: string; const indent: string); override;
  end;

  TJSON = class;
  TJSONArray = class(TJSONValue)
    list: TList;
    constructor Create(); overload;
    constructor Create(f: TStream); overload;
    procedure add(j: TJSONValue); overload;
    procedure add(i: Integer); overload;
    procedure add(wsz: string); overload;
    function toString(): string; override;
    procedure toJSON(s: TStream; const currentindent: string; const indent: string); override;
    function Count(): Integer;
    function get(i: Integer): TJSONValue;
    function getObj(i: Integer): TJSON;
    function getInt(i: Integer): Integer;
    function getString(i: Integer): string;
    destructor Destroy; override;
  end;

  TJSONInteger = class(TJSONValue)
    Fvalue: Int64;
  public
    constructor Create(value: Int64);
    function toString(): string; override;
    procedure toJSON(s: TStream; const currentindent: string; const indent: string); override;
  end;

  TJSONDouble = class(TJSONValue)
    Fvalue: Double;
  public
    constructor Create(value: Double);
    function toString(): string; override;
    procedure toJSON(s: TStream; const currentindent: string; const indent: string); override;
  end;

  TJSON = class(TJSONValue)
    prefix: string;
    pairs: TList;
    procedure Clear;
    procedure add(const name: string; const value: TJSONValue); overload;
    procedure add(const name: string; const value: string); overload;
    procedure add(const name: string; const value: string; const default: string); overload;
    procedure add(const name: string; const value: Integer); overload;
    procedure add(const name: string; const value: Integer; const default: Integer); overload;
    procedure add(const name: string; const value: Double); overload;
    procedure add(const name: string; const value: Boolean); overload;
    procedure add(const name: string; const value: Boolean; const default: Boolean); overload;
    constructor Create(prefix: string);
    class function readTo(f: TStream; szTo: string; szSkip: string): Char;
    class function readValue(name: string; f: TStream): TJSONValue;
    class function readString(f: TStream): string;
    class function readNumber(f: TStream): string;
    class function Parse(prefix: string; wsz: string): TJSON; overload;
    class function Parse(prefix: string; f: TStream): TJSON; overload;
    function toString(): string; override;
    procedure toJSON(f: TStream; const currentindent: string; const indent: string); override;
    function getArray(name: string): TJSONArray;
    function getValue(name: string): TJSONValue;
    function getInt(name: string): Int64;
    function getBool(name: string): Boolean;
    function getString(name: string): string;
    function optArray(name: string; default: TJSONArray): TJSONArray;
    function opt(name: string; default: TJSON): TJSON;
    function optString(name: string; default: string): string;
    function optBool(name: string; default: Boolean): Boolean;
    function optInt(name: string; default: Integer): Integer;
    destructor Destroy; override;
  public
    function get(path: string): string; override;
  end;

  TObjectClass = class of TObject;
  TJSONObjectClass = class of TJSONObject;
  TJSONPropertyType = (ptString, ptInteger, ptBoolean, ptJSON);
  TJSONObjectArrayClass = class of TJSONObjectArray;
  TJSONProp = record
    name: string;
    _type: TJSONPropertyType;
    address: Pointer;
    objClass: TJSONObjectClass;
    arrClass: TJSONObjectArrayClass;
  end;

  IJSONSerializable = interface(IUnknown)
    ['{FB617F9C-D521-47AB-9DBE-50151BB8A0EF}']
    function toJSON(): TJSONValue;
  end;

  IObject = interface(IUnknown)
    ['{E91B87BA-D2F2-47A9-9806-A043AF573A68}']
    function get(): TObject;
  end;

  TJSONObject = class(TInterfacedObject, IObject, IJSONSerializable)
  private
    props: array of TJSONProp;
  protected
    procedure addProps(props: array of TJSONProp);
    class function fromJSON(j: TJSONValue): TJSONObject; overload; virtual; abstract;
    class function fromJSON(objClass: TJSONObjectClass; j: TJSONValue): TJSONObject; overload;
    function get(): TObject;
  public
    function toJSON(): TJSONValue;
  end;

  TJSONObjectArray = class(TInterfaceList, IJSONSerializable)
  protected
    class function fromJSON(j: TJSONValue): TJSONObjectArray; overload; virtual; abstract;
    class function fromJSON(objClass: TJSONObjectArrayClass; j: TJSONValue): TJSONObjectArray; overload;
    function getItemClass(j: TJSONValue): TJSONObjectClass; virtual; abstract;
  public
    function toJSON(): TJSONValue;
  end;

type
  TJSONRefObject = class(TRefObject)
    function toJSON(): TJSONValue; virtual;
    class function fromJSON(j: TJSONValue): TJSONRefObject; virtual;
  end;

  TJSONList<T: TJSONRefObject> = class(TRefList<T>)
    function toJSON(): TJSONArray;
    procedure fromJSON(js: TJSONArray);
    procedure copyFrom(from: TJSONList<T>);
  end;

implementation

destructor TJSONPair.Destroy;
begin
  value.Free;
  inherited Destroy;
end;

destructor TJSON.Destroy;
var
  i: Integer;
begin
  for i := 0 to pairs.Count - 1 do
  begin
    TObject(pairs[i]).Free;
  end;
  pairs.Free;
  inherited Destroy;
end;

{function PosW(c: WideChar; const wsz: WideString): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(wsz) do
  begin
    if wsz[i] = c then
    begin
      Result := i;
      Break;
    end;
  end;
end;}

class function TJSON.Parse(prefix: string; f: TStream): TJSON;
var
  c: Char;
  name: string;
  value: TJSONValue;
begin
  readTo(f, '{', ' '#13#10#9);
  f.Seek(1, soFromCurrent);
  Result := TJSON.Create(prefix);
  while f.Position < f.Size do
  begin
    if readTo(f, '}"', ' '#13#10#9) = '}' then
    begin
      f.Read(c, 1);
      Break;
    end;
    name := readString(f);
    readTo(f, ':', ' '#13#10#9);
    f.Seek(1, soFromCurrent);
    value := readValue(prefix + name, f);
    Result.add(name, value);
    readTo(f, '},', ' '#13#10#9);
    f.Read(c, 1);
    if c = '}' then Break;
  end;
end;

class function TJSON.Parse(prefix: string; wsz: string): TJSON;
begin
  result := Parse(prefix, TExtMemoryStream.Create(@wsz[1], Length(wsz) * 2));
end;

class function TJSON.readNumber(f: TStream): string;
var
  c: Char;
  first: Boolean;
begin
  first := True;
  while True do
  begin
    f.Read(c, 1);
    if (c = '-') and (first) then
    begin
    end else
    if (c <> '.') and ((c < '0') or (c > '9')) then
    begin
      f.Seek(-1, soFromCurrent);
      Break;
    end;
    Result := Result + c;
    first := False;
  end;
end;

class function TJSON.readString(f: TStream): string;
var
  iESC: Integer;
  szESC: string;
  c: Char;
  Size: Integer;
begin
  iESC := 0;
  Result := '';
  szESC := '';
  Size := f.Size;
  while f.Position < Size do
  begin
    f.Read(c, 1);
    if c = '"' then Break;
    if c = ' ' then Continue;
    if c = #13 then Continue;
    if c = #10 then Continue;
    if c = #9 then Continue;
    raise Exception.Create('Unexpected character [' + IntToStr(Ord(c)) + '] at ' + IntToStr(f.Position));
  end;

  while f.Position < Size do
  begin
    f.Read(c, 1);
    if iESC > 0 then
    begin
      szESC := szESC + c;
      iESC := iESC - 1;
      if iESC = 0 then
      begin
        if szESC = 'u' then
        begin
          iESC := 4;
          szESC := '';
        end else
        if szESC = '"' then Result := Result + szESC else
        if szESC = '\' then Result := Result + szESC else
        if szESC = '/' then Result := Result + szESC else
        if szESC = 'b' then Result := Result + #08 else
        if szESC = 'f' then Result := Result + #12 else
        if szESC = 'n' then Result := Result + #10 else
        if szESC = 'r' then Result := Result + #13 else
        if szESC = 't' then Result := Result + #09 else
        if Length(szESC) = 4 then Result := Result + String(WideChar(Hex2Dec(szESC))) else
          raise Exception.Create('Bad escape sequence ' + szESC);
      end;
    end else
    if c = '\' then
    begin
      szESC := '';
      iESC := 1;
    end else
    if c = '"' then Break
    else
      Result := Result + c;
  end;
end;

class function TJSON.readTo(f: TStream; szTo: string; szSkip: string): Char;
var
  c: Char;
begin
  while f.Position < f.Size do
  begin
    Result := #$00;
    f.Read(c, 1);
    if Pos(c, szSkip) > 0 then Continue;
    f.Seek(-1, soFromCurrent);
    Result := c;
    if (Length(szTo) = 0) then Break;
    if Pos(c, szTo) > 0 then Break;;
    raise Exception.Create('Unexpected character [' + IntToStr(Word(c)) + '] at ' + IntToStr(f.Position));
  end;
end;

class function TJSON.readValue(name: string; f: TStream): TJSONValue;
var
  c: Char;
  i: Int64;
  szV: string;
  d: Double;
begin
  Result := nil;
  readTo(f, '', ' '#13#10#9);
  f.Read(c, 1);
  f.Seek(-1, soFromCurrent);
  if c = '"' then
  begin
    Result := TJSONString.Create(readString(f));
  end else
  if c = '[' then
  begin
    f.Seek(1, soFromCurrent);
    Result := TJSONArray.Create(f);
  end else
  if c = '{' then
  begin
    Result := TJSON.Parse(name + '.', f);
  end else
  if (c = '-') or ((c >= '0') and (c <= '9')) then
  begin
    szV := readNumber(f);
    try
      i := StrToInt64(szV);
      Result := TJSONInteger.Create(i);
    except
      try
        d := StrToFloat(szV);
        Result := TJSONDouble.Create(d);
      except
        raise Exception.Create('Unknown value [' + szV + '] at ' + IntToStr(f.Position));
      end;
    end;
  end else
  begin
    szV := c;
    f.Seek(1, soFromCurrent);
    while True do
    begin
      f.Read(c, 1);
      if ((c >= 'a') and (c <= 'z')) or ((c >= '0') and (c <= '9')) or ((c >= 'A') and (c <= 'Z')) or (c = '_') then
      begin
        szV := szV + c;
      end else
      begin
        f.Seek(-1, soFromCurrent);
        Break;
      end;
    end;
    if (szV = 'null') then Result := nil else
    if (szV = 'false') then Result := TJSONBool.Create(False) else
    if (szV = 'true') then Result := TJSONBool.Create(True) else
      raise Exception.Create('Unknown value [' + szV + ']');
  end;
end;

constructor TJSONString.Create(value: string);
begin
  Fvalue := value;
end;

function TJSONString.toString(): string;
begin
  Result := Fvalue;
end;

constructor TJSONBool.Create(value: Boolean);
begin
  Fvalue := value;
end;

function TJSONBool.toString(): string;
begin
  if Fvalue then Result := 'true' else Result := 'false';
end;

constructor TJSONPair.Create(name: string; value: TJSONValue);
begin
  Self.name := name;
  Self.value := value;
end;

procedure TJSON.add(const name: string; const value: TJSONValue);
begin
  pairs.add(TJSONPair.Create(name, value));
end;

procedure TJSON.Clear;
begin
  pairs.Clear;
end;

constructor TJSON.Create(prefix: string);
begin
  inherited Create;
  Self.prefix := prefix;
  pairs := TList.Create;
end;

function TJSON.toString(): string;
var
  i: Integer;
  p: TJSONPair;
begin
  Result := '';
  for i := 0 to pairs.Count - 1 do
  begin
    p := pairs[i];
    if p.value = nil then
      Result := Result + prefix + p.name + ' = null' + #13#10
    else
    if p.value is TJSON then
      Result := Result + p.value.toString()
    else
      Result := Result + prefix + p.name + ' = ' + p.value.toString() + #13#10;
  end;
end;

function TJSON.get(path: string): string;
var
  v: TJSONValue;
begin
  v := getValue(path);
  Result := v.toString();
end;

procedure TJSON.toJSON(f: TStream; const currentindent: string; const indent: string);
var
  i: Integer;
  p: TJSONPair;
  sz: string;
begin
  sz := '{';
  if (Length(indent) > 0) then sz := sz + #13#10;
  f.Write(sz[1], Length(sz));
  for i := 0 to pairs.Count - 1 do
  begin
    if i > 0 then
    begin
      sz := ', ';
      if (Length(indent) > 0) then
        sz := sz + #13#10;
      f.Write(sz[1], Length(sz));
    end;
    p := pairs[i];
    sz := currentindent + indent + '"' + p.name + '": ';
    f.Write(sz[1], Length(sz));
    p.value.toJSON(f, currentindent + indent, indent);
  end;
  if (Length(indent) > 0) then sz := #13#10 + currentindent else sz := '';
  sz := sz + '}';
  f.Write(sz[1], Length(sz));
end;

procedure TJSONArray.toJSON(s: TStream; const currentindent: string; const indent: string);
var
  i: Integer;
  j: TJSONValue;
  sz: string;
begin
  sz := '[';
  s.Write(sz[1], Length(sz));
  for i := 0 to list.Count - 1 do
  begin
    if i > 0 then
    begin
      sz := ', ';
      s.Write(sz[1], Length(sz));
    end;
    j := list[i];
    j.toJSON(s, currentindent + indent, indent);
  end;
  sz := ']';
  s.Write(sz[1], Length(sz));
end;

constructor TJSONArray.Create;
begin
  inherited;
  list := TList.Create;
end;

function TJSONArray.toString(): string;
var
  s: TStringStream;
begin
  s := TStringStream.Create();
  toJSON(s, '', ' ');
  Result := s.DataString;
  s.Free;
end;

constructor TJSONArray.Create(f: TStream);
var
  c: Char;
begin
  Create;
  f.Read(c, 1);
  if c = ']' then
  begin
  end else
  begin
    f.Seek(-1, soFromCurrent);
    while True do
    begin
      add(TJSON.readValue('', f));
      TJSON.readTo(f, '],', ' '#13#10#9);
      f.Read(c, 1);
      if c = ']' then Break;
    end;
  end;
end;

procedure TJSONArray.add(j: TJSONValue);
begin
  list.add(j);
end;

procedure TJSONArray.add(i: Integer);
begin
  list.add(TJSONInteger.Create(i));
end;

procedure TJSONArray.add(wsz: string);
begin
  list.add(TJSONString.Create(wsz));
end;

procedure TJSONString.toJSON(s: TStream; const currentindent: string; const indent: string);
var
  wsz: string;
  i: Integer;
  c: Char;
begin
  wsz := '';
  for i := 1 to Length(Fvalue) do
  begin
    c := Fvalue[i];
    if c = '\' then wsz := wsz + '\';
    wsz := wsz + c;
  end;
  s.Write(string('"' + wsz + '"')[1], Length(wsz) + 2);
end;

procedure TJSONBool.toJSON(s: TStream; const currentindent: string; const indent: string);
begin
  if Fvalue then s.Write(string('true')[1], 4) else
    s.Write(string('false')[1], 5);
end;

procedure TJSON.add(const name: string; const value: string);
begin
  add(name, TJSONString.Create(value));
end;

procedure TJSON.add(const name: string; const value: Double);
begin
  add(name, TJSONDouble.Create(value));
end;

procedure TJSON.add(const name: string; const value: Integer);
begin
  add(name, TJSONInteger.Create(value));
end;

procedure TJSON.add(const name: string; const value: Integer; const default: Integer);
begin
  if value <> default then add(name, value);
end;

procedure TJSON.add(const name: string; const value: Boolean; const default: Boolean);
begin
  if value <> default then add(name, value);
end;

procedure TJSON.add(const name: string; const value: Boolean);
begin
  add(name, TJSONBool.Create(value));
end;

procedure TJSON.add(const name: string; const value: string; const default: string);
begin
  if (value <> default) then add(name, value);
end;

constructor TJSONInteger.Create(value: Int64);
begin
  inherited Create();
  Fvalue := value;
end;

function TJSONInteger.toString(): string;
begin
  Result := IntToStr(Fvalue);
end;

procedure TJSONInteger.toJSON(s: TStream; const currentindent: string; const indent: string);
var
  sz: string;
begin
  sz := toString();
  s.Write(sz[1], Length(sz));
end;

constructor TJSONDouble.Create(value: Double);
begin
  inherited Create();
  Fvalue := value;
end;

function TJSONDouble.toString(): string;
begin
  Result := FloatToStr(Fvalue);
end;

procedure TJSONDouble.toJSON(s: TStream; const currentindent: string; const indent: string);
var
  sz: string;
begin
  sz := toString();
  s.Write(sz[1], Length(sz));
end;

function TJSON.optArray(name: string; default: TJSONArray): TJSONArray;
var
  o: TObject;
begin
  Result := default;
  if Self = nil then Exit;
  o := getValue(name);
  if (o = nil) then Exit;
  if not (o is TJSONArray) then raise Exception.Create('Expected [' + name + '] Array. Found [' + o.ClassName + ']');
  Result := o as TJSONArray;
end;

function TJSON.opt(name: string; default: TJSON): TJSON;
var
  o: TObject;
begin
  Result := default;
  o := getValue(name);
  if (o = nil) then Exit;
  if not (o is TJSON) then raise Exception.Create('Expected [' + name + '] Object. Found [' + o.ClassName + ']');
  Result := o as TJSON;
end;

function TJSON.getArray(name: string): TJSONArray;
var
  o: TObject;
begin
  o := getValue(name);
  if (o = nil) then raise Exception.Create('[' + name + '] not found');
  if not (o is TJSONArray) then raise Exception.Create('Expected [' + name + '] Array. Found [' + o.ClassName + ']');
  Result := o as TJSONArray;
end;

function TJSONArray.Count(): Integer;
begin
  Result := list.Count;
end;

function TJSONArray.get(i: Integer): TJSONValue;
var
  o: TObject;
begin
  o := list[i];
  if (o = nil) then Result := nil else
  if not (o is TJSONValue) then raise Exception.Create('Expected [' + IntToStr(i) + '] Object. Found [' + o.ClassName + ']');
  Result := o as TJSONValue;
end;

function TJSONArray.getInt(i: Integer): Integer;
var
  o: TObject;
begin
  o := list[i];
  if (o = nil) then raise Exception.Create('Expected Integer but got null value') else
  if not (o is TJSONInteger) then raise Exception.Create('Expected [' + IntToStr(i) + '] Integer. Found [' + o.ClassName + ']');
  Result := (o as TJSONInteger).Fvalue;
end;

function TJSONArray.getString(i: Integer): string;
var
  o: TObject;
begin
  o := list[i];
  if (o = nil) then raise Exception.Create('Expected String but got null value') else
  if not (o is TJSONString) then raise Exception.Create('Expected [' + IntToStr(i) + '] String. Found [' + o.ClassName + ']');
  Result := (o as TJSONString).Fvalue;
end;

destructor TJSONArray.Destroy;
var
  i: Integer;
begin
  for i := 0 to list.Count - 1 do
  begin
    if list[i] <> nil then TObject(list[i]).Free;
  end;
  list.Free;
  inherited Destroy;
end;

function TJSONArray.getObj(i: Integer): TJSON;
var
  o: TObject;
begin
  o := list[i];
  if (o = nil) then raise Exception.Create('Expected Object but got null value') else
  if not (o is TJSON) then raise Exception.Create('Expected [' + IntToStr(i) + '] Object. Found [' + o.ClassName + ']');
  Result := (o as TJSON);
end;

function TJSON.getValue(name: string): TJSONValue;
var
  p: TJSONPair;
  i: Integer;
begin
  Result := nil;
  for i := 0 to pairs.Count - 1 do
  begin
    p := pairs[i];
    if (p.name = name) then
    begin
      Result := p.value;
      Exit;
    end;
  end;
end;

function TJSON.getString(name: string): string;
var
  o: TJSONValue;
begin
  o := getValue(name);
  if o = nil then raise Exception.Create('[' + name + '] not found');
  if not (o is TJSONString) then raise Exception.Create('Expected [' + name + '] String but found [' + o.ClassName + ']');
  Result := (o as TJSONString).toString;
end;

function TJSON.optString(name: string; default: string): string;
var
  o: TJSONValue;
begin
  Result := default;
  o := getValue(name);
  if o = nil then Exit;
  if not (o is TJSONString) then raise Exception.Create('Expected [' + name + '] String but found [' + o.ClassName + ']');
  Result := (o as TJSONString).toString;
end;

function TJSON.optBool(name: string; default: Boolean): Boolean;
var
  o: TJSONValue;
begin
  Result := default;
  o := getValue(name);
  if o = nil then Exit;
  if not (o is TJSONBool) then raise Exception.Create('Expected [' + name + '] Boolean but found [' + o.ClassName + ']');
  Result := (o as TJSONBool).Fvalue;
end;

function TJSON.optInt(name: string; default: Integer): Integer;
var
  o: TJSONValue;
begin
  Result := default;
  o := getValue(name);
  if o = nil then Exit;
  if not (o is TJSONInteger) then raise Exception.Create('Expected [' + name + '] Integer but found [' + o.ClassName + ']');
  Result := (o as TJSONInteger).Fvalue;
end;

function TJSON.getInt(name: string): Int64;
var
  o: TJSONValue;
begin
  o := getValue(name);
  if o = nil then raise Exception.Create('[' + name + '] not found');
  if not (o is TJSONInteger) then raise Exception.Create('Expected [' + name + '] Integer but found [' + o.ClassName + ']');
  Result := (o as TJSONInteger).Fvalue;
end;

function TJSON.getBool(name: string): Boolean;
var
  o: TJSONValue;
begin
  o := getValue(name);
  if o = nil then raise Exception.Create('[' + name + '] not found');
  if not (o is TJSONBool) then raise Exception.Create('Expected [' + name + '] Boolean but found [' + o.ClassName + ']');
  Result := (o as TJSONBool).Fvalue;
end;

procedure TJSONObject.addProps(props: array of TJSONProp);
var
  i: Integer;
begin
  i := Length(Self.props);
  SetLength(Self.props, i + Length(props));
  Move(props[0], Self.props[i], Length(props) * SizeOf(props[0]));
end;

class function TJSONObject.fromJSON(objClass: TJSONObjectClass; j: TJSONValue): TJSONObject;
type
  PBoolean = ^Boolean;
var
  i: Integer;
  o: TJSON;
  prop: TJSONProp;
begin
  Result := objClass.Create();
  if j = nil then Exit;
  if not (j is TJSON) then raise Exception.Create(
    'Reading ' + objClass.ClassName + ' ' +
    'expects TJSON ' +
    'but got ' + j.ClassName);
  o := TJSON(j);
  for i := 0 to Length(Result.props) - 1 do
  begin
    prop := Result.props[i];
    if prop._type = ptString then
    begin
      PString(prop.address)^ := o.optString(prop.name, '');
    end else
    if prop._type = ptBoolean then
    begin
      PBoolean(prop.address)^ := o.optBool(prop.name, False);
    end else
    if prop._type = ptJSON then
    begin
      if prop.objClass <> nil then
        prop.address := prop.objClass.fromJSON(o.opt(prop.name, nil)) else
      if prop.arrClass <> nil then
        prop.address := prop.arrClass.fromJSON(o.getValue(prop.name));
      //IJSONSerializable(Result.props[i].address).toJSON
    end;
  end;
end;

function TJSONObject.toJSON(): TJSONValue;
type
  PBoolean = ^Boolean;
var
  j: TJSON;
  i: Integer;
begin
  j := TJSON.Create('');
  for i := 0 to Length(props) - 1 do
  begin
    if props[i]._type = ptString then
    begin
      j.add(props[i].name, PString(props[i].address)^);
    end else
    if props[i]._type = ptBoolean then
    begin
      j.add(props[i].name, PBoolean(props[i].address)^);
    end else
    if props[i]._type = ptJSON then
    begin
      j.add(props[i].name, IJSONSerializable(props[i].address).toJSON());
    end;
  end;
  Result := j;
end;

class function TJSONObjectArray.fromJSON(objClass: TJSONObjectArrayClass; j: TJSONValue): TJSONObjectArray;
var
  a: TJSONArray;
  i: Integer;
  item: TJSONObject;
  itemClass: TJSONObjectClass;
  v: TJSONValue;
begin
  Result := objClass.Create() as TJSONObjectArray;
  if (j = nil) then Exit;
  if not (j is TJSONArray) then raise Exception.Create(
    'Reading ' + objClass.ClassName + ' ' +
    'expects TJSONArray ' +
    'but got ' + j.ClassName);
  a := TJSONArray(j);
  for i := 0 to a.Count - 1 do
  begin
    v := a.get(i);
    itemClass := Result.getItemclass(v);
    Result.add(itemClass.fromJSON(itemClass, v));
  end;
end;

function TJSONObjectArray.toJSON(): TJSONValue;
var
  a: TJSONArray;
  i: Integer;
begin
  a := TJSONArray.Create();
  for i := 0 to Count - 1 do
  begin
    a.add((Items[i] as IJSONSerializable).toJSON());
  end;
  Result := a;
end;

function TJSONObject.get(): TObject;
begin
  Result := Self;
end;

procedure TJSONList<T>.fromJSON(js: TJSONArray);
var
  i: Integer;
begin
  for i := 0 to js.Count - 1 do
  begin
    Add(T(T.fromJSON(js.get(i))));
  end;
end;

procedure TJSONList<T>.copyFrom(from: TJSONList<T>);
var
  i: Integer;
begin
  Clear();
  for i := 0 to from.Count - 1 do
  begin
    Add(from[i]);
  end;
end;

function TJSONList<T>.toJSON(): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create();
  for i := 0 to Count - 1 do
  begin
    Result.Add(Items[i].toJSON());
  end;
end;

class function TJSONRefObject.fromJSON(j: TJSONValue): TJSONRefObject;
begin
  Result := TJSONRefObject.Create();
end;

function TJSONRefObject.toJSON(): TJSONValue;
begin
  Result := nil;
end;

end.


unit ConsoleFrame;

{$mode DELPHI}{$H+}

interface

uses
  Windows, LCLType, Classes, SysUtils, Forms, Controls, ExtCtrls, StdCtrls, SyncObjs,
  Graphics, Math, Types, Common, Streams, Clipbrd;

type
  TTermMode = (MODE_NUMPAD, MODE_APPLICATION);

const
  fgcolor8: array [0..9] of TColor = (
    $000000, // 0 - black
    $0000bb, // 1 - red
    $00bb00, // 2 - green
    $00bbbb, // 3 - yellow
    $bb0000, // 4 - blue
    $bb00bb, // 5 - magenta
    $bbbb00, // 6 - cyan
    $bbbbbb, // 7 - white
    $999999, // 8
    $999999  // 9 - default
  );
  // Bold colors
  fgcolor8b: array [0..9] of TColor = (
    $000000, // 0 - black
    $0000ff, // 1 - red
    $00ff00, // 2 - green
    $00ffff, // 3 - yellow
    $ff0000, // 4 - blue
    $ff00ff, // 5 - magenta
    $ffff00, // 6 - cyan
    $ffffff, // 7 - white
    $ffffff, // 8
    $ffffff  // 9 - default
  );

  bgcolor8: array [0..9] of TColor = (
    $000000, // 0 - black
    $0000bb, // 1 - red
    $00bb00, // 2 - green
    $00bbbb, // 3 - yellow
    $bb0000, // 4 - blue
    $bb00bb, // 5 - magenta
    $bbbb00, // 6 - cyan
    $bbbbbb, // 7 - white
    $000000, // 8
    $000000  // 9 - default
  );

type
  TTermState = (
    STATE_NONE, // Noraml - character printing
    STATE_ESC,  // ESC received
    STATE_CSI,  // Control Sequence Introducer received
    STATE_CSSEL, // Character Set Selector received
    STATE_SCRTITLE, // Screen title
    STATE_OSC,   // Operating System Command received
    STATE_OSC_ESC // OSC terminating
  );

const
  ATTRIB_BOLD      = 1;
  ATTRIB_INVERSE   = 4;
  ATTRIB_UNDERLINE = 8;

type
  TAttrib = record
    fg: Byte;
    bg: Byte;
    style: Byte;
    charset: Byte;
  end;

  PLine = ^TLine;
  TLine = record
    date: TDateTime;
    attribs: array of TAttrib;
    chars: array of Cardinal;
  end;

  TLog = class
    width: Integer;
    scrollpos: Integer;

    dChar: DWord;
    nChar: Integer;
    nChars: Integer;

    nLines: Integer; // Shortcut for Length(lines)
    lines: array of TLine;
    iYWrite: Integer;
    pageTop: Integer;
    offsetY: Integer;
    iXWrite: Integer;
    iCount: Integer; // Number of lines written
    iScroll: Integer;
    screenHeight: Integer; // Number of visible lines
    Changed: Boolean;
    fullRepaint: Boolean;
    cs: TCriticalSection;
    f: TFileStream;

    state: TTermState; // escape sequences state
    params: array of string; // escape sequences params
    attrib: TAttrib; // current character attribute
    csiQuery: Boolean;
    bLastAutoWrap: Boolean; // https://github.com/mattiase/wraptest

    mode: TTermMode;

    ui: HWND;

    scrollTop: Integer;
    scrollBottom: Integer;

    szTitle: string;
    szScreenTitle: string;
    bMouse: Boolean; // Report mouse events
    bAltScreen: Boolean; // Use altscreen buffer
    bAutoStart: Boolean;

    onAutoStart: TNotifyEvent;

    procedure setColumns(i: Integer);
    function GetLine(iLine: Integer): PLine;
    procedure advanceY();
    procedure Write(const sz: string; size: Integer = -1; color: Integer = 0);
    procedure lock();
    procedure unlock();
    constructor Create(iLines: Integer = 1000; iWidth: Integer = 80);
  end;

const
  WM_CONCLOSED = WM_USER + 1;
  WM_CONSETTITLE = WM_USER + 2;

type
  { TfrmConsole }

  TfrmConsole = class(TFrame)
    pb: TPaintBox;
    pnl: TPanel;
    scr: TScrollBar;
    tmr: TTimer;
    procedure pbClick(Sender: TObject);
    procedure pbMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure pbPaint(Sender: TObject);
    procedure pbResize(Sender: TObject);
    procedure pnlEnter(Sender: TObject);
    procedure pnlExit(Sender: TObject);
    procedure scrChange(Sender: TObject);
    procedure tmrTimer(Sender: TObject);
  private
    active: Boolean;
    lineHeight: Integer;
    bmp: TBitmap;
    charWidth: Integer;
    s: TRefStream;
    hReader: THandle;
    lastX: Integer;
    lastY: Integer;
    selStartX: Integer;
    selStartY: Integer;
    selEndX: Integer;
    selEndY: Integer;
    function reader(): Integer; stdcall;
    procedure onKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure conClosed(var msg: TMessage); message WM_CONCLOSED;
    procedure conSetTitle(var msg: TMessage); message WM_CONSETTITLE;
  protected
    procedure CreateWnd; override;
    procedure autoStart(Sender: TObject);
  public
    id: Integer;
    log: TLog;
    onConClosed: TNotifyEvent;
    onConTitle: TNotifyEvent;
    szAutoStart: string;
    procedure Write(sz: string; size: Integer = -1);
    function setPinned(bPinned: Boolean): Boolean;
    procedure SetLog(log: TLog);
    function getTitle(): string;
    function getScreenTitle(): string;
    procedure disconnect();
    procedure BeforeDestruction(); override;
    procedure setStream(s: TRefStream);
    constructor Create(AOwner: TComponent); override; overload;
    constructor Create(AOwner: TComponent; s: TRefStream; bAcceptInput: Boolean = False); overload;
  end;

implementation

var
  lineDrawing: array[0..255] of string;

{$R *.lfm}

procedure TLog.setColumns(i: Integer);
begin
  width := i;
  for i := 0 to Length(lines) - 1 do
  begin
    SetLength(lines[i].chars, width);
    SetLength(lines[i].attribs, width);
  end;
end;

function TLog.GetLine(iLine: Integer): PLine;
begin
  cs.Acquire;
  try
    if iLine >= Length(lines) then
      Result := nil else
    begin
      iLine := (iLine + offsetY) mod Length(lines);
      Result := @lines[iLine];
    end;
  finally
    cs.Release;
  end;
end;

procedure TLog.lock();
begin
  cs.Acquire;
end;

procedure TLog.unlock();
begin
  cs.Release;
end;

procedure TLog.advanceY();
var
  j: Integer;
  l: Integer;
begin
  Inc(iYWrite);
  if (iYWrite >= (pageTop + screenHeight) mod nLines) then
  begin
    if (bAltScreen) then
    begin
      // scroll down
      j := pageTop;
      while j < pageTop + screenHeight do
      begin
        Move(lines[j + 1].chars[0], lines[j].chars[0], width * SizeOf(lines[j].chars[0]));
        Move(lines[j + 1].attribs[0], lines[j].attribs[0], width * SizeOf(lines[j].attribs[0]));
        for l := 0 to Length(lines[j].attribs) - 1 do
          lines[j].attribs[l].style := lines[j].attribs[l].style and (not 2);
        Inc(j);
      end;
      Dec(iYWrite);
    end else
    begin
      pageTop := iYWrite;
      if pageTop = nLines then
        pageTop := 0;
    end;
  end;
  if iYWrite = offsetY then
  begin
    if (offsetY = Length(lines)) then offsetY := 1 else
      Inc(offsetY);
    fullRepaint := True;
    FillDWord(lines[offsetY - 1].chars[0], Length(lines[offsetY - 1].chars), 32);
    FillDWord(lines[offsetY - 1].attribs[0], Length(lines[offsetY - 1].attribs), 0);
  end;
  if iYWrite = nLines then
  begin
    iYWrite := 0;
  end;
  if iYWrite > iCount then
  begin
    iCount := (iCount + 1);
    if (iCount >= nLines) then
    begin
      iCount := nLines;
    end else
    if iCount >= screenHeight then
    begin
      iScroll := iScroll + 1;
    end;
    FillDWord(lines[iYWrite].chars[0], Length(lines[iYWrite].chars), 32);
    FillDWord(lines[iYWrite].attribs[0], Length(lines[iYWrite].attribs), 0);
  end;
  lines[iYWrite].date := date;
end;

procedure TLog.Write(const sz: string; size: Integer = -1; color: Integer = 0);
var
  i: Integer;
  j: Integer;
  k: Integer;
  l: Integer;
  c: Char;
  date: TDateTime;
procedure processCSI_Lm();
var
  code: Integer;
  i: Integer;
begin
  try
    for i := 0 to Length(params) - 1 do
    begin
      if params[i] = '' then code := 0 else
        code := StrToInt(params[i]);
      if code = 1 then attrib.style := attrib.style or ATTRIB_BOLD else
      if code = 7 then attrib.style := attrib.style or ATTRIB_INVERSE else
      if code = 27 then attrib.style := attrib.style and (not ATTRIB_INVERSE) else
      if code = 4 then attrib.style := attrib.style or ATTRIB_UNDERLINE else
      if code = 24 then attrib.style := attrib.style and (not ATTRIB_UNDERLINE) else
      if code = 0 then
      begin
        attrib.style := 0;
        attrib.fg := 9;
        attrib.bg := 9;
      end else
      if (code >= 30) and (code <= 39) then
      begin
        attrib.fg := code - 30;
      end else
      if (code >= 40) and (code <= 49) then
      begin
        attrib.bg := code - 40;
      end else
      begin
        Writeln('CSI m ', code, ' not processed');
      end;
    end;
  except
    on E: Exception do
    begin
      System.Write('Error processing CSI [m]');
      for i := 0 to Length(params) - 1 do System.Write(' [', params[i], ']');
      Writeln('');
    end;
  end;
end;
procedure DumpCmd(szDesc: string; c: Char);
var
  i: Integer;
begin
  System.Write(szDesc, ' [', c, '] not processed');
  for i := 0 to Length(params) - 1 do System.Write(' [', params[i], ']');
  Writeln('');
end;
procedure DumpCSI(c: Char);
begin
  DumpCmd('CSI', c);
end;
begin
  cs.Acquire;
  try
    //if iCount < screenHeight - 1 then iCount := screenHeight - 1;
    if f <> nil then f.Write(sz[1], size);
    Changed := True;
    date := Now();
    lines[iYWrite].date := date;
    //lines[iYWrite].color := color;
    if size = -1 then size := Length(sz);
    for i := 1 to size do
    begin
      c := sz[i];
      if state = STATE_NONE then
      begin
        if c = #$1B then
        begin
          state := STATE_ESC;
          Continue;
        end;
      end else
      if state = STATE_ESC then
      begin
        if c = '[' then
        begin
          state := STATE_CSI;
          SetLength(params, 0);
          SetLength(params, 1);
          Continue;
        end;
        if c = ']' then
        begin
          state := STATE_OSC;
          SetLength(params, 0);
          SetLength(params, 1);
          Continue;
        end;
        if c = '(' then
        begin
          state := STATE_CSSEL;
          Continue;
        end;
        if c = '>' then
        begin
          mode := MODE_NUMPAD;
          //Writeln('Mode numpad');
        end else
        if c = '=' then
        begin
          mode := MODE_APPLICATION;
          //Writeln('Mode app');
        end else
        if c = 'M' then // (RI) Moves cursor up one line in same column. If cursor is at top margin, screen performs a scroll down.
        begin
          if iYWrite = pageTop then
          begin
            //Writeln('scroll up');
            j := pageTop + screenHeight - 1;
            while j >= iYWrite do
            begin
              for l := 0 to Length(lines[j].attribs) - 1 do
                lines[j].attribs[l].style := lines[j].attribs[l].style and (not 2);
              Move(lines[j].chars[0], lines[j + 1].chars[0], width * SizeOf(lines[j].chars[0]));
              Move(lines[j].attribs[0], lines[j + 1].attribs[0], width * SizeOf(lines[j].attribs[0]));
              Dec(j);
            end;
            j := iYWrite;
            FillDWord(lines[j].chars[0], Length(lines[j].chars), 32);
            FillDWord(lines[j].attribs[0], Length(lines[j].attribs), DWord(attrib));
          end else
          begin
            iYWrite := iYWrite - 1;
          end;
        end else
        if c = '7' then // Save Cursor (DECSC), VT100.
        begin
          //Writeln('DECSC');
        end else
        if c = '8' then // Restore Cursor (DECRC), VT100.
        begin
          //Writeln('DECRC');
        end else
        if c = 'k' then // Screen title set
        begin
          state := STATE_SCRTITLE;
          SetLength(params, 0);
          SetLength(params, 1);
          Continue;
        end else
        begin
          System.Write('Unhandled esc ', Byte(c));
          if c > #$20 then System.Write(' [', c, ']');
          Writeln('');
        end;
        state := STATE_NONE;
        Continue;
      end else
      if state = STATE_CSSEL then // Charset select
      begin
        //Writeln('CSSEL ', c);
        attrib.charset := Byte(c);
        state := STATE_NONE;
        Continue;
      end else
      if state = STATE_CSI then
      begin
        if (c >= #$40) and (c <= #$7E) then // Dispatch
        begin
          try
            if csiQuery then
            begin
              if (
                (c = 'l') or // reset
                (c = 'h') or // set
                (c = 's') or // save
                (c = 'r') // restore
                ) and (Length(params) = 1) then
              begin
                csiQuery := False;
                state := STATE_NONE;
                repeat
                  if params[0] = '1049' then
                  begin
                    // Save cursor as in DECSC and use Alternate Screen Buffer,
                    // clearing it first (unless disabled by the titeInhibit resource). This combines the effects of the 1 0 4 7 and 1 0 4 8 modes. Use this with terminfo-based applications rather than the 4 7 mode.
                    if (c = 'h') then
                    begin
                      bAltScreen := True;
                      iYWrite := (iCount + offsetY) mod nLines;
                      pageTop := iYWrite;
                      //Writeln('Alt screen');
                    end else
                    begin
                      bAltScreen := False;
                      //Writeln('Norm screen');
                    end;
                    Break;
                  end;
                  if params[0] = '2004' then // Set bracketed paste mode.
                  begin
                    Break;
                  end;
                  if params[0] = '1002' then // Use Cell Motion Mouse Tracking
                  begin
                    Break;
                  end;
                  if params[0] = '1001' then // Use Hilite Mouse Tracking
                  begin
                    Break;
                  end else
                  if params[0] = '1006' then // Set Decimal Mouse Tracking Mode
                  begin
                    if c = 'h' then bMouse := True else
                    if c = 'l' then bMouse := False;
                    Break;
                  end else
                  if params[0] = '47' then // Use Normal Screen Buffer, xterm
                  begin
                    Break;
                  end else
                  if params[0] = '1' then // Application Cursor Keys (DECCKM)
                  begin
                    Break
                  end;
                  if params[0] = '12' then // Start/stop blinking cursor (AT&T 610).
                  begin
                    Break;
                  end;
                  if params[0] = '25' then // Show / Hide cursor (DECTCEM), VT220.
                  begin
                    Break;
                  end;
                  DumpCmd('CSI?', c);
                until True;
                Continue;
              end;
              Writeln('Inquiry');
              DumpCSI(c);
              csiQuery := False;
              state := STATE_NONE;
              Continue;
            end;
            repeat
              if (c = 'l') then // Reset Mode (RM)
              begin
                for j := 0 to Length(params) - 1 do
                begin
                  if (params[j] = '4') then // Replace Mode (IRM)
                  begin
                    //Break;
                  end else
                    DumpCSI(c);
                end;
                Break;
              end;
              if (c = '@') and (Length(params) = 1) then // Insert Ps (Blank) Character(s) (default = 1) (ICH).
              begin
                k := 1;
                if params[0] <> '' then k := StrToInt(params[0]);
                j := Length(lines[iYWrite].chars) - 1;
                while j >= iXWrite do
                begin
                  if j >= iXWrite + k then
                  begin
                    lines[iYWrite].chars[j] := lines[iYWrite].chars[j - k];
                    lines[iYWrite].attribs[j] := lines[iYWrite].attribs[j - k];
                    lines[iYWrite].attribs[j].style := lines[iYWrite].attribs[j].style and (not 2);
                  end else
                  begin
                    lines[iYWrite].chars[j] := 32;
                    lines[iYWrite].attribs[j] := attrib;
                  end;
                  Dec(j);
                end;
                Break;
              end else
              if (c = 'P') and (Length(params) = 1) then // Delete Ps Character(s) (default = 1) (DCH).
              begin
                k := 1;
                if params[0] <> '' then k := StrToInt(params[0]);
                j := iXWrite;
                while j <= Length(lines[iYWrite].chars) - 1 do
                begin
                  if j + k <= Length(lines[iYWrite].chars) - 1 then
                  begin
                    lines[iYWrite].chars[j] := lines[iYWrite].chars[j + k];
                    lines[iYWrite].attribs[j] := lines[iYWrite].attribs[j + k];
                    lines[iYWrite].attribs[j].style := lines[iYWrite].attribs[j].style and (not 2);
                  end else
                  begin
                    lines[iYWrite].chars[j] := 32;
                    lines[iYWrite].attribs[j] := attrib;
                  end;
                  Inc(j);
                end;
                Break;
              end;
              if (c = 'A') and (Length(params) = 1) then // Cursor Up Ps Times (default = 1) (CUU).
              begin
                k := 1;
                if params[0] <> '' then k := StrToInt(params[0]);
                iYWrite := iYWrite - k;
                Break;
              end;
              if (c = 'B') and (Length(params) = 1) then // Cursor Down Ps Times (default = 1) (CUD).
              begin
                k := 1;
                if params[0] <> '' then k := StrToInt(params[0]);
                iYWrite := iYWrite + k;
                Break;
              end;
              if (c = 'M') and (Length(params) = 1) then // Delete Ps Line(s) (default = 1) (DL)
              begin
                j := iYWrite;
                k := 1;
                if params[0] <> '' then k := StrToint(params[0]);
                while (j <= scrollBottom) do
                begin
                  if j + k <= scrollBottom then
                  begin
                    Move(lines[j + k].chars[0], lines[j].chars[0], Length(lines[j].chars) * SizeOf(lines[j].chars[0]));
                    Move(lines[j + k].attribs[0], lines[j].attribs[0], Length(lines[j].attribs) * SizeOf(lines[j].attribs[0]));
                    for l := 0 to Length(lines[j].attribs) - 1 do
                      lines[j].attribs[l].style := lines[j].attribs[l].style and (not 2);
                  end else
                  begin
                    FillDWord(lines[j].chars[0], Length(lines[j].chars), 32);
                    FillDWord(lines[j].attribs[0], Length(lines[j].attribs), DWord(attrib));
                  end;
                  Inc(j);
                end;
                Break;
              end;
              if (c = 'L') and (Length(params) = 1) then // Insert Ps Line(s) (default = 1) (IL)
              begin
                j := scrollBottom;
                k := 1;
                if params[0] <> '' then k := StrToint(params[0]);
                while (j >= iYWrite) do
                begin
                  if j - k >= iYWrite then
                  begin
                    Move(lines[j - k].chars[0], lines[j].chars[0], Length(lines[j].chars) * SizeOf(lines[j].chars[0]));
                    Move(lines[j - k].attribs[0], lines[j].attribs[0], Length(lines[j].attribs) * SizeOf(lines[j].attribs[0]));
                    for l := 0 to Length(lines[j].attribs) - 1 do
                      lines[j].attribs[l].style := lines[j].attribs[l].style and (not 2);
                  end else
                  begin
                    FillDWord(lines[j].chars[0], Length(lines[j].chars), 32);
                    FillDWord(lines[j].attribs[0], Length(lines[j].attribs), DWord(attrib));
                  end;
                  Dec(j);
                end;
                Break;
              end;
              if c = 'm' then
              begin
                processCSI_Lm();
                Break;
              end;
              if c = 'J' then
              begin
                if (params[0] = '') or (params[0] = '0') then
                begin
                  Writeln('Erase below ', iYWrite, ' ', pageTop, ' ', screenHeight);
                end else
                if params[0] = '2' then
                begin
                  iYWrite := (iCount + offsetY) mod nLines;
                  pageTop := iYWrite;
                  for k := 0 to screenHeight - 2 do advanceY();
                  iYWrite := iYWrite - screenHeight + 1;
                end else DumpCSI(c);
                Break;
              end;
              if c = 'X' then // Erase Ps Character(s) (default = 1) (ECH).
              begin
                // This control function erases one or more characters,
                // from the cursor position to the right. ECH clears
                // character attributes from erased character positions.
                // ECH works inside or outside the scrolling margins.
                Break;
              end;
              if c = 't' then
              begin
                repeat
                  if (params[0] = '22') and (Length(params) > 1) then
                  begin
                    if (params[1] = '0') or (params[1] = '1') or (params[1] = '2') then // Save current title on the stack
                    begin
                      Break;
                    end;
                  end;
                  if (params[0] = '23') and (Length(params) > 1) then
                  begin
                    if (params[1] = '0') or (params[1] = '1') or (params[1] = '2') then // Restore current title from the stack
                    begin
                      Break;
                    end;
                  end;
                  DumpCSI(c);
                until True;
                Break;
              end;
              if (c = 'r') and (Length(params) = 2) then
              begin
                repeat
                  if (params[0] <> '') and (params[1] <> '') then // Set scrolling region [top, bottom]
                  begin
                    scrollTop := iCount - screenHeight + StrToInt(params[0]);
                    scrollBottom := iCount - screenHeight + StrToInt(params[1]);
                    scrollTop := Max(0, Min(iCount, scrollTop));
                    scrollBottom := Max(0, Min(iCount, scrollBottom));
                    Break;
                  end;
                  DumpCSI(c);
                until True;
                Break;
              end;
              if (c = 'G') and (Length(params) = 1) then // Cursor Character Absolute [column] (default = [row,1]) (CHA)
              begin
                if params[0] = '' then iXWrite := 0 else
                  iXWrite := StrToInt(params[0]) - 1;
                Break;
              end;
              if (c = 'K') and (Length(params) = 1) then // Erase in Line (EL)
              begin
                repeat
                  if (params[0] = '') or (params[0] = '0') then // Erase to Right (default)
                  begin
                    FillDword(lines[iYWrite].chars[iXWrite], Length(lines[iYWrite].chars) - iXWrite, 32);
                    FillDword(lines[iYWrite].attribs[iXWrite], Length(lines[iYWrite].attribs) - iXWrite, PDWord(@attrib)^);
                    Break;
                  end;
                  if (params[0] = '1') then // Erase to Left
                  begin
                    FillDword(lines[iYWrite].chars[0], iXWrite, 32);
                    FillDword(lines[iYWrite].attribs[0], iXWrite, PDWord(@attrib)^);
                    Break;
                  end;
                  if (params[0] = '2') then // Erase All
                  begin
                    FillDword(lines[iYWrite].chars[0], Length(lines[iYWrite].chars), 32);
                    FillDword(lines[iYWrite].attribs[0], Length(lines[iYWrite].attribs), PDWord(@attrib)^);
                    Break;
                  end;
                  bLastAutoWrap := False;
                  DumpCSI(c);
                until True;
                Break;
              end else
              if (c = 'C') and (Length(params) = 1) then // Cursor forward N times
              begin
                if params[0] = '' then iXWrite := iXWrite + 1 else
                  iXWrite := iXWrite + StrToInt(params[0]);
                Break;
              end else
              if (c = 'H') then
              begin
                iYWrite := pageTop - 1;
                if (params[0] = '') then
                  iYWrite := iYWrite + 1 else
                  iYWrite := iYWrite + StrToInt(params[0]);
                if (Length(params) <> 2) or (params[1] = '') then iXWrite := 0 else
                  iXWrite := StrToInt(params[1]) - 1;
                bLastAutoWrap := False;
                Break;
              end;
              DumpCSI(c);
            until True;
          except
            on E: Exception do
            begin
              Writeln('Error ' + E.Message);
              Writeln('While processing CSI');
              DumpCSI(c);
            end;
          end;

          if iYWrite < 0 then
            iYWrite := 0 else
          if iYWrite >= Length(lines) then
            iYWrite := Length(lines) - 1;
          if iYWrite > (iCount + offsetY) mod nLines then
          begin
            iYWrite := (iCount + offsetY) mod nLines;
          end;

          if iXWrite < 0 then iXWrite := 0 else
          if iXWrite >= Length(lines[iYWrite].chars) then
            iXWrite := Length(lines[iYWrite].chars) - 1;

          state := STATE_NONE;
          Continue;
        end else
        if ((c >= #$30) and (c <= #$39)) or (c = #$3b) then
        begin
          if c = #$3B then
          begin
            SetLength(params, Length(params) + 1);
            Continue;
          end;
          params[Length(params) - 1] := params[Length(params) - 1] + c;
          Continue;
        end else
        if c = #$3F then
        begin
          csiQuery := True;
          Continue;
        end else
          DumpCSI(c);
        state := STATE_NONE;
      end else
      if state = STATE_SCRTITLE then
      begin
        if (c = #$1B) then
        begin
          szScreenTitle := params[0];
          if (ui <> 0) then PostMessage(ui, WM_CONSETTITLE, 0, 0);
          state := STATE_OSC_ESC;
        end else
          params[Length(params) - 1] := params[Length(params) - 1] + c;
        Continue;
      end else
      if state = STATE_OSC then
      begin
        if (c = #$07) or (c = #$1B) then
        begin
          if (c = #$07) then state := STATE_NONE else
          if (c = #$1B) then state := STATE_OSC_ESC;
          if Length(params) = 2 then
          begin
            szTitle := params[1];
            if (ui <> 0) then PostMessage(ui, WM_CONSETTITLE, 0, 0);
          end;
        end else
        begin
          if c = #$3B then
          begin
            SetLength(params, Length(params) + 1);
            Continue;
          end;
          params[Length(params) - 1] := params[Length(params) - 1] + c;
          Continue;
        end;
        Continue;
      end else
      if state = STATE_OSC_ESC then
      begin
        state := STATE_NONE;
        Continue;
      end;

      if (nChars <> 0) then
      begin
        if (Byte(c) and $C0 <> $80) then
        begin
          Writeln('Bad UTF seq ', Format('%.2X', [Byte(c)]));
          nChars := 0;
          Continue;
        end;
        Inc(nChar);
        dChar := dChar + (Byte(c) shl (nChar * 8));
        if nChar = nChars then
        begin
          nChars := 0;
        end else
          Continue;
      end else
      if (Byte(c) and $E0 = $C0) then
      begin
        nChar := 0;
        nChars := 1;
        dChar := Byte(c);
        Continue;
      end else
      if (Byte(c) and $F0 = $E0) then
      begin
        nChar := 0;
        nChars := 2;
        dChar := Byte(c);
        Continue;
      end else
      if (Byte(c) and $F8 = $F0) then
      begin
        nChar := 0;
        nChars := 3;
        dChar := Byte(c);
        Continue;
      end else
        dChar := Byte(c);

      if c = #$05 then
      begin
        Writeln('inquiry');
      end else
      if (c = #$07) then // Beep
      begin
      end else
      if (c = #$08) then
      begin
        if iXWrite = 0 then
        begin
          if iYWrite = 0 then Continue;
          //lines[iYWrite].chars[iXWrite] := 32;
          iXWrite := Length(lines[iYWrite].chars) - 1;
          iYWrite := iYWrite - 1;
        end else
        begin
          iXWrite := iXWrite - 1;
          //lines[iYWrite].chars[iXWrite] := 32;
        end;
      end else
      if (c = #$0D) then
      begin
        iXWrite := 0;
        bLastAutoWrap := False;
      end else
      if (c = #$0A) then
      begin
        if bAltScreen then
        begin
          {TODO: if at end of bottom margin - scroll up
          }
        end;
        if (bLastAutoWrap) then
        begin
          iXWrite := 0;
          bLastAutoWrap := False;
        end;
        advanceY();
        //iXWrite := 0;
      end else
      begin
        if bAutoStart and (c = '#') then
        begin
          bAutoStart := False;
          onAutoStart(Self);
        end;
        if (bLastAutoWrap) then
        begin
          iXWrite := 0;
          advanceY();
          bLastAutoWrap := False;
        end;
        lines[iYWrite].chars[iXWrite] := dChar;
        lines[iYWrite].attribs[iXWrite] := attrib;
        iXWrite := iXWrite + 1;
        if (iXWrite >= Length(lines[iYWrite].chars)) then
        begin
          bLastAutoWrap := True;
        end;
      end;
    end;
  finally
    cs.Release;
  end;
end;

constructor TLog.Create(iLines: Integer = 1000; iWidth: Integer = 80);
var
  i: Integer;
begin
  cs := TCriticalSection.Create;
  attrib.fg := 9;
  attrib.bg := 9;
  Changed := True;
  Self.nLines := iLines;
  offsetY := iLines;
  SetLength(lines, iLines);
  for i := 0 to iLines - 1 do
  begin
    SetLength(lines[i].chars, iWidth);
    SetLength(lines[i].attribs, iWidth);
  end;
  inherited Create;
end;

{ TfrmConsole }

procedure TfrmConsole.disconnect();
begin
  if s <> nil then
  begin
    s.close();
    if hReader <> 0 then
    begin
      WaitForSingleObject(hReader, INFINITE);
      CloseHandle(hReader);
    end;
  end;
end;

procedure TfrmConsole.BeforeDestruction();
begin
  disconnect();
  inherited BeforeDestruction();
end;

procedure TfrmConsole.setStream(s: TRefStream);
begin
  Self.s := s;
  if s <> nil then s.AddRef();
  if HandleAllocated then
    hReader := CreateThread(reader);
end;

constructor TfrmConsole.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  lastX := -1;
  selStartX := -1;
  bmp := TBitmap.Create;
  bmp.Width := pb.Width;
  bmp.Height := pb.Height;
  bmp.Canvas.Font.Name := 'Courier New';
  bmp.Canvas.Font.Size := 10;
  charWidth := bmp.Canvas.TextWidth('W');
  lineheight := 16;
  Name := 'con_' + IntToStr(QWord(Self));
  SetLog(TLog.Create());
  pb.ControlStyle := pb.ControlStyle + [csOpaque];
end;

constructor TfrmConsole.Create(AOwner: TComponent; s: TRefStream; bAcceptInput: Boolean = False);
begin
  Create(AOwner);
  setStream(s);
end;

procedure TfrmConsole.conClosed(var msg: TMessage);
begin
  if s <> nil then
  begin
    if (s.Release()) then
    begin
      if (Assigned(onConClosed)) then onConClosed(Self);
      s := nil;
    end;
  end;
end;

function TfrmConsole.getTitle(): string;
begin
  log.lock();
  try
    Result := log.szTitle;
  finally
    log.unlock();
  end;
end;

function TfrmConsole.getScreenTitle(): string;
begin
  log.lock();
  try
    Result := log.szScreenTitle;
  finally
    log.unlock();
  end;
end;

procedure TfrmConsole.conSetTitle(var msg: TMessage);
begin
  if Assigned(onConTitle) then onConTitle(Self);
end;

procedure TfrmConsole.onKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  wsz: WideString;
  keyState: array[0..255] of Byte;
  scan: DWord;
  r: Integer;
  bw: Cardinal;
  sz: string;
  szMod: string;
begin
  if (Key = VK_INSERT) and (ssShift in Shift) then
  begin
    if s = nil then Exit;
    sz := Clipboard.AsText;
    s.Write(sz[1], Length(sz));
    Exit;
  end;

  szMod := '';
  if ssShift in Shift then szMod := ';2';
  if (Key = VK_ESCAPE) then  sz := #$1B#$1B else
  if (Key = VK_UP) then      sz := #$1B'OA' else
  if (Key = VK_DOWN) then    sz := #$1B'OB' else
  if (Key = VK_RIGHT) then   sz := #$1B'OC' else
  if (Key = VK_LEFT) then    sz := #$1B'OD' else
  if (Key = VK_HOME) then    sz := #$1B'[1' + szMod + '~' else
  if (Key = VK_INSERT) then  sz := #$1B'[2' + szMod + '~' else
  if (Key = VK_DELETE) then  sz := #$1B'[3' + szMod + '~' else
  if (Key = VK_END) then     sz := #$1B'[4' + szMod + '~' else
  if (Key = VK_PRIOR) then   sz := #$1B'[5' + szMod + '~' else
  if (Key = VK_NEXT) then    sz := #$1B'[6' + szMod + '~' else
  if (Key = VK_F1) then      sz := #$1B'[11' + szMod + '~' else
  if (Key = VK_F2) then      sz := #$1B'[12' + szMod + '~' else
  if (Key = VK_F3) then      sz := #$1B'[13' + szMod + '~' else
  if (Key = VK_F4) then      sz := #$1B'[14' + szMod + '~' else
  if (Key = VK_F5) then      sz := #$1B'[15' + szMod + '~' else
  if (Key = VK_F6) then      sz := #$1B'[17' + szMod + '~' else
  if (Key = VK_F7) then      sz := #$1B'[18' + szMod + '~' else
  if (Key = VK_F8) then      sz := #$1B'[19' + szMod + '~' else
  if (Key = VK_F9) then      sz := #$1B'[20' + szMod + '~' else
  if (Key = VK_F10) then     sz := #$1B'[21' + szMod + '~' else
  if (Key = VK_F11) then     sz := #$1B'[23' + szMod + '~' else
  if (Key = VK_F12) then     sz := #$1B'[24' + szMod + '~' else
  begin
    scan := MapVirtualKey(Key, MAPVK_VK_TO_VSC);
    if scan = 0 then Exit;
    if not GetKeyboardState(@keyState[0]) then Exit;
    SetLength(wsz, 5);
    r := ToUnicode(Key, scan, @keyState[0], @wsz[1], Length(wsz), 0);
    if r <= 0 then Exit;
    sz := Copy(wsz, 1, r);
    if ssAlt in Shift then sz := #$1B + sz;
  end;
  if s <> nil then
  begin
    s.Write(sz[1], Length(sz));
  end;
  Key := 0;
end;

function TfrmConsole.reader(): Integer;
var
  sz: string;
  r: Integer;
begin
  try
    SetLength(sz, 1024);
    while True do
    begin
      r := s.Read(sz[1], 1024);
      Write(sz, r);
    end;
  except
    on E: Exception do
    begin
      Common.Log('console reader: ' + E.Message);
    end;
  end;
  PostMessage(log.ui, WM_CONCLOSED, 0, 0);
end;

function TfrmConsole.setPinned(bPinned: Boolean): Boolean;
var
  cmd: DWord;
begin
  Result := False;
  if (s <> nil) and (s is TTerminalStream) then
  begin
    TTerminalStream(s).setPinned(bPinned);
    Result := True;
  end;
end;

procedure TfrmConsole.Write(sz: string; size: Integer = -1);
begin
  log.cs.Acquire;
  try
    log.Write(sz, size);
  finally
    log.cs.Release;
  end;
  //pbPaint(pb);
end;

procedure TfrmConsole.autoStart(Sender: TObject);
begin
  if Length(szAutostart) > 0 then
  begin
    s.write(szAutoStart + #$0D);
  end;
end;

procedure TfrmConsole.CreateWnd;
begin
  inherited CreateWnd();
  log.lock;
  try
    log.ui := Handle;
    if (s <> nil) and (hReader = 0) then
    begin
      hReader := CreateThread(reader);
      pnl.OnKeyDown := onKeyDown;
    end;
  finally
    log.unlock;
  end;
end;

procedure TfrmConsole.SetLog(log: TLog);
begin
  Self.log := log;
  log.bAutoStart := True;
  log.onAutoStart := autoStart;
end;

procedure TfrmConsole.tmrTimer(Sender: TObject);
begin
  if log.Changed then
  begin
    pbPaint(pb);
  end;
end;

procedure TfrmConsole.pbPaint(Sender: TObject);
var
  c: TCanvas;
  y: Integer;
  sz: string;
  from: Integer;
  line: PLine;
  ch: DWord;
  utf: array [0..4] of Char;
  i: Integer;
  attrib: ^TAttrib;
  x: Integer;
  nDrawn: Integer;
  bActiveLine: Boolean;
begin
  nDrawn := 0;
  log.cs.Acquire;
  try
    FillChar(utf[0], 5, 0);
    if log.bMouse then pb.Cursor := crDefault else
      pb.Cursor := crIBeam;
    //Writeln('repaint ', IntToStr(IntPtr(Self)), isVisible());
    if not isVisible() then Exit;
    if bmp = nil then
    begin
      bmp := TBitmap.Create;
      bmp.Width := pb.Width;
      bmp.Height := pb.Height;
      bmp.Canvas.Font.Name := 'Courier New';
      bmp.Canvas.Font.Size := 10;
      charWidth := bmp.Canvas.TextWidth('W');
    end;

    if not log.Changed then
    begin
      pb.Canvas.Draw(0, 0, bmp);
      Exit;
    end;
    if scr.Max <> log.iCount then
    begin
      if (scr.Position + scr.PageSize >= scr.Max) then
      begin
        scr.Max := log.iCount;
        scr.Position := Max(0, log.iCount - log.screenHeight + 1);
      end else
      begin
        scr.Max := log.iCount;
      end;
    end;
    c := bmp.Canvas;
    c.Brush.Color := clBlack;
    //c.Brush.Style := bsSolid;
    //c.Rectangle(0, 0, pb.Width, pb.Height);
    try
      from := scr.Position;
      y := 5;
      while y + lineHeight <= pb.Height - 5 do
      begin
        line := log.GetLine(from);
        bActiveLine := False;
        if from - (log.nLines - log.offsetY) = log.iYWrite then
        begin
          bActiveLine := True;
        end;
        if line = nil then Break;
        sz := '';
        x := 5 - charWidth;
        for i := 0 to Length(line.chars) - 1 do
        begin
          x := x + charWidth;
          ch := line.chars[i];
          if ch = $00 then ch := $20;
          attrib := @line.attribs[i];
          {if (attrib.style and ATTRIB_INVERSE) <> 0 then
          begin
            if (attrib.style and ATTRIB_BOLD) <> 0 then
              c.Font.Color := fgcolor8b[attrib.bg] else
              c.Font.Color := fgcolor8[attrib.bg];
          end else}
          begin
            if (attrib.style and ATTRIB_BOLD) <> 0 then
              c.Font.Color := fgcolor8b[attrib.fg] else
              c.Font.Color := fgcolor8[attrib.fg];
          end;
          if (attrib.style and ATTRIB_INVERSE) <> 0 then
            c.Font.Color := not c.Font.Color;
          if (attrib.style and ATTRIB_UNDERLINE) <> 0 then
            c.Font.Style := [fsUnderline] else
            c.Font.Style := [];
          if (bActiveLine) and (i = log.iXWrite) then
          begin
            c.Brush.Style := bsSolid;
            if active then
            begin
              c.Brush.Color := clLime;
              c.Font.Color := clBlack;
            end else
            begin
              {if (attrib.style and ATTRIB_INVERSE) <> 0 then
              begin
                if (attrib.style and ATTRIB_BOLD) <> 0 then
                  c.Brush.Color := fgcolor8b[attrib.fg] else
                  c.Brush.Color := fgcolor8[attrib.fg];
              end else}
              begin
                c.Brush.Color := bgcolor8[attrib.bg];
              end;
              if (attrib.style and ATTRIB_INVERSE) <> 0 then
                c.Brush.Color := not c.Brush.Color;
            end;
            // Cursor
            c.Pen.Style := psSolid;
            c.Pen.Color := clLime;
            c.Rectangle(
              x, y,
              x + charWidth, y + lineheight);
            c.Pen.Color := clBlack;
            attrib.style := attrib.style and (not 2);
          end else
          begin
            if ((not log.fullRepaint) and ((attrib.style and 2) = 2)) then Continue;
            c.Brush.Style := bsSolid;
            if (attrib.style and 4) <> 0 then
            begin
              if (attrib.style and 1) <> 0 then
                c.Brush.Color := fgcolor8b[attrib.fg] else
                c.Brush.Color := fgcolor8[attrib.fg];
            end else
            begin
              c.Brush.Color := bgcolor8[attrib.bg];
            end;
            c.FillRect(x, y,
              x + charWidth,
              y + lineHeight);
            attrib.style := attrib.style or 2; // drawn
          end;

          c.Brush.Style := bsClear;
          if ch > 255 then
          begin
            Move(ch, utf[0], 4);
            c.TextOut(x, y, PChar(@utf[0]));
          end else
          if attrib.charset = $30 then // '0'
          begin
            c.TextOut(x, y, lineDrawing[ch]);
          end else
          begin
            c.TextOut(x, y, Char(ch));
          end;
          Inc(nDrawn);
        end;
        y := y + lineheight;
        from := from + 1;
      end;

      c.Brush.Style := bsClear;
      c.Rectangle(0, 0, pb.Width, pb.Height);
    finally
      pb.Canvas.Draw(0, 0, bmp);
      log.Changed := False;
    end;
  finally
    log.cs.Release;
  end;
  log.fullRepaint := False;
  //Writeln('Drew: ', nDrawn, ' chars');
end;

procedure TfrmConsole.pbMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  NewScrollPos: Integer;
  sz: string;
  x: Integer;
  y: Integer;
begin
  Handled := False;
  if (s <> nil) and active and log.bMouse then
  begin
    x := MousePos.X;
    y := MousePos.Y;
    if (x < 5) or (x > pb.Width - 5) then Exit;
    if (y < 5) or (y > pb.Height - 5) then Exit;
    x := ((x - 5) div charWidth) + 1;
    y := ((y - 5) div lineHeight) + 1;
    if WheelDelta > 0 then
      sz := #$1B'[<64;' + IntToStr(x) + ';' + IntToStr(y) + 'M' else
      sz := #$1B'[<65;' + IntToStr(x) + ';' + IntToStr(y) + 'M';
    s.Write(sz[1], Length(sz));
    Handled := True;
  end;
  if not Handled then
  begin
    if WheelDelta > 0 then
      NewScrollPos := scr.Position - scr.PageSize + 2
    else
      NewScrollPos := scr.Position + scr.PageSize - 2;
    scr.Position := Min(scr.Max - scr.PageSize + 1, NewScrollPos);
  end;
  Handled := True;
end;

procedure TfrmConsole.pbClick(Sender: TObject);
begin
  pnl.SetFocus;
end;

procedure TfrmConsole.pbMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  sz: string;
begin
  if (not active) then Exit;
  if (x < 5) or (x > pb.Width - 5) then Exit;
  if (y < 5) or (y > pb.Height - 5) then Exit;
  x := ((x - 5) div charWidth);
  y := ((y - 5) div lineHeight);
  lastX := x;
  lastY := y;
  if (not log.bMouse) then
  begin
    Inc(y, scr.Position);
    Writeln(x, ' ', y);
    Exit;
  end;
  if s = nil then Exit;
  Inc(x);
  Inc(y);
  sz := #$1B'[<';
  sz := sz + '0;';
  sz := sz + IntToStr(x) + ';';
  sz := sz + IntToStr(y);
  sz := sz + 'M';
  s.Write(sz[1], Length(sz));
end;

procedure TfrmConsole.pbMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
var
  sz: string;
begin
  if s = nil then Exit;
  if lastX = -1 then Exit;
  if (x < 5) or (x > pb.Width - 5) then Exit;
  if (y < 5) or (y > pb.Height - 5) then Exit;
  x := ((x - 5) div charWidth);
  y := ((y - 5) div lineHeight);
  if (lastX = x) and (lastY = y) then Exit;
  if not log.bMouse then
  begin
    if selStartX = - 1 then
    begin
      selStartX := lastX;
      selStartY := lastY;
      Inc(selStartY, scr.Position);
    end;
    lastX := x;
    lastY := y;
    Inc(y, scr.Position);

    selEndX := x;
    selEndY := y;
    Writeln(selStartX, 'x', selStartY, ' - ', selEndX, 'x', selEndY);
    Exit;
  end;
  lastX := x;
  lastY := y;
  Inc(x);
  Inc(y);
  sz := #$1B'[<';
  sz := sz + '32;';
  sz := sz + IntToStr(x) + ';';
  sz := sz + IntToStr(y);
  sz := sz + 'M';
  s.Write(sz[1], Length(sz));
end;

procedure TfrmConsole.pbMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  sz: string;
begin
  if lastX = -1 then Exit;
  if s = nil then Exit;
  if (x >= 5) and (x <= pb.Width - 5) and
    (y >= 5) and (y <= pb.Height - 5) then
  begin
    x := ((x - 5) div charWidth);
    y := ((y - 5) div lineHeight);
  end else
  begin
    X := lastX;
    Y := lastY;
  end;

  lastX := -1;
  lastY := -1;
  if not log.bMouse then
  begin
    Inc(Y, scr.Position);
    selEndX := X;
    selEndY := Y;
    Writeln(selStartX, 'x', selStartY, ' - ', selEndX, 'x', selEndY);
    Exit;
  end;

  Inc(X);
  Inc(Y);
  sz := #$1B'[<';
  sz := sz + '0;';
  sz := sz + IntToStr(x) + ';';
  sz := sz + IntToStr(y);
  sz := sz + 'm';
  s.Write(sz[1], Length(sz));
end;

procedure TfrmConsole.pbResize(Sender: TObject);
var
  oldScreenHeight: Integer;
begin
  log.lock();
  try
    log.Changed := True;
    log.fullRepaint := True;
    oldScreenHeight := log.screenHeight;
    log.screenHeight := (pb.Height - 10) div lineHeight;
    log.setColumns((pb.Width - 10) div charWidth);
    scr.PageSize := log.screenHeight;
    log.iScroll := Max(0, log.iScroll + oldScreenHeight - log.screenHeight);
    scr.Position := Max(0, scr.Position + oldScreenHeight - log.screenHeight);
    if (s <> nil) and (s is TTerminalStream) then
    begin
      TTerminalStream(s).setWinSize(log.screenHeight, log.width);
    end;
  finally
    log.unlock();
  end;

  bmp.Free;
  bmp := nil;
end;

procedure TfrmConsole.pnlEnter(Sender: TObject);
begin
  active := True;
  log.Changed := True;
end;

procedure TfrmConsole.pnlExit(Sender: TObject);
begin
  active := False;
  log.Changed := True;
end;

procedure TfrmConsole.scrChange(Sender: TObject);
begin
  log.fullRepaint := True;
  log.Changed := True;
  //Writeln(scr.Position, ' / ', scr.PageSize, ' / ', scr.Max);
end;

initialization
  lineDrawing[$71] := '─';
  lineDrawing[$74] := '├';
  lineDrawing[$75] := '┤';
  lineDrawing[$76] := '┴';
  lineDrawing[$77] := '┬';
  lineDrawing[$78] := '│';
  lineDrawing[$6a] := '┘';
  lineDrawing[$6b] := '┐';
  lineDrawing[$6c] := '┌';
  lineDrawing[$6d] := '└';

end.


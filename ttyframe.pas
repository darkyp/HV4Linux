unit ttyframe;

{$mode DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls, StdCtrls, ConsoleFrame,
  Common, Messages;

type

  { TfrmTTY }

  TfrmTTY = class(TFrame)
    btnClose: TButton;
    btnPin: TButton;
    chkLog: TCheckBox;
    lblLog: TLabel;
    lblCaption: TLabel;
    pnl: TPanel;
    procedure btnPinClick(Sender: TObject);
    procedure chkLogChange(Sender: TObject);
  private
    con: TfrmConsole;
  public
    bPinned: Boolean;
    bConnected: Boolean;
    onStateChanged: TNotifyEvent;
    onScreenTitle: TNotifyEvent;
    procedure conTitle(Sender: TObject);
    procedure setConsole(con: TfrmConsole);
    function getConsole(): TfrmConsole;
    procedure setPinned(bPinned: Boolean);
    procedure setConnected(bConnected: Boolean);
    constructor Create(AOwner: TComponent); override;
  end;

implementation

{$R *.lfm}

procedure TfrmTTY.btnPinClick(Sender: TObject);
begin
  if con <> nil then
  begin
    if con.setPinned(not bPinned) then
    begin
      setPinned(not bPinned);
    end;
  end;
end;

procedure TfrmTTY.chkLogChange(Sender: TObject);
begin
  if con <> nil then
  begin
    if con.log.f <> nil then
      FreeAndNil(con.log.f) else
      con.log.f := TFileStream.Create(AppPath + '\console.log', fmCreate);
  end;
end;

procedure TfrmTTY.setPinned(bPinned: Boolean);
begin
  Self.bPinned := bPinned;
  if bPinned then
    pnl.Color := $bb0000 else
    pnl.Color := $00bb00;
  if Assigned(onStateChanged) then onStateChanged(Self);
end;

procedure TfrmTTY.setConnected(bConnected: Boolean);
begin
  Self.bConnected := bConnected;
  if not bConnected then
  begin
    pnl.Color := $0000bb;
  end;
  if Assigned(onStateChanged) then onStateChanged(Self);
end;

procedure TfrmTTY.conTitle(Sender: TObject);
begin
  lblCaption.Caption := con.getTitle();
  if Assigned(onScreenTitle) then onScreenTitle(con);
end;

procedure TfrmTTY.setConsole(con: TfrmConsole);
begin
  Self.con := con;
  con.Parent := Self;
  con.Align := alClient;
  con.onConTitle := conTitle;
end;

function TfrmTTY.getConsole(): TfrmConsole;
begin
  Result := con;
end;

constructor TfrmTTY.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Name := 'tty_' + IntToStr(IntPtr(Self));
  pnl.Color := $00bb00;
  if IsConsole then
  begin
    chkLog.Visible := True;
    lblLog.Visible := True;
  end else
  begin
    chkLog.Visible := False;
    lblLog.Visible := False;
  end;
end;

end.


unit commoncontrols;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls;

type

  { TfrmCommon }

  TfrmCommon = class(TDataModule)
    il: TImageList;
  private

  public

  end;

var
  frmCommon: TfrmCommon;

implementation

{$R *.lfm}

end.


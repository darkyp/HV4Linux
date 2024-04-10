unit VHD;

{$mode Delphi}

interface

uses SysUtils, Common, Windows;

type
  TVHDCHS = packed record
    cyl: Word;
    heads: Byte;
    sec: Byte;
  end;

  TVHDFooter = packed record
    cookie: array[0..7] of Byte;
    features: DWord;
    fileFormatVersion: DWord;
    dataOffset: Int64;
    timeStamp: DWord;
    creatorApplication: DWord;
    creatorVersion: DWord;
    creatorHostOS: DWord;
    originalSize: Int64;
    currentSize: Int64;
    diskGeometry: TVHDCHS;
    diskType: DWord;
    checksum: DWord;
    uniqueId: TGUID;
    savedState: Byte;
    reserved: array[0..426] of Byte;
  end;

  TVHD = class
    class function getFooter(diskSize: Int64): TVHDFooter;
  end;

implementation

class function TVHD.getFooter(diskSize: Int64): TVHDFooter;
var
  vhdFooter: ^TVHDFooter;
  checksum: DWord;
  p: PByte;
  nSecs: Int64;
  cylHead: DWord;
  heads: DWord;
  i: Integer;
begin
  nSecs := diskSize div 512;
  vhdFooter := @Result;
  FillChar(vhdFooter^, SizeOf(vhdFooter^), 0);
  Move('conectix'[1], vhdFooter.cookie[0], 8);
  vhdFooter.features := $02000000;
  vhdFooter.fileFormatVersion := $00000100;
  vhdFooter.dataOffset := -1;
  //vhdFooter.timeStamp := 0;
  Move('hv4l'[1], vhdFooter.creatorApplication, 4);
  vhdFooter.creatorVersion := $01000000;
  vhdFooter.creatorHostOS := $6B326957;
  Reverse(vhdFooter.originalSize, diskSize, 8);
  vhdFooter.currentSize := vhdFooter.originalSize;

  if nSecs > 65535 * 16 * 255 then
    nSecs := 65535 * 16 * 255;
  if nSecs > 65535 * 16 * 63 then
  begin
    vhdFooter.diskGeometry.sec := 255;
    heads := 16;
    cylHead := nSecs div 255;
  end else
  begin
    vhdFooter.diskGeometry.sec := 17;
    cylHead := nSecs div 17;
    heads := (cylHead + 1023) div 1024;
    if (heads < 4) then heads := 4;
    if (cylHead >= heads * 1024) or (heads > 16) then
    begin
      vhdFooter.diskGeometry.sec := 31;
      heads := 16;
      cylHead := nSecs div 31;
    end;
    if (cylHead >= heads * 1024) then
    begin
      vhdFooter.diskGeometry.sec := 63;
      heads := 16;
      cylHead := nSecs div 63;
    end;
  end;
  vhdFooter.diskGeometry.heads := heads;
  vhdFooter.diskGeometry.cyl := Swap(Word(cylHead div 16));
  vhdFooter.diskType := $02000000;
  CreateGUID(vhdFooter.uniqueId);
  vhdFooter.savedState := 0;
  checksum := 0;
  p := Pointer(vhdFooter);
  for i := 0 to SizeOf(vhdFooter^) - 1 do
  begin
    checksum := checksum + p^;
    Inc(p);
  end;
  checksum := not checksum;
  Reverse(vhdFooter.checksum, checksum, 4);
end;

end.


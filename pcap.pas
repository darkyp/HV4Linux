unit pcap;

{$mode DELPHI}{$H+}

interface

uses Windows, Classes;

const
  wpcap = 'wpcap.dll';
  PCAP_ERRBUF_SIZE = 256;
  PCAP_CHAR_ENC_LOCAL = 0;

type
  TAdapter = class
    szName: string;
    szDesc: string;
    szPath: string;
    constructor Create(szName: string; szDesc: string; szPath: string);
  end;

type
  Ppcap_if = ^Tpcap_if;
  Tpcap_if = record
    next: Ppcap_if;
    name: PChar;
    description: PChar;
    addresses: Pointer;// pcap_addr
    flag: DWord;
  end;
  Tpcap = Pointer;
  Ppcap_pkthdr = ^Tpcap_pkthdr;
  Tpcap_pkthdr = record
    ts: Cardinal;
    ts1: Cardinal;
    caplen: Cardinal;
    len: Cardinal;
  end;

function pcap_init(opts: Integer; errbuf: Pointer): Integer; cdecl; external wpcap;
function pcap_findalldevs(var alldevsp: Ppcap_if; errbuf: Pointer): Integer; cdecl; external wpcap;
procedure pcap_freealldevs(alldevs: Ppcap_if); cdecl; external wpcap;
function pcap_create(source: PChar; errbuf: Pointer): Tpcap; cdecl; external wpcap;
procedure pcap_close(p: Tpcap); cdecl; external wpcap;
function pcap_set_promisc(p: Tpcap; promis: Integer): Integer; cdecl; external wpcap;
function pcap_activate(p: Tpcap): Integer; cdecl; external wpcap;
function pcap_next_ex(p: Tpcap; var pkt_header: Ppcap_pkthdr; var pkt_data: PChar): Integer; cdecl; external wpcap;
function pcap_set_timeout(p: Tpcap; to_ms: Integer): Integer; cdecl; external wpcap;
function pcap_inject(p: Tpcap; var buf; len: Integer): Integer; cdecl; external wpcap;
function pcap_set_immediate_mode(p: Tpcap; immediate_mode: Integer): Integer; cdecl; external wpcap;

var
  adapters: TThreadList;

implementation

constructor TAdapter.Create(szName: string; szDesc: string; szPath: string);
begin
  inherited Create();
  Self.szName := szName;
  Self.szDesc := szDesc;
  Self.szPath := szPath;
end;

initialization
  adapters := TThreadList.Create();

end.

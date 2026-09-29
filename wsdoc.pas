{ Reading WordStar (5.x-7.0) documents, shared by the Markdown / text and RTF writers.
  Follows "File Format for WordStar Release 7.0" (wsformat.txt): control codes, extended
  characters (1Bh xx 1Ch), symmetrical sequences (1Dh ... 1Dh), dot commands and the paragraph
  style library at the end of the file. }
unit wsdoc;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, wsutil;

const
  SEQ_FOOTNOTE = $03; SEQ_ENDNOTE = $04; SEQ_ANNOTATION = $05; SEQ_COMMENT = $06;
  SEQ_TAB = $09; SEQ_PAGE_END = $0B; SEQ_PARNUM = $0D; SEQ_INDEX = $0E;
  SEQ_GRAPHIC = $10; SEQ_STYLE = $11; SEQ_TRUNCATED = $16;

type
  TFileKind = (fkWs5, fkWs4, fkAscii);
  TTri = (tNone, tOff, tOn);           { a style attribute: not set, off, on }

  TStyle = record
    name: UStr;
    hasFont: Boolean;
    fontWidth, fontHeight, fontStyle: Integer;     { width 1/1800", height 1/1440", typestyle }
    hasLm, hasRm, hasPm: Boolean;
    lm, rm, pm: Integer;                           { 1/1800" }
    just: Char;                                    { 'j' justified, 'l', 'c', 'r'; #0 = not set }
    spacing: Integer;                              { 0 = not set }
    bold, italic, underline: TTri;
    color: Integer;                                { 0-15; -1 = not set }
  end;
  TStyles = array of TStyle;

function ReadSequence(const data: TData; i: SizeInt; out kind: Integer; out payload: TData;
                      out next: SizeInt): Boolean;
function ExtChar(b, cp: Integer): UStr;
function ReadStyles(const data: TData; cp: Integer; namesOnly: Boolean = False): TStyles;
function ParagraphNumber(const p: TData; compound: Boolean = True): UStr;
function FileKind(const data: TData): TFileKind;
function GuessDocCodepage(const data: TData; kind: TFileKind; codepage: Integer): Integer;

implementation

uses wsmerge;

function ReadSequence(const data: TData; i: SizeInt; out kind: Integer; out payload: TData;
                      out next: SizeInt): Boolean;
{ Symmetrical sequence starting at data[i] = 1Dh. Layout: 1Dh, count(2), type, payload...,
  count(2), 1Dh; count = total length - 3. False if the bytes don't form a valid sequence. }
var total, e: SizeInt;
begin
  Result := False;
  kind := 0;
  payload := '';
  next := i;
  if i + 3 >= Length(data) then Exit;
  total := W16(data, i + 1) + 3;
  e := i + total;
  if (total < 7) or (e > Length(data)) or (DB(data, e - 1) <> $1D)
     or (W16(data, e - 3) <> W16(data, i + 1)) then Exit;
  kind := DB(data, i + 3);
  payload := Slice(data, i + 4, e - 3);
  next := e;
  Result := True;
end;

const
  { codes 01h-1Fh as characters (an extended character 1Bh xx 1Ch, entered with ^P0) are the IBM
    glyphs WordStar shows }
  LOW_GLYPHS: UStr = #0'☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼';

function ExtChar(b, cp: Integer): UStr;
begin
  if (b > 0) and (b < $20) then Result := LOW_GLYPHS[b + 1]
  else Result := DecodeByte(b, cp);
end;

function ReadStyles(const data: TData; cp: Integer; namesOnly: Boolean): TStyles;
{ namesOnly: as read_style_names (a last entry cut off after its name still counts).
 Paragraph styles of the document's library, in index order. Tab stops are not read (their counts
  do not match the documented layout). }
var kind: Integer;
    p: TData;
    nx: SizeInt;
    lib, block, link, item, e: Int64;
    count, k, onb, offb: Integer;
    seen: array of Int64;
    st: TStyle;
    sane: Boolean;

  function Seen_(b: Int64): Boolean;
  var s: Int64;
  begin
    for s in seen do if s = b then Exit(True);
    Result := False;
  end;

  function WW(o: Int64): Integer;
  begin
    Result := W16(data, o);
  end;

begin
  Result := nil;
  if (DB(data, 0) <> $1D) or not ReadSequence(data, 0, kind, p, nx) or (kind <> 0) or (Length(p) < 16) then Exit;
  lib := W16(p, 12) or (Int64(W16(p, 14)) shl 16);
  if (lib = 0) or (lib + 13 > Length(data)) then Exit;
  seen := nil;
  block := lib + D32(data, lib + 9);
  while (block < Length(data)) and not Seen_(block) do
  begin
    SetLength(seen, Length(seen) + 1);
    seen[High(seen)] := block;
    count := DB(data, block);
    link := D32(data, block + 1);
    for k := 0 to count - 1 do
    begin
      item := block + 5 + k * 33;                  { 24 name + 1 + 2 + 2 + 4 pointer }
      if item + 24 > Length(data) then Exit;
      if not namesOnly and (item + 33 > Length(data)) then Exit;
      FillChar(st, SizeOf(st), 0);
      st.name := Strip(DecodeBytes(Slice(data, item, item + 24), cp));
      st.color := -1;
      if not namesOnly then
      begin
        e := lib + D32(data, item + 29);
        { free slots of the library hold leftovers (names like '????', font height 5, spacing 32):
          only entries with plausible values are read }
        sane := (e + 102 <= Length(data)) and ((WW(e) = $FFFF) or ((WW(e + 2) >= 60) and (WW(e + 2) <= 2000)))
                and ((DB(data, e + 90) = $FF) or ((DB(data, e + 90) >= 1) and (DB(data, e + 90) <= 9)));
        if sane then
        begin
          if WW(e) <> $FFFF then
          begin
            st.hasFont := True;
            st.fontWidth := WW(e); st.fontHeight := WW(e + 2); st.fontStyle := WW(e + 4);
          end;
          if WW(e + 10) < $FFFE then begin st.hasLm := True; st.lm := WW(e + 10); end;
          if WW(e + 12) < $FFFE then begin st.hasRm := True; st.rm := WW(e + 12); end;
          if WW(e + 14) < $FFFE then begin st.hasPm := True; st.pm := WW(e + 14); end;
          case DB(data, e + 86) of
            0: st.just := 'l';
            1: st.just := 'j';
            $FE: st.just := 'c';
            $FD: st.just := 'r';
          end;
          if DB(data, e + 90) <> $FF then st.spacing := DB(data, e + 90);
          onb := WW(e + 91);
          offb := WW(e + 93);
          { bit 01h (strikeout in the file format document) does not show in WordStar's printout
            (style H3 of Sawyer's NOVEL.WS has it and prints as plain Helvetica-Bold): not read }
          if onb and $40 <> 0 then st.bold := tOn else if offb and $40 <> 0 then st.bold := tOff;
          if onb and $80 <> 0 then st.italic := tOn else if offb and $80 <> 0 then st.italic := tOff;
          if onb and $08 <> 0 then st.underline := tOn else if offb and $08 <> 0 then st.underline := tOff;
          if DB(data, e + 95) < 16 then st.color := DB(data, e + 95);     { FFh = inherited }
        end;
      end;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := st;
    end;
    if link = 0 then Break;
    block := lib + link;
  end;
end;

function Roman(n: Integer): UStr;
const V: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
      L: array[0..12] of UStr = ('M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I');
var k: Integer;
begin
  Result := '';
  for k := 0 to 12 do
    while n >= V[k] do
    begin
      Result := Result + L[k];
      Dec(n, V[k]);
    end;
end;

function Letters(n: Integer): UStr;
{ 1 -> A, 26 -> Z, 27 -> AA }
var r: Integer;
begin
  Result := '';
  while n > 0 do
  begin
    r := (n - 1) mod 26;
    n := (n - 1) div 26;
    Result := WideChar(65 + r) + Result;
  end;
end;

function ParagraphNumber(const p: TData; compound: Boolean): UStr;
{ Paragraph outline number (sequence 0Dh) rendered with its format string. Format placeholders
  (from the WordStar help): 1 numerals from 1, 9 numerals from 0, Z / z upper / lower case letters,
  I / i upper / lower case roman numerals; other characters are separators. compound=False
  (.p# ...,o) shows only the last level. }
const PH = '19ZzIi';
var level, k, j: Integer;
    values: array[0..7] of Integer;
    fmt: UStr;
    kinds: array of WideChar;
    seps: TUStrArray;

  function Render(k: Integer): UStr;
  var t: Integer;
      sep, text: UStr;
      v: Integer;
  begin
    t := k;
    if t > High(kinds) then t := High(kinds);
    sep := seps[t];
    v := values[k];
    case kinds[t] of
      '1': text := UStr(IntToStr(v + 1));
      '9': text := UStr(IntToStr(v));
      'Z': text := Letters(v + 1);
      'z': text := Lower(Letters(v + 1));
      'I': text := Roman(v + 1);
    else text := Lower(Roman(v + 1));
    end;
    if (k >= Length(kinds) - 1) and (sep = '') and (k < level - 1) then sep := '.';  { format shorter than the level depth }
    Result := text + sep;
  end;

begin
  if Length(p) < 19 then Exit('');
  level := DB(p, 2);
  if level > 8 then level := 8;
  if level < 1 then level := 1;
  for k := 0 to level - 1 do values[k] := W16(p, 3 + 2 * k);
  fmt := DecodeBytes(UntilZero(Slice(p, 19, 50)), 437);
  if fmt = '' then fmt := RepeatStr('1.', 8);
  kinds := nil;
  seps := nil;
  k := 1;
  while k <= Length(fmt) do
  begin
    if CharIn(fmt[k], PH) then
    begin
      j := k + 1;
      while (j <= Length(fmt)) and not CharIn(fmt[j], PH) do Inc(j);
      SetLength(kinds, Length(kinds) + 1);
      kinds[High(kinds)] := fmt[k];
      Append(seps, Copy(fmt, k + 1, j - k - 1));
      k := j;
    end
    else Inc(k);
  end;
  if Length(kinds) = 0 then
  begin
    SetLength(kinds, 1);
    kinds[0] := '1';
    Append(seps, '.');
  end;
  if not compound then Exit(Render(level - 1));
  Result := '';
  for k := 0 to level - 1 do Result := Result + Render(k);
  if not (EndsWith(fmt, '.') or EndsWith(fmt, ')')) then Result := RStripChars(Result, '.');
end;

function FileKind(const data: TData): TFileKind;
{ fkWs5 (WordStar 5-7 document: header sequence), fkWs4 (WordStar 3-4 document: soft returns,
  high bit used for formatting) or fkAscii (nondocument / plain text: high bytes are characters) }
var kind: Integer;
    p: TData;
    nx: SizeInt;
begin
  if (DB(data, 0) = $1D) and ReadSequence(data, 0, kind, p, nx) and (kind = 0) then Exit(fkWs5);
  if Pos(#$8D#10, data) > 0 then Result := fkWs4 else Result := fkAscii;
end;

function GuessDocCodepage(const data: TData; kind: TFileKind; codepage: Integer): Integer;
{ as given; WordStar 3-4 use the high bit for formatting, so their text can only be guessed as cp437 }
begin
  if codepage <> 0 then Result := codepage
  else if kind = fkWs4 then Result := 437
  else Result := GuessCodepage(data, kind = fkWs5);
end;

end.

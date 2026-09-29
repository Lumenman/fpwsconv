{ Helpers for wsconv: file data access, DOS code pages, Python-like string functions,
  regular expressions and exact number formatting (the converter was first written in Python;
  outputs are checked against it by compare.py). }
unit wsutil;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, Math, uregexpr;

type
  TData = RawByteString;               { file bytes; indexes below are 0-based as in the Python version }
  UStr = UnicodeString;
  TUStrArray = array of UStr;

{ ---- bytes }
function DB(const d: TData; i: SizeInt): Integer; inline;      { byte at i, -1 past the end }
function W16(const d: TData; i: SizeInt): Integer;
function D32(const d: TData; i: SizeInt): Int64;
function Slice(const d: TData; a, b: SizeInt): TData;           { d[a:b] }
function ReadFileData(const path: string; out d: TData): Boolean;
function UntilZero(const d: TData): TData;                      { d.split(b'\0', 1)[0] }

{ ---- code pages: cp is a number (437, 866, 1125 ...), 0 = none }
function KnownCodepage(cp: Integer): Boolean;
function DecodeByte(b: Integer; cp: Integer): WideChar;
function DecodeBytes(const s: TData; cp: Integer): UStr;

{ ---- strings as in Python }
function IsSpace(c: WideChar): Boolean;
function IsDigit(c: WideChar): Boolean;
function Strip(const s: UStr): UStr;
function LStrip(const s: UStr): UStr;
function RStrip(const s: UStr): UStr;
function StripChars(const s, chars: UStr): UStr;
function LStripChars(const s, chars: UStr): UStr;
function RStripChars(const s, chars: UStr): UStr;
function SplitWS(const s: UStr): TUStrArray;                     { s.split() }
function SplitStr(const s, sep: UStr): TUStrArray;               { s.split(sep) }
function JoinStr(const a: TUStrArray; const sep: UStr): UStr;
function Lower(const s: UStr): UStr;
function Upper(const s: UStr): UStr;
function Replace(const s, a, b: UStr): UStr;
function StartsWith(const s, prefix: UStr): Boolean;
function EndsWith(const s, suffix: UStr): Boolean;
function Partition(const s, sep: UStr; out before, after: UStr): Boolean;
function RepeatStr(const s: UStr; n: Integer): UStr;
function Contains(const s, sub: UStr): Boolean;
function CharIn(c: WideChar; const chars: UStr): Boolean;
procedure Append(var a: TUStrArray; const s: UStr);
function U8(const s: UStr): RawByteString;                       { UTF-8 bytes }

{ ---- regular expressions (TRegExpr; patterns compiled once and cached) }
function Rx(const pattern: UStr): TRegExpr;
function ReMatch(const pattern, s: UStr): TRegExpr;              { anchored at start (re.match); nil if none }
function ReFull(const pattern, s: UStr): TRegExpr;               { re.fullmatch; nil if none }
function ReSearch(const pattern, s: UStr): TRegExpr;             { re.search; nil if none }
function Group(r: TRegExpr; n: Integer): UStr;                   { '' if the group did not take part }
function HasGroup(r: TRegExpr; n: Integer): Boolean;
function ReSplit(const pattern, s: UStr; maxsplit: Integer = 0): TUStrArray;   { no capture groups }
function ReSubStr(const pattern, s, repl: UStr): UStr;            { repl may use $1 .. $9 }
function CollapseNewlines(const s: UStr): UStr;                  { runs of 3+ newlines -> 2 }

{ ---- files }
function FindFileCI(const baseDir, name: string): string;        { '' if absent }
function ListDir(const folder: string): TStringList;             { names, sorted by code point }
function JoinPath(const a, b: string): string;

{ ---- numbers as Python formats them }
function FmtG(x: Double; prec: Integer): string;                 { '%.<prec>g' }
function FmtE(x: Double; prec: Integer; upper: Boolean): string; { '%.<prec>e' / E }
function FmtF(x: Double; prec: Integer): string;                 { '%.<prec>f' }
function FixedHalfUp(x: Double; decimals: Integer; grouping: Boolean): string;   { str(Decimal(repr(x)).quantize(ROUND_HALF_UP)) }
function ParsePyFloat(const s: UStr; out v: Double): Boolean;    { float(s) }
function IntStr(v: Double): string;                              { str(int(v)) for |v| < 1e15 }

implementation

{$I cptables.inc}

{ ---------------------------------------------------------------- bytes }

function DB(const d: TData; i: SizeInt): Integer; inline;
begin
  if (i >= 0) and (i < Length(d)) then Result := Ord(d[i + 1]) else Result := -1;
end;

function W16(const d: TData; i: SizeInt): Integer;
begin
  Result := 0;
  if (i >= 0) and (i + 1 < Length(d)) then Result := Ord(d[i + 1]) or Ord(d[i + 2]) shl 8
  else if (i >= 0) and (i < Length(d)) then Result := Ord(d[i + 1]);
end;

function D32(const d: TData; i: SizeInt): Int64;
var k: Integer;
begin
  Result := 0;
  for k := 3 downto 0 do
    if (i + k >= 0) and (i + k < Length(d)) then Result := Result shl 8 or Ord(d[i + k + 1])
    else Result := Result shl 8;
end;

function Slice(const d: TData; a, b: SizeInt): TData;
begin
  if a < 0 then a := 0;
  if b > Length(d) then b := Length(d);
  if b <= a then Exit('');
  Result := Copy(d, a + 1, b - a);
end;

function ReadFileData(const path: string; out d: TData): Boolean;
var f: TFileStream;
begin
  d := '';
  try
    f := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
    try
      SetLength(d, f.Size);
      if f.Size > 0 then f.ReadBuffer(d[1], f.Size);
    finally
      f.Free;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

function UntilZero(const d: TData): TData;
var p: SizeInt;
begin
  p := Pos(#0, d);
  if p > 0 then Result := Copy(d, 1, p - 1) else Result := d;
end;

{ ---------------------------------------------------------------- code pages }

function CpIndex(cp: Integer): Integer;
var k: Integer;
begin
  for k := 0 to CP_COUNT - 1 do
    if CP_NUMBERS[k] = cp then Exit(k);
  Result := -1;
end;

function KnownCodepage(cp: Integer): Boolean;
begin
  Result := CpIndex(cp) >= 0;
end;

function DecodeByte(b: Integer; cp: Integer): WideChar;
var k: Integer;
begin
  if b < $80 then Exit(WideChar(b));
  k := CpIndex(cp);
  if k < 0 then k := 0;
  Result := WideChar(CP_HIGH[k, b]);
end;

function DecodeBytes(const s: TData; cp: Integer): UStr;
var i: SizeInt;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do Result[i] := DecodeByte(Ord(s[i]), cp);
end;

{ ---------------------------------------------------------------- strings }

function IsSpace(c: WideChar): Boolean;
begin
  case Ord(c) of
    9..13, $1C..$20, $85, $A0, $1680, $2000..$200A, $2028, $2029, $202F, $205F, $3000: Result := True;
  else Result := False;
  end;
end;

function IsDigit(c: WideChar): Boolean;
begin
  Result := (c >= '0') and (c <= '9');
end;

function Strip(const s: UStr): UStr;
begin
  Result := LStrip(RStrip(s));
end;

function LStrip(const s: UStr): UStr;
var i: SizeInt;
begin
  i := 1;
  while (i <= Length(s)) and IsSpace(s[i]) do Inc(i);
  Result := Copy(s, i, MaxInt);
end;

function RStrip(const s: UStr): UStr;
var i: SizeInt;
begin
  i := Length(s);
  while (i > 0) and IsSpace(s[i]) do Dec(i);
  Result := Copy(s, 1, i);
end;

function CharIn(c: WideChar; const chars: UStr): Boolean;
begin
  Result := Pos(c, chars) > 0;
end;

function StripChars(const s, chars: UStr): UStr;
begin
  Result := LStripChars(RStripChars(s, chars), chars);
end;

function LStripChars(const s, chars: UStr): UStr;
var i: SizeInt;
begin
  i := 1;
  while (i <= Length(s)) and CharIn(s[i], chars) do Inc(i);
  Result := Copy(s, i, MaxInt);
end;

function RStripChars(const s, chars: UStr): UStr;
var i: SizeInt;
begin
  i := Length(s);
  while (i > 0) and CharIn(s[i], chars) do Dec(i);
  Result := Copy(s, 1, i);
end;

procedure Append(var a: TUStrArray; const s: UStr);
begin
  SetLength(a, Length(a) + 1);
  a[High(a)] := s;
end;

function SplitWS(const s: UStr): TUStrArray;
var i, j: SizeInt;
begin
  Result := nil;
  i := 1;
  while i <= Length(s) do
  begin
    while (i <= Length(s)) and IsSpace(s[i]) do Inc(i);
    if i > Length(s) then Break;
    j := i;
    while (j <= Length(s)) and not IsSpace(s[j]) do Inc(j);
    Append(Result, Copy(s, i, j - i));
    i := j;
  end;
end;

function SplitStr(const s, sep: UStr): TUStrArray;
var i, p: SizeInt;
begin
  Result := nil;
  i := 1;
  repeat
    p := Pos(sep, s, i);
    if p = 0 then
    begin
      Append(Result, Copy(s, i, MaxInt));
      Break;
    end;
    Append(Result, Copy(s, i, p - i));
    i := p + Length(sep);
  until False;
end;

function JoinStr(const a: TUStrArray; const sep: UStr): UStr;
var k: Integer;
begin
  Result := '';
  for k := 0 to High(a) do
  begin
    if k > 0 then Result := Result + sep;
    Result := Result + a[k];
  end;
end;

function Lower(const s: UStr): UStr;
begin
  Result := UnicodeLowerCase(s);
end;

function Upper(const s: UStr): UStr;
begin
  Result := UnicodeUpperCase(s);
end;

function Replace(const s, a, b: UStr): UStr;
begin
  Result := UnicodeStringReplace(s, a, b, [rfReplaceAll]);
end;

function StartsWith(const s, prefix: UStr): Boolean;
begin
  Result := Copy(s, 1, Length(prefix)) = prefix;
end;

function EndsWith(const s, suffix: UStr): Boolean;
begin
  Result := (Length(s) >= Length(suffix)) and (Copy(s, Length(s) - Length(suffix) + 1, MaxInt) = suffix);
end;

function Partition(const s, sep: UStr; out before, after: UStr): Boolean;
var p: SizeInt;
begin
  p := Pos(sep, s);
  Result := p > 0;
  if Result then
  begin
    before := Copy(s, 1, p - 1);
    after := Copy(s, p + Length(sep), MaxInt);
  end
  else
  begin
    before := s;
    after := '';
  end;
end;

function RepeatStr(const s: UStr; n: Integer): UStr;
var k: Integer;
begin
  Result := '';
  for k := 1 to n do Result := Result + s;
end;

function Contains(const s, sub: UStr): Boolean;
begin
  Result := Pos(sub, s) > 0;
end;

function U8(const s: UStr): RawByteString;
begin
  Result := UTF8Encode(s);
end;

{ ---------------------------------------------------------------- regular expressions }

var
  Cache: TStringList;

function Rx(const pattern: UStr): TRegExpr;
var k: Integer;
    key: string;
begin
  key := U8(pattern);
  k := Cache.IndexOf(key);
  if k >= 0 then Exit(TRegExpr(Cache.Objects[k]));
  Result := TRegExpr.Create(pattern);
  Result.ModifierM := False;
  Result.ModifierS := False;           { . does not match a newline (as in Python) }
  Cache.AddObject(key, Result);
end;

function ReMatch(const pattern, s: UStr): TRegExpr;
begin
  Result := Rx('^(?:' + pattern + ')');
  if not Result.Exec(s) then Result := nil;
end;

function ReFull(const pattern, s: UStr): TRegExpr;
begin
  Result := Rx('^(?:' + pattern + ')$');
  if not Result.Exec(s) or (Result.MatchLen[0] <> Length(s)) then Result := nil;
end;

function ReSearch(const pattern, s: UStr): TRegExpr;
begin
  Result := Rx(pattern);
  if not Result.Exec(s) then Result := nil;
end;

function HasGroup(r: TRegExpr; n: Integer): Boolean;
begin
  Result := (n <= r.SubExprMatchCount) and (r.MatchPos[n] > 0);
end;

function Group(r: TRegExpr; n: Integer): UStr;
begin
  if HasGroup(r, n) then Result := r.Match[n] else Result := '';
end;

function ReSplit(const pattern, s: UStr; maxsplit: Integer): TUStrArray;
var r: TRegExpr;
    last, n: SizeInt;
begin
  Result := nil;
  r := Rx(pattern);
  last := 1;
  n := 0;
  if r.Exec(s) then
    repeat
      if r.MatchLen[0] = 0 then Continue;
      Append(Result, Copy(s, last, r.MatchPos[0] - last));
      last := r.MatchPos[0] + r.MatchLen[0];
      Inc(n);
      if (maxsplit > 0) and (n >= maxsplit) then Break;
    until not r.ExecNext;
  Append(Result, Copy(s, last, MaxInt));
end;

function ReSubStr(const pattern, s, repl: UStr): UStr;
begin
  Result := Rx(pattern).Replace(s, repl, True);
end;

function CollapseNewlines(const s: UStr): UStr;
var i, j: SizeInt;
begin
  Result := '';
  i := 1;
  while i <= Length(s) do
  begin
    if s[i] = #10 then
    begin
      j := i;
      while (j <= Length(s)) and (s[j] = #10) do Inc(j);
      if j - i >= 3 then Result := Result + #10#10 else Result := Result + Copy(s, i, j - i);
      i := j;
    end
    else
    begin
      j := i;
      while (j <= Length(s)) and (s[j] <> #10) do Inc(j);
      Result := Result + Copy(s, i, j - i);
      i := j;
    end;
  end;
end;

{ ---------------------------------------------------------------- files }

function JoinPath(const a, b: string): string;
begin
  if a = '' then Exit(b);
  Result := IncludeTrailingPathDelimiter(a) + b;
end;

function CompareCodepoints(List: TStringList; a, b: Integer): Integer;
begin
  Result := CompareStr(List[a], List[b]);
end;

function ListDir(const folder: string): TStringList;
var sr: TSearchRec;
begin
  Result := TStringList.Create;
  if FindFirst(JoinPath(folder, '*'), faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then Result.Add(sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  Result.CustomSort(@CompareCodepoints);
end;

function FindFileCI(const baseDir, name: string): string;
var path, folder, base: string;
    list: TStringList;
    k: Integer;
begin
  path := JoinPath(baseDir, name);
  if FileExists(path) then Exit(path);
  folder := ExtractFileDir(path);
  base := ExtractFileName(path);
  if folder = '' then folder := '.';
  Result := '';
  if DirectoryExists(folder) then
  begin
    list := ListDir(folder);
    for k := 0 to list.Count - 1 do
      if LowerCase(list[k]) = LowerCase(base) then
      begin
        Result := JoinPath(folder, list[k]);
        Break;
      end;
    list.Free;
  end;
end;

{ ---------------------------------------------------------------- numbers
  A double is m * 2^e exactly; its full decimal expansion (digits, point position) is computed with
  decimal big-number arithmetic, then rounded as Python does (formats: half-even on the exact
  value; Decimal quantize: half-up on the shortest repr). }

type
  TDec = record
    neg: Boolean;
    digits: string;     { no leading zeros; '' for zero }
    point: Integer;     { value = 0.digits * 10^point }
  end;

procedure MulSmall(var n: string; m: Integer);       { decimal digit string (most significant first) * m }
var i, carry, v: Integer;
begin
  carry := 0;
  for i := Length(n) downto 1 do
  begin
    v := (Ord(n[i]) - 48) * m + carry;
    n[i] := Chr(48 + v mod 10);
    carry := v div 10;
  end;
  while carry > 0 do
  begin
    n := Chr(48 + carry mod 10) + n;
    carry := carry div 10;
  end;
end;

function Exact(x: Double): TDec;
var bits: QWord;
    m: QWord;
    e, k: Integer;
    n: string;
begin
  bits := PQWord(@x)^;
  Result.neg := bits shr 63 <> 0;
  e := (bits shr 52) and $7FF;
  m := bits and ((QWord(1) shl 52) - 1);
  if e = 0 then e := -1074 else begin m := m or (QWord(1) shl 52); e := e - 1075; end;
  n := IntToStr(m);
  if m = 0 then
  begin
    Result.digits := '';
    Result.point := 0;
    Exit;
  end;
  if e >= 0 then
  begin
    for k := 1 to e do MulSmall(n, 2);
    Result.point := Length(n);
  end
  else
  begin
    for k := 1 to -e do MulSmall(n, 5);
    Result.point := Length(n) + e;
  end;
  { strip trailing zeros }
  k := Length(n);
  while (k > 0) and (n[k] = '0') do Dec(k);
  Result.digits := Copy(n, 1, k);
end;

{ round d to keep `keep` digits (keep may be <= 0); halfUp or half-even on the exact value }
procedure RoundDigits(var d: TDec; keep: Integer; halfUp: Boolean);
var rest: string;
    up: Boolean;
    i: Integer;
begin
  if keep >= Length(d.digits) then Exit;
  if keep < 0 then
  begin
    d.digits := '';
    Exit;
  end;
  rest := Copy(d.digits, keep + 1, MaxInt);
  if rest[1] > '5' then up := True
  else if rest[1] < '5' then up := False
  else if Length(rest) > 1 then up := True                     { more digits after 5: above half }
  else if halfUp then up := True
  else up := (keep > 0) and Odd(Ord(d.digits[keep]) - 48);     { exact tie: to even }
  d.digits := Copy(d.digits, 1, keep);
  if up then
  begin
    i := keep;
    while (i > 0) and (d.digits[i] = '9') do
    begin
      d.digits[i] := '0';
      Dec(i);
    end;
    if i = 0 then
    begin
      d.digits := '1' + d.digits;
      Inc(d.point);
    end
    else d.digits[i] := Chr(Ord(d.digits[i]) + 1);
  end;
  i := Length(d.digits);
  while (i > 0) and (d.digits[i] = '0') do Dec(i);
  SetLength(d.digits, i);
  if d.digits = '' then d.point := 0;
end;

{ digits of d as fixed-point with prec decimals (d already rounded there) }
function FixedText(const d: TDec; prec: Integer): string;
var intpart, frac: string;
begin
  if d.point > 0 then
  begin
    intpart := Copy(d.digits, 1, d.point);
    while Length(intpart) < d.point do intpart := intpart + '0';
    frac := Copy(d.digits, d.point + 1, MaxInt);
  end
  else
  begin
    intpart := '0';
    frac := StringOfChar('0', -d.point) + d.digits;
  end;
  if intpart = '' then intpart := '0';
  while Length(frac) < prec do frac := frac + '0';
  frac := Copy(frac, 1, prec);
  Result := intpart;
  if prec > 0 then Result := Result + '.' + frac;
end;

function Special(x: Double; out s: string): Boolean;
begin
  Result := True;
  if IsNan(x) then s := 'nan'
  else if IsInfinite(x) then
  begin
    if x > 0 then s := 'inf' else s := '-inf';
  end
  else Result := False;
end;

function FmtF(x: Double; prec: Integer): string;
var d: TDec;
begin
  if Special(x, Result) then Exit;
  d := Exact(x);
  RoundDigits(d, d.point + prec, False);
  Result := FixedText(d, prec);
  if d.neg then Result := '-' + Result;
end;

function ExpText(const d: TDec; prec: Integer; upper: Boolean): string;
var mant: string;
    ex: Integer;
begin
  if d.digits = '' then begin mant := '0'; ex := 0; end
  else begin mant := d.digits; ex := d.point - 1; end;
  while Length(mant) < prec + 1 do mant := mant + '0';
  Result := mant[1];
  if prec > 0 then Result := Result + '.' + Copy(mant, 2, prec);
  if upper then Result := Result + 'E' else Result := Result + 'e';
  if ex < 0 then Result := Result + '-' else Result := Result + '+';
  Result := Result + Format('%.2d', [Abs(ex)]);
end;

function FmtE(x: Double; prec: Integer; upper: Boolean): string;
var d: TDec;
begin
  if Special(x, Result) then
  begin
    if upper then Result := UpperCase(Result);
    Exit;
  end;
  d := Exact(x);
  RoundDigits(d, prec + 1, False);
  Result := ExpText(d, prec, upper);
  if d.neg then Result := '-' + Result;
end;

function FmtG(x: Double; prec: Integer): string;
var d: TDec;
    ex: Integer;
    s: string;
begin
  if Special(x, Result) then Exit;
  if prec = 0 then prec := 1;
  d := Exact(x);
  RoundDigits(d, prec, False);
  if d.digits = '' then ex := 0 else ex := d.point - 1;
  if (ex >= -4) and (ex < prec) then
  begin
    s := FixedText(d, prec - 1 - ex);
    if Pos('.', s) > 0 then
    begin
      while s[Length(s)] = '0' do SetLength(s, Length(s) - 1);
      if s[Length(s)] = '.' then SetLength(s, Length(s) - 1);
    end;
  end
  else
  begin
    s := ExpText(d, prec - 1, False);
    { strip zeros of the mantissa }
    ex := Pos('e', s);
    Result := Copy(s, 1, ex - 1);
    if Pos('.', Result) > 0 then
    begin
      while Result[Length(Result)] = '0' do SetLength(Result, Length(Result) - 1);
      if Result[Length(Result)] = '.' then SetLength(Result, Length(Result) - 1);
    end;
    s := Result + Copy(s, ex, MaxInt);
  end;
  if d.neg then s := '-' + s;
  Result := s;
end;

function ReprDigits(x: Double): TDec;               { shortest digits that read back as x (repr) }
var p: Integer;
    d: TDec;
    v: Double;
    s: string;
begin
  for p := 1 to 17 do
  begin
    d := Exact(x);
    RoundDigits(d, p, False);
    s := d.digits;
    if s = '' then s := '0';
    s := '0.' + s + 'e' + IntToStr(d.point);
    if TryStrToFloat(s, v, DefaultFormatSettings) and (v = Abs(x)) then Exit(d);
  end;
  Result := Exact(x);
end;

function FixedHalfUp(x: Double; decimals: Integer; grouping: Boolean): string;
var d: TDec;
    intpart, frac: string;
    k: Integer;
begin
  if Special(x, Result) then Exit;
  d := ReprDigits(x);
  d.neg := x < 0;
  if (x = 0) and (PQWord(@x)^ shr 63 <> 0) then d.neg := True;
  RoundDigits(d, d.point + decimals, True);
  Result := FixedText(d, decimals);
  if grouping then
  begin
    k := Pos('.', Result);
    if k = 0 then k := Length(Result) + 1;
    intpart := Copy(Result, 1, k - 1);
    frac := Copy(Result, k, MaxInt);
    k := Length(intpart) - 3;
    while k > 0 do
    begin
      intpart := Copy(intpart, 1, k) + ',' + Copy(intpart, k + 1, MaxInt);
      Dec(k, 3);
    end;
    Result := intpart + frac;
  end;
  if d.neg then Result := '-' + Result;
end;

function ParsePyFloat(const s: UStr; out v: Double): Boolean;
var t: string;
    fs: TFormatSettings;
    k: Integer;
begin
  t := LowerCase(string(U8(Strip(s))));
  t := StringReplace(t, '_', '', [rfReplaceAll]);
  v := 0;
  if t = '' then Exit(False);
  if (t = 'inf') or (t = '+inf') or (t = 'infinity') then begin v := Infinity; Exit(True); end;
  if (t = '-inf') or (t = '-infinity') then begin v := NegInfinity; Exit(True); end;
  if (t = 'nan') or (t = '+nan') or (t = '-nan') then begin v := NaN; Exit(True); end;
  for k := 1 to Length(t) do
    if not (t[k] in ['0'..'9', '.', 'e', '+', '-']) then Exit(False);
  if (t[1] = '.') and (Length(t) = 1) then Exit(False);
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  Result := TryStrToFloat(t, v, fs);
end;

function IntStr(v: Double): string;
begin
  Result := IntToStr(Trunc(v));
end;

initialization
  Cache := TStringList.Create;
  Cache.Sorted := True;
  Cache.CaseSensitive := True;
  Cache.OwnsObjects := True;
finalization
  Cache.Free;
end.

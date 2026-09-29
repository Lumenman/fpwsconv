{ WordStar merge printing and data files (port of wsmerge.py).
  Data sources (for .df and .fi): comma-delimited text, dBASE (.DBF), and Lotus-format worksheets
  (1-2-3 .WKS/.WK1, Symphony .WRK/.WR1, Quattro .WQ1, VP-Planner) - the formats WordStar 7 accepts.
  Merge dot commands: .df .rv .sv .ma .av .if/.el/.ei .go .rp .dm .cs; variables &name[/o][/x]&. }
unit wsmerge;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, Math, Generics.Collections, uregexpr, wsutil
     {$if defined(windows)}, Windows{$elseif defined(go32v2)}, Dos{$endif};

type
  TRows = array of TUStrArray;
  TTable = record
    ok, hasNames: Boolean;
    names: TUStrArray;
    rows: TRows;
  end;
  TVars = specialize TDictionary<UStr, UStr>;

const
  MARK = #0;                        { converted text carries merge dot commands as #0.cmd args#0 }
  OMIT = #1;                        { a /o variable that came out empty }

function FindFile(const baseDir, name: string): string;
function GuessCodepage(const data: TData; ws5: Boolean = False): Integer;
function ReadTableFile(const path: string; const spec: UStr; codepage: Integer): TTable;
function TableText(const rows: TRows; textmode: Boolean): UStr;
function FormatNumber(const value, fmt: UStr): UStr;
function MergeText(const text: UStr; const baseDir, docPath: string; preset: TVars; textmode: Boolean;
                   codepage: Integer): UStr;

implementation

{ ---------------------------------------------------------------- files }

function FindFile(const baseDir, name: string): string;
begin
  Result := FindFileCI(baseDir, name);
end;

{ ---------------------------------------------------------------- code pages
  Cyrillic letters: А-Я а-п (80h-AFh), р-я (E0h-EFh), and F0h-F9h: cp866 Ё ё Є є Ї ї Ў ў ° ∙,
  cp1125 (Ukrainian) Ё ё Ґ ґ Є є І і Ї ї. cp437 and the Cyrillic code pages all use 80h-AFh for
  letters, but a cp437 text has single accented letters inside Latin words, while in Cyrillic text
  almost every letter has another letter next to it. F6h-F9h inside words are Ukrainian І і Ї ї
  (cp1125). In WordStar 5+ files extended characters are stored as 1Bh xx 1Ch. }

function IsCyr(c: Integer): Boolean; inline;
begin
  Result := ((c >= $80) and (c < $B0)) or ((c >= $E0) and (c < $FA));
end;

function GuessCodepage(const data: TData; ws5: Boolean): Integer;
var chars: array of Byte;
    n, i, k, c, letters, near, ukr: Integer;
begin
  SetLength(chars, Length(data));
  n := 0;
  i := 0;
  while i < Length(data) do
  begin
    c := DB(data, i);
    if ws5 then
    begin
      if (c = $1B) and (i + 2 < Length(data)) and (DB(data, i + 2) = $1C) then
      begin
        chars[n] := DB(data, i + 1);
        Inc(n);
        Inc(i, 3);
        Continue;
      end;
      if c >= $80 then c := 0;
    end;
    chars[n] := c;
    Inc(n);
    Inc(i);
  end;
  letters := 0; near := 0; ukr := 0;
  for k := 0 to n - 1 do
    if IsCyr(chars[k]) then
    begin
      Inc(letters);
      if ((k > 0) and IsCyr(chars[k - 1])) or ((k + 1 < n) and IsCyr(chars[k + 1])) then
      begin
        Inc(near);
        if (chars[k] >= $F6) and (chars[k] <= $F9) then Inc(ukr);
      end;
    end;
  if (letters < 2) or (near * 2 < letters) then Exit(437);
  if ukr > 0 then Result := 1125 else Result := 866;
end;

function PickCp(codepage: Integer; const sample: TData): Integer;
begin
  if codepage <> 0 then Result := codepage else Result := GuessCodepage(sample);
end;

function DecodeAscii(const s: TData): UStr;     { .decode('ascii', 'replace') }
var i: Integer;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do
    if Ord(s[i]) < $80 then Result[i] := WideChar(Ord(s[i])) else Result[i] := #$FFFD;
end;

{ ---------------------------------------------------------------- worksheets (Lotus record format) }

type
  TCells = specialize TDictionary<Int64, UStr>;
  TRange = record c1, r1, c2, r2: Integer; end;
  TNames = specialize TDictionary<UStr, TRange>;

function CellKey(col, row: Integer): Int64; inline;
begin
  Result := Int64(row) shl 20 or col;
end;

function ColNumber(const letters: UStr): Integer;
var k: Integer;
begin
  Result := 0;
  for k := 1 to Length(letters) do Result := Result * 26 + Ord(Upcase(Char(Ord(letters[k])))) - 64;
  Dec(Result);
end;

const
  MONTHS: array[1..12] of string = ('January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December');

function LotusNumber(value: Double; fmt: Integer): UStr;
{ Cell value text as WordStar 7.0D merge prints it for a Lotus cell format byte: default format
  (FFh) prints whole numbers; percent has no % sign; negative currency / comma values start with (
  and have no closing parenthesis. }
var kind, dec: Integer;
    d: TDateTime;
    y, m, dd: Word;
    neg: string;
begin
  kind := (fmt shr 4) and 7;
  dec := fmt and $0F;
  if value < 0 then neg := '(' else neg := '';
  if fmt = $FF then Exit(UStr(FixedHalfUp(value, 0, False)));
  if (kind = 7) and ((dec = 0) or (dec = 1) or (dec = 15)) then Exit(UStr(FmtG(value, 15)));
  case kind of
    0: Exit(UStr(FixedHalfUp(value, dec, False)));
    1: Exit(UStr(FmtE(value, dec, True)));
    2: Exit(UStr(neg + '$' + FixedHalfUp(Abs(value), dec, True)));
    3: Exit(UStr(FixedHalfUp(value * 100, dec, False)));
    4: Exit(UStr(neg + FixedHalfUp(Abs(value), dec, True)));
  end;
  if (kind = 7) and (dec in [2, 3, 4]) then
  begin
    d := EncodeDate(1899, 12, 30) + Trunc(value);
    DecodeDate(d, y, m, dd);
    case dec of
      2: Exit(UStr(Format('%.2d-%s-%.2d', [dd, Copy(MONTHS[m], 1, 3), y mod 100])));
      3: Exit(UStr(Format('%.2d-%s', [dd, Copy(MONTHS[m], 1, 3)])));
      4: Exit(UStr(Format('%s-%.2d', [Copy(MONTHS[m], 1, 3), y mod 100])));
    end;
  end;
  if (kind = 7) and (dec = 6) then Exit('');
  Result := UStr(FmtG(value, 15));
end;

function ReadWorksheet(const data: TData; codepage: Integer; cells: TCells; names: TNames): Boolean;
{ False if data is not a Lotus-format worksheet. codepage 0: guessed from the label texts. }
type TLabel = record key: Int64; raw: TData; end;
var labels: array of TLabel;
    i, op, ln, col, row, fmt, k: Integer;
    body, raw, joined: TData;
    text: UStr;
    dv: Double;
    rg: TRange;
    cp: Integer;
    found: Boolean;
begin
  Result := False;
  if (Length(data) < 6) or (Copy(data, 1, 4) <> #0#0#2#0) then Exit;
  labels := nil;
  i := 0;
  while i + 4 <= Length(data) do
  begin
    op := W16(data, i);
    ln := W16(data, i + 2);
    body := Slice(data, i + 4, i + 4 + ln);
    Inc(i, 4 + ln);
    if op = $01 then Break;
    if (op in [$0D, $0E, $0F, $10]) and (Length(body) >= 5) then
    begin
      fmt := DB(body, 0);
      col := W16(body, 1);
      row := W16(body, 3);
      if (op = $0D) and (Length(body) >= 7) then
        text := LotusNumber(SmallInt(W16(body, 5)), fmt)
      else if (op in [$0E, $10]) and (Length(body) >= 13) then
      begin
        Move(body[6], dv, 8);
        text := LotusNumber(dv, fmt);
      end
      else if op = $0F then
      begin
        raw := UntilZero(Slice(body, 5, Length(body)));
        if (raw = '') or (raw[1] in ['''', '"', '^', '\']) then raw := Copy(raw, 2, MaxInt);
        found := False;
        for k := 0 to High(labels) do
          if labels[k].key = CellKey(col, row) then
          begin
            labels[k].raw := raw;
            found := True;
          end;
        if not found then
        begin
          SetLength(labels, Length(labels) + 1);
          labels[High(labels)].key := CellKey(col, row);
          labels[High(labels)].raw := raw;
        end;
        Continue;
      end
      else Continue;
      cells.AddOrSetValue(CellKey(col, row), text);
    end
    else if (op = $0B) and (Length(body) >= 24) then
    begin
      rg.c1 := W16(body, 16); rg.r1 := W16(body, 18); rg.c2 := W16(body, 20); rg.r2 := W16(body, 22);
      names.AddOrSetValue(Upper(DecodeAscii(UntilZero(Copy(body, 1, 16)))), rg);
    end;
  end;
  joined := '';
  for k := 0 to High(labels) do
  begin
    if k > 0 then joined := joined + ' ';
    joined := joined + labels[k].raw;
  end;
  cp := PickCp(codepage, joined);
  for k := 0 to High(labels) do cells.AddOrSetValue(labels[k].key, DecodeBytes(labels[k].raw, cp));
  Result := True;
end;

function ParseRange(const spec0: UStr; names: TNames; out rg: TRange): Boolean;
{ range from 'A1..C5', 'A1.C5', 'A1:C5', 'B2' or a range name; False if unknown }
var spec: UStr;
    r: TRegExpr;
    c1, r1, c2, r2: Integer;
begin
  spec := Upper(Strip(spec0));
  r := ReFull('([A-Z]{1,2})(\d+)(?:\s*(?:\.\.?|:)\s*([A-Z]{1,2})(\d+))?', spec);
  if r <> nil then
  begin
    c1 := ColNumber(Group(r, 1));
    r1 := StrToInt(string(Group(r, 2))) - 1;
    if HasGroup(r, 3) then
    begin
      c2 := ColNumber(Group(r, 3));
      r2 := StrToInt(string(Group(r, 4))) - 1;
    end
    else begin c2 := c1; r2 := r1; end;
    rg.c1 := Min(c1, c2); rg.r1 := Min(r1, r2); rg.c2 := Max(c1, c2); rg.r2 := Max(r1, r2);
    Exit(True);
  end;
  Result := names.TryGetValue(spec, rg);
end;

function WorksheetRows(cells: TCells; useRange: Boolean; rg: TRange): TRows;
var key: Int64;
    c, r, col, row: Integer;
    line: TUStrArray;
    v: UStr;
    any: Boolean;
begin
  Result := nil;
  if cells.Count = 0 then Exit;
  if not useRange then
  begin
    rg.c1 := MaxInt; rg.r1 := MaxInt; rg.c2 := -1; rg.r2 := -1;
    for key in cells.Keys do
    begin
      col := key and $FFFFF;
      row := key shr 20;
      rg.c1 := Min(rg.c1, col); rg.c2 := Max(rg.c2, col);
      rg.r1 := Min(rg.r1, row); rg.r2 := Max(rg.r2, row);
    end;
  end;
  for r := rg.r1 to rg.r2 do
  begin
    line := nil;
    any := False;
    for c := rg.c1 to rg.c2 do
    begin
      if not cells.TryGetValue(CellKey(c, r), v) then v := '';
      Append(line, v);
      any := any or (v <> '');
    end;
    if any then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := line;
    end;
  end;
end;

{ ---------------------------------------------------------------- dBASE }

function ReadDbf(const data: TData; codepage: Integer): TTable;
{ field names and records of a dBASE III/IV file; ok = False if not one. codepage 0: guessed. }
var count, head, reclen, pos, k, off, f: Integer;
    cp: Integer;
    sizes: array of Integer;
    rec: TData;
    values: TUStrArray;
begin
  Result.ok := False;
  Result.hasNames := True;
  Result.names := nil;
  Result.rows := nil;
  if (Length(data) < 33) or not (DB(data, 0) in [$03, $83, $8B, $F5, $30]) then Exit;
  count := D32(data, 4);
  head := W16(data, 8);
  reclen := W16(data, 10);
  cp := PickCp(codepage, Slice(data, head, Length(data)));
  sizes := nil;
  pos := 32;
  while (pos + 32 <= head) and (DB(data, pos) <> $0D) do
  begin
    Append(Result.names, DecodeAscii(UntilZero(Slice(data, pos, pos + 11))));
    SetLength(sizes, Length(sizes) + 1);
    sizes[High(sizes)] := DB(data, pos + 16);
    Inc(pos, 32);
  end;
  if (Length(sizes) = 0) or (Int64(head) + Int64(reclen) * count > Length(data) + reclen) then Exit;
  for k := 0 to count - 1 do
  begin
    rec := Slice(data, head + k * reclen, head + (k + 1) * reclen);
    if (rec = '') or (rec[1] = '*') then Continue;
    values := nil;
    off := 1;
    for f := 0 to High(sizes) do
    begin
      Append(values, Strip(DecodeBytes(Slice(rec, off, off + sizes[f]), cp)));
      Inc(off, sizes[f]);
    end;
    SetLength(Result.rows, Length(Result.rows) + 1);
    Result.rows[High(Result.rows)] := values;
  end;
  Result.ok := True;
end;

{ ---------------------------------------------------------------- any table file }

function ReadTableFile(const path: string; const spec: UStr; codepage: Integer): TTable;
{ names (hasNames) and rows for a worksheet or dBASE file; ok = False if the file is neither.
  spec is a worksheet range ('A1..C5' or a range name); ignored for dBASE. }
var data: TData;
    cells: TCells;
    names: TNames;
    rg: TRange;
    useRange: Boolean;
begin
  Result.ok := False;
  Result.hasNames := False;
  Result.names := nil;
  Result.rows := nil;
  if not ReadFileData(path, data) then Exit;
  cells := TCells.Create;
  names := TNames.Create;
  try
    if ReadWorksheet(data, codepage, cells, names) then
    begin
      useRange := (spec <> '') and ParseRange(spec, names, rg);   { unknown range: the used area }
      Result.ok := True;
      Result.rows := WorksheetRows(cells, useRange, rg);
      Exit;
    end;
  finally
    cells.Free;
    names.Free;
  end;
  if LowerCase(ExtractFileExt(path)) = '.dbf' then Result := ReadDbf(data, codepage);
end;

function ReadDelimited(const path: string; sep: WideChar; codepage: Integer): TRows;
{ Records of a WordStar comma-delimited data file (quotes allowed around fields), as csv.reader
  with skipinitialspace reads them. }
var raw: TData;
    text, field: UStr;
    row: TUStrArray;
    i: Integer;
    quoted, rowHasData: Boolean;

  procedure EndField;
  begin
    Append(row, field);
    field := '';
  end;

  procedure EndRow;
  var k: Integer;
      any: Boolean;
  begin
    any := False;
    for k := 0 to High(row) do
    begin
      row[k] := Strip(row[k]);
      any := any or (row[k] <> '');
    end;
    if any then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := row;
    end;
    row := nil;
  end;

begin
  Result := nil;
  if not ReadFileData(path, raw) then Exit;
  i := Pos(#$1A, raw);
  if i > 0 then SetLength(raw, i - 1);
  text := DecodeBytes(raw, PickCp(codepage, raw));
  row := nil;
  field := '';
  i := 1;
  rowHasData := False;
  while i <= Length(text) do
  begin
    { start of a field }
    while (i <= Length(text)) and (text[i] = ' ') do Inc(i);
    quoted := (i <= Length(text)) and (text[i] = '"');
    if quoted then
    begin
      Inc(i);
      while i <= Length(text) do
      begin
        if text[i] = '"' then
        begin
          if (i < Length(text)) and (text[i + 1] = '"') then
          begin
            field := field + '"';
            Inc(i, 2);
            Continue;
          end;
          Inc(i);
          Break;
        end;
        field := field + text[i];
        Inc(i);
      end;
    end;
    while (i <= Length(text)) and (text[i] <> sep) and (text[i] <> #13) and (text[i] <> #10) do
    begin
      field := field + text[i];
      Inc(i);
    end;
    rowHasData := True;
    if i > Length(text) then
    begin
      EndField;
      EndRow;
      rowHasData := False;
      Break;
    end;
    if text[i] = sep then
    begin
      EndField;
      Inc(i);
      if i > Length(text) then
      begin
        EndField;
        EndRow;
        rowHasData := False;
      end;
      Continue;
    end;
    { line end }
    EndField;
    EndRow;
    rowHasData := False;
    if (text[i] = #13) and (i < Length(text)) and (text[i + 1] = #10) then Inc(i);
    Inc(i);
  end;
  if rowHasData then EndRow;
end;

{ ---------------------------------------------------------------- formats and math }

function FormatNumber(const value, fmt: UStr): UStr;
{ Apply a WordStar number format (the value of the variable named after the slash in &name/x&):
  9 digit, Z digit or blank, * digit or *, $ floating dollar, , thousands, . decimal point,
  - / + sign position. Checked against WordStar 7.0D merge printing: too many digits fill every
  position with ?, a negative value without a sign position loses its sign. Non-numeric values are
  returned unchanged. }
const DIG = '9Z*$';
var num, back: Double;
    intFmt, decFmt, digits, intDigits, decDigits, outs, decOut, dot: UStr;
    ndec, nint, k, di: Integer;
    negative, dollarDone, hasDot: Boolean;
    pending: UStr;
    ch: WideChar;

  function Sign(c: WideChar): UStr;
  begin
    if negative then Result := '-' else if c = '+' then Result := '+' else Result := ' ';
  end;

begin
  if not ParsePyFloat(Replace(Replace(value, ',', ''), '$', ''), num) then Exit(value);
  hasDot := Partition(fmt, '.', intFmt, decFmt);
  if hasDot then dot := '.' else dot := '';
  ndec := 0;
  for k := 1 to Length(decFmt) do if CharIn(decFmt[k], DIG) then Inc(ndec);
  nint := 0;
  for k := 1 to Length(intFmt) do if CharIn(intFmt[k], DIG) then Inc(nint);
  digits := UStr(FmtF(Abs(num), ndec));
  Partition(digits, '.', intDigits, decDigits);
  intDigits := LStripChars(intDigits, '0');
  if Length(intDigits) > nint then Exit(RepeatStr('?', Length(fmt)));
  ParsePyFloat(digits, back);
  negative := (num < 0) and (back <> 0);
  outs := '';                       { built right to left, reversed at the end }
  pending := intDigits;
  dollarDone := False;
  for k := Length(intFmt) downto 1 do
  begin
    ch := intFmt[k];
    if CharIn(ch, DIG) then
    begin
      if pending <> '' then
      begin
        outs := outs + pending[Length(pending)];
        SetLength(pending, Length(pending) - 1);
      end
      else if ch = '9' then outs := outs + '0'
      else if ch = '*' then outs := outs + '*'
      else if (ch = '$') and not dollarDone then
      begin
        outs := outs + '$';
        dollarDone := True;
      end
      else outs := outs + ' ';
    end
    else if ch = ',' then
    begin
      if pending <> '' then outs := outs + ','
      else if (outs <> '') and CharIn(outs[Length(outs)], ' *') then outs := outs + outs[Length(outs)]
      else outs := outs + ' ';
    end
    else if (ch = '-') or (ch = '+') then outs := outs + Sign(ch)
    else outs := outs + ch;
  end;
  decOut := '';
  di := 1;
  for k := 1 to Length(decFmt) do
  begin
    ch := decFmt[k];
    if CharIn(ch, DIG) then
    begin
      decOut := decOut + decDigits[di];
      Inc(di);
    end
    else if (ch = '-') or (ch = '+') then decOut := decOut + Sign(ch)
    else decOut := decOut + ch;
  end;
  Result := '';
  for k := Length(outs) downto 1 do Result := Result + outs[k];
  Result := Result + dot + decOut;
end;

{ Value of a WordStar math expression: + - * / ^ %, parentheses, sqr exp int log ln sin cos tan atn
  abs. The Python version rewrote it to a Python expression and evaluated its syntax tree; this
  parser follows the same grammar: ** binds tighter than a unary minus on its left and is right
  associative; numbers are Python literals. }
type
  EEval = class(Exception);

  TParser = class
    s: UStr;
    p: Integer;
    procedure Skip;
    function Peek(const t: UStr): Boolean;
    function Expr: Double;
    function Term: Double;
    function Factor: Double;
    function Power: Double;
    function Atom: Double;
  end;

procedure Fail;
begin
  raise EEval.Create('unsupported expression');
end;

function Chk(v: Double): Double;
begin
  if IsNan(v) or IsInfinite(v) then Fail;
  Result := v;
end;

procedure TParser.Skip;
begin
  while (p <= Length(s)) and CharIn(s[p], ' '#9#10#13#12#11) do Inc(p);
end;

function TParser.Peek(const t: UStr): Boolean;
begin
  Skip;
  Result := Copy(s, p, Length(t)) = t;
end;

function TParser.Expr: Double;
begin
  Result := Term;
  repeat
    if Peek('+') then begin Inc(p); Result := Result + Term; end
    else if Peek('-') then begin Inc(p); Result := Result - Term; end
    else Break;
  until False;
end;

function TParser.Term: Double;
var b: Double;
begin
  Result := Factor;
  repeat
    if Peek('**') then Fail
    else if Peek('//') then Fail
    else if Peek('*') then begin Inc(p); Result := Result * Factor; end
    else if Peek('/') then
    begin
      Inc(p);
      b := Factor;
      if b = 0 then Fail;
      Result := Result / b;
    end
    else if Peek('%') or Peek('@') then Fail
    else Break;
  until False;
end;

function TParser.Factor: Double;
begin
  if Peek('-') then begin Inc(p); Exit(-Factor()); end;
  if Peek('+') then begin Inc(p); Exit(Factor()); end;
  if Peek('~') then Fail;
  Result := Power;
end;

function TParser.Power: Double;
var b: Double;
begin
  Result := Atom;
  if Peek('**') then
  begin
    Inc(p, 2);
    b := Factor;
    if (Result = 0) and (b < 0) then Fail;
    if (Result < 0) and (Frac(b) <> 0) then Fail;     { a complex number in Python }
    Result := Math.Power(Result, b);
    if IsInfinite(Result) or IsNan(Result) then Fail;
  end;
end;

function TParser.Atom: Double;
var st: Integer;
    name: UStr;
    v: Double;
    fs: TFormatSettings;
    t: string;
begin
  Skip;
  if p > Length(s) then Fail;
  if s[p] = '(' then
  begin
    Inc(p);
    Result := Expr;
    if not Peek(')') then Fail;
    Inc(p);
    Exit;
  end;
  if IsDigit(s[p]) or (s[p] = '.') then
  begin
    st := p;
    while (p <= Length(s)) and (IsDigit(s[p]) or (s[p] = '_')) do Inc(p);
    if (p <= Length(s)) and (s[p] = '.') then
    begin
      Inc(p);
      while (p <= Length(s)) and IsDigit(s[p]) do Inc(p);
    end;
    if (p <= Length(s)) and CharIn(s[p], 'eE') then
    begin
      Inc(p);
      if (p <= Length(s)) and CharIn(s[p], '+-') then Inc(p);
      if (p > Length(s)) or not IsDigit(s[p]) then Fail;
      while (p <= Length(s)) and IsDigit(s[p]) do Inc(p);
    end;
    t := string(U8(Replace(Copy(s, st, p - st), '_', '')));
    if t = '.' then Fail;
    if (p <= Length(s)) and (IsDigit(s[p]) or CharIn(s[p], 'abcdfghijklmnopqrstuvwxyzABCDFGHIJKLMNOPQRSTUVWXYZ_.')) then Fail;
    { leading zeros in an integer literal are a syntax error in Python }
    if (Length(t) > 1) and (t[1] = '0') and (Pos('.', t) = 0) and (Pos('e', LowerCase(t)) = 0)
       and (StrToInt64Def(t, 1) <> 0) then Fail;
    fs := DefaultFormatSettings;
    fs.DecimalSeparator := '.';
    if not TryStrToFloat(t, v, fs) then Fail;
    Exit(v);
  end;
  if CharIn(s[p], 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_') then
  begin
    st := p;
    while (p <= Length(s)) and CharIn(s[p], 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789') do Inc(p);
    name := Lower(Copy(s, st, p - st));
    if not Peek('(') then Fail;
    Inc(p);
    v := Expr;
    if not Peek(')') then Fail;
    Inc(p);
    if name = 'sqr' then begin if v < 0 then Fail; Exit(Sqrt(v)); end;
    if name = 'exp' then Exit(Chk(Exp(v)));
    if name = 'int' then begin if IsNan(v) or IsInfinite(v) then Fail; Exit(Int(v)); end;
    if name = 'log' then begin if v <= 0 then Fail; Exit(Log10(v)); end;
    if name = 'ln' then begin if v <= 0 then Fail; Exit(Ln(v)); end;
    if name = 'sin' then Exit(Chk(Sin(v)));
    if name = 'cos' then Exit(Chk(Cos(v)));
    if name = 'tan' then Exit(Chk(Tan(v)));
    if name = 'atn' then Exit(ArcTan(v));
    if name = 'abs' then Exit(Abs(v));
    Fail;
  end;
  Fail;
  Result := 0;
end;

function Evaluate(const expr0: UStr): Double;
var expr: UStr;
    ps: TParser;
begin
  expr := ReSubStr('(\d+(?:\.\d*)?|\.\d+)\s*%', Replace(expr0, ',', ''), '($1/100)');
  expr := Replace(expr, '^', '**');
  ps := TParser.Create;
  try
    ps.s := Strip(expr);
    ps.p := 1;
    Result := ps.Expr;
    ps.Skip;
    if ps.p <= Length(ps.s) then Fail;
  finally
    ps.Free;
  end;
end;

function NumberText(v: Double): UStr;
begin
  if IsNan(v) or IsInfinite(v) then Fail;
  if (v = Int(v)) and (Abs(v) < 1e15) then Result := UStr(IntStr(v))
  else Result := UStr(FmtG(v, 12));
end;

function ToNumber(const s: UStr): Double;
var t: UStr;
begin
  t := Strip(Replace(Replace(s, ',', ''), '$', ''));
  if t = '' then Exit(0);
  if not ParsePyFloat(t, Result) then Result := 0;
end;

const
  IF_OPS: array[0..11] of UStr = ('#<>', '#<=', '#>=', '#=', '#<', '#>', '<>', '<=', '>=', '=', '<', '>');

function Condition(const left, op0, right: UStr): Boolean;
var a, b: Double;
    sa, sb, op: UStr;
    c: Integer;
begin
  op := op0;
  if StartsWith(op, '#') then
  begin
    a := ToNumber(left);
    b := ToNumber(right);
    op := Copy(op, 2, MaxInt);
    if IsNan(a) or IsNan(b) then c := 2
    else if a < b then c := -1 else if a > b then c := 1 else c := 0;
  end
  else
  begin
    sa := Lower(left);
    sb := Lower(right);
    if sa < sb then c := -1 else if sa > sb then c := 1 else c := 0;
  end;
  if c = 2 then Exit(op = '<>');      { NaN compares unequal }
  if op = '=' then Result := c = 0
  else if op = '<>' then Result := c <> 0
  else if op = '<' then Result := c < 0
  else if op = '>' then Result := c > 0
  else if op = '<=' then Result := c <= 0
  else Result := c >= 0;
end;

{ ---------------------------------------------------------------- merge engine }

type
  TDataFile = class
    hasNames: Boolean;
    names: TUStrArray;
    rows: TRows;
    pos: Integer;
    function Next(out rec: TUStrArray): Boolean;
  end;

  TSeg = record
    isCmd: Boolean;
    text, cmd, arg: UStr;
  end;

  TMerger = class
    baseDir, docPath: string;
    codepage: Integer;
    preset, vars: TVars;
    separator: UStr;
    data: TDataFile;
    messages: TUStrArray;
    constructor Create(const aBaseDir, aDocPath: string; aPreset: TVars; const aSep: UStr; aCodepage: Integer);
    destructor Destroy; override;
    function Ask(const prompt: UStr): UStr;
    function SystemVar(const name: UStr; out value: UStr): Boolean;
    function Substitute(const text: UStr): UStr;
    procedure OpenData(const arg: UStr);
    function ReadRecord(const arg: UStr): Boolean;
    procedure SetVar(const arg: UStr);
    procedure DoMath(const arg: UStr);
    procedure AskVar(const arg: UStr);
    function Test(const arg: UStr): Boolean;
    function Run(const text: UStr): UStr;
  end;

function TDataFile.Next(out rec: TUStrArray): Boolean;
begin
  rec := nil;
  if pos >= Length(rows) then Exit(False);
  Inc(pos);
  rec := rows[pos - 1];
  Result := True;
end;

constructor TMerger.Create(const aBaseDir, aDocPath: string; aPreset: TVars; const aSep: UStr; aCodepage: Integer);
var k: UStr;
begin
  baseDir := aBaseDir;
  docPath := aDocPath;
  codepage := aCodepage;
  separator := aSep;
  preset := TVars.Create;
  vars := TVars.Create;
  if aPreset <> nil then
    for k in aPreset.Keys do
    begin
      preset.AddOrSetValue(Lower(k), aPreset[k]);
      vars.AddOrSetValue(Lower(k), aPreset[k]);
    end;
  data := nil;
end;

destructor TMerger.Destroy;
begin
  preset.Free;
  vars.Free;
  data.Free;
  inherited;
end;

function StdinIsConsole: Boolean;
{$if defined(windows)}
var mode: DWORD;
begin
  Result := GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), @mode);     { NUL is a character device too }
end;
{$elseif defined(go32v2)}
var r: Registers;
begin
  r.ax := $4400;                     { IOCTL: device information of handle 0 }
  r.bx := 0;
  MsDos(r);
  Result := (r.flags and 1 = 0) and (r.dx and $80 <> 0);
end;
{$else}
begin
  Result := False;
end;
{$endif}

function TMerger.Ask(const prompt: UStr): UStr;
var line: string;
begin
  { interactive only: with input redirected (no answers typed) the value is empty }
  Result := '';
  if not StdinIsConsole then Exit;
  Write(U8(prompt + ' '));
  if EOF(Input) then Exit;
  ReadLn(line);
  Result := UTF8Decode(line);
end;

function TMerger.SystemVar(const name: UStr; out value: UStr): Boolean;
var now: TDateTime;
    y, m, d, h, mi, s, ms: Word;
    path: string;
    ampm: string;
    h12: Integer;
begin
  Result := True;
  now := SysUtils.Now;
  DecodeDate(now, y, m, d);
  DecodeTime(now, h, mi, s, ms);
  if docPath <> '' then path := ExpandFileName(docPath) else path := '';
  if name = '@' then value := UStr(Format('%s %d, %d', [MONTHS[m], d, y]))
  else if name = '!' then
  begin
    h12 := h mod 12;
    if h12 = 0 then h12 := 12;
    if h < 12 then ampm := 'a.m.' else ampm := 'p.m.';
    value := UStr(Format('%d:%.2d %s', [h12, mi, ampm]));
  end
  else if name = '*' then value := UTF8Decode(ExtractFileName(path))
  else if name = ':' then value := UTF8Decode(ExtractFileDrive(path))
  else if name = '.' then value := UTF8Decode(ExcludeTrailingPathDelimiter(ExtractFileDir(path)))
  else if name = '\' then value := UTF8Decode(path)
  else Result := False;
end;

function TMerger.Substitute(const text: UStr): UStr;
var r: TRegExpr;
    last, k: Integer;
    name, value, whole: UStr;
    flags: TUStrArray;
    omitFlag: Boolean;
begin
  r := Rx('&([^&\s/]+)((?:/[^&\s/]+)*)&');
  Result := '';
  last := 1;
  if r.Exec(text) then
    repeat
      Result := Result + Copy(text, last, r.MatchPos[0] - last);
      last := r.MatchPos[0] + r.MatchLen[0];
      whole := r.Match[0];
      name := Group(r, 1);
      flags := nil;
      for value in SplitStr(Group(r, 2), '/') do
        if value <> '' then Append(flags, value);
      if not SystemVar(name, value) then
        if not vars.TryGetValue(Lower(name), value) then
        begin
          Result := Result + whole;          { unknown (e.g. &#& page): keep }
          Continue;
        end;
      omitFlag := False;
      for k := 0 to High(flags) do
      begin
        if Lower(flags[k]) = 'o' then omitFlag := True
        else if vars.ContainsKey(Lower(flags[k])) then value := FormatNumber(value, vars[Lower(flags[k])]);
      end;
      if (value = '') and omitFlag then Result := Result + OMIT
      else Result := Result + value;
    until not r.ExecNext;
  Result := Result + Copy(text, last, MaxInt);
end;

procedure TMerger.OpenData(const arg: UStr);
var parts: TUStrArray;
    name, rest: UStr;
    path: string;
    table: TTable;
    sep: WideChar;
begin
  parts := ReSplit('[\s,]+', Strip(arg), 1);
  name := parts[0];
  if Length(parts) > 1 then rest := Strip(parts[1]) else rest := '';
  path := FindFile(baseDir, string(name));
  data := TDataFile.Create;
  if path = '' then
  begin
    Append(messages, 'merge data file not found: ' + name);
    Exit;
  end;
  table := ReadTableFile(path, rest, codepage);
  if table.ok then
  begin
    data.hasNames := table.hasNames;
    data.names := table.names;
    data.rows := table.rows;
  end
  else
  begin
    if rest <> '' then sep := rest[1] else sep := ',';
    data.rows := ReadDelimited(path, sep, codepage);
  end;
end;

function TMerger.ReadRecord(const arg: UStr): Boolean;
{ .rv: assign the next record; False when the data file is exhausted }
var star: Boolean;
    rec, names: TUStrArray;
    n: UStr;
    k: Integer;
begin
  if data = nil then Exit(False);
  star := StartsWith(arg, '*');
  if star and not data.hasNames then
  begin
    data.Next(data.names);
    data.hasNames := True;
  end;
  if not data.Next(rec) then Exit(False);
  if star then names := data.names
  else
  begin
    names := nil;
    for n in SplitStr(LStripChars(arg, '+'), ',') do
      if Strip(n) <> '' then Append(names, Strip(n));
  end;
  for k := 0 to High(names) do
    if k < Length(rec) then vars.AddOrSetValue(Lower(names[k]), rec[k])
    else vars.AddOrSetValue(Lower(names[k]), '');
  Result := True;
end;

procedure TMerger.SetVar(const arg: UStr);
var r: TRegExpr;
    name, value: UStr;
begin
  r := ReMatch('\s*([^=,\s]+)\s*[=,]\s*(.*)$', arg);
  if r = nil then Exit;
  name := Group(r, 1);
  value := Group(r, 2);
  vars.AddOrSetValue(Lower(name), StripChars(Strip(Substitute(value)), '"'));
end;

procedure TMerger.DoMath(const arg: UStr);
var r: TRegExpr;
    name, expr: UStr;
begin
  r := ReMatch('\s*([^=\s]+)\s*=\s*(.+)$', arg);
  if r = nil then Exit;
  name := Lower(Group(r, 1));
  expr := Group(r, 2);
  try
    vars.AddOrSetValue(name, NumberText(Evaluate(Substitute(expr))));
  except
    on EEval do
    begin
      Append(messages, 'can''t evaluate: ' + Strip(arg));
      vars.AddOrSetValue(name, '');
    end;
  end;
end;

procedure TMerger.AskVar(const arg: UStr);
var r: TRegExpr;
    name, prompt, key, v: UStr;
begin
  r := ReMatch('\s*(?:(?:"([^"]*)"|''([^'']*)'')\s*,\s*)?([^\s,]+)\s*$', arg);
  if r = nil then Exit;
  name := Group(r, 3);
  if HasGroup(r, 1) then prompt := Group(r, 1)
  else if HasGroup(r, 2) then prompt := Group(r, 2)
  else prompt := Upper(name) + '?';
  key := Lower(name);
  if preset.TryGetValue(key, v) then vars.AddOrSetValue(key, v)
  else vars.AddOrSetValue(key, Ask(prompt));
end;

function TMerger.Test(const arg: UStr): Boolean;
var text, left, right: UStr;
    k: Integer;
begin
  text := Strip(Substitute(arg));
  for k := 0 to High(IF_OPS) do
    if Partition(text, IF_OPS[k], left, right) then
      Exit(Condition(StripChars(Strip(left), '"'), IF_OPS[k], StripChars(Strip(right), '"')));
  Result := text <> '';
end;

function TMerger.Run(const text: UStr): UStr;
type TSegs = array of TSeg;
var segs: TSegs;
    passes, lines: TUStrArray;
    outs, stripped, line: UStr;
    i, j, nl, pc, steps, rep, pass, k: Integer;
    usesData, skipping, readAny, exhausted, outer, was: Boolean;
    stack: array of record outer, skip: Boolean; end;
    sg: TSeg;
    cmdline: UStr;

  procedure AddSeg(isCmd: Boolean; const t: UStr);
  begin
    SetLength(segs, Length(segs) + 1);
    segs[High(segs)].isCmd := isCmd;
    if isCmd then
    begin
      segs[High(segs)].cmd := Lower(Copy(t, 2, 2));
      segs[High(segs)].arg := Strip(Copy(t, 4, MaxInt));
    end
    else segs[High(segs)].text := t;
  end;

begin
  { split: text, command (newlines after it dropped), text, ... }
  segs := nil;
  i := 1;
  j := Pos(MARK, text);
  while True do
  begin
    if j = 0 then
    begin
      AddSeg(False, Copy(text, i, MaxInt));
      Break;
    end;
    k := Pos(MARK, text, j + 1);
    if k = 0 then
    begin
      AddSeg(False, Copy(text, i, MaxInt));
      Break;
    end;
    AddSeg(False, Copy(text, i, j - i));
    cmdline := Copy(text, j + 1, k - j - 1);
    AddSeg(True, cmdline);
    i := k + 1;
    nl := 0;
    while (nl < 2) and (i <= Length(text)) and (text[i] = #10) do begin Inc(i); Inc(nl); end;
    j := Pos(MARK, text, i);
  end;
  usesData := False;
  rep := 1;
  for sg in segs do
    if sg.isCmd then
    begin
      if (sg.cmd = 'df') or (sg.cmd = 'rv') then usesData := True;
      if sg.cmd = 'rp' then rep := Max(1, Trunc(ToNumber(sg.arg)));
    end;
  passes := nil;
  for pass := 1 to 100000 do                       { guard against endless merges }
  begin
    outs := '';
    stack := nil;
    skipping := False; readAny := False; exhausted := False;
    pc := 0; steps := 0;
    while pc < Length(segs) do
    begin
      sg := segs[pc];
      Inc(pc);
      Inc(steps);
      if steps > 1000000 then                       { .go t without data to end it }
      begin
        Append(messages, 'merge stopped: endless .go t loop');
        exhausted := True;
        Break;
      end;
      if not sg.isCmd then
      begin
        if not skipping then outs := outs + Substitute(sg.text);
        Continue;
      end;
      if sg.cmd = 'if' then
      begin
        SetLength(stack, Length(stack) + 1);
        stack[High(stack)].outer := skipping;
        stack[High(stack)].skip := skipping or not Test(sg.arg);
        skipping := stack[High(stack)].skip;
      end
      else if sg.cmd = 'el' then
      begin
        if Length(stack) > 0 then
        begin
          outer := stack[High(stack)].outer;
          was := stack[High(stack)].skip;
          skipping := outer or not was;
          stack[High(stack)].skip := skipping;
        end;
      end
      else if sg.cmd = 'ei' then
      begin
        if Length(stack) > 0 then
        begin
          skipping := stack[High(stack)].outer;
          SetLength(stack, Length(stack) - 1);
        end;
      end
      else if skipping then Continue
      else if sg.cmd = 'df' then
      begin
        if data = nil then OpenData(sg.arg);
      end
      else if sg.cmd = 'rv' then
      begin
        if not ReadRecord(sg.arg) then
        begin
          exhausted := True;
          Break;
        end;
        readAny := True;
      end
      else if sg.cmd = 'sv' then SetVar(sg.arg)
      else if sg.cmd = 'ma' then DoMath(sg.arg)
      else if sg.cmd = 'av' then AskVar(sg.arg)
      else if sg.cmd = 'go' then
      begin
        if Lower(Copy(sg.arg, 1, 1)) = 't' then pc := 0 else Break;
      end
      else if ((sg.cmd = 'dm') or (sg.cmd = 'cs')) and (sg.arg <> '') then
        Append(messages, Substitute(sg.arg));
    end;
    if exhausted then
    begin
      { data ran out: what this copy printed so far (e.g. labels via .go t) is kept }
      if Strip(outs) <> '' then Append(passes, outs);
      Break;
    end;
    Append(passes, outs);
    if (usesData and not readAny) or (not usesData and (Length(passes) >= rep)) then Break;
  end;
  for k := 0 to High(passes) do passes[k] := StripChars(passes[k], #10);
  Result := JoinStr(passes, separator);
  { a line holding only empty /o variables disappears }
  lines := nil;
  for line in SplitStr(Result, #10) do
  begin
    stripped := Replace(line, OMIT, '');
    if not (Contains(line, OMIT) and (Strip(stripped) = '')) then Append(lines, line);
  end;
  Result := Replace(JoinStr(lines, #10), OMIT, '');
end;

function MergeText(const text: UStr; const baseDir, docPath: string; preset: TVars; textmode: Boolean;
                   codepage: Integer): UStr;
var m: TMerger;
    sep, msg: UStr;
begin
  if textmode then sep := #10 else sep := #10#10;
  m := TMerger.Create(baseDir, docPath, preset, sep, codepage);
  try
    Result := m.Run(text);
    if not textmode then Result := CollapseNewlines(Result);
    for msg in m.messages do WriteLn(StdErr, U8(msg));
  finally
    m.Free;
  end;
end;

function TableText(const rows: TRows; textmode: Boolean): UStr;
{ A worksheet or dBASE range as a Markdown table (first row is the header) or tab-separated lines }
var width, k, c: Integer;
    lines: TUStrArray;
    r: TUStrArray;
begin
  if Length(rows) = 0 then Exit('');
  lines := nil;
  if textmode then
  begin
    for k := 0 to High(rows) do Append(lines, JoinStr(rows[k], #9));
    Exit(JoinStr(lines, #10));
  end;
  width := 0;
  for k := 0 to High(rows) do width := Max(width, Length(rows[k]));
  for k := 0 to High(rows) do
  begin
    r := Copy(rows[k]);
    for c := 0 to High(r) do r[c] := Replace(r[c], '|', '\|');
    while Length(r) < width do Append(r, '');
    Append(lines, '| ' + JoinStr(r, ' | ') + ' |');
    if k = 0 then Append(lines, '|' + RepeatStr('---|', width));
  end;
  Result := JoinStr(lines, #10);
end;

end.

{ Plain text and Markdown to a WordStar document in the WordStar 4 style (no header): hard returns
  CR LF, soft returns 8Dh LF where a paragraph is wrapped at the right margin (the space before the
  break stays, as WordStar keeps it), soft spaces A0h for the hanging indent of list items, print
  controls ^B / ^Y / ^X for Markdown emphasis. Characters above 7Fh are written as extended
  characters 1Bh xx 1Ch, since WordStar 4 uses the high bit of text bytes for formatting. }
unit wsfrom;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, uregexpr, wsutil, wsdoc;

const
  RIGHT_MARGIN = 65;                   { WordStar's default .rm }

{ s: the input text; missing counts the characters the code page lacks (written as "?") }
function ToWs(const s: UStr; markdown: Boolean; cp: Integer; out missing: Integer): RawByteString;

implementation

const
  C_BOLD = #2; C_STRIKE = #$18; C_ITALIC = #$19;
  TAB_WIDTH = 5;                       { WordStar's default tab stops }

var
  gCp, gMissing: Integer;

function Raw(b: Byte; n: Integer = 1): RawByteString;
{ n bytes b; a literal like #$8D#10 is converted from UTF-8 to the DOS code page (as "?") by go32v2 }
begin
  SetLength(Result, n);
  if n > 0 then FillChar(Result[1], n, b);
end;

function Enc(c: WideChar): RawByteString;
var b: Integer;
begin
  if c < #$80 then
  begin
    if (c >= ' ') and (c <> #$7F) or (c in [#9, C_BOLD, C_STRIKE, C_ITALIC]) then Result := AnsiChar(Ord(c))
    else Result := '';                 { other control characters would be print controls }
    Exit;
  end;
  b := ExtByte(c, gCp);
  if b >= 0 then Exit(#$1B + AnsiChar(b) + #$1C);
  case c of
    #$2018, #$2019, #$201A, #$2032: Result := '''';
    #$201C, #$201D, #$201E, #$00AB, #$00BB, #$2033: Result := '"';
    #$2013, #$2014, #$2012, #$2212: Result := '-';
    #$2026: Result := '...';
    #$00A0, #$2002, #$2003, #$2009, #$202F: Result := ' ';
    #$FEFF, #$200B, #$00AD: Result := '';
  else
    Inc(gMissing);
    Result := '?';
  end;
end;

function EncStr(const s: UStr): RawByteString;
var c: WideChar;
begin
  Result := '';
  for c in s do Result := Result + Enc(c);
end;

function Wrap(const par: UStr; hang: Integer): RawByteString;
{ par as lines of at most RIGHT_MARGIN columns: words (with their trailing spaces) are moved to a new
  line (soft return, then hang soft spaces) when they don't fit; a word longer than a line stays whole }
var
  i, j, col, w, start: Integer;
  word: Boolean;
  tok: UStr;

  function Width(const t: UStr; at: Integer): Integer;
  var c: WideChar;
  begin
    Result := at;
    for c in t do
      if c = #9 then Result := (Result div TAB_WIDTH + 1) * TAB_WIDTH
      else if c >= ' ' then Inc(Result);
    Result := Result - at;
  end;

begin
  Result := '';
  col := 0;
  i := 1;
  while i <= Length(par) do
  begin
    j := i;                                              { token: a word, then its spaces }
    while (j <= Length(par)) and (par[j] <> ' ') do Inc(j);
    start := j;
    while (j <= Length(par)) and (par[j] = ' ') do Inc(j);
    tok := Copy(par, i, j - i);
    word := start > i;
    w := Width(Copy(par, i, start - i), col);
    if word and (col > 0) and (col + w > RIGHT_MARGIN) and (col > hang) then
    begin
      Result := Result + Raw($8D) + #10 + Raw($A0, hang);
      col := hang;
    end;
    if (col = 0) and (tok[1] = '.') then Result := Result + Raw($A0);   { else the line would be a dot command }
    Result := Result + EncStr(tok);
    col := col + Width(tok, col);
    i := j;
  end;
  Result := Result + #13#10;
end;

{ ---- plain text: each line is a paragraph }

function TextToWs(const lines: TUStrArray): RawByteString;
var line: UStr;
begin
  Result := '';
  for line in lines do
    if line = #12 then Result := Result + '.pa'#13#10  { form feed: page break }
    else Result := Result + Wrap(line, 0);
end;

{ ---- Markdown }

function IsAlnum(c: WideChar): Boolean;
begin
  Result := (c >= '0') and (c <= '9') or (c >= 'A') and (c <= 'Z') or (c >= 'a') and (c <= 'z')
            or (c >= #$C0) and (c <> #$D7) and (c <> #$F7);
end;

function InlineMd(const s: UStr): UStr;
{ emphasis to print controls (** __ bold, * _ italic, ~~ strikeout), links and images to their text,
  code spans and backslash escapes to literal text }
var
  i, j, n, k: Integer;
  bold, italic, strike: Boolean;
  prev, next: WideChar;
  m, code, res: UStr;

  function Toggle(var state: Boolean; ctrl: WideChar; len: Integer; under: Boolean): Boolean;
  begin
    if i > 1 then prev := s[i - 1] else prev := ' ';
    if i + len <= Length(s) then next := s[i + len] else next := ' ';
    if state then Result := not IsSpace(prev) and not (under and IsAlnum(next))
    else Result := not IsSpace(next) and not (under and IsAlnum(prev));
    if Result then
    begin
      state := not state;
      res := res + ctrl;
      Inc(i, len);
    end;
  end;

begin
  res := '';
  bold := False; italic := False; strike := False;
  i := 1;
  while i <= Length(s) do
  begin
    m := Copy(s, i, 2);
    if (s[i] = '\') and (i < Length(s)) and (Pos(s[i + 1], '\`*_{}[]()#+-.!|~<>') > 0) then
    begin
      res := res + s[i + 1];
      Inc(i, 2);
      Continue;
    end;
    if s[i] = '`' then
    begin
      n := 0;
      while (i + n <= Length(s)) and (s[i + n] = '`') do Inc(n);
      code := RepeatStr('`', n);
      k := Pos(code, Copy(s, i + n, MaxInt));
      if k > 0 then
      begin
        res := res + Strip(Copy(s, i + n, k - 1));
        Inc(i, n + k - 1 + n);
      end
      else
      begin
        res := res + code;
        Inc(i, n);
      end;
      Continue;
    end;
    if (s[i] = '[') or (m = '![') then
    begin
      j := i;
      if s[j] = '!' then Inc(j);
      k := Pos('](', Copy(s, j, MaxInt));
      if k > 0 then
      begin
        n := Pos(')', Copy(s, j + k + 1, MaxInt));
        if n > 0 then
        begin
          res := res + InlineMd(Copy(s, j + 1, k - 2));
          i := j + k + n + 1;
          Continue;
        end;
      end;
    end;
    if (s[i] = '<') and (ReMatch('<((?:https?|ftp|mailto):[^>\s]*)>', Copy(s, i, MaxInt)) <> nil) then
    begin
      code := Group(ReMatch('<((?:https?|ftp|mailto):[^>\s]*)>', Copy(s, i, MaxInt)), 1);
      res := res + code;
      Inc(i, Length(code) + 2);
      Continue;
    end;
    if (m = '**') and Toggle(bold, C_BOLD, 2, False) then Continue;
    if (m = '__') and Toggle(bold, C_BOLD, 2, True) then Continue;
    if (m = '~~') and Toggle(strike, C_STRIKE, 2, False) then Continue;
    if (s[i] = '*') and Toggle(italic, C_ITALIC, 1, False) then Continue;
    if (s[i] = '_') and Toggle(italic, C_ITALIC, 1, True) then Continue;
    res := res + s[i];
    Inc(i);
  end;
  if bold then res := res + C_BOLD;                        { WordStar would keep them on past the paragraph }
  if italic then res := res + C_ITALIC;
  if strike then res := res + C_STRIKE;
  Result := res;
end;

function MarkdownToWs(const lines: TUStrArray): RawByteString;
var
  k: Integer;
  line, par, fence, marker: UStr;
  hang: Integer;
  r: TRegExpr;
  inPar: Boolean;

  procedure Flush;
  var hard: TUStrArray;
      h: Integer;
  begin
    if not inPar then Exit;
    hard := SplitStr(par, #10);                          { hard line breaks }
    for h := 0 to High(hard) do
      if h = 0 then Result := Result + Wrap(InlineMd(RStrip(hard[h])), hang)
      else Result := Result + Wrap(RepeatStr(' ', hang) + InlineMd(RStrip(hard[h])), hang);
    inPar := False;
  end;

  procedure Start(const text: UStr; aHang: Integer);
  begin
    Flush;
    par := text;
    hang := aHang;
    inPar := True;
  end;

  procedure AddLine(const text: UStr);                   { a line continuing the paragraph }
  var t: UStr;
  begin
    t := LStrip(text);
    if EndsWith(par, '  ') or EndsWith(par, '\') then par := RStripChars(RStrip(par), '\') + #10 + t
    else par := RStrip(par) + ' ' + t;
  end;

begin
  Result := '';
  inPar := False;
  fence := '';
  hang := 0;
  for k := 0 to High(lines) do
  begin
    line := lines[k];
    if fence <> '' then                                  { inside a fenced code block: as is }
    begin
      if StartsWith(Strip(line), fence) then fence := ''
      else Result := Result + EncStr(line) + #13#10;
      Continue;
    end;
    r := ReMatch(' {0,3}(```+|~~~+)', line);
    if r <> nil then
    begin
      Flush;
      fence := Group(r, 1);
      Continue;
    end;
    if line = #12 then
    begin
      Flush;
      Result := Result + '.pa'#13#10;
      Continue;
    end;
    if Strip(line) = '' then
    begin
      Flush;
      Result := Result + #13#10;
      Continue;
    end;
    if inPar and (hang = 0) and (ReFull(' {0,3}(=+|-+) *', line) <> nil) then
    begin                                                { setext heading underline }
      par := C_BOLD + par + C_BOLD;
      Flush;
      Continue;
    end;
    if ReFull(' {0,3}([-*_])( *\1){2,} *', line) <> nil then
    begin
      Flush;
      Result := Result + StringOfChar('-', RIGHT_MARGIN) + #13#10;
      Continue;
    end;
    r := ReMatch(' {0,3}(#{1,6}) +', line);
    if (r <> nil) or (ReFull(' {0,3}#{1,6}', line) <> nil) then
    begin
      Flush;
      line := ReSubStr('(^| +)#+ *$', LStripChars(Strip(line), '#'), '');   { closing #s }
      Result := Result + Wrap(C_BOLD + InlineMd(Strip(line)) + C_BOLD, 0);
      Continue;
    end;
    if StartsWith(LStrip(line), '|') then                { table row: as is }
    begin
      Flush;
      Result := Result + EncStr(InlineMd(RStrip(line))) + #13#10;
      Continue;
    end;
    r := ReMatch('( *)([-*+]|\d{1,9}[.)])( +|$)', line);
    if r <> nil then
    begin
      marker := Group(r, 2);
      if Pos(marker[1], '*+') > 0 then marker := '-';
      marker := Group(r, 1) + marker + ' ';
      Start(marker + Copy(line, Length(Group(r, 0)) + 1, MaxInt), Length(marker));
      Continue;
    end;
    r := ReMatch(' {0,3}> ?', line);
    if r <> nil then
    begin
      line := Copy(line, Length(Group(r, 0)) + 1, MaxInt);
      if inPar and (hang = 4) and StartsWith(par, '    ') then AddLine(line)
      else Start('    ' + line, 4);
      Continue;
    end;
    if not inPar and ((line[1] = #9) or StartsWith(line, '    ')) then
    begin                                                { indented code block }
      Result := Result + EncStr(line) + #13#10;
      Continue;
    end;
    if inPar then AddLine(line) else Start(LStrip(line), 0);
  end;
  Flush;
end;

function ToWs(const s: UStr; markdown: Boolean; cp: Integer; out missing: Integer): RawByteString;
var lines: TUStrArray;
    t: UStr;
begin
  gCp := cp;
  gMissing := 0;
  t := Replace(Replace(s, #13#10, #10), #13, #10);
  if StartsWith(t, #$FEFF) then Delete(t, 1, 1);
  if EndsWith(t, #10) then SetLength(t, Length(t) - 1);
  t := Replace(t, #12, #10#12#10);                     { a form feed on its own line }
  lines := SplitStr(t, #10);
  if markdown then Result := MarkdownToWs(lines) else Result := TextToWs(lines);
  missing := gMissing;
end;

end.

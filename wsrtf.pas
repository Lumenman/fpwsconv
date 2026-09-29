{ WordStar (5.x-7.0) to RTF (port of wsrtf.py).
  Uses the same reading of the file as the Markdown writer but keeps the layout: fonts and sizes
  (font tags), character attributes, alignment, margins and indents (.po .lm .rm .pm .mt .mb .pl .ls
  .oj), centered / right-aligned lines, page breaks, headers / footers with page numbers, footnotes
  and endnotes, heading styles, paragraph numbers and pictures (PNG embedded). No merge printing. }
unit wsrtf;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, Math, uregexpr, wsutil, wsdoc, wsmerge, wsimage;

type
  TTab = record pos: Integer; dec: Boolean; end;

  TLayout = class
    { Page and paragraph settings from dot commands (WordStar defaults: 66-line page, margins 3/8
      lines, page offset 8 columns, left margin 1, right margin 65 = 6.4") }
    pl, mt, mb, po, lm, rm, pm: Integer;
    hasPm: Boolean;
    align: Char;
    spacing: Integer;
    header, footer: UStr;
    tabs: array of TTab;             { none = every 0.5" (RTF default too) }
    cols, gutter: Integer;
    kern: Boolean;                   { .kr (on unless turned off) }
    newSection, started: Boolean;
    constructor Create;
    procedure Dot(const cmd, arg: UStr);
    function Pard(alignLine: Char = #0): UStr;
    function Columns: UStr;
    function Width: Integer;
    function Section: UStr;
  end;

  TFontList = class
    names: TUStrArray;
    function Index(const name: UStr): Integer;
  end;

  TRtfWriter = class
    data: TData;
    baseDir, docPath: string;
    kind: TFileKind;
    cp, depth: Integer;
    styles: TStyles;
    fonts: TFontList;
    ownFonts, ownLayout: Boolean;
    layout: TLayout;
    images: Integer;
    quotes: Boolean;                 { straight quotes -> typographic }
    constructor Create(const aData: TData; const aBaseDir: string; aCodepage, aDepth: Integer;
                       aFonts: TFontList; const aDocPath: string; aQuotes: Boolean);
    destructor Destroy; override;
    function ColorRtf(n: Integer): UStr;
    function FontTag(const p: TData): UStr;
    function FontRtf(height, style: Integer): UStr;
    function ApplyStyle(const st: TStyle): UStr;
    function Picture(const name: UStr): UStr;
    function Note(nkind: Integer; const p: TData): UStr;
    function Body(const d: TData; inNote: Boolean = False): UStr;
    procedure DotCommand(const line: UStr; var para: TUStrArray);
    function HF(const text, hkind: UStr): UStr;
    function Document: UStr;
  end;

function ConvertFileRtf(const path, outPath: string; codepage: Integer; quotes: Boolean;
                        out written: string; out images: Integer): Boolean;

implementation

const
  TWIP = 1440;                        { twips per inch }
  HMI = 1440 / 1800;                  { twips per horizontal motion index (1/1800") }

{ typestyle number (low 9 bits of the font tag's typestyle word) -> font name in RTF; the WordStar 7
  list ("File Format for WordStar Release 7.0") mapped to fonts present today }
function TypeStyle(n: Integer): UStr;
begin
  case n of
    0, 1, 2, 3, 6, 8, 48, 130: Result := 'Courier New';
    4, 145: Result := 'Arial';
    5, 31, 146: Result := 'Times New Roman';
    7: Result := 'Script';
    9: Result := 'Caslon';
    10: Result := 'Orator';
    12, 45, 91: Result := 'Arial Narrow';
    16: Result := 'Century';
    18: Result := 'Garamond';
    22: Result := 'Bodoni';
    23, 72: Result := 'Century Schoolbook';
    24, 46: Result := 'Univers';
    49: Result := 'Optima';
    51: Result := 'American Typewriter';
    52: Result := 'Century Gothic';
    58: Result := 'Franklin Gothic Medium';
    61: Result := 'Futura';
    64: Result := 'Goudy Old Style';
    67: Result := 'Lucida Bright';
    71: Result := 'Baskerville Old Face';
    74: Result := 'Palatino Linotype';
    79: Result := 'Souvenir';
    81: Result := 'Monotype Corsiva';
    82: Result := 'Wingdings';
    94: Result := 'Lucida Sans';
    95: Result := 'Memphis';
    115: Result := 'Gill Sans MT';
    116: Result := 'Rockwell';
    123, 151: Result := 'Bookman Old Style';
  else Result := '';
  end;
end;

const
  { attribute toggles, in the order the Python version keeps them (dict.fromkeys(TOGGLES.values())) }
  TOGGLE_NAMES: array[0..5] of UStr = ('b', 'ul', 'i', 'strike', 'super', 'sub');

function ToggleIndex(c: Integer): Integer;
begin
  case c of
    $02, $04: Result := 0;
    $13: Result := 1;
    $19: Result := 2;
    $18: Result := 3;
    $14: Result := 4;
    $16: Result := 5;
  else Result := -1;
  end;
end;

type TRGB = array[0..2] of Byte;
const
  { WordStar colour numbers (^P-, colour tag, style colour) -> RGB: the 16 EGA colours; \colortbl
    entry n + 1 (entry 0 = auto). 0Fh ("white on black" on screen) prints white. }
  COLORS: array[0..15] of TRGB = ((0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0),
    (170, 0, 170), (170, 85, 0), (170, 170, 170), (85, 85, 85), (85, 85, 255), (85, 255, 85),
    (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255));

function RtfText(const s: UStr): UStr;
{ RTF escapes; non-ASCII characters as \uN? (Unicode, ? for readers without Unicode) }
var k, o: Integer;
begin
  Result := '';
  for k := 1 to Length(s) do
  begin
    o := Ord(s[k]);
    if CharIn(s[k], '\{}') then Result := Result + '\' + s[k]
    else if o < $80 then Result := Result + s[k]
    else if o > $7FFF then Result := Result + '\u' + UStr(IntToStr(o - $10000)) + '?'
    else Result := Result + '\u' + UStr(IntToStr(o)) + '?';
  end;
end;

function Field(const inst, res: UStr): UStr;
begin
  Result := '{\field{\*\fldinst ' + inst + '}{\fldrslt ' + res + '}}';
end;

const BS = #92;                        { backslash: keeps \u + digits out of literals }

function Dashes(const rtf: UStr): UStr;
{ -- -> em dash, ... -> ellipsis in a paragraph's RTF (spaces around the dash kept as typed). Not
  after a backslash: \- is a soft hyphen. }
var i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(rtf) do
    if (i < Length(rtf)) and (rtf[i] = '-') and (rtf[i + 1] = '-') and ((i = 1) or (rtf[i - 1] <> '\')) then
    begin
      Result := Result + BS + 'u8212?';
      Inc(i, 2);
    end
    else
    begin
      Result := Result + rtf[i];
      Inc(i);
    end;
  Result := Replace(Result, '...', BS + 'u8230?');
end;

function SysVars(const rtf: UStr; const docPath: string): UStr;
{ WordStar's system variables (filled in at print time): page, date, time -> RTF fields the word
  processor fills in; file name and path -> those of the WordStar document (as text) }
var i: Integer;
    rest: UStr;
begin
  Result := '';
  i := 1;
  while i <= Length(rtf) do
  begin
    rest := Copy(rtf, i, 5);
    if StartsWith(rest, '&#&') then begin Result := Result + Field('PAGE', '1'); Inc(i, 3); end
    else if StartsWith(rest, '&@&') then begin Result := Result + Field('DATE \\@ "MMMM d, yyyy"', 'date'); Inc(i, 3); end
    else if StartsWith(rest, '&!&') then begin Result := Result + Field('TIME \\@ "h:mm am/pm"', 'time'); Inc(i, 3); end
    else if StartsWith(rest, '&*&') then
    begin
      Result := Result + RtfText(UTF8Decode(ExtractFileName(docPath)));
      Inc(i, 3);
    end
    else if StartsWith(rest, '&\\&') then
    begin
      if docPath <> '' then Result := Result + RtfText(UTF8Decode(ExpandFileName(docPath)));
      Inc(i, 4);
    end
    else
    begin
      Result := Result + rtf[i];
      Inc(i);
    end;
  end;
end;

function Measure(const arg: UStr; unitTw: Double; out v: Integer): Boolean;
{ Dot command value in twips: a number with " is inches, otherwise lines (1/6") or columns (1/10") }
var r: TRegExpr;
    x: Double;
begin
  r := ReMatch('\s*(-?(?:\d+(?:\.\d*)?|\.\d+))\s*(")?', arg);
  Result := r <> nil;
  v := 0;
  if not Result then Exit;
  ParsePyFloat(Group(r, 1), x);
  if HasGroup(r, 2) then v := Round(x * TWIP) else v := Round(x * unitTw);
end;

function FloorDiv(a, b: Integer): Integer;
begin
  Result := Floor(a / b);
end;

{ ---------------------------------------------------------------- layout }

constructor TLayout.Create;
begin
  pl := 11 * TWIP; mt := TWIP div 2; mb := TWIP * 4 div 3; po := TWIP * 8 div 10;
  lm := 0; rm := Round(6.4 * TWIP); hasPm := False; pm := 0;
  align := 'l'; spacing := 1; header := ''; footer := '';
  tabs := nil;
  cols := 1; gutter := TWIP div 5;
  kern := True;
  newSection := False; started := False;
end;

procedure TLayout.Dot(const cmd, arg: UStr);
const col = TWIP div 10; line = TWIP div 6;
var a, t, u: UStr;
    v, k: Integer;
    parts: TUStrArray;
    ch: WideChar;
    found: Boolean;
begin
  a := Lower(Strip(arg));
  if cmd = 'tb' then
  begin
    { .tb 5,11,#20 or .tb 1.8" 3.2": columns (1 = the left edge) or inches; # = decimal tab }
    tabs := nil;
    for t in ReSplit('[,\s]+', a) do
      if Measure(LStripChars(t, '#'), col, v) then
      begin
        SetLength(tabs, Length(tabs) + 1);
        if Contains(t, '"') then tabs[High(tabs)].pos := v else tabs[High(tabs)].pos := v - col;
        tabs[High(tabs)].dec := StartsWith(t, '#');
      end;
  end
  else if cmd = 'rr' then
  begin
    { the ruler as shown above the text: ".rr" covers columns 1-3, its characters start at column 4
      (L left, R right, V paragraph margin, ! tab, # decimal tab) }
    u := Upper(RStrip(arg));
    if Contains(u, 'R') then
    begin
      lm := 0;
      for k := 1 to Length(u) do if u[k] = 'L' then begin lm := (k + 2) * col; Break; end;
      for k := 1 to Length(u) do if u[k] = 'R' then begin rm := (k + 2) * col; Break; end;
      hasPm := False;
      for k := 1 to Length(u) do if u[k] = 'V' then begin pm := (k + 2) * col; hasPm := True; Break; end;
      tabs := nil;
      for k := 1 to Length(u) do
      begin
        ch := u[k];
        if (ch = '!') or (ch = '#') then
        begin
          SetLength(tabs, Length(tabs) + 1);
          tabs[High(tabs)].pos := (k + 2) * col;
          tabs[High(tabs)].dec := ch = '#';
        end;
      end;
    end;
  end
  else if cmd = 'kr' then kern := not ((a = 'off') or (a = '0') or (a = 'n') or (a = 'no'))
  else if cmd = 'co' then
  begin
    parts := nil;
    for t in ReSplit('[,\s]+', a) do if t <> '' then Append(parts, t);
    cols := 1;
    if Length(parts) > 0 then
    begin
      if not Measure(parts[0], 1, v) or (v = 0) then v := 1;
      cols := Max(1, v);
    end;
    if (Length(parts) > 1) and Measure(parts[1], col, v) then gutter := v;
  end
  else if cmd = 'pl' then
  begin
    if Measure(arg, line, v) and (v <> 0) then pl := v;
  end
  else if cmd = 'mt' then begin if Measure(arg, line, v) then mt := v; end
  else if cmd = 'mb' then begin if Measure(arg, line, v) then mb := v; end
  else if (cmd = 'po') or (cmd = 'poe') or (cmd = 'poo') then begin if Measure(arg, col, v) then po := v; end
  else if cmd = 'lm' then
  begin
    if Measure(arg, col, v) then if Contains(arg, '"') then lm := v else lm := v - col;   { column 1 = 0" }
  end
  else if cmd = 'rm' then
  begin
    if Measure(arg, col, v) then if Contains(arg, '"') then rm := v else rm := v - col;
  end
  else if cmd = 'pm' then
  begin
    found := Measure(arg, col, v);
    hasPm := found;
    if found then if Contains(arg, '"') then pm := v else pm := v - col;
  end
  else if cmd = 'ls' then
  begin
    if not Measure(arg, 1, v) or (v = 0) then v := 1;
    spacing := Max(1, Min(9, v));
  end
  else if cmd = 'oj' then
  begin
    if a = 'on' then align := 'j'
    else if a = 'off' then align := 'l'
    else if a = 'r' then align := 'r'
    else if a = 'c' then align := 'c';
  end
  else if (cmd = 'he') or (cmd = 'h1') then header := Strip(arg)
  else if (cmd = 'fo') or (cmd = 'f1') then footer := Strip(arg);
end;

function TLayout.Pard(alignLine: Char): UStr;
var colw, k, j: Integer;
    sorted: array of TTab;
    t: TTab;
    al: Char;
begin
  { with columns WordStar's margins are those of one column }
  colw := FloorDiv(Width - (cols - 1) * gutter, cols);
  if alignLine <> #0 then al := alignLine else al := align;
  Result := '\pard\plain';
  if kern then Result := Result + '\kerning1';
  Result := Result + '\q' + al + '\li' + UStr(IntToStr(lm)) + '\ri' + UStr(IntToStr(Max(0, colw - rm)));
  if hasPm then Result := Result + '\fi' + UStr(IntToStr(pm - lm));
  if spacing > 1 then Result := Result + '\sl' + UStr(IntToStr(240 * spacing)) + '\slmult1';
  sorted := Copy(tabs);
  for k := 1 to High(sorted) do                   { sorted by position, then decimal flag }
  begin
    t := sorted[k];
    j := k - 1;
    while (j >= 0) and ((sorted[j].pos > t.pos) or ((sorted[j].pos = t.pos) and sorted[j].dec and not t.dec)) do
    begin
      sorted[j + 1] := sorted[j];
      Dec(j);
    end;
    sorted[j + 1] := t;
  end;
  for t in sorted do
  begin
    if t.dec then Result := Result + '\tqdec';
    Result := Result + '\tx' + UStr(IntToStr(t.pos));
  end;
end;

function TLayout.Columns: UStr;
begin
  Result := '\sectd\sbknone\cols' + UStr(IntToStr(cols)) + '\colsx' + UStr(IntToStr(gutter)) + ' ';
end;

function TLayout.Width: Integer;
begin
  Result := Max(rm, Round(6.4 * TWIP));
end;

function TLayout.Section: UStr;
var paperw: Integer;
begin
  paperw := Round(8.5 * TWIP);
  Result := UStr(Format('\paperw%d\paperh%d\margl%d\margr%d\margt%d\margb%d',
                        [paperw, pl, po, Max(TWIP div 4, paperw - po - Width), mt, mb]));
end;

function TFontList.Index(const name: UStr): Integer;
var k: Integer;
begin
  for k := 0 to High(names) do
    if names[k] = name then Exit(k);
  Append(names, name);
  Result := High(names);
end;

{ ---------------------------------------------------------------- writer }

constructor TRtfWriter.Create(const aData: TData; const aBaseDir: string; aCodepage, aDepth: Integer;
                              aFonts: TFontList; const aDocPath: string; aQuotes: Boolean);
begin
  data := aData;
  baseDir := aBaseDir;
  docPath := aDocPath;
  kind := FileKind(data);
  cp := GuessDocCodepage(data, kind, aCodepage);
  styles := ReadStyles(data, cp);
  depth := aDepth;
  ownFonts := aFonts = nil;
  if ownFonts then
  begin
    fonts := TFontList.Create;
    fonts.Index('Courier New');
  end
  else fonts := aFonts;
  layout := TLayout.Create;
  ownLayout := True;
  images := 0;
  quotes := aQuotes;
end;

destructor TRtfWriter.Destroy;
begin
  if ownFonts then fonts.Free;
  if ownLayout then layout.Free;
  inherited;
end;

function TRtfWriter.ColorRtf(n: Integer): UStr;
{ \cfN for a WordStar colour number; '' for none / inherited }
begin
  if n <= 15 then Result := '\cf' + UStr(IntToStr(n + 1)) + ' ' else Result := '';
end;

function TRtfWriter.FontTag(const p: TData): UStr;
{ \fN\fsM for a font tag: height in 1/1440" (1/20 pt), typestyle word }
begin
  if Length(p) < 6 then Exit('');
  Result := FontRtf(W16(p, 2), W16(p, 4));
end;

function TRtfWriter.FontRtf(height, style: Integer): UStr;
var name: UStr;
    fs: Integer;
begin
  name := TypeStyle(style and $1FF);
  if name = '' then
    if (style shr 10) and 3 = 1 then name := 'Times New Roman'
    else if style and $8000 <> 0 then name := 'Arial'
    else name := 'Courier New';
  if height <> 0 then fs := Max(8, Round(height / 10)) else fs := 24;
  Result := '\f' + UStr(IntToStr(fonts.Index(name))) + '\fs' + UStr(IntToStr(fs)) + ' ';
end;

function TRtfWriter.ApplyStyle(const st: TStyle): UStr;
{ Paragraph style: margins, alignment, spacing into the layout; returns its font (RTF) or '' }
begin
  if st.hasLm then layout.lm := Round(st.lm * HMI);
  if st.hasRm then layout.rm := Round(st.rm * HMI);
  if st.hasPm then
  begin
    layout.pm := Round(st.pm * HMI);
    layout.hasPm := True;
  end
  else if st.hasLm then layout.hasPm := False;
  if st.just <> #0 then layout.align := st.just;
  if st.spacing <> 0 then layout.spacing := st.spacing;
  if st.hasFont then Result := FontRtf(st.fontHeight, st.fontStyle) else Result := '';
end;

function TRtfWriter.Picture(const name: UStr): UStr;
const HEXDIGITS = '0123456789abcdef';
var src: string;
    pic: TPicture;
    png, hex: string;
    w, h, wt, ht, k: Integer;
    lines: TUStrArray;
begin
  src := ImageSource(LocateGraphic(baseDir, string(name)));
  if src = '' then Exit('');
  pic := OpenImage(src);
  if pic.img = nil then Exit('');
  try
    png := PngData(pic.img);
    w := pic.img.Width;
    h := pic.img.Height;
  finally
    pic.img.Free;
  end;
  if png = '' then Exit('');
  Inc(images);
  { scale wide scans down to the text width }
  wt := Round(w / pic.dpi * TWIP);
  ht := Round(h / pic.dpi * TWIP);
  if wt > layout.Width then
  begin
    ht := Round(ht * layout.Width / wt);
    wt := layout.Width;
  end;
  SetLength(hex, 2 * Length(png));
  for k := 1 to Length(png) do
  begin
    hex[2 * k - 1] := HEXDIGITS[Ord(png[k]) shr 4 + 1];
    hex[2 * k] := HEXDIGITS[Ord(png[k]) and 15 + 1];
  end;
  lines := nil;
  k := 1;
  while k <= Length(hex) do
  begin
    Append(lines, UStr(Copy(hex, k, 128)));
    Inc(k, 128);
  end;
  Result := UStr(Format('{\pict\pngblip\picw%d\pich%d\picwgoal%d\pichgoal%d', [w, h, wt, ht])) + #10
            + JoinStr(lines, #10) + '}';
end;

function TRtfWriter.Note(nkind: Integer; const p: TData): UStr;
var text, alt: UStr;
begin
  text := Strip(Body(Slice(p, 5, Length(p)), True));
  if nkind = SEQ_ANNOTATION then Exit('{\chatn{\*\annotation\pard\plain ' + text + '}}');
  if nkind = SEQ_ENDNOTE then alt := '\ftnalt' else alt := '';
  Result := '{\super\chftn}{\footnote' + alt + '\pard\plain{\super\chftn} ' + text + '}';
end;

function TRtfWriter.Body(const d: TData; inNote: Boolean): UStr;
{ RTF of the text: paragraphs, character formatting, notes }
var outs, para: TUStrArray;
    state: array[0..5] of Boolean;
    alignLine: Char;                  { 'c' / 'r' for a centered / right-aligned line }
    dotline: UStr;
    inDot, lineStart, tabbed: Boolean;
    heading, font, color, prev, ch, s, f: UStr;
    i, nx: SizeInt;
    c, skind, k, level, b: Integer;
    p: TData;
    st: TStyle;
    r: TRegExpr;
    tri: array[0..3] of TTri;
    on: Boolean;

  procedure Put(ch: UStr; nxt: Integer);
  var opening: Boolean;
  begin
    if quotes and ((ch = '"') or (ch = '''')) then
    begin
      opening := IsSpace(prev[1]) or CharIn(prev[1], '([{<-/–—“‘');
      if (ch = '''') and ((nxt >= $30) and (nxt <= $39) or (nxt = $B2) or (nxt = $B3) or (nxt = $B9)) then
        opening := False;                            { '19, '90s: an apostrophe }
      if ch = '"' then
      begin
        if opening then ch := '“' else ch := '”';
      end
      else if opening then ch := '‘' else ch := '’';
    end;
    Append(para, RtfText(ch));
    prev := ch;
    lineStart := False;
  end;

  procedure Flush;
  var text: UStr;
      j: Integer;
      last: UStr;
  begin
    text := SysVars(JoinStr(para, ''), docPath);
    if quotes then text := Dashes(text);
    if inNote then Append(outs, text + ' ')
    else
    begin
      if layout.newSection then                    { .co: the columns start a section (no page break) }
      begin
        layout.newSection := False;
        if Length(outs) > 0 then
        begin
          last := outs[High(outs)];
          outs[High(outs)] := Copy(last, 1, Max(0, Length(last) - 5)) + '\sect'#10;
        end;
        if layout.started and (Length(outs) = 0) then Append(outs, '\sect' + layout.Columns)
        else Append(outs, layout.Columns);
      end;
      layout.started := True;
      Append(outs, layout.Pard(alignLine) + heading + '{' + text + '}\par'#10);
    end;
    para := nil;
    alignLine := #0;
    heading := '';
    prev := ' ';
    if font <> '' then Append(para, font);        { the font, colour and attributes run on across paragraphs }
    if color <> '' then Append(para, color);
    for j := 0 to 5 do
      if state[j] then Append(para, '\' + TOGGLE_NAMES[j] + ' ');
  end;

  function Off(j: Integer): UStr;
  begin
    if j = 1 then Result := 'none' else Result := '0';
  end;

begin
  outs := nil;
  para := nil;
  for k := 0 to 5 do state[k] := False;
  alignLine := #0;
  inDot := False;
  dotline := '';
  lineStart := True;
  tabbed := False;
  heading := '';
  font := '';
  color := '';
  prev := ' ';                                     { the text's last character (for quotes) }
  i := 0;
  while i < Length(d) do
  begin
    c := DB(d, i);
    if (c = $1A) and not inNote then Break;
    if c = $1D then
    begin
      if not ReadSequence(d, i, skind, p, nx) then
      begin
        if i + W16(d, i + 1) + 3 > Length(d) then i := Length(d) else Inc(i);
        Continue;
      end;
      i := nx;
      tabbed := tabbed or (skind = SEQ_TAB);
      if inDot then Continue;
      if skind in [SEQ_FOOTNOTE, SEQ_ENDNOTE, SEQ_ANNOTATION] then
      begin
        if not inNote then Append(para, Note(skind, p));
      end
      else if (skind = SEQ_TAB) and (Length(p) >= 5) then
      begin
        if DB(p, 4) in [$21, $5B] then             { center / right align line tab (^OC, ^O]) }
        begin
          if DB(p, 4) = $21 then alignLine := 'c' else alignLine := 'r';
        end
        else if DB(p, 4) = $A0 then                 { soft tab: layout of a wrapped line }
        else
        begin
          Append(para, '\tab ');
          prev := ' ';
        end;
        lineStart := False;
      end
      else if skind = SEQ_PARNUM then Append(para, RtfText(ParagraphNumber(p) + ' '))
      else if skind = SEQ_GRAPHIC then
      begin
        s := Strip(DecodeBytes(UntilZero(p), cp));
        if s <> '' then Append(para, Picture(s)) else Append(para, '');
      end
      else if (skind = $01) and (p <> '') then     { colour }
      begin
        color := ColorRtf(DB(p, 0));
        Append(para, color);
      end
      else if skind = $02 then                     { font }
      begin
        font := FontTag(p);
        Append(para, font);
      end
      else if (skind = $15) and (Length(p) >= 7) then   { alternate / normal font: font tag after one byte }
      begin
        font := FontTag(Slice(p, 1, Length(p)));
        Append(para, font);
      end
      else if (skind = SEQ_STYLE) and (Length(p) >= 2) and (DB(p, 0) < Length(styles)) and not inNote then
      begin
        st := styles[DB(p, 0)];
        f := ApplyStyle(st);
        if f <> '' then
        begin
          font := f;
          Append(para, f);
        end;
        if st.color >= 0 then
        begin
          color := ColorRtf(st.color);
          Append(para, color);
        end;
        { a style's attributes hold for its paragraphs only: those it does not set are off (inherited
          from the base style), not carried over from the previous style }
        tri[0] := st.bold; tri[1] := st.italic; tri[2] := st.underline; tri[3] := tNone;
        for b := 0 to 3 do
        begin
          case b of 0: k := 0; 1: k := 2; 2: k := 1; else k := 3; end;   { b, i, ul, strike }
          on := tri[b] = tOn;
          if state[k] <> on then
          begin
            state[k] := on;
            if on then Append(para, '\' + TOGGLE_NAMES[k] + ' ')
            else Append(para, '\' + TOGGLE_NAMES[k] + Off(k) + ' ');
          end;
        end;
        r := ReMatch('(?i)(title)|(sub)?heading\s*(\d)?$|h(\d)$', st.name);
        heading := '';
        if r <> nil then
        begin
          if HasGroup(r, 1) and (Group(r, 1) <> '') then level := 1
          else if HasGroup(r, 4) and (Group(r, 4) <> '') then level := StrToInt(string(Group(r, 4)))
          else
          begin
            if HasGroup(r, 3) and (Group(r, 3) <> '') then level := StrToInt(string(Group(r, 3))) else level := 1;
            if HasGroup(r, 2) and (Group(r, 2) <> '') then Inc(level);
          end;
          heading := '\s' + UStr(IntToStr(Min(level, 3))) + '\outlinelevel' + UStr(IntToStr(Min(level, 3) - 1)) + ' ';
        end;
      end
      else if skind = SEQ_TRUNCATED then Append(para, '<TRUNCATED>');
      Continue;
    end;
    if c = $1B then
    begin
      if (i + 2 < Length(d)) and (DB(d, i + 2) = $1C) then
      begin
        ch := ExtChar(DB(d, i + 1), cp);
        if inDot then dotline := dotline + ch else Put(ch, -1);
        Inc(i, 3);
      end
      else Inc(i);
      Continue;
    end;
    Inc(i);
    if (c >= $80) and (kind <> fkAscii) and not (c in [$8D, $8A, $8C, $A0]) then c := c and $7F;
    { the line end after .cb / .cc is 0Dh 8Ch (a column break marker) }
    if (c = $0D) and inDot and not (DB(d, i) in [$0A, $8A, $8C]) then
    begin
      dotline := dotline + ' ';
      Continue;
    end;
    if c = $0D then
    begin
      if inDot then
      begin
        { .cc (conditional column break) with 8Ch: the column did break when WordStar laid it out }
        if (Lower(Copy(dotline, 2, 2)) = 'cc') and (DB(d, i) = $8C) then Append(para, '\column ');
        DotCommand(dotline, para);
        inDot := False;
        dotline := '';
      end
      else if not inNote then Flush
      else Append(para, ' ');
      lineStart := True;
      tabbed := False;
      Continue;
    end;
    if (c = $8D) and (kind <> fkAscii) then          { soft return: the line goes on }
    begin
      if not inDot and (Length(para) > 0) and not EndsWith(para[High(para)], ' ') then
      begin
        Append(para, ' ');
        prev := ' ';
      end;
      Continue;
    end;
    if c = $1F then                                  { soft hyphen: joins the word at a wrap }
    begin
      if DB(d, i) = $8D then
      begin
        Inc(i);
        if DB(d, i) = $0A then Inc(i);
      end
      else Append(para, '\-');
      Continue;
    end;
    if c < $20 then
    begin
      if inDot then Continue;
      if c = $09 then
      begin
        Append(para, '\tab ');
        prev := ' ';
      end
      else if c = $0F then Append(para, '\~')
      else if c = $0C then Append(para, '\page ')
      else if ToggleIndex(c) >= 0 then
      begin
        k := ToggleIndex(c);
        state[k] := not state[k];
        if state[k] then Append(para, '\' + TOGGLE_NAMES[k] + ' ')
        else Append(para, '\' + TOGGLE_NAMES[k] + Off(k) + ' ');
        if (k >= 4) and not state[k] then para[High(para)] := '\nosupersub ';
      end;
      Continue;
    end;
    if c < $80 then ch := WideChar(c)
    else if kind = fkAscii then ch := DecodeByte(c, cp)
    else Continue;                                   { 8Ah, soft space A0h, 7Fh with the high bit }
    if lineStart and not tabbed and (ch = '.') and not inDot and not inNote then
    begin
      inDot := True;
      dotline := '.';
      lineStart := False;
      Continue;
    end;
    if inDot then dotline := dotline + ch
    else Put(ch, DB(d, i));
  end;
  if inDot then                                      { a dot command on the last line, without CR }
  begin
    DotCommand(dotline, para);
    inDot := False;
  end;
  if Length(para) > 0 then
  begin
    on := False;
    for s in para do if Strip(s) <> '' then on := True;
    if on and not inDot then Flush;
  end;
  Result := JoinStr(outs, '');
end;

procedure TRtfWriter.DotCommand(const line: UStr; var para: TUStrArray);
var cmd, arg, full: UStr;
    path: string;
    d: TData;
    sub: TRtfWriter;
    r: TRegExpr;
begin
  cmd := Strip(Lower(Copy(line, 2, 2)));
  arg := Copy(line, 4, MaxInt);
  if StartsWith(line, '..') or (cmd = 'ig') then Exit;
  if cmd = 'pa' then
  begin
    Append(para, '\page ');
    Exit;
  end;
  if cmd = 'cb' then
  begin
    Append(para, '\column ');
    Exit;
  end;
  if cmd = 'co' then layout.newSection := True;
  if (cmd = 'fi') and (Strip(arg) <> '') and (depth < 7) then
  begin
    path := FindFile(baseDir, string(SplitWS(arg)[0]));
    if (path <> '') and ReadFileData(path, d) then
    begin
      sub := TRtfWriter.Create(d, ExtractFileDir(path), cp, depth + 1, fonts, '', quotes);
      try
        sub.layout.Free;
        sub.layout := layout;
        sub.ownLayout := False;
        Append(para, '}\par'#10 + sub.Body(sub.data) + layout.Pard + '{');
      finally
        sub.Free;
      end;
    end;
    Exit;
  end;
  r := ReMatch('[a-z#]+', Lower(Copy(line, 2, MaxInt)));
  if r <> nil then full := r.Match[0] else full := cmd;
  if (full = 'poe') or (full = 'poo') then
  begin
    cmd := full;
    arg := Copy(line, 5, MaxInt);
  end;
  layout.Dot(cmd, arg);
end;

function TRtfWriter.HF(const text, hkind: UStr): UStr;
{ Header / footer: # is the page number (as in WordStar) }
var bodyText, name, fmt: UStr;
    k: Integer;
    st: TStyle;
    found: Boolean;
begin
  bodyText := JoinStr(SplitStr(SysVars(RtfText(text), docPath), '#'), Field('PAGE', '1'));
  { WordStar formats headers / footers with the styles of these names (when the document has them) }
  if hkind = 'header' then name := 'header at top of page' else name := 'footer at bottom of page';
  found := False;
  for k := 0 to High(styles) do
    if Lower(styles[k].name) = name then
    begin
      st := styles[k];
      found := True;
      Break;
    end;
  if not found then
  begin
    st := Default(TStyle);
    st.color := -1;
  end;
  if st.just <> #0 then fmt := '\q' + st.just else fmt := '\ql';
  if st.hasFont then fmt := fmt + RStrip(FontRtf(st.fontHeight, st.fontStyle));
  if st.color >= 0 then fmt := fmt + RStrip(ColorRtf(st.color));
  if st.bold = tOn then fmt := fmt + '\b';
  if st.italic = tOn then fmt := fmt + '\i';
  if st.underline = tOn then fmt := fmt + '\ul';
  Result := '{\' + hkind + '\pard\plain' + fmt + ' ' + bodyText + '\par}'#10;
end;

function TRtfWriter.Document: UStr;
var text, hfs, fontTbl, styleTbl, colorTbl, head, n, m: UStr;
    k, e: Integer;
begin
  text := Body(data);
  hfs := '';
  if layout.header <> '' then hfs := hfs + HF(layout.header, 'header');
  if layout.footer <> '' then hfs := hfs + HF(layout.footer, 'footer');
  fontTbl := '';
  for k := 0 to High(fonts.names) do
  begin
    n := fonts.names[k];
    if Contains(n, 'Courier') then m := 'modern' else m := 'nil';
    fontTbl := fontTbl + '{\f' + UStr(IntToStr(k)) + '\f' + m + ' ' + n + ';}';
  end;
  styleTbl := '';
  for k := 1 to 3 do
    styleTbl := styleTbl + UStr(Format('{\s%d\outlinelevel%d heading %d;}', [k, k - 1, k]));
  colorTbl := '';
  for k := 0 to 15 do
    colorTbl := colorTbl + UStr(Format('\red%d\green%d\blue%d;', [COLORS[k][0], COLORS[k][1], COLORS[k][2]]));
  head := '{\rtf1\ansi\ansicpg1252\deff0\uc1'#10'{\fonttbl' + fontTbl + '}'#10'{\colortbl;' + colorTbl + '}'#10
          + '{\stylesheet{\s0 Normal;}' + styleTbl + '}'#10'\fet2' + layout.Section + #10;
  { columns from the start: the first section's settings go before the header / footer }
  if StartsWith(text, '\sectd') then
  begin
    e := Pos(' ', text);
    if e > 0 then
    begin
      head := head + Copy(text, 1, e);
      text := Copy(text, e + 1, MaxInt);
    end;
  end;
  Result := head + hfs + text + '}'#10;
end;

function ConvertFileRtf(const path, outPath: string; codepage: Integer; quotes: Boolean;
                        out written: string; out images: Integer): Boolean;
var d: TData;
    w: TRtfWriter;
    rtf: RawByteString;
    f: TFileStream;
begin
  Result := False;
  images := 0;
  written := '';
  if not ReadFileData(path, d) then Exit;
  w := TRtfWriter.Create(d, ExtractFileDir(ExpandFileName(path)), codepage, 0, nil, path, quotes);
  try
    rtf := U8(Replace(w.Document, #10, #13#10));
    images := w.images;
  finally
    w.Free;
  end;
  if outPath <> '' then written := outPath else written := ChangeFileExt(path, '.rtf');
  f := TFileStream.Create(written, fmCreate);
  try
    if rtf <> '' then f.WriteBuffer(rtf[1], Length(rtf));
  finally
    f.Free;
  end;
  Result := True;
end;

end.

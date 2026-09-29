{ WordStar (5.x-7.0) to Markdown / plain text (port of wsconvert.py). }
unit wsmd;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, uregexpr, wsutil, wsdoc, wsmerge, wsimage;

type
  TConverter = class
    data: TData;
    textmode, merge: Boolean;
    baseDir, docPath, imageDir: string;  { imageDir '': pictures are only linked }
    depth: Integer;                      { .fi nesting level (WordStar allows 7) }
    preset: TVars;                       { variable values given on the command line }
    parnumCompound: Boolean;             { .p# ...,c (full number) or ,o (last level only) }
    kind: TFileKind;
    codepage, cp: Integer;               { codepage as given (0: guess for every file separately) }
    styles: TStyles;
    images: TUStrArray;                  { PNG files written }
    constructor Create(const aData: TData; aTextmode: Boolean; const aBaseDir: string; aDepth: Integer;
                       aMerge: Boolean; aPreset: TVars; const aDocPath: string; aCodepage: Integer;
                       const aImageDir: string);
    function Convert: UStr;
    function ConvertChunk(const chunk: TData; isChunk, inNote: Boolean): UStr;
    function DotCommand(const line: UStr): UStr;
    function InsertFile(const name, spec: UStr): UStr;
    function Graphic(const name: UStr): UStr;
    function Sequence(skind: Integer; const p: TData; inNote, lineStart: Boolean): UStr;
  end;

function MdBlocks(const text: UStr): UStr;

implementation

const
  MERGE_COMMANDS: array[0..11] of UStr = ('df', 'rv', 'sv', 'ma', 'av', 'if', 'el', 'ei', 'go', 'rp', 'dm', 'cs');

{ control code -> markdown marker (toggles) }
function MdMark(c: Integer; out m: UStr): Boolean;
begin
  Result := True;
  case c of
    $02, $04: m := '**';                { bold; double strike -> bold }
    $13, $19: m := '*';                 { underline -> italic; italic }
    $14: m := '^';                      { superscript (pandoc) }
    $16: m := '~';                      { subscript (pandoc) }
    $18: m := '~~';                     { strikeout }
  else Result := False;
  end;
end;

function StylePrefix(const name: UStr): UStr;
{ Markdown heading prefix for a paragraph style name }
var n: UStr;
    r: TRegExpr;
    level: Integer;
begin
  n := Lower(name);
  if n = 'title' then Exit('# ');
  if StartsWith(n, 'subheading') then Exit('### ');
  r := ReFull('heading\s*(\d)?', n);
  if r <> nil then
  begin
    if HasGroup(r, 1) then level := StrToInt(string(Group(r, 1))) else level := 1;
    if level + 1 > 6 then level := 5;
    Exit(RepeatStr('#', level + 1) + ' ');
  end;
  Result := '';
end;

const
  BOX_SEP = '│║';                        { vertical box-drawing characters used as column rules }
  BOX_RULE = '─═┼╪╫╬┌┐└┘├┤┬┴╔╗╚╝╠╣╦╩╒╕╘╛╞╡╤╧╓╖╙╜╟╢╥╨-+=|│║ ';

function TableCells(const line: UStr; out cells: TUStrArray): Boolean;
{ Cells of a table row (tab- or box-separated); [] for a pure border line; False if not a row }
var k: Integer;
    allRule, hasSep: Boolean;
    s: UStr;
begin
  cells := nil;
  allRule := True;
  hasSep := False;
  for k := 1 to Length(line) do
  begin
    if not CharIn(line[k], BOX_RULE) then allRule := False;
    if CharIn(line[k], BOX_SEP) then hasSep := True;
  end;
  if allRule and (Contains(line, '─') or Contains(line, '═') or Contains(line, '-')) then Exit(True);
  if hasSep then
  begin
    cells := ReSplit('[│║]', Strip(line));
    if (Length(cells) > 0) and (Strip(cells[0]) = '') then cells := Copy(cells, 1, MaxInt);
    if (Length(cells) > 0) and (Strip(cells[High(cells)]) = '') then SetLength(cells, Length(cells) - 1);
  end
  else if Contains(line, #9) then
    { ponytail: runs of tabs are one separator (tabs also align columns), so empty cells collapse }
    cells := ReSplit('\t+', StripChars(line, #9))
  else Exit(False);
  for k := 0 to High(cells) do
  begin
    s := Strip(cells[k]);
    cells[k] := Replace(s, '|', '\|');
  end;
  Result := Length(cells) >= 2;
  if not Result then cells := nil;
end;

function ListItem(const p: UStr; out item: UStr): Boolean;
{ LIST_ITEM = ^[ \t]*(?:([-*+•■·∙])|(\d+[.)]))[ \t]+(\S.*)$ ($ also before a final newline) }
var s: UStr;
    r: TRegExpr;
begin
  s := p;
  if EndsWith(s, #10) then SetLength(s, Length(s) - 1);
  r := ReFull('[ \t]*(?:([-*+•■·∙])|(\d+[.)]))[ \t]+(\S[^\n]*)', s);
  Result := r <> nil;
  if not Result then Exit;
  if HasGroup(r, 1) then item := '- ' else item := Group(r, 2) + ' ';
  item := item + Replace(Group(r, 3), #9, ' ');
end;

type
  TGroupKind = (gkNone, gkTable, gkList, gkCode);

function MdBlocks(const text: UStr): UStr;
{ Markdown paragraph post-processing. Every hard return became a paragraph break; here runs of
  single-line paragraphs are regrouped: list items and indented code lines are joined without
  blank lines, and rows with the same column count become tables (WordStar has no table object:
  tables are typed with tabs or drawn with box characters). }
var outs: TUStrArray;
    items, raws: TUStrArray;
    cellRows: array of TUStrArray;
    kind, k2: TGroupKind;
    p, item: UStr;
    single, isList: Boolean;
    cells: TUStrArray;
    isRow: Boolean;

  procedure Flush;
  var body: array of TUStrArray;
      k, n: Integer;
      same: Boolean;
      lines: TUStrArray;
  begin
    if kind = gkTable then
    begin
      body := nil;
      for k := 0 to High(cellRows) do
        if Length(cellRows[k]) > 0 then
        begin
          SetLength(body, Length(body) + 1);
          body[High(body)] := cellRows[k];
        end;
      same := Length(body) >= 2;
      if same then
      begin
        n := Length(body[0]);
        for k := 1 to High(body) do if Length(body[k]) <> n then same := False;
      end;
      if same then
      begin
        lines := nil;
        Append(lines, '| ' + JoinStr(body[0], ' | ') + ' |');
        Append(lines, '|' + RepeatStr('---|', Length(body[0])));
        for k := 1 to High(body) do Append(lines, '| ' + JoinStr(body[k], ' | ') + ' |');
        Append(outs, JoinStr(lines, #10));
      end
      else
        for k := 0 to High(raws) do Append(outs, Replace(raws[k], #9, ' '));
    end
    else if kind in [gkList, gkCode] then Append(outs, JoinStr(items, #10));
    items := nil;
    raws := nil;
    cellRows := nil;
    kind := gkNone;
  end;

begin
  outs := nil;
  items := nil;
  raws := nil;
  cellRows := nil;
  kind := gkNone;
  for p in SplitStr(text, #10#10) do
  begin
    single := not Contains(StripChars(p, #10), #10);
    isList := single and ListItem(p, item);
    isRow := False;
    if single and not isList then isRow := TableCells(p, cells);
    if isList then k2 := gkList
    else if isRow then k2 := gkTable
    else if single and StartsWith(p, '    ') and (Strip(p) <> '') then
    begin
      k2 := gkCode;
      item := Replace(p, #9, '    ');
    end
    else
    begin
      Flush;
      Append(outs, Replace(p, #9, ' '));
      Continue;
    end;
    if k2 <> kind then
    begin
      Flush;
      kind := k2;
    end;
    if k2 = gkTable then
    begin
      SetLength(cellRows, Length(cellRows) + 1);
      cellRows[High(cellRows)] := cells;
    end
    else Append(items, item);
    Append(raws, p);
  end;
  Flush;
  Result := JoinStr(outs, #10#10);
end;

{ ---------------------------------------------------------------- converter }

constructor TConverter.Create(const aData: TData; aTextmode: Boolean; const aBaseDir: string; aDepth: Integer;
                              aMerge: Boolean; aPreset: TVars; const aDocPath: string; aCodepage: Integer;
                              const aImageDir: string);
begin
  data := aData;
  textmode := aTextmode;
  baseDir := aBaseDir;
  depth := aDepth;
  merge := aMerge;
  preset := aPreset;
  docPath := aDocPath;
  parnumCompound := True;
  kind := FileKind(data);
  codepage := aCodepage;
  cp := GuessDocCodepage(data, kind, codepage);
  styles := ReadStyles(data, cp, True);
  imageDir := aImageDir;
  images := nil;
end;

function TConverter.Convert: UStr;
begin
  Result := ConvertChunk(data, False, False);
end;

function TConverter.ConvertChunk(const chunk: TData; isChunk, inNote: Boolean): UStr;
var outs: UStr;
    dotline: UStr;
    inDot, lineStart, tabbed, pendingBreak: Boolean;
    i, nx: SizeInt;
    c, skind, nxt: Integer;
    payload: TData;
    s, ch, m: UStr;

  procedure Emit(const t: UStr);
  begin
    if pendingBreak then
    begin
      if textmode or inNote then outs := outs + #10 else outs := outs + #10#10;
      pendingBreak := False;
    end;
    outs := outs + t;
    lineStart := False;
  end;

begin
  outs := '';
  dotline := '';
  inDot := False;                      { collecting the characters of a dot command line }
  lineStart := True;                   { at the start of a hard line }
  tabbed := False;                     { a tab sequence opened this line: a '.' after it is text }
  pendingBreak := False;
  i := 0;
  while i < Length(chunk) do
  begin
    c := DB(chunk, i);

    if (c = $1A) and not isChunk then Break;         { end of text; style library follows }

    if c = $1D then                                  { symmetrical sequence }
    begin
      if not ReadSequence(chunk, i, skind, payload, nx) then
      begin
        { cut off at end of data: drop the rest; otherwise a stray 1Dh }
        if i + W16(chunk, i + 1) + 3 > Length(chunk) then i := Length(chunk) else Inc(i);
        Continue;
      end;
      i := nx;
      tabbed := tabbed or (skind = SEQ_TAB);
      if not inDot then
      begin
        s := Sequence(skind, payload, inNote, lineStart);
        if s <> '' then Emit(s);
      end;
      Continue;
    end;

    if c = $1B then                                  { extended character 1Bh xx 1Ch }
    begin
      if (i + 2 < Length(chunk)) and (DB(chunk, i + 2) = $1C) then
      begin
        ch := ExtChar(DB(chunk, i + 1), cp);
        if inDot then dotline := dotline + ch else Emit(ch);
        Inc(i, 3);
      end
      else Inc(i);
      Continue;
    end;

    Inc(i);

    if (c >= $80) and (kind <> fkAscii) and not (c in [$8D, $8A, $8C, $A0]) then
      c := c and $7F;                               { code with the high bit set (text from WordStar 3-4) }

    nxt := DB(chunk, i);
    { the line end after .cb / .cc is 0Dh 8Ch (a column break marker) }
    if (c = $0D) and inDot and not (nxt in [$0A, $8A, $8C]) then
    begin
      dotline := dotline + ' ';                     { CR without LF (^P Enter) continues a dot command }
      Continue;
    end;

    if c = $0D then                                  { hard return }
    begin
      if inDot then
      begin
        s := DotCommand(dotline);
        inDot := False;
        dotline := '';
        if s <> '' then
        begin
          Emit(s);
          pendingBreak := True;
        end;
      end
      else if textmode or inNote then outs := outs + #10
      else if not lineStart then pendingBreak := True;
      lineStart := True;
      tabbed := False;
      Continue;
    end;

    if (c = $8D) and (kind <> fkAscii) then          { soft return (word wrap) }
    begin
      if not inDot then
        if inNote then outs := outs + ' ' else outs := outs + #10;
      Continue;
    end;

    if c = $1F then                                  { active soft hyphen: word re-joins }
    begin
      if DB(chunk, i) = $8D then
      begin
        Inc(i);                                      { drop the soft return that follows }
        if DB(chunk, i) = $0A then Inc(i);
      end;
      Continue;
    end;

    if c < $20 then
    begin
      if inDot then Continue;
      if c = $09 then
      begin
        if inNote then Emit(' ') else Emit(#9);      { markdown tabs are resolved by MdBlocks }
      end
      else if c = $0F then Emit(' ')                 { binding space }
      else if c = $0C then                           { form feed }
      begin
        if textmode then outs := outs + #12
        else
        begin
          Emit(#10'---'#10);
          pendingBreak := True;
        end;
      end
      else if not textmode and MdMark(c, m) then Emit(m);
      Continue;                                      { LF, soft hyphen, printer codes: skip }
    end;

    if c < $80 then ch := WideChar(c)
    else if kind = fkAscii then ch := DecodeByte(c, cp)    { plain text: 8Dh, A0h are letters (cp866 Н, а) }
    else if c in [$8A, $8C] then Continue                  { line feed after a page / column break }
    else if c = $A0 then                                   { soft space: margin indent / justification }
    begin
      if not textmode then Continue;                       { layout only }
      ch := ' ';
    end
    else Continue;                                         { 7Fh with the high bit }
    if lineStart and not tabbed and (ch = '.') and not inDot and not inNote then
    begin
      inDot := True;
      dotline := '.';
      lineStart := False;
      Continue;
    end;
    if inDot then dotline := dotline + ch else Emit(ch);
  end;

  if inDot then
  begin
    s := DotCommand(dotline);
    if s <> '' then Emit(s);
  end;
  if isChunk then Exit(outs);
  if merge and (depth = 0) then
    outs := MergeText(outs, baseDir, docPath, preset, textmode, codepage);
  if textmode then Result := outs else Result := CollapseNewlines(MdBlocks(outs));
end;

function TConverter.DotCommand(const line: UStr): UStr;
{ Markdown for a dot command line; most commands only affect printing }
var cmd, arg, name, spec, text, o: UStr;
    opts: TUStrArray;
    r: TRegExpr;
    k: Integer;
begin
  cmd := Lower(Copy(line, 2, 2));
  arg := Strip(Copy(line, 4, MaxInt));
  if (cmd = 'fi') and (arg <> '') then             { file inserted at print time: part of the text }
  begin
    Partition(arg, ' ', name, spec);
    Exit(InsertFile(name, Strip(spec)));
  end;
  if cmd = 'p#' then                               { .p# n,style,c/o }
  begin
    opts := nil;
    for o in SplitStr(arg, ',') do Append(opts, Lower(Strip(o)));
    if (Length(opts) >= 3) and ((opts[2] = 'c') or (opts[2] = 'o')) then parnumCompound := opts[2] = 'c';
    Exit('');
  end;
  if merge then
    for k := 0 to High(MERGE_COMMANDS) do
      if cmd = MERGE_COMMANDS[k] then Exit(MARK + line + MARK);     { evaluated later by the merge engine }
  if textmode then Exit('');
  if StartsWith(line, '..') or (cmd = 'ig') then   { nonprinting comment }
  begin
    if StartsWith(line, '..') then text := Strip(Copy(line, 3, MaxInt)) else text := arg;
    if text <> '' then Exit('<!-- ' + text + ' -->') else Exit('');
  end;
  if (cmd = 'df') and (arg <> '') then             { merge print data file; merging is not done }
    Exit('<!-- Merge data file: ' + Strip(SplitStr(arg, ',')[0]) + ' -->');
  if cmd = 'pa' then Exit(#10'---'#10);
  r := ReMatch('(?i)\.(he|h[1-5])[eo]?(?:\s|$)(.*)', line);
  if (r <> nil) and (Strip(Group(r, 2)) <> '') then Exit('<!-- Header: ' + Strip(Group(r, 2)) + ' -->');
  r := ReMatch('(?i)\.(fo|f[1-5])[eo]?(?:\s|$)(.*)', line);
  if (r <> nil) and (Strip(Group(r, 2)) <> '') then Exit('<!-- Footer: ' + Strip(Group(r, 2)) + ' -->');
  Result := '';
end;

function TConverter.InsertFile(const name, spec: UStr): UStr;
{ Contents of a .fi file looked up next to the document: a WordStar or ASCII file is converted; a
  worksheet (optionally a range or range name) or dBASE file becomes a table. }
var path: string;
    table: TTable;
    rows: TRows;
    d: TData;
    sub: TConverter;
begin
  path := FindFile(baseDir, string(name));
  if (path = '') or (depth >= 7) then
  begin
    if textmode then Exit('');
    if path = '' then Exit('<!-- .fi ' + name + ': file not found -->');
    Exit('<!-- .fi ' + name + ': nested too deep -->');
  end;
  table := ReadTableFile(path, spec, codepage);
  if table.ok then
  begin
    rows := nil;
    if table.hasNames and (Length(table.names) > 0) then
    begin
      SetLength(rows, 1);
      rows[0] := table.names;
    end;
    rows := Concat(rows, table.rows);
    Exit(TableText(rows, textmode));
  end;
  ReadFileData(path, d);
  sub := TConverter.Create(d, textmode, ExtractFileDir(path), depth + 1, merge, nil, '', codepage, '');
  try
    Result := StripChars(sub.Convert, #10);
  finally
    sub.Free;
  end;
end;

function TConverter.Graphic(const name: UStr): UStr;
{ Markdown image for a graphic tag: the picture converted to PNG next to the output when it can be
  found and read, otherwise a link to the file named in the document. }
var src: string;
    stem: UStr;
    pic: TPicture;
begin
  src := '';
  if imageDir <> '' then src := ImageSource(LocateGraphic(baseDir, string(name)));
  if src <> '' then
  begin
    stem := Lower(UTF8Decode(ChangeFileExt(ExtractFileName(src), '')));
    pic := OpenImage(src);
    if pic.img <> nil then
    try
      if SavePng(pic.img, JoinPath(imageDir, string(stem + '.png'))) then
      begin
        Append(images, stem + '.png');
        Exit('![' + stem + '](' + stem + '.png)');
      end;
    finally
      pic.img.Free;
    end;
  end;
  Result := '![](' + name + ')';
end;

function TConverter.Sequence(skind: Integer; const p: TData; inNote, lineStart: Boolean): UStr;
var text, name: UStr;
    num: Integer;
begin
  Result := '';
  if skind in [SEQ_FOOTNOTE, SEQ_ENDNOTE, SEQ_ANNOTATION] then
  begin
    if inNote then Exit('');                         { internal tag of the note: number only }
    text := JoinStr(SplitWS(ConvertChunk(Slice(p, 5, Length(p)), True, True)), ' ');
    if skind = SEQ_ANNOTATION then
    begin
      if textmode then Exit('') else Exit('<!-- ' + text + ' -->');
    end;
    if textmode then Exit(' [' + text + ']') else Exit('^[' + text + ']');
  end;
  if skind = SEQ_TAB then
  begin
    { tabs WordStar adds itself while formatting are layout, not text: soft tabs (A0h, the indent of
      a wrapped line), center line (!) and right align line ([) tabs }
    if (Length(p) >= 5) and ((DB(p, 4) in [$21, $5B]) or ((DB(p, 4) = $A0) and not lineStart)) then Exit('');
    if lineStart and not textmode then Exit('');
    if inNote then Exit(' ') else Exit(#9);
  end;
  if skind = SEQ_PARNUM then Exit(ParagraphNumber(p, parnumCompound));
  if (skind = SEQ_GRAPHIC) and not textmode then
  begin
    name := Strip(DecodeBytes(UntilZero(p), cp));
    if name <> '' then Exit(Graphic(name)) else Exit('');
  end;
  if (skind = SEQ_STYLE) and not textmode and (Length(p) >= 2) then
  begin
    { low byte: 0-based index into the file's style library (entry 0 is WordStar's own copy of the
      default style); high byte is a flag (02h in files saved by WordStar 7.0D) }
    num := DB(p, 0);
    if (num < Length(styles)) and lineStart then Exit(StylePrefix(styles[num].name));
    Exit('');
  end;
  if skind = SEQ_TRUNCATED then
  begin
    if textmode then Exit('<TRUNCATED>') else Exit('\<TRUNCATED\>');
  end;
  { header, colors, fonts, comments, page ends, index items, printer codes: nothing to show }
end;

end.

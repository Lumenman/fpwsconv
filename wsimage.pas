{ Pictures of graphic tags: Inset PIX (WordStar's graphics) and other formats read with fcl-image,
  written as PNG; the picture file is looked up from the DOS path in the document. }
unit wsimage;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses SysUtils, Classes, FPImage, FPReadPCX, FPReadPNG, FPReadBMP, FPReadJPEG, FPReadGIF, FPReadTiff,
     FPWritePNG, wsutil;

type
  TPicture = record
    img: TFPMemoryImage;               { nil if the file could not be read }
    dpi: Double;                       { horizontal resolution from the file, 150 if none }
  end;

function OpenImage(const path: string): TPicture;
function PngData(img: TFPMemoryImage): TData;
function SavePng(const d: TData; const path: string): Boolean;
function LocateGraphic(const baseDir, dosPath: string): string;
function ImageSource(const path: string): string;
function ScreenAspect(var w, h: Integer): Boolean;

implementation

const
  IMAGE_EXTS: array[0..7] of string = ('.pix', '.png', '.pcx', '.gif', '.tif', '.tiff', '.bmp', '.jpg');
  { Inset PIX palette levels (2 bits per component as the EGA sets them: 1 = 2/3, 2 = 1/3) }
  PIX_LEVEL: array[0..3] of Byte = ($00, $AA, $55, $FF);

function IsImageExt(const ext: string): Boolean;
var e: string;
begin
  for e in IMAGE_EXTS do
    if LowerCase(ext) = e then Exit(True);
  Result := False;
end;

function ScreenAspect(var w, h: Integer): Boolean;
{ Size with square pixels for a screen capture: CGA 320 x 200 / 640 x 200 and EGA 640 x 350 pixels
  fill a 4:3 screen, so they are taller than wide -> 640 x 480. Other sizes as they are. }
begin
  Result := ((w = 320) and (h = 200)) or ((w = 640) and (h = 200)) or ((w = 640) and (h = 350));
  if Result then
  begin
    w := 640;
    h := 480;
  end;
end;

type EPix = class(Exception);

function ReadPix(const data: TData): TFPMemoryImage;
{ Picture of an Inset PIX file. The file starts with a record count and a table of records (type
  word, length word, offset dword). Type 0: width at +18, height at +20, bits per pixel at +22;
  type 1: 16 palette entries (0, R, G, B); type 2: tile height, width, tiles down, across;
  8000h + n: tile n, left to right, top to bottom (tiles in the last row / column may run past the
  picture). A tile holds its bit planes one after another; in a plane the first row is stored as
  is, each next row as a mask (a bit per byte of the row, high bit first) followed by the bytes
  that differ from the row above. }
var recType: array of Integer;
    recData: array of TData;
    k, e, off, width, height, bpp, th, tw, down, across, rb, mb, stride, n, i, x0, y0, rows,
      plane, y, b, bit, kk, base, c, outW, outH, x, sx, sy: Integer;
    pix: array of Byte;
    t, mask, row, pal, r0, r2: TData;
    colors: array[0..255] of TFPColor;

  function Rec(typ: Integer; out d: TData): Boolean;
  var j: Integer;
  begin
    for j := High(recType) downto 0 do        { a later record of the same type wins (dict) }
      if recType[j] = typ then
      begin
        d := recData[j];
        Exit(True);
      end;
    d := '';
    Result := False;
  end;

  function Level(v: Integer): Word;
  begin
    Result := PIX_LEVEL[v and 3] * 257;
  end;

begin
  SetLength(recType, W16(data, 2));
  SetLength(recData, W16(data, 2));
  for k := 0 to W16(data, 2) - 1 do
  begin
    e := 4 + 8 * k;
    off := D32(data, e + 4);
    recType[k] := W16(data, e);
    recData[k] := Slice(data, off, off + W16(data, e + 2));
  end;
  if not Rec(0, r0) or not Rec(2, r2) or (Length(r0) < 23) then raise EPix.Create('no PIX header');
  width := W16(r0, 18);
  height := W16(r0, 20);
  bpp := DB(r0, 22);
  th := W16(r2, 0); tw := W16(r2, 2); down := W16(r2, 4); across := W16(r2, 6);
  if (width <= 0) or (height <= 0) or (tw <= 0) or (th <= 0) then raise EPix.Create('empty PIX');
  rb := (tw + 7) div 8;                               { bytes in a tile row of one plane }
  mb := (rb + 7) div 8;                               { bytes in its mask }
  stride := across * tw;
  SetLength(pix, stride * down * th);
  for n := 0 to down * across - 1 do
  begin
    Rec($8000 + n, t);
    i := 0;
    x0 := (n mod across) * tw;
    y0 := (n div across) * th;
    rows := th;
    if height - y0 < rows then rows := height - y0;
    if rows < 0 then rows := 0;
    for plane := 0 to bpp - 1 do
    begin
      row := StringOfChar(#0, rb);
      for y := 0 to rows - 1 do
      begin
        if y = 0 then
        begin
          row := Slice(t, i, i + rb);
          while Length(row) < rb do row := row + #0;
          Inc(i, rb);
        end
        else
        begin
          mask := Slice(t, i, i + mb);
          Inc(i, mb);
          for b := 0 to rb - 1 do
            if (b shr 3 < Length(mask)) and (Ord(mask[b shr 3 + 1]) and ($80 shr (b and 7)) <> 0) then
            begin
              if i < Length(t) then row[b + 1] := t[i + 1] else row[b + 1] := #0;
              Inc(i);
            end;
        end;
        base := (y0 + y) * stride + x0;
        bit := 1 shl plane;
        for b := 0 to rb - 1 do
          if row[b + 1] <> #0 then
            for kk := 0 to 7 do
              if (kk < tw - b * 8) and (Ord(row[b + 1]) and ($80 shr kk) <> 0) then
                pix[base + b * 8 + kk] := pix[base + b * 8 + kk] or bit;
      end;
    end;
  end;
  { one bit per pixel: ink on paper (the palette of WORDSTAR.PIX says white on black, but its .PCX
    and PIX2PCX's FIG1.PCX both have the set bits black) }
  if bpp = 1 then pal := #0#3#3#3#0#0#0#0 else Rec(1, pal);
  for c := 0 to 255 do
  begin
    colors[c] := colBlack;
    if 4 * c + 1 < Length(pal) then colors[c].red := Level(Ord(pal[4 * c + 2]));
    if 4 * c + 2 < Length(pal) then colors[c].green := Level(Ord(pal[4 * c + 3]));
    if 4 * c + 3 < Length(pal) then colors[c].blue := Level(Ord(pal[4 * c + 4]));
    colors[c].alpha := alphaOpaque;
  end;
  outW := width;
  outH := height;
  ScreenAspect(outW, outH);
  Result := TFPMemoryImage.Create(outW, outH);
  for y := 0 to outH - 1 do
    for x := 0 to outW - 1 do
    begin
      sx := Trunc((x + 0.5) * width / outW);           { nearest neighbour }
      sy := Trunc((y + 0.5) * height / outH);
      if (sx < stride) and (sy < down * th) then Result.Colors[x, y] := colors[pix[sy * stride + sx]]
      else Result.Colors[x, y] := colors[0];
    end;
end;

function FileDpi(const path: string): Double;
{ horizontal resolution as the Python version read it (Pillow's info['dpi']); 0 if none.
  ponytail: PCX, PNG, BMP and JFIF JPEG headers only; GIF / TIFF count as none (150). }
var d: TData;
    ext: string;
    i, len: Integer;
begin
  Result := 0;
  if not ReadFileData(path, d) then Exit;
  ext := LowerCase(ExtractFileExt(path));
  if (ext = '.pcx') and (Length(d) >= 16) then Exit(W16(d, 12));
  if Copy(d, 1, 8) = #$89'PNG'#13#10#$1A#10 then
  begin
    i := 8;
    while i + 12 <= Length(d) do
    begin
      len := (DB(d, i) shl 24) or (DB(d, i + 1) shl 16) or (DB(d, i + 2) shl 8) or DB(d, i + 3);
      if (Copy(d, i + 5, 4) = 'pHYs') and (len >= 9) then
      begin
        if DB(d, i + 16) = 1 then
          Result := ((Int64(DB(d, i + 8)) shl 24) or (DB(d, i + 9) shl 16) or (DB(d, i + 10) shl 8)
                     or DB(d, i + 11)) * 0.0254;
        Exit;
      end;
      if Copy(d, i + 5, 4) = 'IDAT' then Exit;
      Inc(i, 12 + len);
    end;
    Exit;
  end;
  if (Copy(d, 1, 2) = 'BM') and (Length(d) >= 46) and (D32(d, 14) >= 40) then
    Exit(D32(d, 38) / 39.3701);
  if (Copy(d, 1, 2) = #$FF#$D8) and (Copy(d, 7, 5) = 'JFIF'#0) then
  begin
    case DB(d, 13) of
      1: Exit(W16(d, 14) shr 8 or (W16(d, 14) and $FF) shl 8);
      2: Exit((W16(d, 14) shr 8 or (W16(d, 14) and $FF) shl 8) * 2.54);
    end;
  end;
end;

function OpenImage(const path: string): TPicture;
var d: TData;
begin
  Result.img := nil;
  Result.dpi := 150;
  try
    if LowerCase(ExtractFileExt(path)) = '.pix' then
    begin
      if ReadFileData(path, d) then Result.img := ReadPix(d);
      Exit;                                     { built image: no resolution of its own }
    end;
    Result.img := TFPMemoryImage.Create(0, 0);
    Result.img.LoadFromFile(path);
    Result.dpi := FileDpi(path);
    if Result.dpi = 0 then Result.dpi := 150;
  except
    FreeAndNil(Result.img);                     { unreadable (Inset also has text PIX) }
  end;
end;

function PngData(img: TFPMemoryImage): TData;
var s: TStringStream;
    w: TFPWriterPNG;
begin
  s := TStringStream.Create('');
  w := TFPWriterPNG.Create;
  try
    w.UseAlpha := False;
    img.SaveToStream(s, w);
    Result := s.DataString;
  finally
    w.Free;
    s.Free;
  end;
end;

function SavePng(const d: TData; const path: string): Boolean;
var f: TFileStream;
begin
  Result := False;
  try
    f := TFileStream.Create(path, fmCreate);
    try
      if d <> '' then f.WriteBuffer(d[1], Length(d));
    finally
      f.Free;
    end;
    Result := True;
  except
  end;
end;

function CiJoin(const folder0: string; const parts: array of string; out found: string): Boolean;
{ folder + parts, each part matched case-insensitively (DOS names) }
var folder: string;
    k, j: Integer;
    list: TStringList;
    hit: Boolean;
begin
  folder := folder0;
  Result := False;
  for k := 0 to High(parts) do
  begin
    if not DirectoryExists(folder) then Exit;
    list := ListDir(folder);
    hit := False;
    for j := 0 to list.Count - 1 do
      if LowerCase(list[j]) = LowerCase(parts[k]) then
      begin
        folder := JoinPath(folder, list[j]);
        hit := True;
        Break;
      end;
    list.Free;
    if not hit then Exit;
  end;
  found := folder;
  Result := True;
end;

function ImageSource(const path: string): string;
{ A file OpenImage can read for this graphic: the file itself, or the same picture in another
  format next to it (the .PIX may be gone while the original .PCX etc. is there); '' if none. }
var folder, stem: string;
    list: TStringList;
    k: Integer;
begin
  Result := '';
  if path = '' then Exit;
  if IsImageExt(ExtractFileExt(path)) and FileExists(path) then Exit(path);
  folder := ExtractFileDir(path);
  stem := ChangeFileExt(ExtractFileName(path), '');
  list := ListDir(folder);
  for k := 0 to list.Count - 1 do
    if (LowerCase(ChangeFileExt(list[k], '')) = LowerCase(stem)) and IsImageExt(ExtractFileExt(list[k])) then
    begin
      Result := JoinPath(folder, list[k]);
      Break;
    end;
  list.Free;
end;

function LocateGraphic(const baseDir, dosPath: string): string;
{ File named in a graphic tag (a DOS path such as C:\WS\INSET\PIX\WORDSTAR.PIX), looked up next to
  the document and under its parent folders, keeping as much of the DOS path as matches. }
var parts: array of string;
    s, folder, parent, where, path: string;
    k, j, p: Integer;
    sub: array of string;
begin
  Result := '';
  s := dosPath;
  p := LastDelimiter(':', s);
  if p > 0 then s := Copy(s, p + 1, MaxInt);
  parts := nil;
  for path in s.Split(['\', '/']) do
    if path <> '' then
    begin
      SetLength(parts, Length(parts) + 1);
      parts[High(parts)] := path;
    end;
  if Length(parts) = 0 then Exit;
  folder := ExcludeTrailingPathDelimiter(ExpandFileName(baseDir));
  while True do
  begin
    for k := 0 to High(parts) do                      { longest tail of the DOS path first }
    begin
      SetLength(sub, High(parts) - k);
      for j := k to High(parts) - 1 do sub[j - k] := parts[j];
      if CiJoin(folder, sub, where) then
      begin
        if not CiJoin(where, [parts[High(parts)]], path) then path := JoinPath(where, parts[High(parts)]);
        { the file itself, or (the .PIX gone) the same picture in another format }
        if FileExists(path) or (ImageSource(path) <> '') then Exit(path);
      end;
    end;
    parent := ExcludeTrailingPathDelimiter(ExtractFileDir(folder));
    if (parent = '') or (parent = folder) or (Length(parent) >= Length(folder)) then Exit;
    folder := parent;
  end;
end;

end.

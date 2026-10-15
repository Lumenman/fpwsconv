{ wsconv: WordStar (3.x-7.0) documents to Markdown, plain text or RTF.
  Free Pascal translation of the Python converter (same options and output; compare.py checks
  both give the same results). Builds for Windows (fpc wsconv.pas) and DOS (go32v2, see README). }
program wsconv;

{$mode objfpc}{$H+}{$codepage utf8}

uses
  {$ifdef go32v2}fpwidestring,{$endif}
  SysUtils, Classes, Math, wsutil, wsdoc, wsmerge, wsmd, wsrtf, wsfrom;

procedure Usage;
begin
  WriteLn('usage: wsconv [-h] [-o OUTPUT] [-t] [-r] [-q] [-m] [-s NAME=VALUE] [-c CP] [-w] ws_file ...');
  WriteLn;
  WriteLn('Convert a WordStar document to Markdown, plain text or RTF.');
  WriteLn;
  WriteLn('  ws_file               the WordStar file to convert; a folder (its WordStar documents, not *.BAK)');
  WriteLn('                        or a mask (DOCS\*.WS) converts several files');
  WriteLn('  -o, --output OUTPUT   output file name (several files: output folder, created if missing)');
  WriteLn('  -t, --textmode        output to unformatted (text) file');
  WriteLn('  -r, --rtf             output RTF with fonts, margins, alignment, notes and pictures (no merging)');
  WriteLn('  -q, --quotes          RTF: typographic quotes for straight " and '' (opening or closing by the');
  WriteLn('                        character before), -- as an em dash, ... as an ellipsis');
  WriteLn('  -m, --merge           merge print: fill &variables& from .df data files, run .if/.rv/.ma/...');
  WriteLn('                        (one copy of the document per record)');
  WriteLn('  -s, --set NAME=VALUE  value of a merge variable (answers .av prompts); repeatable');
  WriteLn('  -w, --to-ws           the other way: UTF-8 text or Markdown (.md, .markdown) to a WordStar');
  WriteLn('                        document (WordStar 4 style, .ws; code page 1125 unless -c)');
  WriteLn('  -c, --codepage CP     DOS code page of the text: 437, 866 (Russian / Ukrainian), 1125');
  WriteLn('                        (Ukrainian), 850 ... or auto (default: 866 if extended characters form');
  WriteLn('                        words, else 437)');
end;

procedure Fail(const msg: string);
begin
  WriteLn(StdErr, 'wsconv: error: ', msg);
  Halt(2);
end;

type
  EFail = class(Exception);           { a reported failure (Fail in single-file mode) }

var
  outFile, cpArg, arg, value, outName, outDir: string;
  textmode, rtf, quotes, merge, intoWs, batch: Boolean;
  preset: TVars;
  codepage, k, i, eq, done, failed: Integer;
  inputs, used: TStringList;
  base: string;

function NextValue(const opt: string): string;
begin
  Inc(k);
  if k > ParamCount then Fail('argument ' + opt + ': expected one argument');
  Result := ParamStr(k);
end;

function OutExt: string;
begin
  if intoWs then Result := '.ws'
  else if rtf then Result := '.rtf'
  else if textmode then Result := '.txt'
  else Result := '.md';
end;

function Wanted(const path: string): Boolean;
{ a file found in a folder or by a mask: a WordStar document (with -w: Markdown or text); not a backup or
  something the converter writes }
var ext: string;
    d: TData;
begin
  ext := LowerCase(ExtractFileExt(path));
  if intoWs then Exit((ext = '.md') or (ext = '.markdown') or (ext = '.txt'));
  if Pos(' ' + ext + ' ', ' .bak .md .markdown .txt .rtf .png ') > 0 then Exit(False);
  Result := ReadFileData(path, d) and (FileKind(d) <> fkAscii);
end;

procedure AddInputs(const spec: string);
{ spec: a file, a folder (its files) or a mask like DOCS\*.WS }
var sr: TSearchRec;
    mask, dir: string;
begin
  if DirectoryExists(spec) then mask := IncludeTrailingPathDelimiter(spec) + '*'
  else if (Pos('*', spec) > 0) or (Pos('?', spec) > 0) then mask := spec
  else
  begin
    inputs.Add(spec);
    Exit;
  end;
  batch := True;
  dir := ExtractFilePath(mask);
  if FindFirst(mask, faAnyFile and not faDirectory, sr) = 0 then
  begin
    repeat
      if (sr.Attr and faDirectory = 0) and Wanted(dir + sr.Name) then inputs.Add(dir + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

procedure ConvertOne(const inFile, outFile: string);
{ outFile '' = next to inFile with OutExt; failures raise EFail or another exception }
var
  value, written: string;
  name, imgs: UStr;
  images, missing: Integer;
  d: TData;
  conv: TConverter;
  text: UStr;
  outBytes: RawByteString;
  f: TFileStream;
  cp: Integer;
begin
  if not FileExists(inFile) then raise EFail.Create('file not found: ' + inFile);
  if outFile <> '' then value := outFile else value := ChangeFileExt(inFile, OutExt);
  if LowerCase(ExpandFileName(value)) = LowerCase(ExpandFileName(inFile)) then   { SameFileName crashes under DOS }
    raise EFail.Create('the output file would replace the input file: ' + value + ' (use -o)');
  cp := codepage;

  if intoWs then
  begin
    if not ReadFileData(inFile, d) then raise EFail.Create('cannot read ' + inFile);
    if cp = 0 then cp := 1125;
    outBytes := ToWs(UTF8Decode(d), Pos(LowerCase(ExtractFileExt(inFile)), '.md .markdown') > 0, cp, missing);
    f := TFileStream.Create(value, fmCreate);
    try
      if Length(outBytes) > 0 then f.WriteBuffer(outBytes[1], Length(outBytes));
    finally
      f.Free;
    end;
    if missing > 0 then WriteLn('Written: ', value, ', ', missing, ' character(s) not in code page ', cp, ' (as ?)')
    else WriteLn('Written: ', value);
    Exit;
  end;
  if rtf then
  begin
    if not ConvertFileRtf(inFile, outFile, cp, quotes, written, images) then raise EFail.Create('cannot read ' + inFile);
    if images > 0 then WriteLn('Written: ', written, ', ', images, ' picture(s)')
    else WriteLn('Written: ', written);
    Exit;
  end;

  if not ReadFileData(inFile, d) then raise EFail.Create('cannot read ' + inFile);
  conv := TConverter.Create(d, textmode, ExtractFileDir(ExpandFileName(inFile)), 0, merge, preset, inFile,
                            cp, ExtractFileDir(ExpandFileName(value)));
  try
    text := StripChars(conv.Convert, #10) + #10;
    outBytes := U8(text);
    f := TFileStream.Create(value, fmCreate);
    try
      f.WriteBuffer(outBytes[1], Length(outBytes));
    finally
      f.Free;
    end;
    imgs := '';
    for name in conv.images do imgs := imgs + ', ' + name;
    WriteLn('Written: ', value, U8(imgs));
  finally
    conv.Free;
  end;
end;

function Taken(const name: string): Boolean;     { bytewise: no locale compare under DOS }
var j: Integer;
begin
  for j := 0 to used.Count - 1 do
    if used[j] = LowerCase(name) then Exit(True);
  Result := False;
end;

begin
  {$ifdef windows}
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
  {$endif}
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  outFile := ''; cpArg := 'auto';
  textmode := False; rtf := False; quotes := False; merge := False; intoWs := False; batch := False;
  preset := TVars.Create;
  inputs := TStringList.Create;
  k := 1;
  while k <= ParamCount do
  begin
    arg := ParamStr(k);
    value := '';
    eq := Pos('=', arg);
    if (Copy(arg, 1, 2) = '--') and (eq > 0) then
    begin
      value := Copy(arg, eq + 1, MaxInt);
      arg := Copy(arg, 1, eq - 1);
    end;
    if (arg = '-h') or (arg = '--help') then begin Usage; Halt(0); end
    else if (arg = '-t') or (arg = '--textmode') then textmode := True
    else if (arg = '-r') or (arg = '--rtf') then rtf := True
    else if (arg = '-q') or (arg = '--quotes') then quotes := True
    else if (arg = '-m') or (arg = '--merge') then merge := True
    else if (arg = '-w') or (arg = '--to-ws') then intoWs := True
    else if (arg = '-o') or (arg = '--output') then
    begin
      if value = '' then value := NextValue(arg);
      outFile := value;
    end
    else if (arg = '-c') or (arg = '--codepage') then
    begin
      if value = '' then value := NextValue(arg);
      cpArg := value;
    end
    else if (arg = '-s') or (arg = '--set') then
    begin
      if value = '' then value := NextValue(arg);
      eq := Pos('=', value);
      if eq > 0 then preset.AddOrSetValue(UTF8Decode(Copy(value, 1, eq - 1)), UTF8Decode(Copy(value, eq + 1, MaxInt)));
    end
    else if (Length(arg) > 2) and (arg[1] = '-') and (arg[2] in ['o', 'c', 's']) then
    begin                                          { -oFILE, -c866, -sNAME=VALUE }
      value := Copy(arg, 3, MaxInt);
      if value[1] = '=' then Delete(value, 1, 1);  { -o=FILE }
      case arg[2] of
        'o': outFile := value;
        'c': cpArg := value;
        's':
          begin
            eq := Pos('=', value);
            if eq > 0 then preset.AddOrSetValue(UTF8Decode(Copy(value, 1, eq - 1)), UTF8Decode(Copy(value, eq + 1, MaxInt)));
          end;
      end;
    end
    else if (Length(arg) > 1) and (arg[1] = '-') then Fail('unrecognized arguments: ' + arg)
    else AddInputs(arg);
    Inc(k);
  end;
  if (inputs.Count = 0) and not batch then
  begin
    Usage;
    Fail('the following arguments are required: ws_file');
  end;

  codepage := 0;
  if LowerCase(cpArg) <> 'auto' then
  begin
    value := LowerCase(cpArg);
    if Copy(value, 1, 2) = 'cp' then value := Copy(value, 3, MaxInt);
    codepage := StrToIntDef(value, -1);
    if not KnownCodepage(codepage) then Fail('unknown code page: ' + cpArg);
  end;

  if (inputs.Count = 1) and not batch then
  begin
    try
      ConvertOne(inputs[0], outFile);
    except
      on E: EFail do Fail(E.Message);
      on E: Exception do
      begin                                        { stdout: DOS cannot redirect stderr }
        WriteLn('wsconv: error: ', E.ClassName, ': ', E.Message);
        Halt(1);
      end;
    end;
    Halt(0);
  end;

  { several files: -o is a folder; inputs whose outputs would share a name (LETTER.WS, LETTER.DOC) keep
  their extension in it (LETTER_WS.md, LETTER_DOC.md) }
  if (outFile <> '') and not ForceDirectories(outFile) then Fail('cannot create folder ' + outFile);
  used := TStringList.Create;              { output names in lower case, in the order of inputs, then variants }
  for k := 0 to inputs.Count - 1 do
  begin
    if outFile <> '' then outDir := IncludeTrailingPathDelimiter(outFile) else outDir := ExtractFilePath(inputs[k]);
    used.Add(LowerCase(outDir + ChangeFileExt(ExtractFileName(inputs[k]), OutExt)));
  end;
  done := 0; failed := 0;
  for k := 0 to inputs.Count - 1 do
  begin
    if outFile <> '' then outDir := IncludeTrailingPathDelimiter(outFile) else outDir := ExtractFilePath(inputs[k]);
    outName := outDir + ChangeFileExt(ExtractFileName(inputs[k]), OutExt);
    eq := 0;
    for i := 0 to inputs.Count - 1 do
      if used[i] = used[k] then Inc(eq);   { bytewise: no locale compare under DOS }
    if eq > 1 then
    begin                                  { the variant must not take another input's name: LETTER_WS-2.md }
      base := outDir + StringReplace(ExtractFileName(inputs[k]), '.', '_', [rfReplaceAll]);
      outName := base + OutExt;
      i := 1;
      while Taken(outName) do
      begin
        Inc(i);
        outName := base + '-' + IntToStr(i) + OutExt;
      end;
      used.Add(LowerCase(outName));
    end;
    try
      ConvertOne(inputs[k], outName);
      Inc(done);
    except
      on E: Exception do
      begin
        WriteLn('wsconv: ', inputs[k], ': error: ', E.Message);
        Inc(failed);
      end;
    end;
  end;
  WriteLn(done, ' file(s) converted, ', failed, ' failed');
  if (failed > 0) or (done = 0) then Halt(1);
end.

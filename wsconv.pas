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
  WriteLn('usage: wsconv [-h] [-o OUTPUT] [-t] [-r] [-q] [-m] [-s NAME=VALUE] [-c CP] [-w] ws_file');
  WriteLn;
  WriteLn('Convert a WordStar document to Markdown, plain text or RTF.');
  WriteLn;
  WriteLn('  ws_file               the WordStar file to convert');
  WriteLn('  -o, --output OUTPUT   output file name');
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

var
  inFile, outFile, cpArg, arg, value, written: string;
  name, imgs: UStr;
  textmode, rtf, quotes, merge, intoWs: Boolean;
  preset: TVars;
  codepage, k, images, eq, missing: Integer;
  d: TData;
  conv: TConverter;
  text: UStr;
  outBytes: RawByteString;
  f: TFileStream;

function NextValue(const opt: string): string;
begin
  Inc(k);
  if k > ParamCount then Fail('argument ' + opt + ': expected one argument');
  Result := ParamStr(k);
end;

begin
  {$ifdef windows}
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  SetMultiByteRTLFileSystemCodePage(CP_UTF8);
  {$endif}
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  inFile := ''; outFile := ''; cpArg := 'auto';
  textmode := False; rtf := False; quotes := False; merge := False; intoWs := False;
  preset := TVars.Create;
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
    else if inFile = '' then inFile := arg
    else Fail('unrecognized arguments: ' + arg);
    Inc(k);
  end;
  if inFile = '' then
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

  if not FileExists(inFile) then Fail('file not found: ' + inFile);
  if outFile <> '' then value := outFile
  else if intoWs then value := ChangeFileExt(inFile, '.ws')
  else if rtf then value := ChangeFileExt(inFile, '.rtf')
  else if textmode then value := ChangeFileExt(inFile, '.txt')
  else value := ChangeFileExt(inFile, '.md');
  if LowerCase(ExpandFileName(value)) = LowerCase(ExpandFileName(inFile)) then   { SameFileName crashes under DOS }
    Fail('the output file would replace the input file: ' + value + ' (use -o)');

  try
    if intoWs then
    begin
      if not ReadFileData(inFile, d) then Fail('cannot read ' + inFile);
      if codepage = 0 then codepage := 1125;
      outBytes := ToWs(UTF8Decode(d), Pos(LowerCase(ExtractFileExt(inFile)), '.md .markdown') > 0, codepage, missing);
      f := TFileStream.Create(value, fmCreate);
      try
        if Length(outBytes) > 0 then f.WriteBuffer(outBytes[1], Length(outBytes));
      finally
        f.Free;
      end;
      if missing > 0 then WriteLn('Written: ', value, ', ', missing, ' character(s) not in code page ', codepage, ' (as ?)')
      else WriteLn('Written: ', value);
      Halt(0);
    end;
    if rtf then
    begin
      if not ConvertFileRtf(inFile, outFile, codepage, quotes, written, images) then Fail('cannot read ' + inFile);
      if images > 0 then WriteLn('Written: ', written, ', ', images, ' picture(s)')
      else WriteLn('Written: ', written);
      Halt(0);
    end;

    if outFile = '' then
      if textmode then outFile := ChangeFileExt(inFile, '.txt') else outFile := ChangeFileExt(inFile, '.md');
    if not ReadFileData(inFile, d) then Fail('cannot read ' + inFile);
    conv := TConverter.Create(d, textmode, ExtractFileDir(ExpandFileName(inFile)), 0, merge, preset, inFile,
                              codepage, ExtractFileDir(ExpandFileName(outFile)));
    try
      text := StripChars(conv.Convert, #10) + #10;
      outBytes := U8(text);
      f := TFileStream.Create(outFile, fmCreate);
      try
        f.WriteBuffer(outBytes[1], Length(outBytes));
      finally
        f.Free;
      end;
      imgs := '';
      for name in conv.images do imgs := imgs + ', ' + name;
      WriteLn('Written: ', outFile, U8(imgs));
    finally
      conv.Free;
    end;
  except
    on E: Exception do
    begin                                        { stdout: DOS cannot redirect stderr }
      WriteLn('wsconv: error: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
  preset.Free;
end.

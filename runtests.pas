{ Regression tests: runs wsconv on every tests\NNN\ case and compares the files it writes with expect\.
  Usage: runtests [path to wsconv.exe]   (default wsconv.exe)
  A case folder holds the input files (the document and any .fi / .df / picture files), args (one argument
  per line, run from the case folder) and expect\ (the files the converter must write to got\). }
program runtests;
{$mode objfpc}{$H+}
uses SysUtils, Classes;

function Slurp(const path: string): RawByteString;
var f: File;
begin
  Result := '';
  AssignFile(f, path);
  FileMode := 0;
  Reset(f, 1);
  SetLength(Result, FileSize(f));
  if Length(Result) > 0 then
    BlockRead(f, Result[1], Length(Result));
  CloseFile(f);
end;

function RunCase(const exe, dir: string): string;
var
  args: array of string;
  t: Text;
  s, name: string;
  sr: TSearchRec;
  code: Integer;
begin
  Result := '';
  SetLength(args, 0);
  AssignFile(t, dir + 'args');
  Reset(t);
  while not Eof(t) do
  begin
    ReadLn(t, s);
    if s <> '' then
    begin
      SetLength(args, Length(args) + 1);
      args[High(args)] := s;
    end;
  end;
  CloseFile(t);
  if FindFirst(dir + 'got' + PathDelim + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if sr.Attr and faDirectory = 0 then
        DeleteFile(dir + 'got' + PathDelim + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end
  else
    CreateDir(dir + 'got');
  ChDir(dir);
  try
    code := ExecuteProcess(exe, args);
  except
    on e: Exception do
      Exit('cannot run: ' + e.Message);
  end;
  if code <> 0 then
    Exit('exit code ' + IntToStr(code));
  if FindFirst(dir + 'expect' + PathDelim + '*', faAnyFile and not faDirectory, sr) = 0 then
  begin
    repeat
      name := dir + 'got' + PathDelim + sr.Name;
      if not FileExists(name) then
        Result := Result + ' missing ' + sr.Name
      else if Slurp(name) <> Slurp(dir + 'expect' + PathDelim + sr.Name) then
        Result := Result + ' differs ' + sr.Name;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  if FindFirst(dir + 'got' + PathDelim + '*', faAnyFile and not faDirectory, sr) = 0 then
  begin
    repeat
      if not FileExists(dir + 'expect' + PathDelim + sr.Name) then
        Result := Result + ' extra ' + sr.Name;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

var
  exe, root, err: string;
  sr: TSearchRec;
  run, failed, i: Integer;
  cases: TStringList;
begin
  exe := 'wsconv.exe';
  if ParamCount > 0 then
    exe := ParamStr(1);
  exe := ExpandFileName(exe);
  root := ExpandFileName('tests') + PathDelim;
  run := 0;
  failed := 0;
  cases := TStringList.Create;          { listed first: a DOS directory search does not survive the runs }
  if FindFirst(root + '*', faDirectory, sr) = 0 then
  begin
    repeat
      if (sr.Attr and faDirectory <> 0) and (sr.Name[1] <> '.') then
        cases.Add(sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  for i := 0 to cases.Count - 1 do
  begin
    Inc(run);
    err := RunCase(exe, root + cases[i] + PathDelim);
    if err <> '' then
    begin
      Inc(failed);
      WriteLn('FAIL ', cases[i], ':', err);
    end;
  end;
  WriteLn(run, ' cases, ', failed, ' failed');
  if (run = 0) or (failed > 0) then
    Halt(1);
end.

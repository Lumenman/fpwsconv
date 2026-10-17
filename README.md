# fpwsconv — WordStar document converter in Free Pascal

Converts WordStar 3.x–7.0 documents (DOS) to Markdown, plain text or RTF. Written in Free Pascal 3.2.2;
builds for Windows and for DOS (go32v2).

    wsconv [-o OUTPUT] [-t] [-r] [-q] [-m] [-s NAME=VALUE] [-c 437|866|1125|auto] FILE.WS
    wsconv -w [-o OUTPUT] [-c CP] FILE.md|FILE.txt
    wsconv [options] FOLDER|MASK|FILE ... [-o OUTPUT_FOLDER]

Several files: a folder converts its WordStar documents (`.BAK` backups, plain text and the converter's
own output are skipped; with `-w` its `.md`, `.markdown` and `.txt` files), a mask (`DOCS\*.WS`) the
matching ones; files can also be listed. `-o` is then the output folder (created if missing; default: next to
each input). Inputs whose outputs would share a name keep their extension in it (`LETTER.WS`, `LETTER.DOC`
→ `LETTER_WS.md`, `LETTER_DOC.md`; `-2`, `-3` if that name is taken too). A file that fails is reported and the rest are converted; the exit
code is 1 if any failed. Subfolders are not searched.

| Option | Meaning |
|---|---|
| `--version` | print the version and exit |
| `-o OUTPUT` | output file name, or an existing folder to write it in (several files: output folder); `-o -`: standard output, one input file only (`wsconv -t -e 866 LETTER.WS -o - | more`) |
| `-t` | unformatted plain text instead of Markdown |
| `-r` | RTF with fonts, margins, alignment, notes and pictures |
| `-q` | RTF: typographic quotes, `--` as an em dash, `...` as an ellipsis |
| `-m` | merge print: fill `&variables&` from `.df` data files, run `.if/.rv/.ma/...` (one copy per record) |
| `-s NAME=VALUE` | value of a merge variable (answers `.av` prompts); repeatable |
| `-w` | the other way: UTF-8 Markdown (`.md`, `.markdown`) or plain text to a WordStar document (`.ws`), code page 1125 unless `-c` |
| `-c CP` | DOS code page of the text: 437, 866 (Russian / Ukrainian), 1125 (Ukrainian), 850 … or `auto` (866 if extended characters form words, else 437) |
| `-e CP` | encoding of the Markdown or plain text: `utf8` (default) or a DOS code page as for `-c` — the output, or the input with `-w`; characters the code page lacks become `?`. In the DOS build also the encoding of `-s` values (the DOS command line is in the DOS code page) |

What is handled: bold, italic, underline (`<u>` in Markdown), strike-out, super/subscript and other print controls; dot commands
(headers, footers, margins, page breaks, comments); styles and paragraph numbering; tabs and columns;
footnotes, endnotes, annotations and comments; extended characters in DOS code pages (Cyrillic
included); pictures (`.PIX`, `.PCX` … → PNG next to the output); merge printing with data from comma-delimited
data files, dBASE `.DBF`, Lotus `.WK1` and Quattro `.WQ1`.

Table of contents and index, as WordStar's Opening menu T and I build them (checked against WordStar 7's
`.TOC` / `.IDX`): the `.tc` lines (`.tc1` … `.tc9`: further tables) with their formatting and dot commands
become the table of contents at the start, `#` or `&#…&` its page number; `.ix`, `^ONI` and text marked with
`^PK` become the index at the end (sorted ignoring case, first letter capitalized, `main, sub` as a
subentry, `+` bold page number, `-` cross reference without a page number, `\` quotes the next character;
a blank line where the first letter changes). Markdown: links `→` to anchors at the places instead of page
numbers. RTF: the table of contents is a section of its own (the document's pages are numbered from 1),
page numbers are `PAGEREF` fields to bookmarks that the word processor fills in, and hidden `TC` / `XE`
fields let it build its own table of contents and index. Plain text (`-t`) leaves both out.

To WordStar (`-w`): the document is in the WordStar 4 style (no header; WordStar 7 opens it and saves it in its own
format). Paragraphs are wrapped at column 65 with soft returns; characters above 7Fh become extended characters
(1Bh xx 1Ch), characters missing from the code page become `?` (counted in the message). Plain text: each line
is a paragraph. Markdown: `**`/`__` bold, `*`/`_` italic, `~~` strike-out, `<u>`…`</u>` underline; headings in bold; list items with a
hanging indent; quotes indented; code blocks and table rows as they are; links and pictures as their text.
A line that would start with `.` gets a soft space in front, so it is not a dot command. RTF to WordStar: use
Star Exchange (`RTFCONV.EXE` in WordStar 7's `CONVERT`).

Limitations:

- Pictures with the same name from different folders become `logo.png`, `logo-2.png` …; an existing file of
  that name is never replaced by a different picture.
- The output file may not be the input file (`-o`, or `-t` on a `.txt` document): that is an error.
- A 1Dh sequence cut off at the end of the file drops the rest of the text. In a file damaged inside, a stray
  1Dh followed by bytes that read as a length past the end drops the rest as well.
- RTF has one header and one footer (`.he`/`.h1`, `.fo`/`.f1`); `.h2`-`.h5`, `.f2`-`.f5` and even/odd page
  ones (`.h1e`, `.f3o` ...) are kept as hidden text.
- A damaged `.DBF` is reported (merge message, or a comment for `.fi`), not read as text.
- Worksheets: at most 256 columns of a range; `.PIX` pictures: at most 64M pixels (larger ones stay links).
- Color `.PIX` pictures get their print colors (Inset's map from screen colors to EGA colors: the black
  screen background becomes white paper). Not checked against a color printout; one-bit pictures are ink on paper.
- `.df` in a document included with `.fi` is looked up in the main document's folder (WordStar's rule not
  verified). Files named in a document are read wherever the path points, also outside its folder.
- RTF is checked against the reference output; the table of contents and index were also checked in
  LibreOffice (page numbers filled in), not in Word, which shows them after the fields are updated (F9).
  RTF was compared with Star Exchange, WordStar 7's own converter (`CONVERT\RTFCONV.EXE`): same page size
  (US Letter), margins and line spacing; comments (`..`, `.ig`) are hidden text as there. Star Exchange
  drops paragraph numbers and Cyrillic (it writes code page 437), and its page breaks drift further from
  WordStar's than these.
- RTF index: an entry found twice on one page lists that page twice (`PAGEREF` per place; WordStar
  merges them). Page numbers follow the word processor's layout, which may differ from WordStar's.
- RTF pages: lines are spaced exactly as WordStar prints them (`.lh`, default 6 lines per inch; `.lh a`:
  the word processor's spacing), `.cp` keeps the next lines on one page. With fixed-pitch fonts the page
  breaks then match WordStar's (MICKEE.WS: same pages up to its two-column part); with proportional fonts
  lines wrap by the word processor's font metrics, so pages drift.

Units: `wsutil` (code pages, strings, regular expressions, number formatting), `wsdoc` (document format),
`wsmd` (Markdown / text), `wsrtf` (RTF), `wsfrom` (text / Markdown to WordStar), `wsmerge` (merge printing and data files), `wsimage` (pictures).
The code page tables `cptables.inc` are generated by `python gencp.py`.

## Building

Windows: `fpc -O2 -FUlib wsconv.pas`

DOS (go32v2): run `dosbox-x -conf build-dos.conf` from this folder. It needs DOSBox-X (long file names,
512 MB) and the DOS version of Free Pascal (`dos322full.zip`); set the `mount f` line of `build-dos.conf` to
where it is unpacked. `builddos.bat` writes `dos\wsconv.exe` and copies `dos\cwsdpmi.exe` (the DPMI server,
needed next to the program or in the PATH). The build takes a few minutes with a still screen; compiler
output goes to `dos\build.log`.

DOS specifics: the `fpwidestring` unit provides Unicode without code page tables, so encoded strings are
compared bytewise only — `AnsiCompareStr`, a sorted `TStringList` and the like crash under DOS.

## Testing

`runtests` runs every case in `tests\` and compares the files written with `expect\` byte by byte.
A case folder holds the input (the document, `in.ws` in the synthetic cases, and any `.fi`, `.df` or picture files it uses), `args` (the
command line, one argument per line, run from the case folder) and `expect\`; `tests\index.txt` names
the cases. Build and run on Windows:

    fpc -O2 -FUlib runtests.pas
    runtests wsconv.exe

DOS: `builddos.bat` builds `dos\runtests.exe` as well; `dosbox-x -conf test-dos.conf` then runs the tests
with the DOS build and writes the result to `dos\test.log`.

The expected files were checked against the Python converter this program was translated from
(its unit tests, including the real WordStar 7.0 documents in `samples\`; cases 104-133 are documents from
the WordStar 7 collection at https://sfwriter.com/ws7.htm in md, txt, rtf and rtf `-q`). When a fix changes the output
on purpose, replace the case's `expect\` files with the new, verified output.

## Origin and license

The work started from the idea of [kbarni/wsconvert](https://github.com/kbarni/wsconvert), a small
WordStar-to-Markdown converter in Python. That converter was rewritten and greatly extended in Python,
and fpwsconv is a Free Pascal translation of the extended version.

Copyright (C) 2026 Lumenman. This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version. See [LICENSE](LICENSE).

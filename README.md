# wsconv — конвертер WordStar на Free Pascal

Перенос `..\wsconvert-master` (Python) на Free Pascal 3.2.2: WordStar 3.x–7.0 → Markdown, текст или RTF.
Ключи и результат те же, что у `wsconvert.py`:

    wsconv [-o ВЫХОД] [-t] [-r] [-q] [-m] [-s ИМЯ=ЗНАЧ] [-c 437|866|1125|auto] ФАЙЛ.WS

Модули: `wsutil` (кодовые страницы, строки, регулярки, числа как в Python), `wsdoc` (разбор формата),
`wsmd` (Markdown/текст), `wsrtf` (RTF), `wsmerge` (слияние, WK1/WQ1, DBF, CSV), `wsimage` (PIX, PCX… → PNG).
Таблицы кодовых страниц `cptables.inc` создаёт `python gencp.py`.

## Сборка

Windows: `fpc -O2 -FUlib wsconv.pas`

DOS (go32v2): `D:\DOSBox-X\dosbox-x.exe -conf build-dos.conf` — DOSBox-X (длинные имена, 512 МБ)
с DOS-версией FPC (`dos322full.zip`, распакован в `D:\Programs\FPCDOS`) запускает `builddos.bat`;
результат — `dos\wsconv.exe` и `dos\cwsdpmi.exe` (DPMI-сервер, нужен рядом или в PATH). Сборка идёт
несколько минут, экран всё это время не меняется (вывод компилятора — в `dosuild.log`).

## Проверка

`python compare.py` — сверка с Python-версией:
1. каждое преобразование из `test_wsconvert.py` повторяется через `wsconv.exe`;
2. все документы проекта (.WS, .DOC) → md, txt, rtf, rtf -q.

Картинки в RTF сравниваются по размерам, не по байтам PNG.

`python dostest.py` — DOS-версия в DOSBox-X на `samples\*.WS` (md, txt, rtf) против Windows-версии:
27 файлов, совпадают побайтно.

Особенность DOS: модуль `fpwidestring` (Unicode без таблиц кодовых страниц); строки с кодировкой
сравниваются только побайтно — `AnsiCompareStr`, сортированный `TStringList` и т. п. под DOS падают.

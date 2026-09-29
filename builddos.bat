@echo off
rem DOS build of wsconv (go32v2) with DOS Free Pascal on F: -- run in DOSBox-X via build-dos.conf
if not exist libdos\nul mkdir libdos
if not exist dos\nul mkdir dos
ppc386 -Tgo32v2 -O2 -Xs -Fuf:\units\go32v2\* -FUlibdos -FEdos wsconv.pas > dos\build.log
copy f:\cwsdpmi.exe dos > nul

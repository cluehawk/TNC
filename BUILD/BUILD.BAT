@ECHO OFF
REM Turbo Pascal 7 DOS build script
REM Run this from the project root or from BUILD\ under Windows.

IF EXIST ..\SRC\TNC.PAS GOTO FROMBUILD
IF EXIST SRC\TNC.PAS GOTO FROMROOT
ECHO Could not find SRC\TNC.PAS
EXIT /B 1

:FROMBUILD
CD ..

:FROMROOT
CD SRC
IF EXIST *.TPU DEL *.TPU
ECHO Building TNC.EXE with Turbo Pascal 7...
MSDOS.exe ..\BIN\TPC /B /M /$G- /$R- /$S- TNC.PAS
EXIT /B %ERRORLEVEL%

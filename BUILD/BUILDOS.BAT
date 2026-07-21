@ECHO OFF
REM Turbo Pascal 7 DOS build script
REM Run this from the project root or from BUILD\ under DOS.

IF EXIST ..\SRC\TNC.PAS GOTO FROMBUILD
IF EXIST SRC\TNC.PAS GOTO FROMROOT
ECHO Could not find SRC\TNC.PAS
GOTO END

:FROMBUILD
CD ..

:FROMROOT
CD SRC
IF EXIST *.TPU DEL *.TPU
ECHO Building TNC.EXE with Turbo Pascal 7...
TPC /B /M /$G- /$R- /$S- TNC.PAS

:END

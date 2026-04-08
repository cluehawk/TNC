@ECHO OFF
REM Turbo Pascal 7 DOS build script
REM Run this from the project root or from BUILD\ under DOS.

IF EXIST ..\SRC\TNC.PAS GOTO BUILDROOT
IF EXIST SRC\TNC.PAS GOTO BUILDLOCAL
ECHO Could not find SRC\TNC.PAS
GOTO END

:BUILDROOT
CD ..
CD SRC
del *.tpu

:BUILDLOCAL
ECHO Building TNC.EXE with Turbo Pascal 7...
MSDOS.exe ..\BIN\TPC /B /M /$G- /$R- /$S- TNC.PAS
GOTO END

:END

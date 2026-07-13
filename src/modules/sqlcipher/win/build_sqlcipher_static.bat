@echo off
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
set "SRC=%~1"
if not defined SRC set "SRC=C:\Users\me\Downloads\sqlcipher-4.17.0"
set "OUT=%~dp0"
set "PROV=%OUT%sqlcipher_win32.c"
cd /d "%SRC%" || exit /b 1
if not exist sqlite3.c nmake /f Makefile.msc sqlite3.c || exit /b 1
cl /nologo /O2 /MT /c sqlite3.c /Fosqlcipher.obj /DSQLITE_HAS_CODEC /DSQLITE_TEMP_STORE=2 /DSQLITE_EXTRA_INIT=sqlcipher_extra_init /DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown /DSQLCIPHER_CRYPTO_CUSTOM=sqlcipher_win32_setup /DSQLITE_THREADSAFE=1 /DSQLITE_ENABLE_FTS5 /DSQLITE_ENABLE_RTREE /DSQLITE_ENABLE_COLUMN_METADATA || exit /b 1
cl /nologo /O2 /MT /c "%PROV%" /I"%SRC%" /Fosqlcipher_win32.obj || exit /b 1
lib /nologo /OUT:"%OUT%sqlcipher_static.lib" sqlcipher.obj sqlcipher_win32.obj || exit /b 1
echo Built %OUT%sqlcipher_static.lib

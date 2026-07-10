@echo off
setlocal enableDelayedExpansion

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
if errorlevel 1 (
    echo Failed to initialize MSVC environment
    exit /b 1
)

set PATH=C:\Qt\6.7.3\msvc2019_64\bin;%PATH%

cd /d "%~dp0.."
if exist build rmdir /s /q build
mkdir build\build-x64-release
cd build\build-x64-release

echo Configuring release build...
qmake ..\..\moonlight-qt.pro CONFIG+=release
if errorlevel 1 exit /b 1

echo Compiling...
..\..\scripts\jom.exe release
if errorlevel 1 exit /b 1

cd ..\..

echo.
echo Build OK. Creating portable deploy package...
call scripts\deploy-portable.bat release
exit /b %ERRORLEVEL%

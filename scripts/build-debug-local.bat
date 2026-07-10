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
mkdir build\build-x64-debug
cd build\build-x64-debug

qmake ..\..\moonlight-qt.pro CONFIG+=debug
if errorlevel 1 exit /b 1

..\..\scripts\jom.exe debug
if errorlevel 1 exit /b 1

echo.
echo Build OK: %cd%\app\debug\Moonlight.exe
exit /b 0

@echo off
setlocal enableDelayedExpansion

set SOURCE_ROOT=%~dp0..
set VSWHERE="%SOURCE_ROOT%\scripts\vswhere.exe"
where cl >nul 2>&1
if errorlevel 1 (
    for /f "usebackq delims=" %%i in (`%VSWHERE% -latest -property installationPath`) do (
        call "%%i\VC\Auxiliary\Build\vcvarsall.bat" x64
    )
    if errorlevel 1 (
        echo Failed to initialize MSVC environment
        exit /b 1
    )
)

for /f "delims=" %%P in ('where qmake 2^>nul') do (
    set "PATH=%%~dpP;%PATH%"
    goto QtPathDone
)
set PATH=C:\Qt\6.7.3\msvc2019_64\bin;%PATH%
:QtPathDone

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

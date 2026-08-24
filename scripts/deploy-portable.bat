@echo off
setlocal enableDelayedExpansion

rem Deploy a runnable portable folder (release recommended for other PCs).
rem Usage: scripts\deploy-portable.bat [debug^|release]

set BUILD_CONFIG=%1
if /I "%BUILD_CONFIG%"=="" set BUILD_CONFIG=release
if /I not "%BUILD_CONFIG%"=="debug" if /I not "%BUILD_CONFIG%"=="release" (
    echo Usage: scripts\deploy-portable.bat [debug^|release]
    exit /b 1
)

if /I "%BUILD_CONFIG%"=="debug" (
    echo WARNING: Debug builds require MSVC/Qt debug runtimes and usually fail on other PCs.
    echo          Use "release" for distribution.
    echo.
)

set SOURCE_ROOT=%~dp0..
set BUILD_FOLDER=%SOURCE_ROOT%\build\build-x64-%BUILD_CONFIG%
set DEPLOY_FOLDER=%SOURCE_ROOT%\build\deploy-x64-%BUILD_CONFIG%
set VSWHERE="%SOURCE_ROOT%\scripts\vswhere.exe"

if not exist "%BUILD_FOLDER%\app\%BUILD_CONFIG%\Moonlight.exe" (
    echo Moonlight.exe not found. Build first:
    echo   scripts\build-release-local.bat
    echo or
    echo   scripts\build-debug-local.bat
    exit /b 1
)

where cl >nul 2>&1
if errorlevel 1 (
    call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
    if errorlevel 1 (
        for /f "usebackq delims=" %%i in (`%VSWHERE% -latest -property installationPath`) do (
            call "%%i\VC\Auxiliary\Build\vcvarsall.bat" x64
        )
    )
    if errorlevel 1 (
        echo Failed to initialize MSVC environment.
        exit /b 1
    )
)

for /f "delims=" %%P in ('where qmake 2^>nul') do (
    set "PATH=%%~dpP;%PATH%"
    goto QtPathDone
)
set PATH=C:\Qt\6.7.3\msvc2019_64\bin;%PATH%
:QtPathDone

echo Cleaning deploy folder...
if exist "%DEPLOY_FOLDER%" rmdir /s /q "%DEPLOY_FOLDER%"
mkdir "%DEPLOY_FOLDER%"

echo Copying prebuilt libraries...
copy /Y "%SOURCE_ROOT%\libs\windows\lib\x64\*.dll" "%DEPLOY_FOLDER%\" >nul
if errorlevel 1 goto Error

echo Copying AntiHooking.dll...
copy /Y "%BUILD_FOLDER%\AntiHooking\%BUILD_CONFIG%\AntiHooking.dll" "%DEPLOY_FOLDER%\" >nul
if errorlevel 1 goto Error

echo Copying gamecontrollerdb.txt...
copy /Y "%SOURCE_ROOT%\app\SDL_GameControllerDB\gamecontrollerdb.txt" "%DEPLOY_FOLDER%\" >nul
if errorlevel 1 goto Error

echo Copying Moonlight.exe...
copy /Y "%BUILD_FOLDER%\app\%BUILD_CONFIG%\Moonlight.exe" "%DEPLOY_FOLDER%\" >nul
if errorlevel 1 goto Error

if exist "%SOURCE_ROOT%\app\qt_qt5.conf" (
    copy /Y "%SOURCE_ROOT%\app\qt_qt5.conf" "%DEPLOY_FOLDER%\qt.conf" >nul
)

echo Running windeployqt...
set WINDEPLOYQT_ARGS=--no-system-d3d-compiler --no-system-dxc-compiler --skip-plugin-types qmltooling,generic --no-ffmpeg
set WINDEPLOYQT_ARGS=!WINDEPLOYQT_ARGS! --no-quickcontrols2fusion --no-quickcontrols2imagine --no-quickcontrols2universal
set WINDEPLOYQT_ARGS=!WINDEPLOYQT_ARGS! --no-quickcontrols2fusionstyleimpl --no-quickcontrols2imaginestyleimpl --no-quickcontrols2universalstyleimpl --no-quickcontrols2windowsstyleimpl

windeployqt --dir "%DEPLOY_FOLDER%" --%BUILD_CONFIG% --qmldir "%SOURCE_ROOT%\app\gui" --no-opengl-sw --no-sql !WINDEPLOYQT_ARGS! "%DEPLOY_FOLDER%\Moonlight.exe"
if errorlevel 1 goto Error

echo Removing unused Qt style plugins...
if exist "%DEPLOY_FOLDER%\qml\QtQuick\Controls\Fusion" rmdir /s /q "%DEPLOY_FOLDER%\qml\QtQuick\Controls\Fusion"
if exist "%DEPLOY_FOLDER%\qml\QtQuick\Controls\Imagine" rmdir /s /q "%DEPLOY_FOLDER%\qml\QtQuick\Controls\Imagine"
if exist "%DEPLOY_FOLDER%\qml\QtQuick\Controls\Universal" rmdir /s /q "%DEPLOY_FOLDER%\qml\QtQuick\Controls\Universal"
if exist "%DEPLOY_FOLDER%\qml\QtQuick\Controls\Windows" rmdir /s /q "%DEPLOY_FOLDER%\qml\QtQuick\Controls\Windows"
if exist "%DEPLOY_FOLDER%\qml\QtQuick\NativeStyle" rmdir /s /q "%DEPLOY_FOLDER%\qml\QtQuick\NativeStyle"

echo Copying MSVC runtime DLLs...
set VC_REDIST_COPIED=0
for /f "usebackq delims=" %%i in (`%VSWHERE% -latest -find VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT`) do (
    echo   from %%i
    copy /Y "%%i\*.dll" "%DEPLOY_FOLDER%\" >nul
    if not errorlevel 1 set VC_REDIST_COPIED=1
)

if "!VC_REDIST_COPIED!"=="0" (
    echo   VC Redist folder not found in VS installation.
    echo   Copying from System32 as fallback...
    for %%f in (vcruntime140.dll vcruntime140_1.dll msvcp140.dll msvcp140_1.dll concrt140.dll) do (
        if exist "%SystemRoot%\System32\%%f" copy /Y "%SystemRoot%\System32\%%f" "%DEPLOY_FOLDER%\" >nul
    )
)

echo Creating portable.dat...
echo.>"%DEPLOY_FOLDER%\portable.dat"

echo.
echo Portable package ready:
echo   %DEPLOY_FOLDER%
echo.
echo Zip this entire folder to move to another PC.
if /I "%BUILD_CONFIG%"=="release" (
    echo For release builds, target PC only needs Windows 10+ ^(ucrtbase.dll^).
) else (
    echo DEBUG package: may still fail on PCs without MSVC/Qt debug runtimes.
)
exit /b 0

:Error
echo Deploy failed!
exit /b 1

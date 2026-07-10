@echo off
setlocal EnableExtensions
title Moonlight MLMC - Receptor (manual)

set "DIR=%~dp0"
set "PORT=9000"
set "PRIMING_MS=50"
set "DEVICE=16"
set "LOG=%DIR%udp_audio_server.log"

cd /d "%DIR%"

if exist "%DIR%config.ini" (
    for /f "usebackq tokens=1,* delims==" %%A in (`findstr /i /r "^device=" "%DIR%config.ini"`) do (
        if /i "%%A"=="device" set "DEVICE=%%B"
    )
    for /f "usebackq tokens=1,* delims==" %%A in (`findstr /i /r "^port=" "%DIR%config.ini"`) do (
        if /i "%%A"=="port" set "PORT=%%B"
    )
)

where python >nul 2>&1
if errorlevel 1 (
    echo ERRO: Python nao encontrado. Rode INSTALAR.bat primeiro.
    pause
    exit /b 1
)

if not exist "%DIR%udp_audio_server.py" (
    echo ERRO: udp_audio_server.py nao encontrado.
    pause
    exit /b 1
)

echo Iniciando receptor MLMC (device=%DEVICE%, port=%PORT%)...
echo Log: %LOG%
echo.
echo Feche esta janela para parar o receptor.
echo.

python "%DIR%udp_audio_server.py" --device %DEVICE% --port %PORT% --priming-ms %PRIMING_MS% --log-file "%LOG%"
echo.
echo Servidor encerrou (codigo %ERRORLEVEL%).
pause
exit /b %ERRORLEVEL%

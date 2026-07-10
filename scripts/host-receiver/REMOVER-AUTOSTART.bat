@echo off
setlocal EnableExtensions
title Moonlight MLMC - Remover autostart

set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Moonlight MLMC UDP Audio.lnk"
set "LAUNCHER=%~dp0udp_audio_autostart.vbs"

if exist "%LNK%" (
    del /f /q "%LNK%"
    echo Atalho de inicializacao removido.
) else (
    echo Nenhum atalho de inicializacao encontrado.
)

if exist "%LAUNCHER%" (
    del /f /q "%LAUNCHER%"
    echo Launcher interno removido.
)

echo.
echo O receptor nao vai mais iniciar com o Windows.
echo Para reativar, execute INSTALAR.bat novamente.
pause
exit /b 0

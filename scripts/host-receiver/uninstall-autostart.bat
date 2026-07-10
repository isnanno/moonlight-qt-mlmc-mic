@echo off
setlocal EnableExtensions

set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Moonlight MLMC UDP Audio.lnk"
set "LAUNCHER=%~dp0udp_audio_autostart.vbs"

if exist "%LNK%" del /f /q "%LNK%"
if exist "%LAUNCHER%" del /f /q "%LAUNCHER%"

if exist "%LNK%" (
    echo Falha ao remover atalho.
) else (
    echo Atalho de autostart removido.
)

if exist "%LAUNCHER%" (
    echo Falha ao remover launcher gerado.
) else (
    echo Launcher gerado removido.
)

pause
exit /b 0

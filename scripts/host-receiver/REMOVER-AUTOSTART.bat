@echo off
setlocal EnableExtensions
title Moonlight MLMC - Remover autostart

set "TASK=Moonlight MLMC UDP Audio"
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Moonlight MLMC UDP Audio.lnk"
set "LAUNCHER_BAT=%~dp0udp_audio_autostart.bat"
set "LAUNCHER_VBS=%~dp0udp_audio_autostart.vbs"

schtasks /Query /TN "%TASK%" >nul 2>&1
if not errorlevel 1 (
    schtasks /Delete /TN "%TASK%" /F >nul
    echo Tarefa agendada removida.
) else (
    echo Nenhuma tarefa agendada encontrada.
)

if exist "%LNK%" (
    del /f /q "%LNK%"
    echo Atalho antigo da pasta Inicializar removido.
)

if exist "%LAUNCHER_BAT%" del /f /q "%LAUNCHER_BAT%"
if exist "%LAUNCHER_VBS%" del /f /q "%LAUNCHER_VBS%"

echo.
echo O receptor nao vai mais iniciar com o Windows.
echo Para reativar, execute INSTALAR.bat novamente.
pause
exit /b 0

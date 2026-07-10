@echo off
setlocal EnableExtensions

set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Moonlight MLMC UDP Audio.lnk"

if exist "%LNK%" (
    del /f /q "%LNK%"
    echo Atalho de autostart removido.
) else (
    echo Nenhum atalho de autostart encontrado.
)

pause
exit /b 0

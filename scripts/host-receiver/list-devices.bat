@echo off
setlocal EnableExtensions
cd /d "%~dp0"

where python >nul 2>&1
if errorlevel 1 (
    echo ERRO: Python nao encontrado no PATH.
    pause
    exit /b 1
)

python "%~dp0udp_audio_server.py" --list-devices
echo.
echo Anote o indice do dispositivo de saida (ex.: VB-Cable) e edite:
echo   udp_audio_start.bat  - variavel DEVICE
echo   udp_audio_start.vbs  - variavel deviceIndex
pause
exit /b 0

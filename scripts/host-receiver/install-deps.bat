@echo off
setlocal EnableExtensions

cd /d "%~dp0"

where python >nul 2>&1
if errorlevel 1 (
    echo ERRO: Python nao encontrado no PATH.
    echo Instale Python 3.10+ de https://www.python.org/downloads/
    echo Marque "Add python.exe to PATH" no instalador.
    pause
    exit /b 1
)

echo Instalando dependencias do receptor MLMC...
python -m pip install --upgrade pip
python -m pip install -r "%~dp0requirements-udp-audio.txt"
if errorlevel 1 (
    echo Falha ao instalar dependencias.
    pause
    exit /b 1
)

echo.
echo OK. Proximo passo: execute list-devices.bat e ajuste o indice em udp_audio_start.bat / .vbs
pause
exit /b 0

@echo off
setlocal EnableExtensions

rem Inicia o receptor MLMC/UDP na VM/host (janela visível, logs no console e em arquivo).
rem Ajuste DEVICE para o índice do dispositivo de saída (VB-Cable, etc.).

set "DIR=%~dp0"
set "DEVICE=16"
set "PORT=9000"
set "PRIMING_MS=50"
set "LOG=%DIR%udp_audio_server.log"

cd /d "%DIR%"

where python >nul 2>&1
if errorlevel 1 (
  echo [%date% %time%] ERRO: Python nao encontrado no PATH.>> "%LOG%"
  exit /b 1
)

echo [%date% %time%] Iniciando udp_audio_server.py (device=%DEVICE%, port=%PORT%)>> "%LOG%"

python "%DIR%udp_audio_server.py" --device %DEVICE% --port %PORT% --priming-ms %PRIMING_MS% --log-file "%LOG%"

echo [%date% %time%] Servidor encerrou com codigo %ERRORLEVEL%.>> "%LOG%"
exit /b %ERRORLEVEL%

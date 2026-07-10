@echo off
setlocal EnableExtensions

rem Autostart confiavel: gera launcher com caminho absoluto do pythonw.
set "DIR=%~dp0"
set "PS1=%DIR%install-autostart.ps1"

if not exist "%PS1%" (
    echo ERRO: install-autostart.ps1 nao encontrado.
    pause
    exit /b 1
)

where python >nul 2>&1
if errorlevel 1 (
    echo ERRO: Python nao encontrado no PATH. Rode install-deps.bat primeiro.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
if errorlevel 1 (
    echo Falha ao configurar autostart.
    pause
    exit /b 1
)

pause
exit /b 0

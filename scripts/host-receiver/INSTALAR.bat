@echo off
setlocal EnableExtensions
title Moonlight MLMC - Instalar receptor

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
exit /b %ERRORLEVEL%

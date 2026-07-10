@echo off
setlocal EnableExtensions

set "DIR=%~dp0"
set "VBS=%DIR%udp_audio_start.vbs"
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Moonlight MLMC UDP Audio.lnk"

if not exist "%VBS%" (
    echo ERRO: udp_audio_start.vbs nao encontrado em %DIR%
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$s = (New-Object -ComObject WScript.Shell).CreateShortcut('%LNK%');" ^
  "$s.TargetPath = 'wscript.exe';" ^
  "$s.Arguments = '//B \"\"%VBS%\"\"';" ^
  "$s.WorkingDirectory = '%DIR%';" ^
  "$s.Description = 'Moonlight MLMC UDP microphone receiver (port 9000)';" ^
  "$s.Save()"

if errorlevel 1 (
    echo Falha ao criar atalho de inicializacao.
    pause
    exit /b 1
)

echo Atalho criado:
echo   %LNK%
echo.
echo O receptor iniciara automaticamente no proximo login (sem janela).
echo Logs: %DIR%udp_audio_server.log
pause
exit /b 0

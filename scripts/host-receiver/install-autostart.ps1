# Autostart confiavel via Agendador de Tarefas (logon + 10s).
# A pasta Inicializar NAO executa .vbs no boot — so no duplo clique manual.
$ErrorActionPreference = 'Stop'

$TaskName = 'Moonlight MLMC UDP Audio'
$Dir = if ($PSScriptRoot -match 'host-receiver$') {
    Split-Path $PSScriptRoot -Parent
} else {
    $PSScriptRoot
}

$ServerPy = Join-Path $Dir 'udp_audio_server.py'
$LauncherBat = Join-Path $Dir 'udp_audio_autostart.bat'
$BootLog = Join-Path $Dir 'autostart_boot.log'
$ServerLog = Join-Path $Dir 'udp_audio_server.log'
$ConfigPath = Join-Path $Dir 'config.ini'
$OldShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Moonlight MLMC UDP Audio.lnk'
$OldVbs = Join-Path $Dir 'udp_audio_autostart.vbs'
$Device = 16
$Port = 9000

if (Test-Path $ConfigPath) {
    $configText = Get-Content $ConfigPath -Raw
    if ($configText -match '(?m)^device\s*=\s*(\d+)\s*$') {
        $Device = [int]$Matches[1]
    }
    if ($configText -match '(?m)^port\s*=\s*(\d+)\s*$') {
        $Port = [int]$Matches[1]
    }
}

if (-not (Test-Path $ServerPy)) {
    Write-Error "udp_audio_server.py nao encontrado em: $Dir"
}

$pythonw = & python -c "import sys, pathlib; print(pathlib.Path(sys.executable).with_name('pythonw.exe'))"
if (-not $pythonw -or -not (Test-Path $pythonw)) {
    $pythonCmd = Get-Command python -ErrorAction Stop
    $pythonw = Join-Path (Split-Path $pythonCmd.Source -Parent) 'pythonw.exe'
}
if (-not (Test-Path $pythonw)) {
    throw "pythonw.exe nao encontrado. Rode INSTALAR.bat primeiro."
}

$bat = @"
@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo [%date% %time%] Autostart via tarefa agendada>> "$BootLog"
"$pythonw" "$ServerPy" --host 0.0.0.0 --port $Port --device $Device --priming-ms 50 --log-file "$ServerLog"
echo [%date% %time%] Servidor encerrou (codigo %ERRORLEVEL%)>> "$BootLog"
exit /b %ERRORLEVEL%
"@

Set-Content -Path $LauncherBat -Value $bat -Encoding ASCII

Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

$action = New-ScheduledTaskAction -Execute $LauncherBat -WorkingDirectory $Dir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$trigger.Delay = 'PT10S'
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description 'Receptor microfone Moonlight MLMC (UDP 9000)' | Out-Null

if (Test-Path $OldShortcut) {
    Remove-Item $OldShortcut -Force
}
if (Test-Path $OldVbs) {
    Remove-Item $OldVbs -Force
}

Write-Host ""
Write-Host "Autostart configurado (Agendador de Tarefas)."
Write-Host "  Tarefa : $TaskName"
Write-Host "  Quando : ao fazer login (+ 10 segundos)"
Write-Host "  Launcher: $LauncherBat"
Write-Host "  Pythonw : $pythonw"
Write-Host ""
Write-Host "Reinicie o PC ou faca logout/login para testar."
Write-Host "Log de boot: $BootLog"

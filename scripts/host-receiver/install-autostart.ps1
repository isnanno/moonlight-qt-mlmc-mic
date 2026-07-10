# Autostart via Agendador de Tarefas — pythonw direto, sem janela de console.
$ErrorActionPreference = 'Stop'

$TaskName = 'Moonlight MLMC UDP Audio'
$Dir = if ($PSScriptRoot -match 'host-receiver$') {
    Split-Path $PSScriptRoot -Parent
} else {
    $PSScriptRoot
}

$ServerPy = Join-Path $Dir 'udp_audio_server.py'
$ServerLog = Join-Path $Dir 'udp_audio_server.log'
$ConfigPath = Join-Path $Dir 'config.ini'
$OldShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Moonlight MLMC UDP Audio.lnk'
$OldVbs = Join-Path $Dir 'udp_audio_autostart.vbs'
$OldBat = Join-Path $Dir 'udp_audio_autostart.bat'
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

$arguments = "`"$ServerPy`" --host 0.0.0.0 --port $Port --device $Device --priming-ms 50 --log-file `"$ServerLog`""

Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

$action = New-ScheduledTaskAction -Execute $pythonw -Argument $arguments -WorkingDirectory $Dir
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

foreach ($old in @($OldShortcut, $OldVbs, $OldBat)) {
    if (Test-Path $old) { Remove-Item $old -Force }
}

Write-Host ""
Write-Host "Autostart configurado (sem janela visivel)."
Write-Host "  Tarefa  : $TaskName"
Write-Host "  Quando  : ao fazer login (+ 10 segundos)"
Write-Host "  Pythonw : $pythonw"
Write-Host "  Log     : $ServerLog"
Write-Host ""
Write-Host "Reinicie o PC ou faca logout/login para testar."

# Cria autostart confiavel no Windows (caminho completo do pythonw embutido).
$ErrorActionPreference = 'Stop'

$Dir = if ($PSScriptRoot -match 'host-receiver$') {
    Split-Path $PSScriptRoot -Parent
} else {
    $PSScriptRoot
}

$ServerPy = Join-Path $Dir 'udp_audio_server.py'
$LauncherVbs = Join-Path $Dir 'udp_audio_autostart.vbs'
$ShortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Moonlight MLMC UDP Audio.lnk'
$ConfigPath = Join-Path $Dir 'config.ini'
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

$pythonCmd = Get-Command python -ErrorAction Stop
$pythonw = & python -c "import sys, pathlib; print(pathlib.Path(sys.executable).with_name('pythonw.exe'))"
if (-not $pythonw -or -not (Test-Path $pythonw)) {
    $pythonw = Join-Path (Split-Path $pythonCmd.Source -Parent) 'pythonw.exe'
}
if (-not (Test-Path $pythonw)) {
    throw "pythonw.exe nao encontrado. Rode install-deps.bat primeiro."
}

$vbs = @"
' Gerado por install-autostart - nao editar manualmente.
' Usa caminho absoluto do pythonw para funcionar na pasta Inicializar (PATH incompleto no boot).

Option Explicit

Dim fso, shell, scriptDir, logFile, bootLogFile, pythonwPath, serverPy, cmd, deviceIndex, rc

deviceIndex = $Device

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
logFile = scriptDir & "\udp_audio_server.log"
bootLogFile = scriptDir & "\autostart_boot.log"
serverPy = scriptDir & "\udp_audio_server.py"
pythonwPath = "$($pythonw -replace '\\', '\\')"

Sub WriteBootLog(msg)
    On Error Resume Next
    Dim f
    Set f = fso.OpenTextFile(bootLogFile, 8, True)
    f.WriteLine CStr(Now) & " " & msg
    f.Close
End Sub

WriteBootLog "Autostart disparado."
WriteBootLog "pythonw=" & pythonwPath

If Not fso.FileExists(pythonwPath) Then
    WriteBootLog "ERRO: pythonw.exe nao encontrado."
    WScript.Quit 1
End If

If Not fso.FileExists(serverPy) Then
    WriteBootLog "ERRO: udp_audio_server.py nao encontrado."
    WScript.Quit 1
End If

cmd = """" & pythonwPath & """ """ & serverPy & """ --host 0.0.0.0 --port $Port --device " & deviceIndex & " --priming-ms 50 --log-file """ & logFile & """"
WriteBootLog "Executando: " & cmd

rc = shell.Run(cmd, 0, False)
WriteBootLog "shell.Run retornou: " & rc
"@

Set-Content -Path $LauncherVbs -Value $vbs -Encoding ASCII

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $LauncherVbs
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $Dir
$shortcut.WindowStyle = 7
$shortcut.Description = 'Moonlight MLMC UDP microphone receiver (port 9000)'
$shortcut.Save()

Write-Host ""
Write-Host "Autostart configurado."
Write-Host "  Atalho: $ShortcutPath"
Write-Host "  Launcher: $LauncherVbs"
Write-Host "  Pythonw: $pythonw"
Write-Host ""
Write-Host "Reinicie o PC ou faca logout/login para testar."
Write-Host "Se falhar no boot, veja: $(Join-Path $Dir 'autostart_boot.log')"

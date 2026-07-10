' Inicia o servidor UDP de áudio sem janela visível (ideal para autostart no Windows).
' Uso manual: wscript.exe //B "%~dp0udp_audio_start.vbs"
' Autostart: atalho deste .vbs na pasta Inicializar do Windows.

Option Explicit

Dim fso, shell, scriptDir, logFile, pythonw, serverPy, cmd, deviceIndex

deviceIndex = 16

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
logFile = scriptDir & "\udp_audio_server.log"
serverPy = scriptDir & "\udp_audio_server.py"
pythonw = "pythonw"

cmd = pythonw & " """ & serverPy & """ --host 0.0.0.0 --port 9000 --device " & deviceIndex & " --priming-ms 50 --log-file """ & logFile & """"

shell.Run cmd, 0, False

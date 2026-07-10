' Inicia o servidor UDP de audio sem janela visivel (uso manual).
' Para autostart no Windows, use install-autostart.bat (gera udp_audio_autostart.vbs).

Option Explicit

Dim fso, shell, scriptDir, logFile, bootLogFile, pythonwPath, serverPy, cmd, deviceIndex, rc

deviceIndex = 16

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
logFile = scriptDir & "\udp_audio_server.log"
bootLogFile = scriptDir & "\autostart_boot.log"
serverPy = scriptDir & "\udp_audio_server.py"

Sub WriteBootLog(msg)
    On Error Resume Next
    Dim f
    Set f = fso.OpenTextFile(bootLogFile, 8, True)
    f.WriteLine CStr(Now) & " " & msg
    f.Close
End Sub

Function ResolvePythonw()
    Dim appsDir, subFolder, candidate, programFiles

    programFiles = shell.ExpandEnvironmentStrings("%LocalAppData%") & "\Programs\Python"
    If fso.FolderExists(programFiles) Then
        For Each subFolder In fso.GetFolder(programFiles).SubFolders
            candidate = subFolder.Path & "\pythonw.exe"
            If fso.FileExists(candidate) Then
                ResolvePythonw = candidate
                Exit Function
            End If
        Next
    End If

    appsDir = shell.ExpandEnvironmentStrings("%LocalAppData%") & "\Microsoft\WindowsApps"
    If fso.FolderExists(appsDir) Then
        For Each subFolder In fso.GetFolder(appsDir).SubFolders
            If InStr(1, subFolder.Name, "Python", vbTextCompare) > 0 Then
                candidate = subFolder.Path & "\pythonw.exe"
                If fso.FileExists(candidate) Then
                    ResolvePythonw = candidate
                    Exit Function
                End If
            End If
        Next
    End If

    ResolvePythonw = "pythonw"
End Function

pythonwPath = ResolvePythonw()

If pythonwPath = "" Then
    WriteBootLog "ERRO: pythonw.exe nao encontrado (udp_audio_start.vbs manual)."
    WScript.Quit 1
End If

cmd = """" & pythonwPath & """ """ & serverPy & """ --host 0.0.0.0 --port 9000 --device " & deviceIndex & " --priming-ms 50 --log-file """ & logFile & """"
WriteBootLog "Manual start: " & cmd
rc = shell.Run(cmd, 0, False)

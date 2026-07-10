# Instalacao completa do receptor MLMC (host/VM).
# Uso: duplo clique em INSTALAR.bat
$ErrorActionPreference = 'Stop'

$Dir = $PSScriptRoot
$ConfigPath = Join-Path $Dir 'config.ini'
$Requirements = Join-Path $Dir 'requirements-udp-audio.txt'
$ServerPy = Join-Path $Dir 'udp_audio_server.py'
$AutostartPs1 = Join-Path $Dir 'install-autostart.ps1'

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host ">> $Text" -ForegroundColor Cyan
}

function Write-Config([int]$Device, [string]$DeviceName) {
    $safeName = ($DeviceName -replace '"', "'")
    @"
# Gerado por INSTALAR.bat
device=$Device
device_name=$safeName
port=9000
"@ | Set-Content -Path $ConfigPath -Encoding ASCII
}

Clear-Host
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Moonlight MLMC - Receptor (Host/VM)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Este assistente instala o receptor de microfone UDP (porta 9000)."
Write-Host "Ao final, o receptor inicia automaticamente com o Windows."
Write-Host ""

if (-not (Test-Path $ServerPy)) {
    throw "Arquivo udp_audio_server.py nao encontrado. Extraia o ZIP completo antes de instalar."
}

Write-Step "Verificando Python..."
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host ""
    Write-Host "ERRO: Python nao encontrado." -ForegroundColor Red
    Write-Host "Instale Python 3.10+ em https://www.python.org/downloads/"
    Write-Host "Marque a opcao 'Add python.exe to PATH' no instalador."
    Read-Host "Pressione Enter para sair"
    exit 1
}
Write-Host "OK: $($python.Source)"

Write-Step "Instalando dependencias (sounddevice, numpy)..."
python -m pip install --upgrade pip --quiet
python -m pip install -r $Requirements
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao instalar dependencias Python."
}
Write-Host "OK"

Write-Step "Detectando dispositivo de audio de saida..."
$pickPy = Join-Path $Dir '_pick_device.py'
@'
import sys
import sounddevice as sd

preferred = ("cable input", "vb-audio", "virtual cable", "cable", "voicemeeter")
outputs = []
for i, dev in enumerate(sd.query_devices()):
    if dev.get("max_output_channels", 0) > 0:
        outputs.append((i, dev["name"]))

if not outputs:
    print("ERROR:no_output_devices", file=sys.stderr)
    sys.exit(2)

def rank(name: str) -> tuple:
    n = name.lower()
    for idx, token in enumerate(preferred):
        if token in n:
            return (0, idx, n)
    return (1, 999, n)

outputs.sort(key=lambda item: (rank(item[1]), item[0]))
print(outputs[0][0])
print(outputs[0][1])
'@ | Set-Content -Path $pickPy -Encoding UTF8

$pickResult = python $pickPy
if ($LASTEXITCODE -ne 0 -or -not $pickResult) {
    Remove-Item $pickPy -Force -ErrorAction SilentlyContinue
    throw "Nao foi possivel listar dispositivos de audio."
}

$lines = $pickResult -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
$autoDevice = [int]$lines[0]
$autoName = $lines[1]

$listPy = Join-Path $Dir '_list_devices.py'
@"
import sounddevice as sd
suggest = $autoDevice
for i, dev in enumerate(sd.query_devices()):
    if dev.get("max_output_channels", 0) > 0:
        mark = " <-- sugerido" if i == suggest else ""
        print(f"  [{i}] {dev['name']}{mark}")
"@ | Set-Content -Path $listPy -Encoding UTF8

Write-Host ""
Write-Host "Dispositivos de saida disponiveis:"
Write-Host "-----------------------------------"
python $listPy
Remove-Item $pickPy, $listPy -Force -ErrorAction SilentlyContinue

Write-Host ""
$useAuto = Read-Host "Usar dispositivo sugerido [$autoDevice] $autoName? (S/n)"
if ($useAuto -eq '' -or $useAuto -eq 'S' -or $useAuto -eq 's') {
    $device = $autoDevice
    $deviceName = $autoName
} else {
    $typed = Read-Host "Digite o numero do dispositivo"
    if ($typed -notmatch '^\d+$') {
        throw "Numero invalido."
    }
    $device = [int]$typed
    $deviceName = "manual"
}

Write-Config -Device $device -DeviceName $deviceName
Write-Host "Config salva em config.ini (device=$device)"

Write-Step "Configurando inicializacao automatica com o Windows..."
if (-not (Test-Path $AutostartPs1)) {
    throw "install-autostart.ps1 nao encontrado."
}
& $AutostartPs1

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Instalacao concluida!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "O receptor vai iniciar sozinho ~10 segundos apos o login (Agendador de Tarefas)."
Write-Host ""
Write-Host "  Testar agora (opcional) : INICIAR.bat"
Write-Host "  Remover do boot         : REMOVER-AUTOSTART.bat"
Write-Host "  Log do servidor         : udp_audio_server.log"
Write-Host ""
Write-Host "No PC cliente (Moonlight): Settings > Audio > ativar microfone UDP (porta 9000)"
Write-Host "Firewall desta maquina  : liberar entrada UDP porta 9000"
Write-Host ""
Read-Host "Pressione Enter para fechar"

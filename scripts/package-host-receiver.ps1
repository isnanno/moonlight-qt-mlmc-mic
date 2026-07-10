# Empacota o receptor MLMC (host/VM) para distribuição no release GitHub.
param(
    [string]$Version = "v6.1.0-mlmc"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$staging = Join-Path $root "build\host-receiver-package"
$zip = Join-Path $root "build\Moonlight-qt-mlmc-host-receiver-$Version-win.zip"

$coreFiles = @(
    "udp_audio_server.py",
    "requirements-udp-audio.txt"
)

$userFiles = @(
    "INSTALAR.bat",
    "INICIAR.bat",
    "REMOVER-AUTOSTART.bat",
    "LEIA-ME.md",
    "setup.ps1",
    "install-autostart.ps1",
    "config.ini.example"
)

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null

foreach ($name in $coreFiles) {
    Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $staging $name)
}

foreach ($name in $userFiles) {
    Copy-Item (Join-Path $PSScriptRoot "host-receiver\$name") (Join-Path $staging $name)
}

if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$staging\*" -DestinationPath $zip -CompressionLevel Optimal

Write-Host ""
Write-Host "Pacote host pronto:"
Write-Host "  $zip"
Write-Host ""

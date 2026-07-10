# Baixa dependências com os commits exatos da tag v6.1.0 (para ZIP sem .git).
# Uso: powershell -ExecutionPolicy Bypass -File scripts\fetch-deps.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Ensure-Checkout {
    param(
        [string]$Path,
        [string]$Url,
        [string]$Sha,
        [string]$Marker
    )

    if (Test-Path $Marker) {
        Write-Host "[OK] $Path"
        return
    }

    Write-Host "[FETCH] $Url @ $Sha -> $Path"
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }

    git clone $Url $Path
    Push-Location $Path
    git checkout $Sha
    if (Test-Path ".gitmodules") {
        git submodule update --init --recursive
    }
    Pop-Location
}

# Commits da tag moonlight-qt v6.1.0
Ensure-Checkout "$Root\moonlight-common-c\mc-c-pinned" `
    "https://github.com/moonlight-stream/moonlight-common-c.git" `
    "8599b6042a4ba27749b0f94134dd614b4328a9bc" `
    "$Root\moonlight-common-c\mc-c-pinned\reedsolomon\rs.c"

Ensure-Checkout "$Root\libs" `
    "https://github.com/cgutman/moonlight-qt-prebuilts.git" `
    "a27d6a7995ef504963fa9058c69e6ba1b449cc0f" `
    "$Root\libs\windows\lib\x64\SDL2.dll"

Ensure-Checkout "$Root\qmdnsengine\qmdnsengine" `
    "https://github.com/cgutman/qmdnsengine.git" `
    "b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99" `
    "$Root\qmdnsengine\qmdnsengine\src"

Ensure-Checkout "$Root\soundio\libsoundio" `
    "https://github.com/cgutman/libsoundio.git" `
    "34bbab80bd4034ba5080921b6ba6d61314126310" `
    "$Root\soundio\libsoundio\src\soundio.c"

Ensure-Checkout "$Root\h264bitstream\h264bitstream" `
    "https://github.com/aizvorski/h264bitstream.git" `
    "34f3c58afa3c47b6cf0a49308a68cbf89c5e0bff" `
    "$Root\h264bitstream\h264bitstream\h264_stream.h"

Ensure-Checkout "$Root\app\SDL_GameControllerDB" `
    "https://github.com/gabomdq/SDL_GameControllerDB.git" `
    "e5a5fa2ac6e645d72c619ea99520a3a4586ee005" `
    "$Root\app\SDL_GameControllerDB\gamecontrollerdb.txt"

Write-Host ""
Write-Host "Dependências prontas. Compile com: scripts\build-debug-local.bat"

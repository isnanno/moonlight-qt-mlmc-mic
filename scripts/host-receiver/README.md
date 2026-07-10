# Receptor MLMC — Host / VM (Windows)

Pacote para a máquina que **recebe** o microfone enviado pelo Moonlight modificado (protocolo **MLMC**, UDP porta **9000**).

Modificação do cliente Moonlight por **Nanno** · [moonlight-qt-mlmc-mic](https://github.com/isnanno/moonlight-qt-mlmc-mic)

---

## Conteúdo

| Arquivo | Função |
|---------|--------|
| `udp_audio_server.py` | Receptor UDP → reprodução via sounddevice |
| `requirements-udp-audio.txt` | Dependências Python |
| `install-deps.bat` | Instala dependências (`pip install`) |
| `list-devices.bat` | Lista dispositivos de áudio de saída |
| `udp_audio_start.bat` | Inicia com console + log |
| `udp_audio_start.vbs` | Inicia em segundo plano (`pythonw`) |
| `install-autostart.bat` | Cria atalho na pasta Inicializar do Windows |
| `uninstall-autostart.bat` | Remove o atalho de autostart |

---

## Instalação rápida

1. **Python 3.10+** instalado com **Add to PATH**  
   https://www.python.org/downloads/

2. Execute **`install-deps.bat`**

3. Execute **`list-devices.bat`** e anote o índice do dispositivo de saída (ex.: VB-Cable Virtual Audio)

4. Edite o índice em:
   - `udp_audio_start.bat` → variável `DEVICE`
   - `udp_audio_start.vbs` → variável `deviceIndex`

5. Teste com **`udp_audio_start.bat`** (janela visível, log em `udp_audio_server.log`)

6. Para iniciar com o Windows: **`install-autostart.bat`**

---

## Firewall

Libere **entrada UDP na porta 9000** nesta máquina (VM/host).

---

## Cliente Moonlight

No PC cliente, use o [Moonlight portátil](https://github.com/isnanno/moonlight-qt-mlmc-mic/releases) e ative:

**Settings → Audio → Send microphone to host via parallel UDP channel (port 9000)**

---

## Logs

`udp_audio_server.log` na mesma pasta dos scripts.

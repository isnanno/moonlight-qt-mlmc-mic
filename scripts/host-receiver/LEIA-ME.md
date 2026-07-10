# Receptor MLMC — Host / VM (Windows)

Pacote para a máquina que **recebe** o microfone do Moonlight modificado (UDP porta **9000**).

Modificação do cliente por **Nanno** · [moonlight-qt-mlmc-mic](https://github.com/isnanno/moonlight-qt-mlmc-mic)

---

## Em 2 passos (plug and play)

### Pré-requisito (só uma vez no PC)

Instale **Python 3.10+** com a opção **"Add python.exe to PATH"**:  
https://www.python.org/downloads/

### Na VM / host

1. Baixe e extraia o ZIP **host-receiver** do [release](https://github.com/isnanno/moonlight-qt-mlmc-mic/releases)
2. Dê duplo clique em **`INSTALAR.bat`**

Pronto. O assistente instala dependências, detecta o VB-Cable (ou similar), salva `config.ini` e cria uma **tarefa no Agendador de Tarefas** (inicia 10 s após o login).

> A pasta **Inicializar** não executa `.vbs` no boot — o autostart usa o Agendador de Tarefas.

---

## Arquivos que você usa

| Arquivo | Quando usar |
|---------|-------------|
| **`INSTALAR.bat`** | Primeira vez (ou reinstalar) |
| **`INICIAR.bat`** | Testar manualmente com janela de log |
| **`REMOVER-AUTOSTART.bat`** | Parar de iniciar com o Windows |

Os demais arquivos (`.py`, `.ps1`) são internos — não precisa abrir.

---

## No PC cliente (Moonlight)

1. Baixe o ZIP **portable** do [release](https://github.com/isnanno/moonlight-qt-mlmc-mic/releases)
2. Execute `Moonlight.exe`
3. **Settings → Audio** → ative **microfone UDP (porta 9000)**
4. Inicie o stream

---

## Firewall

Libere **entrada UDP na porta 9000** nesta máquina (VM/host).

---

## Problemas?

| Sintoma | O que verificar |
|---------|-----------------|
| Não inicia no boot | `udp_audio_server.log` + Agendador de Tarefas → **Moonlight MLMC UDP Audio** |
| Não recebe áudio | `udp_audio_server.log` + firewall UDP 9000 |
| Áudio no dispositivo errado | Rode `INSTALAR.bat` de novo e escolha outro índice |
| Python não encontrado | Reinstale Python marcando **Add to PATH** |

---

## Logs

- `udp_audio_server.log` — servidor de áudio
- `config.ini` — dispositivo de saída escolhido (gerado pelo instalador)

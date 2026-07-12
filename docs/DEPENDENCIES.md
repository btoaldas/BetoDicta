# Componentes de terceros y sus actualizaciones

BetoDicta no tiene librerías de terceros dentro del binario Swift, pero **sí usa
motores externos** compilados aparte (y un adaptador para pausar multimedia):

| Componente | Repo | Para qué | Local |
|---|---|---|---|
| **transcribe.cpp** | [handy-computer/transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) | Streaming local en vivo (Voxtral Realtime / Nemotron) → `beto-stream` | `~/transcribe.cpp` |
| **whisper.cpp** | [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp) | Whisper local (`whisper-cli`, `whisper-server`) | `~/whisper.cpp` |
| **llama.cpp** | [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) | Voxtral Mini 3B local (`llama-server`) | `~/llama.cpp-static` |
| **mediaremote-adapter** | [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3) | Pausar/reanudar música y video al dictar | embarcado |

## Avisar de actualizaciones (sin romper nada)

Actualizar un motor de terceros puede **romper la build o el runtime**, así que
**no se auto-actualiza**. Para saber si hay algo nuevo:

```bash
scripts/check-deps.sh
```

Hace `git fetch` en los repos locales y consulta la API pública de GitHub. Reporta
cuántos commits nuevos hay y el último release de cada componente — **solo informa**.
Si decides actualizar uno: entra a su carpeta, `git pull`, recompila el binario,
cópialo al bundle (`make bundle`) y **prueba de punta a punta** antes de publicar.

El manifiesto de componentes está en [`scripts/deps.tsv`](../scripts/deps.tsv) (agrega
filas ahí si sumas un motor nuevo).

## Que avise SOLO (para no olvidarse)

Hay tres formas, y conviene tener la automática puesta:

1. **A mano**, al empezar a trabajar: `scripts/check-deps.sh`.
2. **Automática (recomendada)** — un LaunchAgent que revisa **al iniciar sesión y cada lunes 10:00**, y si hay novedades lanza una **notificación de macOS**:
   ```bash
   scripts/install-checkdeps-agent.sh            # activar
   scripts/install-checkdeps-agent.sh uninstall  # quitar
   ```
   Log en `~/Library/Logs/betodicta-checkdeps.log`. Nunca actualiza solo.
3. **En cada release** — `scripts/release.sh` corre el checker como **recordatorio** (no bloquea) antes de publicar, para que no se te pase que hay motores nuevos.

> Todo esto solo LEE (git fetch + API pública de GitHub) y avisa. Actualizar un
> motor es siempre decisión manual + recompilar + probar de punta a punta.

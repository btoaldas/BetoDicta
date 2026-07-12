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

> Se puede correr al empezar a trabajar en BetoDicta, o programarlo con `launchd`/`cron`.
> No instala ni modifica nada; solo lee.

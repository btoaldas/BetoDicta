# 🎙 BetoDicta

Dictado por voz para macOS que **abraza el notch**: pulsa una tecla, habla, y el texto aparece EN VIVO junto al notch de tu Mac mientras las barras laten con tu voz. Pulsa de nuevo y el texto se pega donde estaba tu cursor.

## 🌐 Página oficial

**[betodicta.eztic.ec](https://betodicta.eztic.ec/)** — todo sobre la app, motores y guía de instalación.

## 📖 Manual de usuario

**[Manual completo](docs/MANUAL.md)** — instalación, cada pestaña, cada motor, cada ajuste, con capturas.

## ⬇️ Descarga

**[Descargar BetoDicta (DMG) — última versión](https://github.com/btoaldas/BetoDicta/releases/latest)**

Arrastra a Aplicaciones. Requiere macOS 14+ y Apple Silicon.

**Primera apertura** (macOS dirá "Apple no pudo verificar…" porque la app es open source y no viene de la App Store): pulsa "Listo" → **Ajustes del Sistema → Privacidad y seguridad** → baja hasta "Seguridad" → **"Abrir de todos modos"**. Es una sola vez.

![BetoDicta en acción — panel junto al notch con latido de voz, tecla fn y texto en vivo](docs/screenshot.png)

Hecho en Ecuador 🇪🇨 para el español latino — nació porque los dictados comerciales no entendían palabras como *Quipux*, *DGTIC* o *SENESCYT*.

## Características

- **Texto en vivo 100% LOCAL**: Voxtral Realtime 4B o Nemotron 3.5 Streaming (motor [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)) — ves lo que dices mientras lo dices, sin internet
- **Texto en vivo en la nube**: streaming con ElevenLabs Scribe v2 Realtime
- **Failover multi-motor**: cascada arrastrable ElevenLabs → Voxtral → Whisper → Groq → Nemotron → Canary; si uno falla, salta al siguiente solo
- **Modelos locales descargables desde la app**: Whisper (tiny→large-v3), Voxtral Mini 3B y Realtime 4B, Nemotron 3.5, Canary 1B Flash
- **Panel abraza-notch**: latido de voz a la izquierda del notch, tecla a la derecha, teleprompter de una línea debajo — negro puro, como si fuera parte del hardware
- **Tecla `fn`** (o F1–F12, configurable) — toque limpio para empezar/terminar, las combinaciones fn+otra-tecla no lo disparan
- **Keyterms**: tu vocabulario personal viaja al modelo — nombres propios y términos técnicos salen bien a la primera
- **Reemplazos**: correcciones automáticas post-transcripción (palabra completa, sin distinguir mayúsculas)
- **Caja negra**: cada dictado guarda audio y texto en `historial/año/mes/día/` — el audio se escribe a disco EN VIVO chunk a chunk; un crash no te roba ni un segundo
- **Pausa real de multimedia**: al dictar pausa lo que suene (Edge, Chrome, Music, Spotify, YouTube…) y lo reanuda al terminar, además de bajar el volumen; usa el estado real de reproducción, sin bug de toggle
- **Guardián del silencio**: si te olvidas la tecla abierta, se cierra solo tras N segundos sin voz (no le regalas plata a la nube)
- **Odómetro**: minutos dictados por día/semana/mes/año y costo estimado, en el menú
- **Copiar último dictado**: rescate en un clic desde el menú

## Requisitos

- macOS 14+ (Apple Silicon)
- Xcode (para compilar)
- Una API key de [ElevenLabs](https://elevenlabs.io) (Scribe se cobra por hora de audio: ~$0.22–0.39/h)

## Instalación

```bash
git clone https://github.com/btoaldas/BetoDicta.git
cd BetoDicta
make install       # compila y copia a /Applications
open -a BetoDicta
```

Tu API key, por cualquiera de estas vías:

```bash
mkdir -p ~/.betodicta
echo 'ELEVENLABS_API_KEY=tu_key_aqui' > ~/.betodicta/.env
```

o exporta la variable de entorno `ELEVENLABS_API_KEY`.

### Permisos de macOS

BetoDicta necesita **Micrófono**, **Monitorización de entrada** (para la tecla `fn`) y **Accesibilidad** (para pegar el texto). macOS los pedirá al primer uso.

### Firma de código (opcional pero recomendado)

macOS identifica cada app por su firma. Con firma **ad-hoc** (por defecto), cada `make install` genera una firma distinta y macOS te vuelve a pedir los permisos. Para que **los permisos se conserven entre recompilaciones**, crea tu propio certificado — una sola vez:

```bash
./scripts/crear-certificado.sh
```

Genera un certificado personal `BetoDicta Self Signed` en **tu** llavero. El `make install` lo detecta y firma con él automáticamente (si no existe, cae a ad-hoc sin fallar).

**¿Por qué no viene un certificado en el repo?** Porque un certificado de firma es una **identidad personal**, como tu firma o la llave de tu casa: compartir su clave privada dejaría que cualquiera suplante tu app. Por eso cada quien crea el suyo y la clave privada nunca sale de tu Mac. No es un secreto tan crítico como una API key, pero la buena práctica es que sea tuyo e intransferible.

## Configuración

Todo vive en `~/.betodicta/` (editable desde el menú 🎙):

| Archivo | Qué es |
|---|---|
| `config.json` | tecla, modelo, silencio_max_seg, sonidos, esc_cancela, atenuar_multimedia, silenciar_ademas, post_proceso, prompt_pulido, panel_visible, modo_desarrollo… |
| `keyterms.txt` | Tu vocabulario, una palabra por línea (streaming usa las primeras 50) |
| `reemplazos.json` | `[{"original": "variante1, variante2", "replacement": "Palabra"}]` |
| `historial/` | Tus dictados: `.wav` + `.txt` por año/mes/día |
| `uso.jsonl` | El odómetro |

Modelos: `scribe_v2_realtime` (texto en vivo) · `scribe_v2` · `scribe_v1` (por lotes, más barato).

## Entorno de desarrollo

- **macOS 14+** en Apple Silicon · **Xcode 26+** (Swift 6) · sin dependencias externas: Swift puro + AppKit/AVFoundation
- `make install` compila (Swift Package Manager) y arma el bundle firmado con certificado propio en /Applications
- Código modular en `Sources/BetoDicta/` (Config, Recorder, HistoryWriter, MediaControl, clientes Scribe, panel, AppDelegate…)
- Copia `.env.example`, `config.example.json`, `keyterms.example.txt` y `reemplazos.example.json` a `~/.betodicta/` como punto de partida
- Este entorno se actualiza con el proyecto: si algo no compila en una versión nueva de Xcode, abre un issue

## Privacidad y seguridad de datos

- **Tu voz solo viaja a ElevenLabs** (cifrada: HTTPS/WSS a `api.elevenlabs.io`) — no hay analítica, ni telemetría, ni terceros
- **Tu API key jamás se escribe en logs** ni en el código — vive en tu `~/.betodicta/.env` (bloqueado por `.gitignore`)
- **Tus dictados nunca salen de tu Mac**: `historial/` y `uso.jsonl` son archivos locales tuyos; la carpeta `~/.betodicta` se recomienda con permisos `700` (`chmod 700 ~/.betodicta`)
- El portapapeles se restaura tras cada pegado — lo que tenías copiado no se pierde

## Hoja de ruta

- [ ] Failover multi-proveedor: ElevenLabs → Groq → Whisper local (¡gratis y sin internet!)
- [ ] UI de configuración (sin editar JSON)
- [ ] Re-transcribir desde el historial

## Créditos

Creado por **Alberto Aldás** ([@btoaldas](https://github.com/btoaldas)) en compañía de **Claude** (Anthropic) — programado a pura voz, dictándole a las mismas herramientas que lo inspiraron.

La pausa de multimedia usa [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) de Jonas van den Berg (BSD-3-Clause).

Inspirado en el gran corazón open source de [Handy](https://github.com/cjpais/Handy) de **@cjpais** — si prefieres dictado 100% local y gratuito, empieza por ahí.

## Licencia

[GPL-3.0](LICENSE) — libre para siempre: cualquiera puede usarlo, estudiarlo y mejorarlo, pero nadie puede convertirlo en un producto cerrado. Las mejoras se quedan en la comunidad.

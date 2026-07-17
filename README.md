# 🎙 BetoDicta

Dictado por voz para macOS que **abraza el notch**: pulsa una tecla, habla, y el texto aparece EN VIVO junto al notch de tu Mac mientras las barras laten con tu voz. Pulsa de nuevo y el texto se pega donde estaba tu cursor.

## 🌐 Página oficial

**[betodicta.eztic.ec](https://betodicta.eztic.ec/)** — todo sobre la app, motores y guía de instalación.

## 📖 Manual de usuario

**[Manual completo](docs/MANUAL.md)** — instalación, cada pestaña, cada motor, cada ajuste, con capturas.

## ⬇️ Descarga

**[Descargar BetoDicta (DMG) — última versión](https://github.com/btoaldas/BetoDicta/releases/latest)**

Arrastra a Aplicaciones. Requiere macOS 14+ y Apple Silicon.

### O con Homebrew

```bash
brew install --cask btoaldas/tap/betodicta
# firma propia: para saltar el aviso de Gatekeeper
brew install --cask --no-quarantine btoaldas/tap/betodicta
```

Instala siempre el **último release**. (La app también se actualiza sola desde dentro.)

**Primera apertura** (macOS dirá "Apple no pudo verificar…" porque la app es open source y no viene de la App Store): pulsa "Listo" → **Ajustes del Sistema → Privacidad y seguridad** → baja hasta "Seguridad" → **"Abrir de todos modos"**. Es una sola vez.

![BetoDicta en acción — panel junto al notch con latido de voz, tecla fn y texto en vivo](docs/screenshot.png)

Hecho en Ecuador 🇪🇨 para el español latino — nació porque los dictados comerciales no entendían palabras como *Quipux*, *DGTIC* o *SENESCYT*.

## Características

- **Modos — entiende la intención y decide qué hacer**: además de **Dictado**, usa **Correo, Oficio, Tarea, Nota, Traducir, Resumir, Asistente, Agente, Buscar** o **Aplicación**, cada uno con comportamiento/color propios. El modo Aplicación hace un inventario de las apps reales del Mac: *"modo abrir aplicación Word, borrador del informe"* abre Word y coloca el texto (sin enviarlo). Entiende comandos explícitos y pedidos naturales, incluso cadenas de **1 a N etapas** (*"resume, traduce al quichua y envía por correo y WhatsApp"*) con idioma y destinatario. Ante una propuesta, el notch se expande: **fn una vez confirma; X continúa el dictado normal**. Reglas locales → embeddings con margen → IA opcional como último árbitro, siempre con degradación suave y sin ejecutar acciones ambiguas. También admite pausa en vivo, app/sitio, un solo uso y modos propios.
- **Texto en vivo 100% LOCAL**: Voxtral Realtime 4B o Nemotron 3.5 Streaming (motor [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)) — ves lo que dices mientras lo dices, sin internet. Los motores locales (whisper.cpp, llama.cpp, transcribe.cpp) se mantienen **al día** con sus proyectos base en cada versión
- **Preview universal en el notch**: en macOS 26, el dictado nativo de Apple puede mostrar **en vivo y de forma local** lo que vas diciendo aunque el motor real (por ejemplo Groq) trabaje por lotes. Es solo una vista previa: al soltar `fn`, tu cascada elegida hace la transcripción definitiva
- **Texto en vivo en la nube**: streaming por WebSocket con ElevenLabs Scribe v2 Realtime y (opt-in) **Deepgram, Soniox, AssemblyAI, Speechmatics, Gladia** — marcados con etiqueta **"EN VIVO"** en la lista de motores
- **Muchos motores de transcripción, varios GRATIS y otros premium**: nube compatible-OpenAI (ElevenLabs, Groq Whisper gratis, OpenAI, Mistral Voxtral, Fireworks) · API propia (Hugging Face gratis, Deepgram, AssemblyAI, Gladia, Speechmatics, Cloudflare, **Soniox**, **Azure con es-EC de Ecuador**) · locales con detección inteligente (Ollama/LM Studio solo si tienen whisper). Precios por hora **se actualizan solos** desde LiteLLM
- **Failover multi-motor**: cascada arrastrable; si uno falla, salta al siguiente solo. Un gateway propio también puede transcribir (no solo pulir)
- **Modelos locales descargables desde la app**: Whisper (tiny→large-v3), Voxtral Mini 3B y Realtime 4B, Nemotron 3.5, Canary 1B Flash
- **Tu propia voz, local y portable**: entrena/importa clones XTTS y crea desde un XTTS ya bueno una variante **Piper/ONNX rápida**. BetoDicta conserva ambas en la misma persona (**Calidad** / **⚡ Rápida**), valida inteligibilidad antes de activar y exporta un paquete que lleva las dos. El trabajo es reanudable tras cerrar la app o apagar la Mac: conserva el plan, guarda un seguro rodante cada 200 pasos y continúa también la validación
- **Panel abraza-notch**: latido de voz a la izquierda del notch, tecla a la derecha, teleprompter de una línea debajo — negro puro, como si fuera parte del hardware
- **Tecla `fn`** (o F1–F12, configurable) — toque limpio para empezar/terminar, las combinaciones fn+otra-tecla no lo disparan; opcionalmente exige **doble pulsación para iniciar** y una para detener
- **Keyterms**: tu vocabulario personal viaja al modelo — nombres propios y términos técnicos salen bien a la primera
- **Reemplazos**: correcciones automáticas post-transcripción (palabra completa, sin distinguir mayúsculas)
- **Pulido con cualquier IA + elige el modelo**: pule/traduce con Groq, OpenAI, Mistral, OpenRouter, DeepSeek, xAI, **Anthropic (Claude)**, **Gemini (Google)** o tu gateway propio — o **local** (LM Studio/Ollama, sin que nada salga de tu Mac). Eliges el **modelo** de cada proveedor al vuelo y, si publica precios (OpenRouter), ves el **costo por modelo** (`$in/$out` o `gratis`). Aviso de privacidad al usar nube/terceros
- **Push-to-talk opcional**: graba mientras mantienes la tecla y termina al soltarla (o el modo toque de siempre)
- **Caja negra**: cada dictado guarda audio y texto en `historial/año/mes/día/` — el audio se escribe a disco EN VIVO chunk a chunk; un crash no te roba ni un segundo
- **Pausa real de multimedia**: al dictar pausa lo que suene (Edge, Chrome, Music, Spotify, YouTube…) y lo reanuda al terminar, además de bajar el volumen; usa el estado real de reproducción, sin bug de toggle
- **Guardián del silencio**: si te olvidas la tecla abierta, se cierra solo tras N segundos sin voz (no le regalas plata a la nube)
- **Odómetro + gasto de pulido**: minutos dictados por día/semana/mes/año y costo estimado, más KPIs de gasto de pulido con IA (tokens→costo) con gráfica, en Estadísticas
- **Búsqueda por significado en el historial** (semántica, opt-in): encuentra dictados por IDEA, no por palabra exacta, con embeddings — motor a elegir (Ollama local gratis, OpenAI, Gemini, Mistral)
- **Salvaguarda anti-inyección** (opt-in): si un gateway de terceros devuelve texto anómalo (comandos shell que no dictaste), pega tu dictado original
- **Ayuda por proveedor**: cada IA de nube (chat y voz) trae un icono de ayuda con explicación instantánea y un enlace **"Conseguir clave"** que abre la página oficial de su API key
- **Copiar último dictado**: rescate en un clic desde el menú
- **Actualizador estable/beta**: canal automático, solo estable o estable+beta; consulta al abrir y periódicamente (1–24 h), permite comprobar a mano y usa failover cuando GitHub excluye las prereleases de `latest`

## Requisitos

- macOS 14+ (Apple Silicon)
- **Nada más para empezar**: los motores **locales** (Whisper, Voxtral, Nemotron, Canary) corren 100% offline, gratis y **sin ninguna API key**
- *(Opcional)* la API key de un servicio de **nube** si quieres máxima calidad o texto en vivo — varios con capa **GRATIS** (Groq Whisper 2000/día, Hugging Face…). El asistente te lo pone fácil y cada proveedor tiene un botón "Conseguir clave"
- *(Solo para compilar desde el código)* Xcode 26+

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
- Los usuarios normales NO tocan archivos: el asistente de configuración (y Ajustes → Modelos) guarda las claves y ajustes solos en `~/.betodicta/`. Los `*.example` (`.env.example`, `config.example.json`, `keyterms.example.txt`, `reemplazos.example.json`) son solo **referencia del formato** para desarrolladores o para pre-cargar valores a mano — opcionales
- Este entorno se actualiza con el proyecto: si algo no compila en una versión nueva de Xcode, abre un issue

## Privacidad y seguridad de datos

- **Tu voz solo viaja al motor que TÚ elijas** (cifrada: HTTPS/WSS) — o a **ningún lado** si usas un motor local (Whisper/Voxtral/Nemotron/Canary, 100% offline). No hay analítica, ni telemetría, ni terceros ocultos
- **Tu API key jamás se escribe en logs** ni en el código — vive en tu `~/.betodicta/.env` (bloqueado por `.gitignore`)
- **Tus dictados nunca salen de tu Mac**: `historial/` y `uso.jsonl` son archivos locales tuyos; la carpeta `~/.betodicta` queda en `700` y los archivos con secretos (`.env`, gateways) en `600`
- **Actualizaciones verificadas por firma**: antes de instalar una actualización, la app comprueba que el nuevo bundle esté firmado con el **mismo certificado** que tu copia — un DMG manipulado o firmado por otro se rechaza (la clave privada del certificado nunca sale del Mac del autor)
- **Gateways propios**: la API key no se envía si el gateway usa `http://` sin cifrar
- El portapapeles se restaura tras cada pegado — lo que tenías copiado no se pierde
- Cada release pasa por **revisión de código y de seguridad** antes de publicarse

## Hoja de ruta

Lo que sigue (pendiente e ideas — ¿te falta algo? [abre un issue](https://github.com/btoaldas/BetoDicta/issues/new)):

- [ ] **Google Cloud Speech (Chirp)** — español LATAM tope de gama (requiere autenticación con cuenta de servicio GCP)
- [ ] **Azure AI Speech EN VIVO** — hoy va por lotes; su tiempo real es por SDK
- [ ] Afinar el streaming en vivo de cada motor de nube (Deepgram, AssemblyAI, Gladia…) con pruebas reales de punta a punta
- [ ] **Traducción en vivo** mientras dictas
- [ ] Más idiomas y mejor multilingüe según lo que pidan
- [ ] Dictado por comandos de voz (puntuación y formato hablados)

## Créditos

Creado por **Alberto Aldás** ([@btoaldas](https://github.com/btoaldas)) en compañía de **Claude** (Anthropic) — programado a pura voz, dictándole a las mismas herramientas que lo inspiraron. Inspirado en el gran corazón open source de [Handy](https://github.com/cjpais/Handy) de **@cjpais**.

**Motores y librerías de código abierto:**
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) y [llama.cpp](https://github.com/ggml-org/llama.cpp) (ggml-org) — Whisper y Voxtral locales
- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) — streaming local en vivo (Voxtral Realtime / Nemotron)
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) de Jonas van den Berg (BSD-3-Clause) — pausa de multimedia
- [Ollama](https://ollama.com) y [LM Studio](https://lmstudio.ai) — IA local (chat, embeddings, whisper)

**Datos y fuentes:** [LiteLLM](https://github.com/BerriAI/litellm) (precios de modelos que se actualizan solos) · modelos ASR: Whisper de OpenAI ([ggml de ggerganov](https://huggingface.co/ggerganov/whisper.cpp)), Voxtral de Mistral ([GGUF de ggml-org](https://huggingface.co/ggml-org/Voxtral-Mini-3B-2507-GGUF)), Nemotron y Canary de NVIDIA ([GGUF de handy-computer](https://huggingface.co/handy-computer)) · [bge-m3](https://huggingface.co/BAAI/bge-m3) (BAAI, búsqueda semántica).

**Servicios de IA que puedes conectar** (opcionales, muchos con capa gratis) — transcripción: ElevenLabs, Groq, OpenAI, Mistral, Fireworks, Hugging Face, Deepgram, AssemblyAI, Gladia, Speechmatics, Cloudflare, Soniox, Azure · pulido/traducción: OpenRouter, Anthropic, Google Gemini, DeepSeek, xAI, Cerebras, GitHub Models, NVIDIA, Together, Novita, Z.ai, SiliconFlow. Cada uno con su enlace y botón "Conseguir clave" dentro de la app (Créditos y Modelos).

## Licencia

[GPL-3.0](LICENSE) — libre para siempre: cualquiera puede usarlo, estudiarlo y mejorarlo, pero nadie puede convertirlo en un producto cerrado. Las mejoras se quedan en la comunidad.

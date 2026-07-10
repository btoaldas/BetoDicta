# 🎙 BetoDicta

Dictado por voz para macOS que **abraza el notch**: pulsa una tecla, habla, y el texto aparece EN VIVO junto al notch de tu Mac mientras las barras laten con tu voz. Pulsa de nuevo y el texto se pega donde estaba tu cursor.

Hecho en Ecuador 🇪🇨 para el español latino — nació porque los dictados comerciales no entendían palabras como *Quipux*, *DGTIC* o *SENESCYT*.

## Características

- **Texto en vivo**: streaming con ElevenLabs Scribe v2 Realtime — ves lo que dices mientras lo dices
- **Panel abraza-notch**: latido de voz a la izquierda del notch, tecla a la derecha, teleprompter de una línea debajo — negro puro, como si fuera parte del hardware
- **Tecla `fn`** (o F1–F12, configurable) — toque limpio para empezar/terminar, las combinaciones fn+otra-tecla no lo disparan
- **Keyterms**: tu vocabulario personal viaja al modelo — nombres propios y términos técnicos salen bien a la primera
- **Reemplazos**: correcciones automáticas post-transcripción (palabra completa, sin distinguir mayúsculas)
- **Caja negra**: cada dictado guarda audio y texto en `historial/año/mes/día/` — el audio se escribe a disco EN VIVO chunk a chunk; un crash no te roba ni un segundo
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

BetoDicta necesita **Micrófono** (obvio) y **Accesibilidad** (para escuchar la tecla `fn` y pegar el texto). macOS los pedirá al primer uso. Nota: al recompilar desde código, macOS puede "olvidar" los permisos (firma ad-hoc nueva) — quita y vuelve a agregar la app en Configuración → Privacidad y Seguridad.

## Configuración

Todo vive en `~/.betodicta/` (editable desde el menú 🎙):

| Archivo | Qué es |
|---|---|
| `config.json` | `{"tecla": "fn", "modelo": "scribe_v2_realtime", "silencio_max_seg": 120}` |
| `keyterms.txt` | Tu vocabulario, una palabra por línea (streaming usa las primeras 50) |
| `reemplazos.json` | `[{"original": "variante1, variante2", "replacement": "Palabra"}]` |
| `historial/` | Tus dictados: `.wav` + `.txt` por año/mes/día |
| `uso.jsonl` | El odómetro |

Modelos: `scribe_v2_realtime` (texto en vivo) · `scribe_v2` · `scribe_v1` (por lotes, más barato).

## Hoja de ruta

- [ ] Failover multi-proveedor: ElevenLabs → Groq → Whisper local (¡gratis y sin internet!)
- [ ] UI de configuración (sin editar JSON)
- [ ] Re-transcribir desde el historial

## Créditos

Creado por **Alberto Aldás** ([@btoaldas](https://github.com/btoaldas)) en compañía de **Claude** (Anthropic) — programado a pura voz, dictándole a las mismas herramientas que lo inspiraron.

Inspirado en el gran corazón open source de [Handy](https://github.com/cjpais/Handy) de **@cjpais** — si prefieres dictado 100% local y gratuito, empieza por ahí.

## Licencia

[GPL-3.0](LICENSE) — libre para siempre: cualquiera puede usarlo, estudiarlo y mejorarlo, pero nadie puede convertirlo en un producto cerrado. Las mejoras se quedan en la comunidad.

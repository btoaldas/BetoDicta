# 🎙 BetoDicta — Manual de usuario

**Dictado por voz para macOS en español latino — con motores en la nube y 100% locales, failover automático, texto en vivo junto al notch, y una app que aprende tu vocabulario.**

> Página oficial: [betodicta.eztic.ec](https://betodicta.eztic.ec/) · Descargas: [GitHub Releases](https://github.com/btoaldas/BetoDicta/releases/latest) · ¿Problemas? [Reporta un issue](https://github.com/btoaldas/BetoDicta/issues/new)

---

## Índice

1. [Qué es BetoDicta](#1-qué-es-betodicta)
2. [Requisitos](#2-requisitos)
3. [Instalación](#3-instalación)
4. [Tu primer dictado](#4-tu-primer-dictado)
5. [El panel del notch](#5-el-panel-del-notch)
6. [El menú de la barra (y el Dock)](#6-el-menú-de-la-barra-y-el-dock)
7. [La cascada de failover](#7-la-cascada-de-failover)
8. [Los motores, uno por uno](#8-los-motores-uno-por-uno)
9. [Pestaña Modelos (y el precio por modelo)](#9-pestaña-modelos-y-el-precio-por-modelo)
10. [Cambiar de motor al vuelo](#10-cambiar-de-motor-al-vuelo)
11. [Pestaña Ajustes](#11-pestaña-ajustes)
12. [Pestaña Acciones](#12-pestaña-acciones)
13. [Glosario y reemplazos](#13-glosario-y-reemplazos)
14. [Que la app aprenda de ti (aprendizaje)](#14-que-la-app-aprenda-de-ti-aprendizaje)
15. [Corrección por sonido (fonética)](#15-corrección-por-sonido-fonética)
16. [Traducir al dictar](#16-traducir-al-dictar)
17. [Pestaña Historial](#17-pestaña-historial)
18. [Pestaña Transcribir](#18-pestaña-transcribir)
19. [Estadísticas y costo por modelo](#19-estadísticas-y-costo-por-modelo)
20. [Actualizar la app](#20-actualizar-la-app)
21. [Apoya el proyecto](#21-apoya-el-proyecto)
22. [La caja negra: tus datos](#22-la-caja-negra-tus-datos)
23. [Solución de problemas](#23-solución-de-problemas)
24. [Preguntas frecuentes](#24-preguntas-frecuentes)
25. [Voz propia: biblioteca y entrenamiento](#25-voz-propia-biblioteca-y-entrenamiento)

---

## 1. Qué es BetoDicta

BetoDicta convierte tu voz en texto en cualquier aplicación del Mac: pulsas una tecla, hablas, vuelves a pulsar, y el texto aparece donde estaba tu cursor. Fue creada en Ecuador 🇪🇨 para el español latino, porque los dictados comerciales no entendían palabras como *Quipux*, *DGTIC* o *SENESCYT*.

Sus cuatro superpoderes:

- **Texto en vivo**: ves lo que dices mientras lo dices, junto al notch — con la nube (ElevenLabs) o **100% sin internet** (Voxtral Realtime, Nemotron).
- **Failover transparente**: si un motor falla, otro toma el mando solo — nunca pierdes un dictado.
- **Tu vocabulario manda**: tu glosario personal llega a todos los motores, y una capa de reemplazos corrige después.
- **Aprende de ti**: cuando corriges una palabra ahí donde la pegaste, la app aprende la regla sola (Kipux → Quipux) — sin que vuelvas a repetir el trabajo.

## 2. Requisitos

- **macOS 14 o superior**
- **Apple Silicon** (chip M1 en adelante)
- Micrófono (el del Mac sirve perfecto)
- Internet **solo** para: descargar modelos, usar motores de nube y actualizar la app. Dictar con motores locales funciona sin conexión.

## 3. Instalación

Hay dos formas. Cualquiera te deja la app lista; los permisos y ajustes se configuran igual (el [asistente](#31-el-asistente-de-primer-arranque) te guía).

**Opción A — Homebrew** (lo más rápido):
```bash
brew install --cask btoaldas/tap/betodicta
# o, para saltar el aviso de Gatekeeper (firma propia):
brew install --cask --no-quarantine btoaldas/tap/betodicta
```
> **¿Ya tenías BetoDicta instalada a mano?** Si brew se queja con `Error: It seems there is already an App at '/Applications/BetoDicta.app'`, adóptala con `--force` (una sola vez):
> ```bash
> brew install --cask --force btoaldas/tap/betodicta
> ```
> **Gobernanza — siempre la última**: el tap usa `version :latest`, así que `brew install` **siempre baja el último release**. Como `:latest` no "sube" solo, para traer la más nueva por brew usa `brew upgrade --cask --greedy` (o `brew reinstall --cask btoaldas/tap/betodicta`). De todos modos, la app **se actualiza sola desde dentro** (ver §20): te avisa al abrir y, si activas *Autoactualizar*, se instala sola.

**Opción B — Manual (DMG):**

1. Descarga el DMG desde [GitHub Releases](https://github.com/btoaldas/BetoDicta/releases/latest).
2. Abre el DMG y **arrastra BetoDicta.app a la carpeta Aplicaciones**.
3. **Primera apertura** — macOS mostrará *"Apple no pudo verificar que BetoDicta no contenga software malicioso"*. Es normal: la app es open source y no viene de la App Store. Haz esto:
   - Pulsa **"Listo"** (¡no "Mover al basurero"!)
   - Ve a **Ajustes del Sistema → Privacidad y seguridad**, baja hasta la sección **Seguridad**
   - Pulsa **"Abrir de todos modos"** y pon tu contraseña. Es una sola vez.
4. **Permisos** — la app pedirá:
   - **Micrófono**: para escucharte (obvio).
   - **Accesibilidad**: para pegar el texto donde está tu cursor, detectar la tecla de dictado y (si lo activas) aprender de tus correcciones. Ve a Ajustes del Sistema → Privacidad y seguridad → Accesibilidad y activa BetoDicta.
5. Verás el **micrófono en la barra de menú** (arriba a la derecha). Listo.

### 3.1 El asistente de primer arranque

La primera vez que abres BetoDicta aparece un **asistente** que te lleva de la mano por todo en ~1 minuto. Si prefieres verlo otra vez más tarde: Configuración → Créditos → **"Volver a ver el asistente de configuración"**.

![Bienvenida del asistente](img/wizard-bienvenida.png)

Son 8 pasos:

0. **Bienvenida** — qué hace la app y qué vas a configurar.
1. **Permisos** — micrófono y accesibilidad, con **check en vivo**: apenas concedes cada uno, su fila se pone en **verde "Activado"**.

   ![Permisos con check en vivo](img/wizard-permisos.png)

   > La accesibilidad **pide reiniciar** la app para tomar efecto. No te preocupes: el asistente vuelve **exactamente a este paso** y verás los dos permisos en verde ("check activado, check activado"). El botón **"Reiniciar BetoDicta ahora"** lo hace por ti. Solo cuando pulses **Finalizar** al final, el asistente se da por terminado — un reinicio a mitad NO te lo salta.
2. **IA en la nube (opcional)** — conecta un servicio pegando su clave, o déjalo en blanco para quedarte 100% gratis y local. Arriba, un recuadro verde resalta las opciones **GRATIS** para máquinas sin fuerza o sin presupuesto: **Groq Whisper** (2000 transcripciones/día) y **Hugging Face** para voz, y modelos **`:free`** de OpenRouter para pulido — **sin tarjeta**. Por seguridad, si ya tienes una clave guardada **no se muestra**: solo pega una nueva si la quieres cambiar.

   ![IA en la nube — opciones gratis](img/wizard-nube.png)
3. **IA local** — descarga los motores que corren gratis y **sin internet** (Voxtral Realtime, Nemotron, Canary, Whisper, Voxtral Mini). La descarga sigue en **segundo plano** aunque avances o cierres; pulsa **"Usar"** para dejarlo en tu cascada.

   ![Descarga de IA local](img/wizard-local.png)
4. **Orden del failover** — cuál motor va #1, cuál de respaldo. Enciende los que quieras (uno basta) y ordénalos con las flechas. En una instalación nueva te **sugiere una IA local de #1** (funciona sin internet) y ElevenLabs de #2; el botón **"Aplicar sugerencia"** lo hace de un clic.

   ![Orden del failover](img/wizard-failover.png)
5. **Aprendizaje y glosario** — enciende que aprenda de tus correcciones, la corrección por sonido y el pulido con IA; y agrega las primeras palabras de tu glosario (nombres, siglas, términos).
6. **Preferencias** — tecla de dictado, micrófono, sonidos, panel, Esc, multimedia, volumen, Dock, arranque al iniciar sesión y modo desarrollo. Cada opción con su nota de qué hace y para qué.

   ![Preferencias del asistente](img/wizard-preferencias.png)
7. **¡Listo!** — a dictar (y, si te sirve, un cafecito para apoyar el proyecto).

Todo lo que elijas aquí se puede cambiar después en Configuración. Los valores de fábrica ya vienen bien para la mayoría.

## 4. Tu primer dictado

1. Pon el cursor donde quieras escribir (un correo, Word, WhatsApp Web, donde sea).
2. **Pulsa y suelta la tecla `fn`** (la de abajo a la izquierda del teclado).
3. Habla normal. Verás el panel negro junto al notch con barras que laten con tu voz.
4. **Pulsa `fn` otra vez**. El texto se escribe donde estaba tu cursor.

Trucos:
- **Esc cancela** el dictado sin escribir nada.
- Si te olvidas la tecla abierta, el **guardián del silencio** cierra el dictado solo tras un rato sin voz (configurable).
- La tecla se puede cambiar (F1–F12 o combinaciones como ⌘⇧D) en Ajustes.

## 5. El panel del notch

![Panel del notch](img/panel-notch.png)

- **Izquierda**: barras que laten con tu voz — si no laten, el micrófono no te escucha.
- **Derecha**: la tecla de dictado y, encima, **el letrero del motor** que está trabajando en ese momento:
  - **Verde** = texto en vivo (ves lo que dices mientras hablas)
  - **Gris** = el texto llega al soltar la tecla
  - El letrero **rota solo** si el failover cambia de motor a mitad del dictado.
- **Abajo**: el teleprompter — una línea con lo último que dijiste.
- **Clic sobre el letrero del motor** abre el selector rápido de proveedor (ver [sección 10](#10-cambiar-de-motor-al-vuelo)).

> **Ver en vivo lo que dices (💬).** Aunque tu motor no tenga streaming (Groq, Whisper local…), el notch te muestra **lo que vas diciendo mientras hablas**, usando el transcriptor nativo de Apple (macOS 26, local y gratis). Es **solo visual**: al soltar la tecla, la transcripción real la hace tu cascada de modelos como siempre — el preview jamás se pega. Se activa/desactiva en `Ajustes → Ver en vivo lo que dices (notch)`. Si un motor con texto en vivo real está trabajando (ElevenLabs realtime, Whisper local en vivo), ese manda y el preview se aparta solo.

## 6. El menú de la barra (y el Dock)

![Menú de la barra](img/menu-barra.png)

**Clic en el micrófono de la barra de menú** (arriba a la derecha) — es tu centro de accesos directos:

| Opción | Qué hace |
|---|---|
| **BetoDicta vX — fn para dictar** | Recordatorio de tu tecla y versión |
| **Configuración…** (⌘,) | Abre la ventana principal |
| **Proveedor principal ▸** | Cambia el motor #1 con un clic (solo lista los activos, ✓ en el actual) |
| **Editar keyterms** | Abre tu glosario en el editor de texto |
| **Editar reemplazos** | Abre tus reglas de corrección |
| **Copiar último dictado** (⌘C) | El texto del dictado más reciente al portapapeles |
| **Últimos dictados ▸** | Los 5 más recientes — clic en uno y se copia |
| **Exportar dictados de hoy** (⌘E) | Genera un Markdown con todos los dictados del día |
| **Abrir historial** | La carpeta con todos tus audios y textos |
| **Ver registro (log)** (⌘L) | El registro técnico de la app |
| **Modo desarrollo** | Detalle técnico extra en el log |
| **Mostrar en el Dock** | La app también en el Dock |
| **Arrancar al iniciar sesión** | Autoarranque con el Mac |
| **Post-proceso con IA (Groq)** | Interruptor rápido del pulido |
| **Traducir al dictar ▸** | Elige idioma o desactiva |
| **— Uso de dictado —** | Resumen de minutos por proveedor |
| **Salir** (⌘Q) | Cierra BetoDicta |

**En el Dock** (si activaste "Mostrar en el Dock"):
- **Clic izquierdo** en el ícono → abre la Configuración
- **Clic derecho** → el mismo menú completo de la barra

## 7. La cascada de failover

La cascada es la lista ordenada de motores en **Configuración → Modelos**. Reglas:

- **El #1 manda**: cada dictado empieza con él.
- **Si falla, salta al #2, luego al #3…** — automático y transparente: tú sigues hablando.
- **Arrastra las filas** (agarra la manito ☰) para cambiar el orden.
- **El switch** enciende/apaga cada proveedor: los apagados no participan.
- La etiqueta **EN VIVO** marca los motores que muestran texto mientras hablas.

Ejemplos de comportamiento:
- ElevenLabs #1 y se cae tu internet → en 4 segundos el primer motor local en vivo de tu cascada toma el mando **con todo lo que ya hablaste**.
- La red muere a MITAD de un dictado → al soltar, el audio completo se transcribe por la cascada. Nada se pierde.
- Tras un fallo de red, ElevenLabs entra en "cuarentena" 60 segundos (ni se intenta) para no hacerte esperar.

## 8. Los motores, uno por uno

| Motor | Tipo | ¿En vivo? | ¿Necesita? | Notas |
|---|---|---|---|---|
| **ElevenLabs Scribe** | Nube | ✅ | API key ([elevenlabs.io](https://elevenlabs.io)) | La mejor calidad con glosario nativo. De pago (~$0.22–0.39/h de audio) |
| **Apple Speech (nativo)** | Local | ❌ lotes | **macOS 26+** (nada más) | El motor de voz→texto **de la propia Mac**, on-device. **Gratis, sin API key, sin internet.** La 1ª vez baja el modelo del idioma solo. Español nativo muy bueno. Actívalo en la cascada |
| **Voxtral Realtime 4B** | Local | ✅ | Descargar modelo (2.8 GB) | Mistral. Detecta idioma solo, muy bueno con siglas. Gratis y sin internet |
| **Nemotron 3.5 Streaming** | Local | ✅ | Descargar modelo (751 MB) | NVIDIA. Liviano, 40 idiomas, rapidísimo. Gratis y sin internet |
| **Whisper local** | Local | ✅ (pseudo) | Descargar modelo (74 MB–3 GB) | OpenAI open source. Del Tiny al Large v3. Gratis y sin internet |
| **Voxtral Mini 3B** | Local | ❌ lotes | Descargar modelo (3.2 GB) | Entiende contexto, respeta el glosario. Gratis y sin internet |
| **Canary 1B Flash** | Local | ❌ lotes | Descargar modelo (1 GB) | NVIDIA. El más veloz por lotes (93x). Gratis y sin internet |
| **Groq Whisper** | Nube | ❌ lotes | API key ([console.groq.com](https://console.groq.com)) | Whisper en la nube, muy rápido. Capa gratis generosa |
| **OpenAI** | Nube | ❌ lotes | API key ([platform.openai.com](https://platform.openai.com)) | whisper-1 y gpt-4o-transcribe |
| **Mistral (Voxtral nube)** | Nube | ❌ lotes | API key ([console.mistral.ai](https://console.mistral.ai)) | Voxtral sin descargar nada |

**¿Cuál elegir?** Sin gastar un centavo y sin internet: **Voxtral Realtime 4B** de #1 (en vivo, calidad top) con **Whisper local** de respaldo. Si tienes key de ElevenLabs: ponlo de #1 y deja los locales de respaldo.

## 9. Pestaña Modelos (y el precio por modelo)

![Pestaña Modelos](img/modelos.png)

Todo el control de motores vive aquí:

> Los motores locales (whisper.cpp, llama.cpp, transcribe.cpp) se mantienen **al día** con sus proyectos base: cada versión de BetoDicta trae las últimas mejoras de rendimiento y correcciones, sin que tengas que hacer nada ni volver a descargar tus modelos.

**Descargar modelos locales**
- Cada familia tiene su sección: Whisper / Voxtral / Nemotron / Canary.
- Clic en el botón de descarga (⬇) → verás la barra de progreso.
- La descarga **sigue en segundo plano** aunque cambies de pestaña o cierres la ventana.
- El **✕** junto a la barra cancela la descarga.
- Al terminar: botón **"Usar"** → ese modelo queda elegido para su proveedor y el proveedor se activa.
- La etiqueta **EN USO** marca el modelo activo de cada familia; el 🗑 borra el archivo del disco.

**API keys de la nube**
- Sección "Proveedores en la nube": pega tu key (⌘V funciona), pulsa **Guardar** → verás **"Guardado ✓"** y el estado pasa a **"conectado"**.
- Cada proveedor trae un icono **ⓘ** con una explicación (qué es, si es gratis, si va en vivo) que aparece **al instante** al pasar el mouse (o al hacer clic), y un enlace **"Conseguir clave"** que abre la **página oficial** donde sacas tu API key — así no pierdes tiempo buscándola. Lo mismo en *Ajustes → Conectar más IAs* para las IAs de chat.
- El ojito 👁 muestra/oculta la key. Las keys viven **solo en tu Mac** (`~/.betodicta/.env`).
- Elige el modelo de cada proveedor en su selector (por ejemplo, ElevenLabs: `scribe_v2_realtime` para texto en vivo, o `scribe_v2` / `scribe_v1` por lotes).

**Muchos motores de transcripción — varios GRATIS y otros de pago premium**:
- **Nube compatible-OpenAI**: ElevenLabs, **Groq Whisper (gratis, 2000/día)** ⭐, OpenAI, Mistral (Voxtral), **Fireworks (Whisper)**.
- **Nube con API propia** (cada uno con su adaptador): **Hugging Face (Whisper, capa gratuita)** ⭐, **Deepgram (Nova)**, **AssemblyAI (Universal)**, **Gladia (10 h/mes gratis)**, **Speechmatics (480 min/mes gratis)**, **Cloudflare Workers AI (Whisper, 10 000 llamadas/día gratis)**. Cloudflare pide tu **Account ID** además de la key (campo aparte en su tarjeta).
- **De pago, calidad premium**: **Soniox** ⭐ (el mejor valor, ~$0.10/h, multilingüe nativo con excelente español latino y mezcla es/en) y **Azure AI Speech** (único con locale **es-EC de Ecuador**; pide la **región** además de la key). Los mejores si quieres máxima calidad en español.
- **Locales con detección inteligente**: **Ollama** y **LM Studio** aparecen como motor de transcripción **solo si tienen un modelo whisper** cargado. Si no lo tienen, la fila se oculta y el motor queda desactivado — nunca te ofrece algo que no puede escuchar. Para habilitarlo: `ollama pull whisper` (o carga un whisper en LM Studio) y reabre.
- Todos entran en la **cascada de failover** (arrástralos al orden que quieras) y su **precio por hora** ya viene puesto (los gratis en $0), ajustable con **"Poner valor"**. Los precios se **actualizan solos** desde una fuente mantenida (LiteLLM), sin gastar IA — igual que los de pulido.
- **En vivo**: por defecto los motores de nube transcriben por lotes (al soltar la tecla). Los que tienen WebSocket — **Deepgram, Soniox, AssemblyAI, Speechmatics y Gladia** — pueden transcribir **EN VIVO** (ves el texto mientras hablas) si lo activas en *Ajustes → Avanzado → "STT en vivo para la nube"*. En la lista de motores, los que van en vivo llevan una etiqueta **"EN VIVO"** (verde = activo; gris = lo soporta pero falta activarlo).

**El precio es POR MODELO** — cada modelo cuesta distinto, no el proveedor entero:
- Debajo del selector de modelo hay un campo **"Costo $/hora de \<modelo\>"**. Muestra el precio de referencia 2026 del modelo que tengas elegido, y **cambia solo** cuando cambias de modelo en el selector.
- Ejemplos reales: ElevenLabs `scribe_v2_realtime` = **$0.39/h** (en vivo) pero `scribe_v2` por lotes = **$0.22/h**; OpenAI `gpt-4o-transcribe` = **$0.36/h** pero `gpt-4o-mini-transcribe` = **$0.18/h**; Groq `whisper-large-v3-turbo` = **$0.04/h**. Los modelos locales = **$0** (gratis).
- ¿No te cuadra un precio? Escribe el tuyo y pulsa **"Poner valor"** → **"Guardado ✓"**. Ese valor manda para el cálculo de costo del mes. Borra el campo para volver al de referencia.
- El costo del mes (pestaña Estadísticas) usa el precio del **modelo que realmente se usó** en cada dictado — incluso si el failover cambió de modelo a mitad de camino.

## 10. Cambiar de motor al vuelo

Tres formas, de la más rápida a la más completa:

1. **Clic en el letrero del motor** (en el panel del notch, incluso mientras dictas) → eliges de la lista de activos → ese pasa a #1. Si estás dictando, **conmuta EN CALIENTE**: el motor nuevo recibe todo lo que llevas hablado y sigue desde ahí — no pierdes ni una palabra.
2. **Menú de la barra** (clic en el micrófono) → **"Proveedor principal"** → un clic y listo.
3. **Pestaña Modelos** → arrastra las filas de la cascada al orden que quieras.

## 11. Pestaña Ajustes

![Pestaña Ajustes](img/ajustes.png)

**General**
- **Tecla de dictado**: clic en el botón y pulsa la tecla o combinación que quieras (fn, F1–F12, ⌘⇧D…). Esc cancela la grabación del atajo.
- **Mantener presionado para hablar (push-to-talk)**: si lo activas, grabas **mientras tengas la tecla presionada** y al **soltarla** termina y transcribe — en vez del modo toque (un toque empieza, otro termina). Funciona con **fn** o combinaciones de modificadores (ctrl+opt…); no con F1–F12. Por defecto está apagado.
- **Doble pulsación para activar** (opcional): evita que un toque accidental abra el micrófono. En **modo toque**, pulsa dos veces rápido para empezar y una sola vez para terminar. Con **push-to-talk**, da un primer toque y **mantén la segunda pulsación** mientras hablas; al soltar termina. La rapidez admitida entre ambas pulsaciones se puede ajustar de **0,25 a 1 segundo**. Funciona con fn, combinaciones de modificadores y, en modo toque, también con F1–F12.
- **Micrófono**: por defecto usa el **integrado del Mac** — así tu iPhone cercano no "roba" la entrada por Continuity y te deja dictando al aire. Puedes elegir cualquier otro o el automático del sistema.
- **Sonidos de inicio y fin**: el "tink" al empezar y el "glass" al entregar.
- **Cancelar con Esc**: Esc a mitad del dictado descarta todo.
- **Mostrar el panel al dictar**: apágalo para modo ninja (dictas sin panel).
- **Mostrar en el Dock**: la app vive en la barra de menú; enciende esto si además la quieres en el Dock.
- **Arrancar al iniciar sesión**: BetoDicta se abre sola al prender el Mac.
- **Auto-cerrar tras N segundos de silencio**: el guardián que te salva si olvidas la tecla abierta (15–300 s).

**Al terminar el dictado** (opt-in, apagados por defecto)
- **Añadir un espacio al final**: separa dictados seguidos para que no queden pegados.
- **Pulsar Enter al terminar**: envía en chats (WhatsApp, Slack…) o salta de línea en editores.
- **Pulsar Shift+Enter al terminar**: salto de línea suave, sin enviar (excluyente con Enter).

**Pulido con IA**
- Pasa el texto por una IA que corrige puntuación y quita muletillas ("eh", "este…").
- **Elige la IA**: no tiene que ser Groq. Cualquiera conectada — **Groq, OpenAI, Mistral, OpenRouter, DeepSeek, xAI (Grok), Anthropic (Claude), Gemini (Google)**, y varias **GRATIS**: **Cerebras, GitHub Models, NVIDIA NIM, Together AI, Novita AI, Z.ai (GLM), SiliconFlow** (nube) o **LM Studio / Ollama** (local, se detectan solos si están corriendo, incluso recién abiertos). El selector muestra **"proveedor · modelo activo"** y solo lista las conectadas; la misma IA pule y traduce.
- **Elige el modelo de CUALQUIER proveedor** (no solo gateways): al elegir una IA aparece una fila **"Modelo"** con un botón **"Descubrir"** que trae su lista completa; eliges cuál usar al vuelo y se guarda por proveedor. Si el proveedor publica precios (ej. **OpenRouter**), cada modelo muestra su costo: **`$entrada/$salida por millón de tokens`** o **`gratis`** — así ves cuánto te costará antes de usarlo.
- **Failover de pulido** (si tienes 2+ IAs conectadas): despliega **"Failover de pulido (respaldo si uno cae)"** y ordena tus proveedores con las flechas. Igual que la cascada de voz: se intenta el **1º** (ej. Groq, el más rápido) y, si no responde (caído, sin cupo, error), salta solo al **2º**, luego al **3º**… (ej. OpenAI → OpenRouter → local). Si un modo tiene su **propia IA**, esa va primero y la cascada queda de respaldo. Así el pulido nunca se queda sin funcionar por un proveedor caído.
- **Glosario inteligente** (opt-in, *Ajustes → Avanzado*): a medida que tu glosario crece, mandarlo entero a la IA en cada dictado alarga el prompt y va más lento. Con esta opción, la app usa **embeddings** para enviar **solo los términos afines a lo que dictaste** (más los que aparecen literalmente) — prompt corto = **pulido más rápido**, y escala aunque tengas cientos de términos. Usa el mismo motor de embeddings que la búsqueda semántica (Ollama local o nube); la primera vez calienta los vectores en segundo plano.
- **Motor de embeddings — usa Ollama (local)**: el glosario inteligente, el reconocimiento de modos y la búsqueda semántica usan embeddings. Con **Ollama** (`bge-m3`) corren **en tu Mac**: gratis, privado, **sin internet ni latencia**. Con un motor de **nube** (OpenAI/Gemini/Mistral) cada dictado nuevo se vectoriza por internet. Recomendado: Ollama. Y si **no hay ningún motor**, no pasa nada — la app **salta** los embeddings y sigue con el glosario completo y el reconocimiento normal, sin error ni demora.
- **Failover del pulido**: si un proveedor no responde (red caída, sin cupo), la app **reintenta una vez con conexión fresca** y, si sigue fallando, **salta al siguiente proveedor** de tu cascada; en el peor caso pega el texto original. Nunca se queda colgada.
- **Red siempre caliente (pulido rápido)** (*Ajustes → Avanzado*, default ON): si usas una **VPN** (WireGuard/OpenVPN/etc.) que "duerme" cuando está inactiva, el primer dictado podía tardar ~14s por rehacer el handshake. Ahora un **latido** cada 15s mantiene el túnel y la conexión **calientes**, y el pulido **reusa** esa conexión → rápido **desde el primer dictado**, aunque dictes cada varios minutos. Si el socket muriera igual, reintenta con conexión fresca. Funciona con cualquier VPN o ninguna, y **nunca frena el dictado**.
- **Voz del sistema (texto → voz)** (*Ajustes → Avanzado*): BetoDicta puede **leerte** respuestas en voz (Modo Agente). Eliges el **motor** con failover — si el elegido falla, cae al siguiente y **termina en la voz de macOS**, nunca se queda mudo:
  - **Voz de macOS** (default): gratis, local, sin setup. Eliges voz + velocidad.
  - **ElevenLabs — tu voz clonada**: tu voz "Bto" en la nube (usa tu `ELEVENLABS_API_KEY`), modelo `eleven_flash_v2_5`. Con **streaming por WebSocket** (opción, default ON) el audio **empieza a sonar en ~75-130ms** mientras se genera; si el streaming falla, cae al modo normal.
  - **Otros motores de nube**: **OpenAI, Google Gemini, Deepgram, Cartesia, Inworld, PlayHT, Azure**. Cada uno parametrizable (voz, modelo, y **streaming con/sin WebSocket por proveedor**) con tu propia key. Sin key → se salta al siguiente motor, nunca truena.
  - **Clon local**: tus voces **clonadas** corriendo 100% offline. Tienes una **biblioteca de voces**: agregas/subes/eliges cuál habla, y cada voz lleva su **persona** (cómo habla esa persona) — el Agente **redacta en ese estilo** antes de leerlo. Una misma persona puede conservar dos variantes intercambiables: **Calidad (XTTS)** y **⚡ Rápida (Piper/ONNX)**. XTTS tiene streaming activable **por voz**; ONNX habla casi al instante. Gratis, sin internet.
  - **Motor de voz** (para correr los clones): BetoDicta trae el suyo **aislado** — pulsas **"Instalar motor de voz"** (descarga ~3-4 GB de Python + IA, bajo `~/.betodicta/voz-engine/`, no toca tu sistema, borrable). Después, 100% local.
  - Si mantienes XTTS precargado, al reabrir BetoDicta **reutiliza** el servidor correcto en vez de cargar otra copia; al salir normalmente lo apaga y libera la RAM. Nunca debe quedar una cascada de servidores huérfanos consumiendo CPU/memoria.
  - La **voz de macOS** ya suena al instante (no necesita streaming); ElevenLabs tiene su streaming por WebSocket. El streaming se configura **por cada motor/voz**, no en forma global.
  - Botón **"Probar voz"** usa el motor y la voz elegidos.
- **Paquete de voz portable**: una voz clonada se guarda/comparte como un **paquete autocontenido** (modelo + su persona + instrucciones). Si creaste su versión rápida, el portable lleva **XTTS + ONNX vinculados**. **⬆︎ Subir voz** lo mete a BetoDicta en cualquier Mac; **⬇︎** lo **descarga** para llevarlo; y funciona incluso **sin BetoDicta**. Libre y sin ataduras.
  - **Subir uno de fuera:** si el clon viene incompleto (solo el modelo, sin config/voz/persona), BetoDicta **arma lo que falta** solo. Si no trae **muestras** de la voz, te las pide (**➕🎙**). Si no trae **persona**, la **genera** transcribiendo las muestras (**🧠**).
- **Entrenar una voz nueva** (**🎓** en *Clon local*): creas un clon **desde cero** dentro de BetoDicta.
  1. Eliges una **carpeta con audios** de UNA persona + un **nombre**.
  2. BetoDicta **mide la duración** y te **recomienda** las etapas (menos de 1 h no sirve; 1-2 h → ~3000; 2-4 h → ~4000; 4-6 h → ~5000). **Tú decides** — todo editable.
  3. **Entrena** en segundo plano (verás el **progreso en vivo**: paso, %, y una **gráfica**).
  4. Al terminar, **compara los cortes** (elige el mejor por parecido a la voz real), **escucha** cualquiera, **elige** el que te guste (o **borra** los descartados), y sale tu **paquete portable** listo. La **persona** (cómo habla) se saca sola de los audios.
- **Aviso de privacidad**: al pulir con una IA de **nube** o un **gateway de terceros**, la app te recuerda que **tu texto sale de tu Mac** — no dictes datos sensibles (claves, tarjetas). Para que **nada** salga, usa una IA **local**. El aviso se puede ocultar en *Ajustes → Avanzado*. Si un gateway usa **http sin cifrar**, la API key **no se envía** (protección).
- **Conectar más IAs de chat** (despliega la sección): pega la API key de la que quieras (OpenRouter/DeepSeek/xAI…). Para los locales, pulsa **"Buscar"** (o préndelos y reabre) — la app encuentra el modelo cargado.
- **IA personalizada (gateway propio)**: para servidores/gateways que no están en la lista. Pones tu **URL base**, **API key**, el **esquema de autenticación** (Bearer, X-API-Key o un encabezado propio), **encabezados extra**, y el **modelo** (a mano o con "Descubrir modelos"). Botón **"Probar conexión"** y marcas si sirve **para pulir** y/o **para reconocer voz (transcripción)**. Un gateway marcado **para voz** (debe exponer `/audio/transcriptions` estilo OpenAI) aparece en la **cascada de Modelos** (apagado; actívalo y ordénalo ahí) y participa en el failover como cualquier motor. Cada gateway aparece también en el selector de pulido. El botón **"+"** trae **plantillas preconfiguradas** (ej. **Cloudflare Workers AI**): crea el gateway casi listo — solo reemplazas tu **Account ID** en la URL y pones el token.
  - **"Descubrir modelos"** trae **todos** los modelos del gateway de una vez (si tu URL base no lleva `/v1`, lo prueba solo y te avisa que la API está bajo `/v1` — súbelo a la URL para que el pulido funcione). Ya no eliges uno solo y listo: **cambia el modelo activo cuando quieras** desde *Ajustes → Pulido*, con el selector **"Modelo del gateway"** que aparece al elegir ese gateway — sin volver a abrir el editor.
- El **estilo del pulido** es una instrucción tuya opcional: "trato formal de usted", "estilo técnico", etc.

**Aprendizaje** — que la app aprenda de tus correcciones y (opcional) corrija por sonido. Es tan importante que tiene sus propias secciones: [14](#14-que-la-app-aprenda-de-ti-aprendizaje) y [15](#15-corrección-por-sonido-fonética).

**Multimedia**
- **Pausar música y videos al dictar**: pausa Spotify, YouTube, Music… y los reanuda al terminar.
- **Bajar el volumen al dictar**: además baja el volumen del sistema y lo restaura exacto.

**Avanzado** (plegado por defecto; se despliega al clic en **todo el título**)
- **Modo desarrollo**: anota detalles técnicos extra en el registro (para diagnosticar) y **desbloquea la bitácora de aprendizajes** en Estadísticas.
- **Buscar actualización al abrir** (encendido por defecto): al arrancar revisa en silencio si hay versión nueva y te lo muestra abajo-izquierda. Nunca instala nada sin permiso.
- **Autoactualizar** (apagado por defecto): si encuentra actualización al abrir, la baja e instala sola (la app se reinicia). Ver §20.
- **Salvaguarda anti-inyección** (apagado por defecto): protección extra por si usas **gateways de terceros**. Si el texto que devuelve la IA de pulido **se dispara de tamaño** o **mete comandos de shell** que tú no dictaste (por ejemplo un gateway malicioso), la app **pega tu dictado ORIGINAL** en vez del pulido. **Nunca bloquea ni borra**: en el peor caso pierdes el pulido, no tus palabras. Útil sobre todo si dictas en terminales. Las IAs de pulido conocidas (Groq, OpenAI, Anthropic…) no necesitan esto.
- **STT en vivo para la nube (WebSocket)** (apagado por defecto): si tu motor de transcripción #1 lo soporta (**Deepgram, Soniox, AssemblyAI, Speechmatics o Gladia**), con esto transcribe **EN VIVO** — ves el texto mientras hablas, en lugar de esperar a soltar la tecla. Necesita la key de ese proveedor. Apagado, transcriben por lotes como el resto.
- **Espera del pulido con IA**: cuánto esperar la respuesta antes de rendirse (10–60 s). La app ya reintenta sola ante cortes de red, y espera más para textos largos. Súbelo si tu conexión es lenta.

## 12. Pestaña Acciones

![Pestaña Acciones](img/acciones.png)

Los accesos rápidos de mantenimiento:

- **Glosario**: abre los editores de palabras del glosario y de reemplazos (ver la sección siguiente).
- **Dictados**: copiar el último dictado, exportar los de hoy a Markdown, abrir la carpeta del historial.
- **Diagnóstico**: ver el registro (log) de la app — útil si algo falla y quieres reportarlo.

## 13. Glosario y reemplazos

El corazón de "que escriba bien mis palabras":

![Editor del glosario](img/editor-keyterms.png)

**Glosario (keyterms)** — Configuración → Acciones → *Editar palabras del glosario*. Una palabra o frase por línea (nombres propios, siglas, términos técnicos: *Quipux, SENESCYT, Aldás…*). El glosario **viaja a TODOS los motores**: ElevenLabs lo recibe nativo, Whisper/Groq/OpenAI como contexto, Voxtral dentro de la instrucción. Editas el archivo y aplica desde el siguiente dictado.

![Editor de reemplazos](img/editor-reemplazos.png)

**Reemplazos** — Configuración → Acciones → *Editar reemplazos*. Correcciones automáticas DESPUÉS de transcribir, para todos los motores siempre: si un motor escribe "Kipux", la regla `kipux, kipox, quipus… → Quipux` lo corrige antes de pegar.

Cada fila del editor tiene, de izquierda a derecha:
- ☑️ **Activo**: apaga la regla sin borrarla.
- **Escuchado** (variantes separadas por coma): todo lo que el motor podría escribir mal.
- **Se escribe**: cómo debe quedar.
- 🔉 **Escuchar**: la Mac pronuncia el término (solo para oírlo — la corrección no usa audio).
- 🔍 **Probar**: escribe una palabra y te dice si la [fonética](#15-corrección-por-sonido-fonética) la corregiría (y por qué).
- 🔊 **Por sonido**: casilla de la onda — activa la corrección fonética para ESE término.
- 🗑 **Borrar**.

Soporta expresiones regulares para cazar familias enteras de variantes. Importar/Exportar tus reglas está en el menú de compartir (arriba a la derecha).

**Coincidencia por audio (experimental)** — arriba del editor hay un interruptor "Coincidir por audio". Con él encendido, cada fila muestra un **🎙** para **grabar tu voz** diciendo el término (varias veces = mejor) y una casilla **Abc** para marcarlo como **sigla** (DGTIC). Al dictar, la app reconoce el término por **cómo suena tu voz** —además del texto— y corrige aunque el motor lo escriba muy distinto. Es experimental: se calibra con "probar por voz" y una **raya al dictar** ajustable, y solo actúa en dictados ≤30 s. Apagado no cambia nada.

**¿Cuál usar?** Los dos: el glosario ayuda al motor a acertar a la primera; los reemplazos son la red de seguridad que corrige lo que se escape.

## 14. Que la app aprenda de ti (aprendizaje)

![Aprendizaje y corrección por sonido](img/aprendizaje.png)

En vez de que edites reglas a mano, BetoDicta puede **aprender sola** de las correcciones que ya haces. Se activa en **Ajustes → Aprendizaje → "Aprender de mis correcciones"** (viene apagado; es opt-in).

**Cómo funciona**
1. Dictas y la app pega el texto donde está tu cursor.
2. Ahí mismo, **antes de enviar**, corriges una palabra que salió mal (ej. borras "Kipux" y escribes "Quipux").
3. Un vigilante lee ese campo, compara lo pegado con lo que quedó, y si el cambio es del tipo *"palabra rara → palabra parecida"*, **aprende la regla solo** (`Kipux → Quipux`). La próxima vez ya te la corrige.
4. Todo **100% local** — nada sale de tu Mac. La regla nueva se guarda en tus reemplazos.

**Dónde funciona automático**
- En **apps nativas** (Notas, Mail, Word, Pages, TextEdit…) es 100% automático: exponen su texto por Accesibilidad y el vigilante lo lee sin que hagas nada.

**Dónde necesitas el atajo (Claude Code CLI, terminales, apps Electron)**
- iTerm, Terminal, Warp, Claude Code CLI y demás **no exponen su texto** por Accesibilidad (dibujan sobre un lienzo). Ahí el vigilante no puede leer solo.
- Solución: corrige la palabra, **SELECCIONA el texto corregido** y pulsa el atajo **⌘⇧L** (configurable en la misma tarjeta). La app copia tu selección, la compara con lo último que dictó y aprende igual.

**Salvaguardas** — solo aprende cambios "palabra rara → parecida" (distancia de edición corta); ignora palabras comunes y muletillas para no inventar reglas basura.

**Verlo y deshacerlo** — activa **Modo desarrollo** (Ajustes → Avanzado) y ve a **Estadísticas**: abajo aparece **"Aprendizaje (debug)"** con las correcciones de las últimas 24 h y el total histórico. Cada una trae un botón **↺** para revertir esa regla al instante (el 🔊 marca las que vinieron por sonido).

## 15. Corrección por sonido (fonética)

Los reemplazos normales corrigen variantes que ya conoces. La **corrección por sonido** va más allá: corrige palabras que **SUENAN** como un término tuyo, aunque nunca las hayas visto antes (cualquier cosa que suene a *Quipux* → *Quipux*).

**Se enciende en dos niveles** (los dos, a propósito — es potente y conservadora):
1. **Global**: Ajustes → Aprendizaje → **"Corrección por sonido (fonética)"** (opt-in, apagada por defecto).
2. **Por término**: en *Editar reemplazos*, marca la casilla de la onda **🔊** en el término que quieras (solo ese usará el sonido). Si el interruptor global está encendido pero **ningún término tiene el 🔊**, no corrige nada — por eso hay que marcar el término.

**Cómo funciona por dentro (Metaphone español)**
Convierte cada palabra en un código de **cómo suena**, normalizando las consonantes que comparten sonido:

| Suena igual | Se normaliza a |
|---|---|
| k / qu / c (ca,co,cu) | **K** |
| b / v / w | **B** |
| s / z / c (ce,ci) | **S** |
| j / g (ge,gi) | **J** |
| ll | **Y** · x → **KS** · ch → **X** · h → (muda) |

Así *Quipux*, *Kipux* y *Guipux* caen en códigos casi idénticos (`KIPUKS`, `GIPUKS`).

**Triple candado (para no sobre-corregir)** — una palabra solo se cambia si cumple las tres:
1. tiene 3+ letras y no es ya el término correcto,
2. su **sonido** está a distancia ≤ 1 del término (suena casi idéntico),
3. su **escritura** no está muy lejos (≤ 40 % de su largo), y no es una palabra común.

**Ejemplos reales** (con el término *Quipux* marcado 🔊):

| Palabra | ¿Qué hace? |
|---|---|
| Kipux, Guipux, Quibux, Whipux | ✅ corrige → **Quipux** |
| cripto, kilos, equipo | ❌ las deja igual (suenan distinto) |

**Reversible siempre** — cada corrección por sonido queda registrada (con 🔊) en Estadísticas → Aprendizaje (debug), con su botón **↺**. Y si un término empieza a corregir de más, basta **quitarle la casilla 🔊** en Editar reemplazos: vuelve a ser un reemplazo normal.

> ⚠️ Es la función más agresiva de la app. Un término puede sonar como muchas palabras; enciéndela término por término y revisa en Estadísticas lo que hizo.

## 16. Traducir al dictar

Menú de la barra → **"Traducir al dictar"** → elige idioma (inglés, portugués, francés…). Dictas en español y se pega traducido. Los términos de tu glosario NO se traducen (nombres propios quedan intactos). Necesita key de Groq. **"Desactivado"** vuelve al español normal.

> **Cancelar de raíz.** Cuando el agente está pensando o hablando (Hermes, IA local o nube), puedes cortar TODO al instante: pulsa **Esc** o **toca el notch**. Se mata la consulta en curso **y sus procesos de verdad** (Hermes corre el trabajo y sus herramientas como procesos aparte; se mata el árbol completo, no solo el enlace), se ignoran respuestas que vengan tarde y se corta el audio (voz de macOS, nube y streaming local). Igual que la X cancela el dictado. No dependes de esperar a que termine.
>
> **Interrumpir (barge-in).** Mientras la IA responde, pulsa **fn** y la interrumpes para decirle otra cosa: se corta lo actual y grabas lo nuevo, que **sigue la misma conversación** (el agente conserva el contexto). Como cortar a alguien a media frase para redirigirlo.

## 16 bis. Modos — qué hacer con lo dictado

Un **modo** decide cómo se procesa tu dictado. Se configura en **Ajustes → Modos** y se cambia de dos maneras:

- **Switch manual**: clic en la etiqueta del modo (**notch**, arriba-izquierda) o **menú de la barra → Modo**.
- **Switch por voz (automático)**: al empezar a hablar, di el modo. Puedes continuar de inmediato o hacer una **pausa corta**. Ejemplo: *"modo traductor… (pausa) …buenos días, ¿cómo estás?"*. En cuanto lo reconoce, **el notch cambia de nombre y color con un doble parpadeo** — esa es la señal de "te escuché" — y tú sigues hablando; la pausa **confirma el modo, pero no termina la grabación**. Funciona con cualquier motor (Groq incluido): los "oídos en vivo" son el transcriptor disponible durante la grabación, mientras tu motor real hace la transcripción definitiva al soltar.

**Cada modo tiene su COLOR** en el notch (letrero + un tinte suave del fondo): dictado = negro neutro, traducir = celeste, agente = magenta, tarea = naranja… Los modos que tú crees reciben color automático (estable), o eliges uno con el **selector de color** del editor de modos. Así sabes de un vistazo en qué modo estás.

La detección por voz tiene varias capas de tolerancia (el micrófono a veces escucha *"molde traductor"* o *"moto agente"* — igual lo entiende). Un único resolver aplica este orden: **cadena de modos → frase final exacta → frase final difusa → gramatical → modo confirmado durante la pausa → app/sitio → semántica con embeddings → respaldo captado en vivo → modo manual**. La detección difusa es local, conservadora y exige una palabra inicial segura; expresiones normales como *"moda de invierno"*, *"modo de empleo"* o *"todo agente tiene un jefe"* no activan nada. Cada grabación tiene una identidad propia: parciales o resultados tardíos de otra grabación se descartan.

**Capa gramatical — el verbo en cualquier conjugación, sin decir "modo".** *"Tradúceme esto al quichua…"*, *"traduce al inglés…"*, *"búscame en google…"*, *"apúntame como tarea…"* cambian **directo** (el verbo imperativo es intención clara; y si nombras el destino — *"como tarea"* — ese manda). Si la intención es indirecta (*"quiero traducir algo…"*), BetoDicta **no adivina**: sale un mini-aviso en el notch — *"¿Cambiar a MODO TRADUCIR? fn = sí · clic = no"* — pulsas **fn** y cambia; con un clic o 8 s de silencio se procesa como dictado normal, sin recortar nada. Cada sí/no queda registrado para que el sistema aprenda de ti. Parametrizable (Ajustes → capa gramatical).

**Motor de embeddings INTERNO (sin instalar nada).** La semántica (modos por significado, búsqueda por idea en el Historial y glosario inteligente) **ya no necesita Ollama**: BetoDicta trae su propio motor — el mismo modelo **bge-m3**, servido por la propia app. Solo descargas el modelo una vez (~417 MB, botón en `Ajustes → Motor de embeddings → ✓ Interno de BetoDicta`). Es rápido de verdad (**~7 ms por consulta**, medido; se precalienta solo al pulsar fn) y **duerme** tras 10 min sin uso para liberar memoria. Ollama, OpenAI, Gemini y Mistral siguen como opciones en el mismo selector.

En **Ajustes → Avanzado** puedes apagar el cambio en vivo, apagar la confirmación por pausa, elegir la pausa (por defecto **2,0 s**) y limitar cuántas palabras del inicio se consideran zona de comando (por defecto **8**). El resto del dictado nunca se examina como orden. Si dices únicamente *"modo agente"* y terminas, BetoDicta deja **Agente listo para el próximo dictado** en vez de llamar a la IA con un texto vacío.

Modos base:

- **Dictado** (por defecto): comportamiento de siempre (pulir + traducir si los tienes activos).
- **Correo / Oficio / Tarea / Nota**: reescriben tu dictado con ese formato. **Tarea** y **Nota** además **guardan** lo dictado en tu lista local (pestaña **Tareas y notas**).
- **Traducir**: traduce a un idioma que eliges de una **lista con banderita** (y puedes **agregar** los idiomas que quieras).
- **Asistente**: trata tu dictado como una instrucción y redacta la respuesta.
- **Agente** (asistente por voz): le pides algo hablando (*"modo agente, dime qué tareas tengo hoy"*) y te **responde por voz** (si la *Voz del sistema* está activa) **y pega el texto**. Conoce **tus tareas y notas** guardadas, así que puede contestarte sobre ellas. Puedes elegir con qué IA piensa y con qué voz habla. Si no tienes IA de chat o TTS, degrada suave (solo pega / no habla).
- **Buscar**: no pega texto — **abre el buscador con tu consulta**. Vienen muchos: **Google, Bing, DuckDuckGo, Wikipedia, YouTube, Google Maps, Gmail** (buscar correo), **Outlook/Hotmail, Facebook, Amazon, MercadoLibre, X (Twitter), GitHub**, **Spotlight** (⌘Espacio en tu Mac) o una **URL propia** (usa `{q}` donde va el texto). Y puedes **agregar los tuyos** (nombre + URL con `{q}`) en el mismo modo Buscar — quedan para todos y se reconocen por voz (*"modo buscar wikipedia Ecuador"*). Sin IA.
- **Acción**: abre una **app o página con tu texto** — **Nuevo correo** (mailto), **Outlook**, **WhatsApp**, **Notas, Recordatorios, Calendario, Finder, Mensajes** (abre la app y copia el texto para que pegues), o **tu propia URL** (ej. Quipux: pones la URL con `{q}`). Sin IA. Ideal como modo propio con su frase de voz (ej. *"modo whatsapp …"*).

Cada modo de texto usa **su propia IA y su propio prompt** — o la IA global de Pulido (Buscar y Acción no usan IA). Puedes crear tus **propios** modos con el botón **+** (nombre, comportamiento, prompt/IA, o acción). Los que producen texto pueden además **guardarse** en Tareas o Notas (opción *"Guardar en"*).

**Tareas y notas** (pestaña propia): lo que dictas con Tarea/Nota se acumula ahí. Marca tareas como **hechas**, bórralas, **"Limpiar hechas"**, o agrega a mano. 100% local.

**Acciones a apps de Mac:** vienen creados modos de acción para las apps por defecto (Outlook, Correo, WhatsApp, Notas, Recordatorios, Calendario, Finder, Safari, Música, Terminal, Mapas, Spotlight, tu web…). Las que llevan tu texto en la URL/esquema lo abren con el texto puesto (Correo, Outlook, WhatsApp, Mapas, tu URL con `{q}`). Para las demás, la app se abre y el texto queda en el portapapeles (pégalo con **⌘V**). *(Insertar el texto automáticamente en Notas/Recordatorios está en mejora.)*

**WhatsApp con contactos:** en el modo WhatsApp puedes **importar** tu lista y/o usar tus **Contactos de Mac**. El import **auto-detecta el formato**: **vCard `.vcf`** (teléfono iPhone/Android, iCloud, Outlook), **CSV de Google/Gmail** (inglés o español), **CSV de Outlook/Edge**, o CSV/JSON simple — y te dice cuántos **válidos/inválidos** importó. Di *"modo whatsapp, enviar a Alberto, hola qué tal"* → busca a Alberto y abre su chat con el texto; si hay varios, **eliges en un modal** (los más probables primero). **Exportar CSV/JSON** te da el formato (con ejemplo si está vacío). *(Los números deben tener código de país — ej. 593… — para abrir el chat correcto.)*

**Un solo uso (por defecto ON):** el modo que eliges en el notch/menú se aplica **solo a ese dictado** y luego vuelve al **modo por defecto**. Marca el por defecto con **"Poner por defecto"**. Si prefieres que el modo elegido se quede fijo, apaga el interruptor *"El modo elegido al vuelo es de un solo uso"*.

**Activación automática:**

- **Por voz** — empieza el dictado con la frase del modo (ej. *"modo tarea comprar la comida"*): se aplica ese modo y la frase se quita. Edita/vacía cada frase en Ajustes → Modos. **Con argumento**: la frase mágica puede llevar un dato que ajusta el modo solo por ese dictado — *"modo traducir quichua hola"* traduce a quichua; *"modo buscar google gatos"* busca en Google. Sin argumento usa el idioma/buscador por defecto del modo.
- **Por app / sitio web** — pon en cada modo las **apps** (ej. Outlook) o **sitios** (ej. `quipux.gob.ec`) donde debe aplicarse solo. La primera vez, los sitios piden permiso de Automatización para leer la URL del navegador.

Precedencia resumida: una cadena o una orden de voz explícita manda sobre el contexto; después vienen **app/sitio**, el reconocimiento semántico, el respaldo en vivo y finalmente el modo elegido a mano.

**El sistema se mejora a sí mismo** (*Ajustes → Modos*, icono de varita ✨): analiza el registro de modos y te dice qué reconoció bien/mal, con **sugerencias**. Los comandos que no reconoció los puedes **agregar como ejemplo con un clic** (y el sistema los aprende), o pedirle **sugerencias a tu IA**. El registro detallado vive en `~/.betodicta/logs/modos.jsonl` (se ve con el icono de lupa; se apaga en Avanzado). La zona-comando del reconocimiento se ajusta sola (**ventana dinámica**): corta donde la intención se entiende y deja el resto como contenido/destinatario.

**Reconocimiento inteligente de modos** (opt-in, *Ajustes → Avanzado*): con esto encendido, la app entiende el llamado de un modo **aunque lo digas de mil formas** — *"modo mándale un WhatsApp a Ana"*, *"modo tradúceme al inglés"*, *"modo apúntame una tarea"* — usando **embeddings** (por significado). Solo actúa si empiezas con **"modo"** (o una mal-escucha como *mudo/molde*) y el reconocimiento exacto no acertó; si nada se parece lo suficiente, sigue como texto normal. Es **parametrizable**: cuántas palabras del inicio se analizan y la sensibilidad (umbral). Y **entrenable por ti**: en *Ajustes → Modos*, cada modo tiene un campo **"Ejemplos"** donde agregas tus propias formas de pedirlo — se procesan con **tu** motor de embeddings (Ollama local o el que elijas). La primera vez calienta los vectores en segundo plano.

**Modos encadenados (pipeline por voz):** puedes juntar un transform + una acción en una sola frase — la palabra mágica es **"modo"** y luego dices los pasos. Ej.: *"modo traducir quichua a correo, hacer la merienda hoy"* → traduce a quichua y abre un correo con ese texto. *"modo traducir inglés whatsapp, nos vemos mañana"* → traduce y abre WhatsApp con el texto. Es **orden-independiente**: *"modo correo y traducir inglés, hola"* hace lo mismo. Los conectores (a, y, al, en…) se ignoran; lo que no sea un paso conocido es el **contenido**. Si solo dices un paso, funciona como el modo normal.

## 17. Pestaña Historial

![Pestaña Historial](img/historial.png)

Todos tus dictados, buscables:

- **Buscador** instantáneo — no distingue mayúsculas ni tildes ("aldas" encuentra "Aldás").
- **Buscar por significado (semántica)** 🧠 — enciende el interruptor y busca por IDEA, no por palabra exacta: "bajar el volumen de la música" encuentra dictados sobre "mutear las reproducciones" aunque no compartan palabras. Escribe y pulsa **Enter**; los resultados salen ordenados por **% afín**. Cada dictado se procesa una vez y queda en caché (la primera búsqueda de un historial grande tarda, las siguientes son instantáneas). Se activa (y se elige **con cuál IA** se calcula) en *Ajustes → Avanzado*: por defecto **Ollama local** (`bge-m3`, gratis y privado — nada sale de tu Mac), pero como Ollama no está en toda máquina puedes elegir **OpenAI, Gemini, Mistral** o uno personalizado. El selector muestra cuáles tienes listos (✓) y cuáles necesitan key (○). Cambiar de motor vuelve a indexar (los vectores de motores distintos no son compatibles). Apagado, el Historial busca por texto exacto como siempre.
- **▶** escucha el audio original de ese dictado.
- **📋** copia el texto al portapapeles.
- **📁** muestra los archivos en Finder.
- El texto es seleccionable directamente.

## 18. Pestaña Transcribir

![Pestaña Transcribir](img/transcribir.png)

- **Procesar como**: arriba eliges un **modo** (Dictado = solo limpieza, o Correo, Oficio, Tarea, Nota, Traducir, Asistente…). Se aplica tanto al archivo que subes como a la re-transcripción — ágil para, por ejemplo, subir un audio y sacarlo ya como correo o traducido. Buscar no aplica aquí (abre navegador, no da texto).
- **Subir un archivo**: elige un audio o video (wav, mp3, m4a, mp4, mov…) y lo convierte a texto con tu glosario. Ideal para grabaciones de reuniones.
- **Re-transcribir un dictado**: vuelve a pasar un audio del historial por el motor — útil si falló la primera vez o si tu glosario mejoró desde entonces.

## 19. Estadísticas y costo por modelo

![Pestaña Estadísticas](img/estadisticas.png)

- Minutos dictados hoy / semana / mes / año, número de dictados y **costo estimado del mes**.
- **El costo se calcula por MODELO**, no por proveedor: cada dictado suma según el precio del modelo que realmente se usó (y si el failover cambió de modelo a mitad, cuenta el que entregó). Los motores locales cuestan $0.
- Gráfica de barras de los últimos 7 días.
- **Gasto de pulido con IA**: si usas una IA de pulido de pago, aparece una sección aparte con lo gastado en **pulido** — **hoy / semana / mes**, número de pulidos, **tokens** del día y una gráfica de gasto de los últimos 7 días. Se calcula con el precio (entrada/salida por millón de tokens) del modelo que pule; con modelos locales o `:free` el gasto es $0. Solo se muestra si has pulido con IA este mes.
- El menú de la barra muestra un resumen por proveedor.
- Con **Modo desarrollo** activo aparece la bitácora **Aprendizaje (debug)** (ver [sección 14](#14-que-la-app-aprenda-de-ti-aprendizaje)): las correcciones aprendidas, con 🔊 para las de sonido y ↺ para revertir.

## 20. Actualizar la app

La app **te avisa sola**. Al abrirla revisa en silencio si hay versión nueva y, por defecto, vuelve a comprobar **cada 6 horas mientras permanezca abierta**. Ambas cosas son configurables en *Ajustes → Avanzado*. Si la hay, lo ves en dos lugares:

- **Abajo a la izquierda** del panel de Configuración: botón **"Actualizar a vX"** y un enlace **"Ver novedades"** (para leer los cambios *antes* de actualizar).
- En el **menú de la barra**: un ítem **"⬆︎ Actualización disponible…"** que abre Configuración.

Al pulsar **"Actualizar a vX"** la app descarga el DMG (con **barra de porcentaje**), se reinstala y se reabre sola. Un clic, cero pasos manuales. Al terminar te muestra las **novedades** de la versión.

Si prefieres no revisar nada a mano, activa **Autoactualizar** (*Ajustes → Avanzado*): cuando encuentre una versión nueva al abrir o en la revisión periódica, la baja e instala sola. Siempre puedes forzar la búsqueda con **"Verificar actualización"** o **"Comprobar de nuevo"** en el pie.

**Estables y beta:** el canal **Automático** (recomendado) sigue versiones beta únicamente cuando la copia instalada ya es beta; una copia estable solo recibe estables. También puedes escoger **Solo estables** o **Estables y beta**. El actualizador consulta la lista de releases como respaldo, porque el endpoint `latest` de GitHub no incluye pre-releases.

- Si no hay nada: "Ya estás en la última versión".
- El historial completo de cambios de cada versión está en **Créditos**.

> **Gobernanza — todo parametrizable**: búsqueda al abrir, canal estable/beta, revisión periódica (1–24 h) y Autoactualizar viven en *Ajustes → Avanzado*. Nada se instala sin tu permiso salvo que actives Autoactualizar.

## 21. Apoya el proyecto

![Créditos y donaciones](img/creditos.png)

BetoDicta es gratis y libre (GPL-3.0). Si te sirve y quieres que siga creciendo, en **Configuración → Créditos → "Apoya el proyecto ☕"** hay varias formas de aportar:

- **☕ Invítame un café** — tarjeta, Apple Pay o Google Pay ([betodicta.eztic.ec/apoyar](https://betodicta.eztic.ec/apoyar)).
- **💜 GitHub Sponsors** — [github.com/sponsors/btoaldas](https://github.com/sponsors/btoaldas).
- **💳 PayPal**.
- Más formas (transferencia, cripto, etc.) en la página de apoyo.

Cualquier aporte suma — plata, código, difusión o una buena idea en [Issues](https://github.com/btoaldas/BetoDicta/issues/new).

## 22. La caja negra: tus datos

Todo vive en tu Mac, en `~/.betodicta/`:

| Archivo/carpeta | Qué es |
|---|---|
| `historial/año/mes/día/` | Cada dictado: audio (.wav) + texto (.txt). El audio se escribe a disco EN VIVO mientras hablas — un corte de luz no te roba ni un segundo (la app rescata lo grabado al reiniciar) |
| `config.json` | Tus ajustes (incluidas las tarifas por modelo que hayas puesto) |
| `providers.json` | Tu cascada de motores |
| `keyterms.txt` | Tu glosario |
| `reemplazos.json` | Tus reglas de corrección (incluido el marcado 🔊 por sonido) |
| `aprendizajes.jsonl` | La bitácora de lo que la app aprendió de tus correcciones |
| `uso.jsonl` | El odómetro de uso (minutos y modelo por dictado) para las estadísticas |
| `.env` | Tus API keys (solo en tu Mac, permisos `0600`) |
| `ia_personalizadas.json` | Tus gateways propios (URL, key, modelos) — permisos `0600` |
| `models/` | Los modelos de IA descargados |
| `betodicta.log` | El registro de todo (se rota y comprime solo). Las API keys **nunca** se escriben aquí |

**Privacidad**: con motores locales, tu voz **jamás sale de tu Mac**. Con motores de nube, el audio va al proveedor que elegiste (ElevenLabs/Groq/OpenAI/Mistral) bajo sus términos. El pulido y la traducción mandan el TEXTO a la IA que elijas — o **no salen de tu Mac** si usas una IA local (LM Studio / Ollama). El aprendizaje y la coincidencia por audio son 100% locales. Tú controlas qué usas.

**Seguridad**:
- Tus **API keys** y gateways se guardan con permisos `0600` (solo tu usuario) y la carpeta `~/.betodicta` en `0700`. La key **no se envía** si un gateway se configuró con `http://` sin cifrar.
- Las **actualizaciones se verifican por firma**: antes de instalar, la app comprueba que el nuevo BetoDicta.app venga firmado con **el mismo certificado** que tu copia actual. Un instalador manipulado o firmado por otro se **rechaza** — así, aunque alguien alterara un release, no se instalaría.
- El código es **abierto** ([GPL-3.0](https://github.com/btoaldas/BetoDicta)): cualquiera puede auditarlo. Cada release pasa por revisión de código y de seguridad antes de publicarse.

## 23. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| Dicto y sale vacío o "(silencio)" | El micrófono no te capta (¿iPhone cerca? ¿mic equivocado?) | Ajustes → Micrófono → "Integrado del Mac". Verifica que las barras del panel laten al hablar |
| "Escuchando (red caída…)" | Tu internet falló — la app te protege | Dicta normal: transcribe con el motor local al soltar. Vuelve solo cuando la red regrese |
| El letrero salta a otro motor | El #1 falló y el siguiente tomó el mando | Es el diseño. Revisa tu conexión o el orden de la cascada |
| "Falta la API key…" | Ese proveedor de nube no tiene key | Ponla en Configuración → Modelos, o usa los motores locales gratis |
| Un modelo local "no disponible" | No está descargado (o quedó a medias) | Pestaña Modelos → descárgalo (verifica el ✓ de descargado) |
| No pega el texto | Falta el permiso de Accesibilidad | Ajustes del Sistema → Privacidad y seguridad → Accesibilidad → activa BetoDicta |
| La tecla fn no responde | Permiso de Accesibilidad, o fn capturada por el sistema | Revisa Accesibilidad; en Ajustes del Sistema → Teclado pon "Al pulsar la tecla fn: No hacer nada" |
| **La corrección por sonido no hace nada** | El interruptor global está, pero **ningún término tiene el 🔊** | Editar reemplazos → marca la casilla de la onda 🔊 en el término que quieras (ver [sección 15](#15-corrección-por-sonido-fonética)) |
| **No aprende mis correcciones en la terminal/Claude Code** | Esas apps no exponen su texto por Accesibilidad | Corrige, SELECCIONA el texto y pulsa **⌘⇧L** (ver [sección 14](#14-que-la-app-aprenda-de-ti-aprendizaje)) |

**¿Nada de esto lo arregla?** → **[Reporta el problema aquí](https://github.com/btoaldas/BetoDicta/issues/new)** — cuéntanos qué hiciste, qué esperabas y qué pasó. Si puedes, adjunta las últimas líneas del registro (Configuración → Acciones → Ver registro).

## 24. Preguntas frecuentes

**¿Cuánto cuesta?** La app es gratis y open source (GPL-3.0). Los motores locales son gratis para siempre. Los de nube cobran por hora de audio y **el precio es por modelo** (lo ves y lo editas en Modelos): ElevenLabs `scribe_v2_realtime` ~$0.39 / `scribe_v2` ~$0.22; OpenAI ~$0.18–0.36; Mistral ~$0.18–0.36; Groq ~$0.04–0.11 (con capa gratis).

**¿Funciona sin internet?** Sí — con cualquier motor local (Voxtral, Nemotron, Whisper, Canary). Descárgalos una vez y dicta offline para siempre.

**¿De verdad aprende mis palabras?** Sí. Corrige la palabra ahí donde la pegaste (o selecciónala y pulsa ⌘⇧L en la terminal) y la app guarda la regla sola, 100% local. Ver [sección 14](#14-que-la-app-aprenda-de-ti-aprendizaje).

**¿Puedo dictar en otros idiomas?** BetoDicta está afinada para español latino. Voxtral Realtime detecta el idioma automáticamente; Nemotron soporta 40 idiomas (hoy la app lo fija en español).

**¿Qué tan pesada es?** La app pesa ~32 MB. Los modelos locales van de 74 MB (Whisper Tiny) a 3.2 GB (Voxtral 3B) — tú eliges cuáles descargar. Los modelos cargan en RAM solo al dictar y se descargan solos tras ~2 minutos sin uso.

**¿Dónde pido una función nueva?** En [GitHub Issues](https://github.com/btoaldas/BetoDicta/issues/new) — las ideas son bienvenidas.

---

## 25. Voz propia: biblioteca y entrenamiento

BetoDicta puede hablar con **tu propia voz** (o la de un ser querido), 100 % local. Se abre desde **la barra → Biblioteca de voces**. Hay dos motores de voz, y conviven:

- **XTTS** — clona una voz con mucha calidad y flexibilidad, pero habla **~a tiempo real** (más lento).
- **Piper** — hornea una voz **fija** que luego habla **casi al instante** (~5× tiempo real, sin torch). Ideal para respuestas rápidas.

Puedes entrenarlos desde una **carpeta de audios** de una sola persona (mientras más voz limpia, mejor; con ~1 a 6 horas rinde muy bien). Si ya tienes un XTTS que suena bien, también puedes usarlo como maestro para crear su versión ONNX sin volver al dataset original. Nada de esto viaja por internet: el motor de voz vive aislado en tu carpeta personal.

### Crear una versión rápida desde un XTTS que ya suena bien

En la fila de una voz XTTS pulsa **Crear ⚡**. No es una conversión directa del archivo —XTTS y Piper son redes distintas— sino una **destilación local**:

1. BetoDicta crea un corpus español variado y hace que tu XTTS lo lea.
2. Cada audio queda asociado al **texto exacto** que se le pidió: no arrastra anuncios, música, otras voces ni errores de transcripción del dataset original.
3. Piper parte de una base española, carga sus **pesos**, pero inicia optimizadores y calendarios **nuevos**; no hereda el entrenamiento envejecido de la base.
4. Al terminar, BetoDicta mide **inteligibilidad con Whisper** y **parecido de voz**. Solo vincula automáticamente un corte que supere el umbral seguro; si ninguno pasa, conserva XTTS y te manda a la vista avanzada para escuchar/revisar, sin activar una voz dañada.
5. En la biblioteca eliges **Calidad** o **⚡ Rápida** para esa misma persona. Crear ONNX nunca borra XTTS.

El plan es parametrizable: **Prueba** (recorrido corto, no voz final), **Recomendado** (~45–60 min sintéticos), **Alta fidelidad** (~1.5–2 h) o **Máximo** (~3–4 h), y puedes editar las actualizaciones. Antes del primer clip, BetoDicta guarda la cantidad, las etapas y la calidad elegidas. Si amplías el corpus, cierras la app o se apaga la Mac, reutiliza los clips válidos y continúa con **el mismo plan**, sin volver silenciosamente a los valores del selector. Para español empieza con la base **Media**, que es la base nativa española.

### Entrenar una voz Piper (rápida)

1. Biblioteca de voces → **⚡ Entrenar voz Piper (rápida)**.
2. **Preparar el entrenador** (una vez): baja las herramientas y arma el motor de entrenamiento.
3. Elige la **carpeta de audios**, ponle **nombre** y, si quieres, una **persona/prompt** (cómo habla; si lo dejas vacío se genera de los audios).
4. Elige la **calidad** (ver abajo) y, si falta, **descarga su base** (una sola vez).
5. **Entrenar**. BetoDicta:
   - **Fase 1** — transcribe y prepara los audios (Whisper): verás *"X de Y archivos (%)"* y cuántos fragmentos lleva.
   - **Fase 2** — entrena: verás *"paso X de Y (%)"* en vivo, con barra de porcentaje.
6. Guarda **varios checkpoints**. Puedes **escuchar** cualquiera y **usar el que más te guste** (los últimos suelen sonar mejor). Ese se registra como voz ⚡ en tu biblioteca.

**Corre en segundo plano y es resumible.** Puedes **cerrar la ventana e incluso salir de BetoDicta**: el entrenamiento sigue. Al reabrir, el progreso **vuelve a aparecer solo** y BetoDicta evita lanzar una segunda copia sobre la misma tanda. Si se apagó la computadora, aparece **“Continuar donde quedó”** y detecta si faltaba terminar el dataset, el entrenamiento o la validación. No re-transcribe ni regenera lo que ya estaba bien.

Durante el entrenamiento hay dos niveles de resguardo: los **cortes/hitos** que puedes escuchar y un **checkpoint de seguridad rodante cada 200 pasos**. Al continuar usa el más reciente de los dos, por lo que un apagón pierde como máximo ese pequeño tramo. La validación también guarda sus resultados después de cada checkpoint: si se interrumpe, reutiliza los ya puntuados y reintenta solo los pendientes o los que tuvieron un fallo transitorio.

**Bitácora viva.** Mientras entrena, la app muestra —refrescándose sola cada 2 segundos— la **fase** (1/2), el **porcentaje**, **paso/total**, **época**, **velocidad (it/s)**, **ETA**, y los recursos que ocupa: **CPU, RAM, disco**, además de **fragmentos**, **checkpoints** y **errores**. Debajo va el **registro imprimiéndose en vivo** (lo que pasa, bueno o malo). El **paso se muestra en tiempo real desde el primer paso** (no hay que esperar al primer checkpoint). Todo queda también guardado en `dataset.log` y `piper.log` dentro de la carpeta del proyecto.

**Detener del todo.** El botón **“⏹ Detener del todo”** corta el entrenamiento **de raíz** —mata todos sus procesos (torch, Whisper, ffmpeg)— y te **confirma en pantalla** que no quedó nada corriendo. El control es tuyo; no depende de nada externo.

> Nota de velocidad: en Apple Silicon el entrenamiento usa solo los **núcleos rápidos** (performance). Incluir los lentos (efficiency) dejaba la CPU al 100 % sin avanzar.

### Calidad: media, alta, baja

| Calidad | Qué es | Base |
|---|---|---|
| **Media** (recomendada) | 22 kHz, natural y rápida | **en español** (davefx) |
| **Alta** | Red más grande = más nítida, pero **más lenta al hablar** | en inglés (lessac), se adapta al español |
| **Baja** | 16 kHz, la más veloz y liviana, menor fidelidad | en inglés (lessac) |

Para español, **Media es la mejor opción**: es la única con base nativa en español. **Alta** y **Baja** solo existen con base en inglés; el entrenamiento las **adapta a tu español** (tu audio manda), así que **no se “dañan” ni pasa nada malo** si les envías audio en español — solo necesitan más etapas y hablan un poco más lento. Empieza con **Media**; si quieres, prueba **Alta** y compara escuchando. Nada se pierde: entrenas, escuchas, eliges.

### Requisitos y descargas

- **ffmpeg** (para preparar el audio): si falta, la app avisa — instálalo con `brew install ffmpeg`.
- **Herramientas de Apple** (solo la primera vez, para compilar una pieza): si faltan, la app avisa — `xcode-select --install`.
- Las piezas **pesadas se descargan bajo demanda y con tu permiso** (motor de voz, checkpoint base ~0.8–1 GB por calidad). Nada pesado viaja en la app ni en el repositorio.

> Créditos: Piper (OHF-Voice/rhasspy, GPL-3.0), checkpoints base de `rhasspy/piper-checkpoints`, Coqui XTTS, PyTorch, Whisper, espeak-ng. Ver [CREDITS.md](../CREDITS.md).

---

*BetoDicta — hecho en Ecuador 🇪🇨 por Alberto Aldás en compañía de Claude (Anthropic), programado a pura voz. Licencia GPL-3.0, libre para siempre.*

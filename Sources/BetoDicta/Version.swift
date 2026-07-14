import Foundation

// MARK: - Versión de la app (UN solo lugar; actualizar aquí en cada release)
//
// La UI (sidebar, Créditos, menú) lee de aquí. El Makefile inyecta
// Version.numero al Info.plist del bundle (CFBundleShortVersionString).

enum Version {
    static let numero = "0.31.0"
    static let fecha = "2026-07-14"

    /// Historial literal, la más nueva primero. Se muestra en Créditos.
    static let historial: [(version: String, fecha: String, cambios: [String])] = [
        ("0.31.0", "2026-07-14", [
            "Motor de voz INTERNO y aislado: BetoDicta corre tus clones con su propio Python (se instala con un botón, ~3-4 GB bajo ~/.betodicta/, no toca tu sistema). Ya no dependes de herramientas externas",
            "SUBIR y DESCARGAR voces: importa un paquete de voz portable (⬆︎) o descárgalo para llevarlo (⬇︎). Cada voz lleva su persona (cómo habla)",
            "Streaming del clon local (por voz): tu voz clonada suena MIENTRAS se genera (1er sonido en ~1-2s). Activable por cada voz, no global",
            "Arreglado: en la cascada de Modelos ya puedes arrastrar cualquier motor (Apple, Azure, OpenAI…) al orden que quieras — antes se trababa con proveedores ocultos",
        ]),
        ("0.30.0", "2026-07-14", [
            "Apple Speech NATIVO como motor de dictado: on-device, gratis, sin API key, sin internet (macOS 26+). Actívalo en la cascada",
            "Voz del sistema mejorada: eliges motor (voz de macOS · ElevenLabs tu voz clonada · clon local) con failover — nunca queda mudo",
            "ElevenLabs por STREAMING (WebSocket): tu voz clonada empieza a sonar en ~75-130ms mientras se genera",
            "Biblioteca de VOCES clonadas locales: agrega/sube/elige tus voces; cada una con su PERSONA (cómo habla) — el Agente redacta en ese estilo y lo dice con esa voz. 100% local",
            "Pulido MÁS RÁPIDO tras inactividad: la red se mantiene caliente (latido) y el pulido reusa la conexión — sin la espera de ~14s con VPN",
            "Modo Agente: te responde por voz + texto usando tus tareas/notas; eliges con qué IA piensa y con qué voz habla",
        ]),
        ("0.29.0", "2026-07-14", [
            "Muchos más buscadores en el modo Buscar: Wikipedia, Gmail, Outlook/Hotmail, Facebook, Amazon, MercadoLibre, X (Twitter), GitHub — y puedes AGREGAR los tuyos (nombre + URL con {q})",
            "Embeddings LOCALES por defecto (Ollama bge-m3): el glosario inteligente, el reconocimiento de modos y la búsqueda semántica corren en tu Mac — gratis, privados, sin internet ni latencia. Y si no tienes ningún motor, la app sigue funcionando igual (sin error ni demora)",
            "Menos latencia con VPN: la app 'despierta' la red mientras hablas (WireGuard/OpenVPN/etc. que duermen el túnel ya no te hacen esperar en el primer dictado)",
            "Pulido más robusto ante caídas: reintento con conexión fresca y, si sigue fallando, salto al siguiente proveedor; nunca se queda colgado",
            "Voz del sistema (texto → voz): BetoDicta ya puede LEERTE respuestas en voz (voz de macOS, gratis) — primer paso del Modo Agente. En Ajustes → Avanzado",
        ]),
        ("0.28.0", "2026-07-14", [
            "Reconocimiento inteligente de modos MÁS PRECISO: la zona-comando se ajusta sola (ventana dinámica) — corta donde la intención se entiende y conserva el resto como contenido (ej. \"modo mándale un WhatsApp a Ana, nos vemos\" reconoce WhatsApp y guarda \"a Ana, nos vemos\")",
            "El sistema se MEJORA A SÍ MISMO: nuevo \"Mejorar modos\" (Ajustes → Modos, icono varita) — analiza el registro y te dice qué reconoció mal, con un clic agregas los comandos no reconocidos como ejemplos, o pide sugerencias a tu IA. Y un registro detallado en ~/.betodicta/logs/modos.jsonl (opcional)",
            "Arreglo: la ventana de Reemplazos ya no corta el encabezado al activar \"coincidir por audio\"",
        ]),
        ("0.27.0", "2026-07-14", [
            "Reconocimiento INTELIGENTE de modos por voz (Ajustes → Avanzado, opt-in): entiende el llamado de un modo aunque lo digas de mil formas (\"modo mándale un WhatsApp…\", \"modo apúntame una tarea…\") con embeddings. Solo actúa si empieza con \"modo\" (o mal-escuchas: mudo/molde/…) y el exacto no acertó; si nada se parece, sigue como texto normal",
            "Es parametrizable (cuántas palabras del inicio se analizan + sensibilidad) y ENTRENABLE por ti: en Ajustes → Modos, cada modo tiene un campo \"Ejemplos\" para agregar TUS formas de pedirlo, procesadas con tu motor de embeddings (Ollama local o el que elijas)",
        ]),
        ("0.26.0", "2026-07-14", [
            "Glosario inteligente (Ajustes → Avanzado, opt-in): en el pulido manda a la IA solo los términos del glosario afines a lo que dictaste (con embeddings), no todos. Prompt más corto = pulido MÁS RÁPIDO, y escala aunque tu glosario crezca a cientos de términos",
            "Importar contactos de WhatsApp desde cualquier lado: auto-detecta vCard (.vcf de teléfono/iCloud/Outlook), CSV de Google/Gmail (inglés y español) y de Outlook/Edge, o CSV/JSON simple; te dice cuántos válidos/inválidos",
            "WhatsApp \"enviar a <nombre>\" más preciso: entiende el nombre aunque el dictado le ponga punto o coma, y el modal prioriza los contactos más probables (muestra hasta 6 de los que coincidan)",
        ]),
        ("0.25.0", "2026-07-14", [
            "WhatsApp con CONTACTOS: importa tu lista (CSV/JSON o export de Google/Gmail) o usa tus Contactos de Mac; di \"modo whatsapp, a Alberto, hola\" y abre su chat con el texto. Si hay varios, eliges en un modal. Exportar CSV/JSON te da el formato",
            "Modos de ACCIÓN listos para las apps de Mac por defecto: Outlook, Correo, WhatsApp, Notas, Recordatorios, Calendario, Finder, Safari, Música, Terminal, Mapas, Spotlight y tu propia web (betodicta.eztic.ec). Créalos/edítalos en Ajustes → Modos",
            "Reconocimiento por VOZ más flexible: varias frases por modo (failover ante mal-escuchas, ej. \"mudo tarea\"=\"modo tarea\") y matcheo por raíz (\"buscador\"→buscar, \"traduce\"→traducir)",
            "Cadenas por voz más robustas: tolera comas/puntos, \"modo\" repetido por etapa, y el idioma tras \"a\" (\"modo traducir a inglés correo, …\")",
            "Arreglos: idiomas con coma (\"modo traducir portugués, …\"), y \"modo <app>\" sin texto ya abre la app sin pedir contenido",
        ]),
        ("0.24.0", "2026-07-14", [
            "Modos ENCADENADOS por voz: junta un paso + una acción en una frase — \"modo traducir quichua a correo, hacer la merienda\" traduce y abre un correo con el texto; \"modo traducir inglés whatsapp, nos vemos\" traduce y abre WhatsApp. Orden-independiente y con conectores (a, y, en…) que se ignoran",
            "Frases de voz MÚLTIPLES por modo (failover ante mal-escuchas del STT): cada modo acepta varias separadas por coma (ej. Tarea: \"modo tarea, mudo tarea, molde tarea\"). Añade las tuyas en Ajustes → Modos",
            "WhatsApp con failover: abre la app de escritorio si la tienes, si no wa.me (web) y te sugiere instalarla",
            "Arreglo: decir solo el comando sin texto (\"modo tarea\" y nada más) ya no crea una tarea vacía — te avisa",
        ]),
        ("0.23.0", "2026-07-14", [
            "Tareas y notas (nueva pestaña): dicta con el modo Tarea o Nota (o \"modo tarea …\") y se guardan en una lista LOCAL en tu Mac. Marca hechas, borra, limpia o agrega a mano",
            "Nuevo modo ACCIÓN: dicta y se abre una app o página con tu texto — Nuevo correo (mailto), Outlook, WhatsApp, o abre Notas/Recordatorios/Calendario/Finder/Mensajes (copia el texto para pegar), o TU propia URL con {q} (ej. Quipux). Sin IA — hazlo un modo propio con su frase de voz (ej. \"modo whatsapp …\")",
        ]),
        ("0.22.0", "2026-07-14", [
            "FAILOVER de pulido: si tienes 2+ IAs de chat conectadas, ordénalas en Ajustes → Pulido (\"Failover de pulido\") y si la 1ª (ej. Groq) no responde, salta sola a la 2ª, 3ª… (ej. OpenAI → OpenRouter → local). El pulido ya no se queda sin funcionar por un proveedor caído",
            "Modos por VOZ con argumento: \"modo traducir quichua …\" traduce a quichua; \"modo buscar google …\" busca en Google — el dato ajusta el modo solo por ese dictado (sin argumento usa el idioma/buscador por defecto). Reconoce rellenos (\"al\", \"en\") y alias (ddg, yt, mapas…)",
            "Transcribir con selector \"Procesar como:\": aplica un modo (Correo, Oficio, Traducir…) al archivo que subes o al dictado que re-transcribes",
            "Nuevo idioma de traducción: quichua (con banderita 🇪🇨)",
        ]),
        ("0.21.0", "2026-07-13", [
            "NUEVO: MODOS — decide qué hacer con lo dictado. Además de Dictado (pulir), elige Correo, Oficio, Tarea, Nota, Traducir, Asistente o Buscar; cada modo con su propia IA y su prompt. Cámbialo al vuelo desde el notch (arriba-izquierda) o el menú de la barra, como el proveedor",
            "El modo elegido al vuelo es de UN SOLO USO: se aplica a ese dictado y vuelve al modo POR DEFECTO (configúralo en Ajustes → Modos; puedes dejarlo fijo apagando el interruptor)",
            "Activa un modo POR VOZ (empieza el dictado con 'modo tarea …'), POR APP o POR SITIO WEB (ej. en Outlook usa Correo; en Quipux usa Oficio)",
            "Modo TRADUCIR con selector de idioma (con banderita) y opción de agregar los idiomas que quieras",
            "Modo BUSCAR: dictas y se abre el buscador con tu consulta — Google, Bing, DuckDuckGo, YouTube, Google Maps, Spotlight (⌘Espacio) o una URL propia",
            "Crea tus PROPIOS modos con nombre, comportamiento, prompt e IA a tu gusto",
        ]),
        ("0.20.11", "2026-07-13", [
            "En Modelos, los motores que transcriben EN VIVO (texto mientras hablas) llevan ahora una etiqueta 'EN VIVO': locales Nemotron/Voxtral Realtime, ElevenLabs realtime, y los de nube por WebSocket (Deepgram, Soniox, AssemblyAI, Speechmatics, Gladia). Verde = activo; gris = lo soporta, actívalo en Avanzado",
            "Speechmatics en vivo más robusto: si su conexión falla, ahora cae al plan B al instante y con el motivo en el registro (antes se demoraba y no decía por qué)",
        ]),
        ("0.20.10", "2026-07-13", [
            "Ayuda por proveedor: cada IA de nube (chat y voz) tiene ahora un icono ⓘ con una explicación INSTANTÁNEA (qué es, si es gratis, si va en vivo) y un enlace 'Conseguir clave' que abre la página oficial donde sacas tu API key — sin perder tiempo buscándola",
        ]),
        ("0.20.9", "2026-07-13", [
            "Motores locales de transcripción al día: whisper.cpp (ggml 0.16.0, más allá de v1.9.1), llama.cpp (build 9976) y transcribe.cpp (v0.1.3) — mejoras de rendimiento y correcciones de los proyectos base, sin tocar tu configuración ni tus modelos",
        ]),
        ("0.20.8", "2026-07-13", [
            "MUCHOS motores de transcripción nuevos, varios GRATIS: Groq Whisper, Hugging Face y Cloudflare (gratis), Fireworks, Deepgram, AssemblyAI, Gladia y Speechmatics; y de pago premium Soniox (mejor español latino) y Azure AI Speech (con locale es-EC de Ecuador). Ollama y LM Studio locales se ofrecen solo si tienen un modelo whisper (detección inteligente)",
            "TEXTO EN VIVO también en la nube: Deepgram, Soniox, AssemblyAI, Speechmatics y Gladia pueden transcribir por WebSocket mientras hablas (actívalo en Avanzado → 'STT en vivo para la nube')",
            "7 IAs de pulido GRATIS más: Cerebras, GitHub Models, NVIDIA NIM, Together, Novita, Z.ai (GLM) y SiliconFlow; y plantilla lista de Cloudflare Workers AI (solo pones tu Account ID)",
            "Precios REALES de todos los modelos (voz y chat) y se actualizan solos desde una fuente mantenida, sin gastar IA; en Estadísticas ves además el GASTO de pulido con IA (hoy/semana/mes) con gráfica",
            "Búsqueda por SIGNIFICADO en el Historial (semántica): encuentra dictados por idea, no por palabra exacta; eliges con cuál IA se calcula (Ollama local gratis, OpenAI, Gemini o Mistral)",
            "Tu gateway propio ahora también puede TRANSCRIBIR (antes solo pulía); y salvaguarda anti-inyección opcional para IAs de terceros",
        ]),
        ("0.20.7", "2026-07-12", [
            "Pulir/traducir con Anthropic (Claude) y Gemini (Google) — se suman a Groq, OpenAI, Mistral, OpenRouter, DeepSeek y xAI. Pon tu key en 'Conectar más IAs'",
            "Push-to-talk: opción para grabar mientras MANTIENES la tecla y terminar al soltarla (Ajustes → General). El modo toque sigue de default",
            "Detección de IA local EN VIVO: LM Studio / Ollama recién abiertos ya se detectan sin reiniciar la app; y elige un modelo de CHAT por defecto (no uno de embeddings)",
        ]),
        ("0.20.6", "2026-07-12", [
            "El selector de pulido muestra 'proveedor · modelo', y puedes elegir el modelo de CUALQUIER IA (nube, local o gateway) al vuelo con el botón 'Descubrir', no solo de los gateways",
            "Descubrir modelos trae el PRECIO por modelo cuando el proveedor lo publica (ej. OpenRouter): '$in/$out por millón de tokens' o 'gratis'",
            "Aviso de privacidad al pulir con una IA de nube o gateway de terceros (tu texto sale de tu Mac) — configurable en Avanzado. Si el gateway usa http sin cifrar, la API key ya no se envía",
            "Descubrir prueba más rutas (/v1/models, /openai/v1/models, /api/v1/models) y acepta una ruta manual para gateways raros",
            "La app no se cuelga al abrir sin internet (el chequeo de actualización es asíncrono y falla rápido)",
        ]),
        ("0.20.5", "2026-07-12", [
            "SEGURIDAD: la actualización ahora VERIFICA la firma del DMG antes de instalar — solo se instala si viene firmado con el mismo certificado de la app; un release manipulado se rechaza. Se quitó el borrado a ciegas de la cuarentena.",
            "SEGURIDAD: las API keys y los gateways (.env, config, personalizadas) se guardan con permisos 0600 (solo tú), y la key no se manda si el gateway usa http sin cifrar.",
            "Auditoría de seguridad completa del sistema (revisión adversarial) — sin puertas traseras ni fugas; correcciones aplicadas.",
        ]),
        ("0.20.4", "2026-07-12", [
            "La app avisa sola: al abrir revisa si hay versión nueva y te lo muestra abajo-izquierda ('Actualización disponible') y en el menú de la barra — puedes ver las novedades antes de actualizar",
            "Nuevo en Avanzado: 'Autoactualizar' (baja e instala sola la versión nueva) y 'Buscar actualización al abrir' (ambos parametrizables)",
            "Gateways propios: 'Descubrir modelos' ahora guarda TODOS los modelos y puedes elegir cualquiera al vuelo desde Ajustes → Pulido, sin abrir el editor",
            "Se puede instalar/actualizar por Homebrew: 'brew install --cask --force' para adoptar una instalación previa; 'brew upgrade --greedy' para traer la última",
        ]),
        ("0.20.3", "2026-07-12", [
            "Descubrir modelos en gateways propios ahora SÍ encuentra la lista aunque tu URL base no lleve /v1: lo prueba solo y te avisa que la API está bajo /v1",
            "El actualizador muestra el PORCENTAJE de descarga con barra de progreso (antes solo decía 'descargando')",
            "Las secciones plegables (Avanzado, Conectar más IAs) se abren al hacer clic en TODO el título, no solo en la flechita",
        ]),
        ("0.20.2", "2026-07-12", [
            "El ícono de la barra de menú ahora REACCIONA: late en rojo mientras grabas y en morado mientras procesa/pule; vuelve a normal al terminar",
            "En el aviso de novedades, botón 'Revisar todas las novedades' que abre Créditos con el historial completo",
        ]),
        ("0.20.1", "2026-07-12", [
            "Más IAs para pulir/traducir: DeepSeek, xAI (Grok), y GATEWAYS personalizados (tu propia URL base, API key, esquema de auth Bearer/X-API-Key/encabezado propio, encabezados extra y descubrimiento de modelos)",
            "Las novedades de la actualización ahora se ven bien formateadas (ya no en texto plano)",
        ]),
        ("0.20.0", "2026-07-12", [
            "Pulido y traducción con CUALQUIER IA conectada: Groq, OpenAI, Mistral, OpenRouter — y hasta LOCAL (LM Studio, Ollama), que se detectan solos si están corriendo. Elige cuál en Ajustes → Pulido",
            "El pulido ya no se cae por cortes de red (reintenta solo) y su espera es ajustable (Avanzado), más larga para textos largos",
            "Al terminar un dictado, opcional: añadir un espacio, pulsar Enter (enviar en chats) o Shift+Enter (salto de línea)",
            "Reemplazos: botón 'probar' (ver qué caza la fonética) y 'escuchar' la pronunciación; y coincidencia por AUDIO experimental (reconoce tus términos por tu propia voz grabada, con soporte de siglas)",
        ]),
        ("0.19.1", "2026-07-11", [
            "Asistente de primer arranque: te guía en 8 pasos por permisos, IA de nube y local, el orden del failover, aprendizaje y preferencias — con check en vivo de los permisos",
            "La app aprende de ti: corriges una palabra donde la pegaste (Kipux → Quipux) y la recuerda sola. En la terminal o Claude Code, selecciónala y pulsa ⌘⇧L",
            "Corrección por sonido (fonética): corrige lo que SUENA como un término tuyo, término por término y siempre reversible",
            "Revierte lo aprendido desde Estadísticas, y apoya el proyecto con un cafecito ☕",
            "Precios por MODELO (no por proveedor) y editables: cada modelo con su costo real, y el gasto del mes se calcula por el modelo que de verdad se usó",
        ]),
        ("0.18.0", "2026-07-10", [
            "Pestaña Historial: todos tus dictados con buscador (sin distinguir tildes), escuchar el audio, copiar y abrir en Finder",
            "OpenAI y Mistral (Voxtral nube) ya funcionan de verdad: pon tu key en Modelos y actívalos en la cascada",
            "Descargas de modelos en segundo plano + botón ✕ para cancelarlas",
            "'Guardado ✓' al guardar la API key y ⌘V/⌘C funcionan en todos los campos",
        ]),
        ("0.17.2", "2026-07-10", [
            "Las API keys viven solo en la configuración de la app (adiós rutas de la máquina del desarrollador)",
            "Mensaje claro cuando falta la key: 'ponla en Configuración → Modelos'",
            "Instrucciones de primera apertura al día para macOS moderno",
        ]),
        ("0.17.1", "2026-07-10", [
            "La app trae TODOS los motores dentro: Voxtral Mini 3B ya no pide instalar nada (adiós brew) — descargar, arrastrar y dictar",
        ]),
        ("0.17.0", "2026-07-10", [
            "Conmutación de motor EN CALIENTE: cambia de IA a mitad del dictado y el motor nuevo retoma todo lo dicho — sin perder una palabra",
            "Selector rápido de proveedor: desde el menú de la barra o con un clic sobre el letrero del notch",
            "El log y las estadísticas nombran el motor exacto (Voxtral/Nemotron en vivo)",
            "betodicta.eztic.ec es la página oficial (en Créditos y README)",
        ]),
        ("0.16.7", "2026-07-10", [
            "Dictados seguidos con ElevenLabs ya no caen a Whisper: el cierre normal de un dictado exitoso contaba como fallo de red (falsa cuarentena)",
            "El plan B en vivo respeta TU orden de la cascada (Whisper #2 antes que Nemotron #3)",
            "Un dictado vacío ya no pega frases raras del pulido ('No hay transcripción para limpiar')",
        ]),
        ("0.16.6", "2026-07-10", [
            "Blindaje final contra el cierre inesperado al dictar con red lenta (doble arranque del grabador)",
        ]),
        ("0.16.5", "2026-07-10", [
            "El notch te dice con qué motor dictas: letrero encima del fn (verde = en vivo, gris = al soltar) que rota cuando el failover conmuta",
        ]),
        ("0.16.4", "2026-07-10", [
            "Failover TRANSPARENTE: el micrófono arranca al instante y si la nube no responde en 4s, el streaming local toma el mando con todo tu audio — sin esperas ni errores",
            "Si la red muere a MITAD del dictado, el audio completo se rescata por la cascada (ya no se pega un pedazo)",
            "Blindaje interno: 8 arreglos de concurrencia y ciclos de vida (dictados consecutivos rápidos, audio duplicado, cierres)",
        ]),
        ("0.16.3", "2026-07-10", [
            "Red caída sin drama: si el streaming falla, el próximo dictado graba directo (sin esperar 'Conectando…')",
            "La nube lenta ya no te frena: a los 15s salta al motor local automáticamente",
        ]),
        ("0.16.2", "2026-07-10", [
            "Micrófono fijado al integrado del Mac: el iPhone cercano (Continuity) ya no roba el micrófono y deja el dictado mudo",
            "Selector de micrófono en Ajustes (integrado / automático / cualquiera conectado)",
        ]),
        ("0.16.1", "2026-07-10", [
            "Release de prueba del actualizador: si estás leyendo esto desde la app, ¡la actualización con un clic funcionó! 🎉",
        ]),
        ("0.16.0", "2026-07-10", [
            "Actualización con un clic: la app revisa GitHub, descarga la versión nueva y se reinstala sola",
            "Botón 'Verificar actualización' junto a la versión",
        ]),
        ("0.15.0", "2026-07-10", [
            "Proveedores separados por familia: Voxtral, Nemotron y Canary, cada uno con su switch y su modelo",
            "Cascada de failover con arrastre (drag & drop) y etiquetas EN VIVO",
            "Instalador DMG y sistema de versiones visible",
        ]),
        ("0.14.0", "2026-07-10", [
            "Dictado EN VIVO 100% local: Voxtral Realtime 4B y Nemotron 3.5 Streaming (motor transcribe.cpp)",
            "Canary 1B Flash por lotes (93x tiempo real)",
            "Texto en vivo también con Whisper local (re-transcripción caliente)",
        ]),
        ("0.13.0", "2026-07-10", [
            "Voxtral Mini 3B local (llama.cpp) en la cascada",
            "Glosario universal: los términos llegan a TODOS los motores",
            "Ventana rediseñada con barra lateral escalable",
        ]),
        ("0.12.0", "2026-07-10", [
            "Whisper local residente bajo demanda: carga al dictar, se apaga solo a los 120s",
            "Rescate automático de dictados tras cierres inesperados",
            "Catálogo de modelos Whisper descargables y API keys por proveedor",
        ]),
        ("0.10.0", "2026-07-09", [
            "Failover multi-proveedor: ElevenLabs → Groq → Whisper local",
            "CRUD de glosario y reemplazos, estadísticas con gráficas, log total",
            "Transcripción de archivos y re-transcripción del historial",
        ]),
        ("0.7.0", "2026-07-09", [
            "Pausa real de música y videos al dictar (mediaremote-adapter)",
            "Firma estable: los permisos ya no se pierden al actualizar",
        ]),
        ("0.4.0", "2026-07-09", [
            "Esc cancela, sonidos, autoarranque, modo estudio",
            "Historial caja negra: audio y texto a disco mientras dictas",
        ]),
        ("0.1.0", "2026-07-09", [
            "Nace BetoDicta: fn para dictar, ElevenLabs Scribe, panel del notch",
        ]),
    ]
}

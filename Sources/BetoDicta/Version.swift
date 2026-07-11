import Foundation

// MARK: - Versión de la app (UN solo lugar; actualizar aquí en cada release)
//
// La UI (sidebar, Créditos, menú) lee de aquí. El Makefile inyecta
// Version.numero al Info.plist del bundle (CFBundleShortVersionString).

enum Version {
    static let numero = "0.19.1"
    static let fecha = "2026-07-11"

    /// Historial literal, la más nueva primero. Se muestra en Créditos.
    static let historial: [(version: String, fecha: String, cambios: [String])] = [
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

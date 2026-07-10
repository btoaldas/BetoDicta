import Foundation

// MARK: - Versión de la app (UN solo lugar; actualizar aquí en cada release)
//
// La UI (sidebar, Créditos, menú) lee de aquí. El Makefile inyecta
// Version.numero al Info.plist del bundle (CFBundleShortVersionString).

enum Version {
    static let numero = "0.16.6"
    static let fecha = "2026-07-10"

    /// Historial literal, la más nueva primero. Se muestra en Créditos.
    static let historial: [(version: String, fecha: String, cambios: [String])] = [
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

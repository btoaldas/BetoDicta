import Foundation

// MARK: - Versión de la app (UN solo lugar; actualizar aquí en cada release)
//
// La UI (sidebar, Créditos, menú) lee de aquí. El Makefile inyecta
// Version.numero al Info.plist del bundle (CFBundleShortVersionString).

enum Version {
    static let numero = "0.16.0"
    static let fecha = "2026-07-10"

    /// Historial literal, la más nueva primero. Se muestra en Créditos.
    static let historial: [(version: String, fecha: String, cambios: [String])] = [
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

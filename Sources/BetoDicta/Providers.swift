import Foundation

// MARK: - Proveedores de transcripción (nube y local) con orden y failover

/// Un proveedor de transcripción. El orden define la cascada de failover:
/// se intenta el activo #1; si falla, el #2; y así.
struct Provider: Codable, Identifiable {
    var id: String            // "elevenlabs", "groq", "whisper_local"
    var nombre: String
    var tipo: String          // "nube" | "local"
    var activo: Bool
    var orden: Int
}

enum Providers {
    private static var url: URL { Config.dir.appendingPathComponent("providers.json") }

    static let porDefecto: [Provider] = [
        Provider(id: "elevenlabs", nombre: "ElevenLabs Scribe", tipo: "nube", activo: true, orden: 0),
        Provider(id: "groq", nombre: "Groq Whisper", tipo: "nube", activo: true, orden: 1),
        Provider(id: "whisper_local", nombre: "Whisper local", tipo: "local", activo: false, orden: 2),
    ]

    static func load() -> [Provider] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Provider].self, from: data), !list.isEmpty else {
            save(porDefecto)
            return porDefecto
        }
        return list.sorted { $0.orden < $1.orden }
    }

    static func save(_ list: [Provider]) {
        var ordenados = list
        for i in ordenados.indices { ordenados[i].orden = i }
        if let data = try? JSONEncoder().encode(ordenados) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// La cadena de failover: activos en orden.
    static func cadena() -> [Provider] {
        load().filter { $0.activo }
    }
}

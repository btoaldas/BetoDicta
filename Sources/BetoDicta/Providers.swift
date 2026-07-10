import Foundation

// MARK: - Proveedores de transcripción (nube y local) con orden y failover

/// Un proveedor de transcripción. El orden define la cascada de failover:
/// se intenta el activo #1; si falla, el #2; y así.
struct Provider: Codable, Identifiable {
    var id: String            // "elevenlabs", "groq", "openai", "mistral", "whisper_local"
    var nombre: String
    var tipo: String          // "nube" | "local"
    var activo: Bool
    var orden: Int
    var modelo: String?       // modelo elegido (cloud) o archivo ggml (local)
}

enum Providers {
    private static var url: URL { Config.dir.appendingPathComponent("providers.json") }

    static let porDefecto: [Provider] = [
        Provider(id: "elevenlabs", nombre: "ElevenLabs Scribe", tipo: "nube", activo: true, orden: 0, modelo: "scribe_v2"),
        Provider(id: "groq", nombre: "Groq Whisper", tipo: "nube", activo: true, orden: 1, modelo: "whisper-large-v3"),
        Provider(id: "whisper_local", nombre: "Whisper local", tipo: "local", activo: false, orden: 2, modelo: "ggml-large-v3-turbo.bin"),
    ]

    /// Proveedores cloud que se pueden añadir (con su config de conexión).
    static let cloudDisponibles: [(id: String, nombre: String, modelos: [String], keyEnv: String)] = [
        ("elevenlabs", "ElevenLabs Scribe", ["scribe_v2_realtime", "scribe_v2", "scribe_v1"], "ELEVENLABS_API_KEY"),
        ("groq", "Groq Whisper", ["whisper-large-v3", "whisper-large-v3-turbo"], "GROQ_API_KEY"),
        ("openai", "OpenAI", ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"], "OPENAI_API_KEY"),
        ("mistral", "Mistral (Voxtral)", ["voxtral-mini-latest", "voxtral-small-latest"], "MISTRAL_API_KEY"),
    ]

    /// Proveedores que se agregan a configs existentes cuando salen en una
    /// versión nueva (apagados, al final — el usuario decide activarlos).
    static let nuevos: [Provider] = [
        Provider(id: "voxtral_local", nombre: "Voxtral local", tipo: "local", activo: false,
                 orden: 99, modelo: "Voxtral-Mini-3B-2507-Q4_K_M.gguf"),
        Provider(id: "tcpp_local", nombre: "Nemotron/Canary local", tipo: "local", activo: false,
                 orden: 100, modelo: "nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf"),
    ]

    static func load() -> [Provider] {
        guard let data = try? Data(contentsOf: url),
              var list = try? JSONDecoder().decode([Provider].self, from: data), !list.isEmpty else {
            save(porDefecto + nuevos)
            return porDefecto + nuevos
        }
        // Migración: sumar proveedores nuevos que el JSON viejo no conoce.
        // Sin recursión: si save() fallara (disco lleno), igual devolvemos
        // la lista migrada en memoria y la app sigue funcionando.
        let faltantes = nuevos.filter { n in !list.contains { $0.id == n.id } }
        if !faltantes.isEmpty {
            list.append(contentsOf: faltantes)
            save(list)
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

    static func cadena() -> [Provider] { load().filter { $0.activo } }

    static func modelo(de id: String) -> String? {
        load().first { $0.id == id }?.modelo
    }
}

// MARK: - Gestión de claves de API en ~/.betodicta/.env

enum ApiKeys {
    private static var envURL: URL { Config.dir.appendingPathComponent(".env") }

    static func get(_ envName: String) -> String {
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n") where line.hasPrefix("\(envName)=") {
            return String(line.dropFirst(envName.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    static func set(_ envName: String, _ value: String) {
        var lineas = (try? String(contentsOf: envURL, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init) ?? []
        lineas.removeAll { $0.hasPrefix("\(envName)=") }
        if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            lineas.append("\(envName)=\(value.trimmingCharacters(in: .whitespaces))")
        }
        let out = lineas.filter { !$0.isEmpty }.joined(separator: "\n") + "\n"
        try? out.write(to: envURL, atomically: true, encoding: .utf8)
        Log.log(.config, "API key actualizada: \(envName)")
    }
}

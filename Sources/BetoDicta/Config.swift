import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Configuración

struct Config {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".betodicta")

    private static func json() -> [String: Any] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    static func hotkey() -> String { (json()["tecla"] as? String) ?? "fn" }
    static func maxSilence() -> TimeInterval { (json()["silencio_max_seg"] as? Double) ?? 120 }
    static func sounds() -> Bool { (json()["sonidos"] as? Bool) ?? true }
    static func escCancels() -> Bool { (json()["esc_cancela"] as? Bool) ?? true }
    static func duckMedia() -> Bool { (json()["atenuar_multimedia"] as? Bool) ?? true }
    static func duckVolume() -> Int { (json()["volumen_dictado"] as? Int) ?? 1 }
    static func model() -> String { (json()["modelo"] as? String) ?? "scribe_v2_realtime" }

    /// Busca la API key en orden: variable de entorno → ~/.betodicta/.env → ~/.hermes/.env
    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !env.isEmpty {
            return env
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for envFile in [dir.appendingPathComponent(".env"), home.appendingPathComponent(".hermes/.env")] {
            guard let text = try? String(contentsOf: envFile, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.hasPrefix("ELEVENLABS_API_KEY=") {
                let key = String(line.dropFirst("ELEVENLABS_API_KEY=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty { return key }
            }
        }
        return nil
    }

    static func keyterms() -> [String] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("keyterms.txt"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    struct Replacement: Decodable {
        let original: String
        let replacement: String
    }

    static func replacements() -> [Replacement] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("reemplazos.json")),
              let rules = try? JSONDecoder().decode([Replacement].self, from: data) else { return [] }
        return rules
    }
}


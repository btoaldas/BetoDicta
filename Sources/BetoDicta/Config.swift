import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Configuración

struct Config {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".betodicta")

    private static let lock = NSLock()
    private static var cache: [String: Any]?

    private static func json() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        if let c = cache { return c }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return cache ?? [:] }
        cache = obj
        return obj
    }

    static func hotkey() -> String { (json()["tecla"] as? String) ?? "fn" }
    static func maxSilence() -> TimeInterval { (json()["silencio_max_seg"] as? Double) ?? 120 }
    static func sounds() -> Bool { (json()["sonidos"] as? Bool) ?? true }
    static func escCancels() -> Bool { (json()["esc_cancela"] as? Bool) ?? true }
    static func duckMedia() -> Bool { (json()["atenuar_multimedia"] as? Bool) ?? true }
    static func duckVolume() -> Int { (json()["volumen_dictado"] as? Int) ?? 1 }
    static func postProcess() -> Bool { (json()["post_proceso"] as? Bool) ?? false }
    static func customPrompt() -> String? {
        guard let s = json()["prompt_pulido"] as? String, !s.isEmpty else { return nil }
        return s
    }
    static func pausePlayback() -> Bool { (json()["pausar_multimedia"] as? Bool) ?? true }
    static func devMode() -> Bool { (json()["modo_desarrollo"] as? Bool) ?? false }
    static func showInDock() -> Bool { (json()["mostrar_en_dock"] as? Bool) ?? false }
    static func muteToo() -> Bool { (json()["silenciar_ademas"] as? Bool) ?? false }
    static func translate() -> Bool { (json()["traducir"] as? Bool) ?? false }
    static func translateTo() -> String { (json()["traducir_idioma"] as? String) ?? "inglés" }
    static func panelVisible() -> Bool { (json()["panel_visible"] as? Bool) ?? true }
    static func exportFolder() -> URL {
        if let s = json()["carpeta_exportar"] as? String, !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static func groqKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !env.isEmpty { return env }
        let envFile = dir.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("GROQ_API_KEY=") {
            let key = String(line.dropFirst("GROQ_API_KEY=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        return nil
    }

    /// Escribe un valor en config.json de forma ATÓMICA y serializada, para
    /// que la GUI y el dictado no corrompan el archivo al leer/escribir a la vez.
    static func set(_ key: String, to value: Any) {
        lock.lock()
        var obj = cache ?? {
            (try? Data(contentsOf: dir.appendingPathComponent("config.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        }()
        obj[key] = value
        cache = obj
        lock.unlock()
        Log.log(.config, "cambio: \(key) = \(value)")
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("config.json"), options: .atomic)
        }
    }
    static func model() -> String { (json()["modelo"] as? String) ?? "scribe_v2_realtime" }
    /// Segundos que el whisper-server local vive tras el último uso (mín. 10).
    static func whisperKeepAlive() -> TimeInterval { max(10, (json()["whisper_keepalive"] as? Double) ?? 120) }
    /// Micrófono: "" = integrado del Mac (default anti-iPhone) · "auto" =
    /// el del sistema · UID = dispositivo específico.
    static func microfono() -> String { (json()["microfono"] as? String) ?? "" }

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

    /// Glosario como "initial prompt" para motores familia Whisper (Groq,
    /// whisper-cli, whisper-server, y futuros OpenAI/Mistral). Una frase en
    /// español sesga mejor que una lista pelada. Vacío si no hay términos.
    /// Tope 80 términos: el initial prompt de Whisper admite ~224 tokens y
    /// trunca por el INICIO, así que pasarse silenciosamente pierde términos.
    static func glosarioPrompt() -> String {
        let terms = keyterms().prefix(80)
        guard !terms.isEmpty else { return "" }
        return "Glosario: \(terms.joined(separator: ", "))."
    }

    struct Replacement: Decodable {
        let original: String
        let replacement: String
        let isRegex: Bool?
        let activo: Bool?
    }

    /// Solo las reglas activas (las desactivadas se conservan pero no se aplican).
    static func replacements() -> [Replacement] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("reemplazos.json")),
              let rules = try? JSONDecoder().decode([Replacement].self, from: data) else { return [] }
        return rules.filter { $0.activo ?? true }
    }
}


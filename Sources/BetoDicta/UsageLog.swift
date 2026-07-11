import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Estadísticas de uso (odómetro por proveedor)

struct UsageLog {
    static var fileURL: URL { Config.dir.appendingPathComponent("uso.jsonl") }
    /// Tarifas por defecto (USD/hora de audio, 2026), por MODELO exacto.
    /// Refs: elevenlabs.io/pricing/api · openai.com/api/pricing · mistral.ai/pricing · groq.com/pricing
    static let tarifasDefecto: [String: Double] = [
        // ElevenLabs
        "scribe_v2_realtime": 0.39, "scribe_v2": 0.22, "scribe_v1": 0.22,
        // Groq
        "whisper-large-v3": 0.11, "whisper-large-v3-turbo": 0.04,
        // OpenAI
        "whisper-1": 0.36, "gpt-4o-transcribe": 0.36, "gpt-4o-mini-transcribe": 0.18,
        // Mistral (Voxtral nube)
        "voxtral-mini-latest": 0.18, "voxtral-small-latest": 0.24,
        // (modelos locales / GGUF → no listados → $0, gratis)
    ]

    /// Fallback por MOTOR para registros viejos sin modelo guardado.
    static let tarifaProveedorFallback: [String: Double] = [
        "ElevenLabs": 0.39, "Groq": 0.04, "OpenAI": 0.18, "Mistral": 0.18,
    ]

    /// Tarifa efectiva de un MODELO: la que tú pusiste, o la de referencia.
    /// Modelos locales no están → gratis ($0).
    static func tarifaModelo(_ modelo: String) -> Double {
        Config.tarifa(modelo) ?? tarifasDefecto[modelo] ?? 0
    }

    /// Tarifa de un registro: por su modelo si lo tiene; si no (registro
    /// viejo), fallback por motor canónico.
    static func tarifaRegistro(modelo: String?, motor: String) -> Double {
        if let m = modelo, !m.isEmpty { return tarifaModelo(m) }
        return tarifaProveedorFallback[motor] ?? 0
    }

    /// Texto de referencia de precios para mostrar en la app.
    static let referenciaPrecios = "Precios aprox. por hora de audio (2026): ElevenLabs ~$0.39 (en vivo) / $0.22 (lotes) · OpenAI ~$0.18–0.36 · Mistral Voxtral ~$0.18–0.36 · Groq ~$0.04–0.11 · motores locales GRATIS. Ajústalos por modelo en Modelos."

    /// Consolida las MUCHAS etiquetas históricas ("scribe_v2_realtime",
    /// "ElevenLabs (en vivo)", "ElevenLabs Scribe"…) en un motor único —
    /// sin esto el uso salía fragmentado y con líneas viejas en 0.
    static func motorCanonico(_ p: String) -> String {
        let s = p.lowercased()
        if s.contains("eleven") || s.contains("scribe") { return "ElevenLabs" }
        if s.contains("groq") { return "Groq" }
        if s.contains("voxtral") { return "Voxtral" }
        if s.contains("nemotron") { return "Nemotron" }
        if s.contains("canary") { return "Canary" }
        if s.contains("whisper") { return "Whisper" }
        if s.contains("openai") { return "OpenAI" }
        if s.contains("mistral") { return "Mistral" }
        if s.contains("local") { return "Local" }
        return p
    }

    static func record(provider: String, modelo: String = "", seconds: Double) {
        let iso = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "fecha": iso, "proveedor": motorCanonico(provider), "modelo": modelo, "segundos": seconds,
        ]), var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let handle = FileHandle(forWritingAtPath: fileURL.path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    struct Totales {
        var hoyMin = 0.0, semanaMin = 0.0, mesMin = 0.0, añoMin = 0.0
        var mesCosto = 0.0
        var dictadosHoy = 0
        var porDiaSemana: [Double] = Array(repeating: 0, count: 7)  // últimos 7 días, en minutos
    }

    /// Datos numéricos para las gráficas del panel de estadísticas.
    static func totales() -> Totales {
        var t = Totales()
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return t }
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let now = Date()
        let día = cal.startOfDay(for: now)
        let semana = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? día
        let mes = cal.dateInterval(of: .month, for: now)?.start ?? día
        let año = cal.dateInterval(of: .year, for: now)?.start ?? día

        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fechaStr = json["fecha"] as? String,
                  let fecha = iso.date(from: fechaStr),
                  let seg = json["segundos"] as? Double else { continue }
            let prov = motorCanonico(json["proveedor"] as? String ?? "")
            let mod = json["modelo"] as? String
            let min = seg / 60
            if fecha >= año { t.añoMin += min }
            if fecha >= mes {
                t.mesMin += min
                t.mesCosto += tarifaRegistro(modelo: mod, motor: prov) * seg / 3600
            }
            if fecha >= semana { t.semanaMin += min }
            if fecha >= día { t.hoyMin += min; t.dictadosHoy += 1 }
            // últimos 7 días
            let diasAtras = cal.dateComponents([.day], from: cal.startOfDay(for: fecha), to: día).day ?? 99
            if diasAtras >= 0 && diasAtras < 7 { t.porDiaSemana[6 - diasAtras] += min }
        }
        return t
    }

    /// Minutos por proveedor en [hoy, semana, mes, año] + costo estimado del mes.
    static func resumen() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ["Sin uso registrado todavía"]
        }
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let now = Date()
        let día = cal.startOfDay(for: now)
        let semana = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? día
        let mes = cal.dateInterval(of: .month, for: now)?.start ?? día
        let año = cal.dateInterval(of: .year, for: now)?.start ?? día

        var acc: [String: (d: Double, s: Double, m: Double, a: Double, costo: Double)] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fechaStr = json["fecha"] as? String,
                  let fecha = iso.date(from: fechaStr),
                  let proveedorRaw = json["proveedor"] as? String,
                  let seg = json["segundos"] as? Double else { continue }
            let proveedor = motorCanonico(proveedorRaw)
            var t = acc[proveedor] ?? (0, 0, 0, 0, 0)
            if fecha >= año { t.a += seg }
            if fecha >= mes {
                t.m += seg
                t.costo += tarifaRegistro(modelo: json["modelo"] as? String, motor: proveedor) * seg / 3600
            }
            if fecha >= semana { t.s += seg }
            if fecha >= día { t.d += seg }
            acc[proveedor] = t
        }
        guard !acc.isEmpty else { return ["Sin uso registrado todavía"] }

        func fmt(_ seg: Double) -> String {
            seg >= 60 ? String(format: "%.1fm", seg / 60) : String(format: "%.0fs", seg)
        }
        var lines: [String] = []
        for (proveedor, t) in acc.sorted(by: { $0.value.a > $1.value.a }) {
            lines.append("\(proveedor): hoy \(fmt(t.d)) · sem \(fmt(t.s)) · mes \(fmt(t.m)) · año \(fmt(t.a)) (mes ≈ $\(String(format: "%.2f", t.costo)))")
        }
        return lines
    }
}


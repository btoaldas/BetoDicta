import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Estadísticas de uso (odómetro por proveedor)

struct UsageLog {
    static var fileURL: URL { Config.dir.appendingPathComponent("uso.jsonl") }
    /// Tarifa estimada por hora, por MOTOR canónico (los locales = gratis).
    static let tarifasPorHora: [String: Double] = [
        "ElevenLabs": 0.39, "Groq": 0.0, "OpenAI": 0.36, "Mistral": 0.0,
    ]

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

    static func record(provider: String, seconds: Double) {
        let iso = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "fecha": iso, "proveedor": motorCanonico(provider), "segundos": seconds,
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
            let min = seg / 60
            if fecha >= año { t.añoMin += min }
            if fecha >= mes {
                t.mesMin += min
                t.mesCosto += (tarifasPorHora[prov] ?? 0) * seg / 3600
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

        var acc: [String: (d: Double, s: Double, m: Double, a: Double)] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fechaStr = json["fecha"] as? String,
                  let fecha = iso.date(from: fechaStr),
                  let proveedorRaw = json["proveedor"] as? String,
                  let seg = json["segundos"] as? Double else { continue }
            let proveedor = motorCanonico(proveedorRaw)
            var t = acc[proveedor] ?? (0, 0, 0, 0)
            if fecha >= año { t.a += seg }
            if fecha >= mes { t.m += seg }
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
            let costo = (tarifasPorHora[proveedor] ?? 0) * t.m / 3600
            lines.append("\(proveedor): hoy \(fmt(t.d)) · sem \(fmt(t.s)) · mes \(fmt(t.m)) · año \(fmt(t.a)) (mes ≈ $\(String(format: "%.2f", costo)))")
        }
        return lines
    }
}


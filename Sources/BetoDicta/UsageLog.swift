import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Estadísticas de uso (odómetro por proveedor)

struct UsageLog {
    static var fileURL: URL { Config.dir.appendingPathComponent("uso.jsonl") }
    static let tarifasPorHora: [String: Double] = [
        "scribe_v2_realtime": 0.39, "scribe_v2": 0.22, "scribe_v1": 0.22,
    ]

    static func record(provider: String, seconds: Double) {
        let iso = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "fecha": iso, "proveedor": provider, "segundos": seconds,
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
                  let proveedor = json["proveedor"] as? String,
                  let seg = json["segundos"] as? Double else { continue }
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


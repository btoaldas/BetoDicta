import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Historial (caja negra: voz + texto a disco EN VIVO)

final class HistoryWriter {
    private let base: URL
    private var pcmHandle: FileHandle?
    private var lastTextWrite = Date.distantPast

    var wavURL: URL { base.appendingPathExtension("wav") }
    var txtURL: URL { base.appendingPathExtension("txt") }
    private var pcmURL: URL { base.appendingPathExtension("pcm") }

    static var historyDir: URL { Config.dir.appendingPathComponent("historial") }

    init() {
        let dir = Self.historyDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        func part(_ format: String) -> String {
            let f = DateFormatter()
            f.dateFormat = format
            return f.string(from: now)
        }
        // Estructura anidada: historial/2026/07/09/HH-mm-ss.*
        let dayDir = dir
            .appendingPathComponent(part("yyyy"))
            .appendingPathComponent(part("MM"))
            .appendingPathComponent(part("dd"))
        try? FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        base = dayDir.appendingPathComponent(part("HH-mm-ss"))
        FileManager.default.createFile(atPath: pcmURL.path, contents: nil)
        pcmHandle = try? FileHandle(forWritingTo: pcmURL)
    }

    /// Audio crudo a disco al instante — sobrevive a cualquier crash.
    func append(chunk: Data) {
        pcmHandle?.write(chunk)
    }

    /// Texto parcial a disco (máx. 2 escrituras/seg para no castigar el SSD).
    func savePartial(_ text: String, force: Bool = false) {
        guard force || Date().timeIntervalSince(lastTextWrite) > 0.5 else { return }
        lastTextWrite = Date()
        try? text.write(to: txtURL, atomically: true, encoding: .utf8)
    }

    /// Cierre normal: WAV con cabecera + texto final; borra el crudo temporal.
    func finish(wav: Data, finalText: String) {
        try? pcmHandle?.close()
        pcmHandle = nil
        try? wav.write(to: wavURL)
        if !finalText.isEmpty {
            try? finalText.write(to: txtURL, atomically: true, encoding: .utf8)
        }
        try? FileManager.default.removeItem(at: pcmURL)
    }

    /// Cierre sin dictado útil: borra los restos vacíos.
    func discard() {
        try? pcmHandle?.close()
        pcmHandle = nil
        try? FileManager.default.removeItem(at: pcmURL)
        try? FileManager.default.removeItem(at: txtURL)
    }
}


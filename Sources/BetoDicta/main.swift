// BetoDicta v0.2 — dictado por voz de Alberto Aldás
// <tecla>: abre panel y graba · <tecla> otra vez: transcribe y pega
// Streaming en vivo (scribe_v2_realtime) o batch (scribe_v1 / scribe_v2)
//
// Config ~/.betodicta/config.json: {"tecla": "fn", "modelo": "scribe_v2_realtime"}
//   tecla: fn | F1..F12
//   modelo: scribe_v2_realtime (texto en vivo) | scribe_v2 | scribe_v1 (batch)
// ~/.betodicta/keyterms.txt — una palabra por línea (streaming usa las primeras 50)
// ~/.betodicta/reemplazos.json — [{"original":"a, b","replacement":"X"}]
// API key: ELEVENLABS_API_KEY en ~/.hermes/.env

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

// MARK: - Reemplazos (palabra completa, sin distinguir mayúsculas)

func applyReplacements(_ text: String) -> String {
    var result = text
    let rules = Config.replacements().sorted { $0.original.count > $1.original.count }
    for rule in rules {
        let variants = rule.original.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for variant in variants {
            let escaped = NSRegularExpression.escapedPattern(for: variant)
            let pattern = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacement))
        }
    }
    return result
}

// MARK: - Grabadora (micrófono → PCM16 16 kHz mono, con chunks y nivel)

final class Recorder {
    private let engine = AVAudioEngine()
    private var samples = Data()
    private var converter: AVAudioConverter?
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    var onChunk: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?
    private(set) var isRecording = false

    func start() throws {
        samples = Data()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: outFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let ratio = self.outFormat.sampleRate / inFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: self.outFormat, frameCapacity: capacity) else { return }
            var served = false
            converter.convert(to: out, error: nil) { _, status in
                if served {
                    status.pointee = .noDataNow
                    return nil
                }
                served = true
                status.pointee = .haveData
                return buffer
            }
            guard out.frameLength > 0, let ch = out.int16ChannelData else { return }
            let chunk = Data(bytes: ch[0], count: Int(out.frameLength) * 2)
            self.samples.append(chunk)
            self.onChunk?(chunk)

            var sum: Double = 0
            let n = Int(out.frameLength)
            for i in 0..<n {
                let v = Double(ch[0][i]) / 32768.0
                sum += v * v
            }
            let rms = Float((sum / Double(max(n, 1))).squareRoot())
            let boosted = Float(pow(Double(min(rms * 12, 1.0)), 0.5))
            self.onLevel?(boosted)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return wavFile(from: samples)
    }

    private func wavFile(from pcm: Data) -> Data {
        var wav = Data()
        let sampleRate: UInt32 = 16000
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + pcm.count).littleEndian)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian)
        append(UInt16(1).littleEndian)
        append(sampleRate.littleEndian)
        append(UInt32(sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian)
        append(UInt16(16).littleEndian)
        wav.append("data".data(using: .ascii)!)
        append(UInt32(pcm.count).littleEndian)
        wav.append(pcm)
        return wav
    }
}

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

// MARK: - Errores

enum ScribeError: LocalizedError {
    case sinApiKey, http(Int, String), sinTexto, ws(String)

    var errorDescription: String? {
        switch self {
        case .sinApiKey: return "No encontré ELEVENLABS_API_KEY en ~/.hermes/.env"
        case .http(let code, let body): return "ElevenLabs respondió \(code): \(body.prefix(120))"
        case .sinTexto: return "Respuesta sin texto"
        case .ws(let message): return "Streaming: \(message)"
        }
    }
}

// MARK: - Cliente batch (scribe_v1 / scribe_v2 + keyterms)

func transcribeBatch(wav: Data, model: String, completion: @escaping (Result<String, Error>) -> Void) {
    guard let key = Config.apiKey() else {
        completion(.failure(ScribeError.sinApiKey))
        return
    }
    let boundary = "BetoDicta-\(UUID().uuidString)"
    var body = Data()
    func field(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }
    field("model_id", model)
    field("language_code", "es")
    field("tag_audio_events", "false")
    for term in Config.keyterms().prefix(1000) { field("keyterms", term) }
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictado.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
    body.append(wav)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "xi-api-key")

    URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
        DispatchQueue.main.async {
            if let error { completion(.failure(error)); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data else { completion(.failure(ScribeError.sinTexto)); return }
            guard (200..<300).contains(code) else {
                completion(.failure(ScribeError.http(code, String(data: data, encoding: .utf8) ?? "")))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                completion(.failure(ScribeError.sinTexto))
                return
            }
            completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }.resume()
}

// MARK: - Cliente streaming (scribe_v2_realtime, texto en vivo)

final class StreamClient: NSObject {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var committedPieces: [String] = []

    var onPartial: ((String) -> Void)?
    var onCommitted: ((String) -> Void)?
    var onError: ((String) -> Void)?

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let key = Config.apiKey() else {
            completion(.failure(ScribeError.sinApiKey))
            return
        }
        committedPieces = []

        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var items = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
            URLQueryItem(name: "language_code", value: "es"),
        ]
        // El WS acepta máx. 50 keyterms de hasta 20 caracteres
        var seen = Set<String>()
        for term in Config.keyterms() {
            let t = term.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.count <= 20, !seen.contains(t.lowercased()) else { continue }
            seen.insert(t.lowercased())
            items.append(URLQueryItem(name: "keyterms", value: t))
            if seen.count == 50 { break }
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()

        task.receive { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    completion(.failure(ScribeError.ws(error.localizedDescription)))
                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["message_type"] as? String {
                        if type == "session_started" {
                            self?.receiveLoop()
                            completion(.success(()))
                        } else {
                            let msg = json["message"] as? String ?? type
                            completion(.failure(ScribeError.ws(msg)))
                        }
                    } else {
                        self?.receiveLoop()
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func send(chunk: Data) {
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": chunk.base64EncodedString(),
            "commit": false,
            "sample_rate": 16000,
        ]
        sendJSON(message)
    }

    func commit() {
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": true,
            "sample_rate": 16000,
        ]
        sendJSON(message)
    }

    func fullText() -> String {
        committedPieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }
        task.send(.string(string)) { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.onError?(error.localizedDescription) }
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                return // conexión cerrada
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["message_type"] as? String else { return }
        DispatchQueue.main.async {
            switch type {
            case "partial_transcript":
                if let t = json["text"] as? String { self.onPartial?(t) }
            case "committed_transcript", "committed_transcript_with_timestamps":
                if let t = json["text"] as? String, !t.isEmpty {
                    self.committedPieces.append(t)
                    self.onCommitted?(self.fullText())
                }
            case "error", "auth_error", "quota_exceeded", "rate_limited",
                 "resource_exhausted", "session_time_limit_exceeded",
                 "input_error", "chunk_size_exceeded", "transcriber_error":
                self.onError?(json["message"] as? String ?? type)
            default:
                break
            }
        }
    }
}

// MARK: - Pegado (clipboard + Cmd+V, restaurando lo que había)

func pasteText(_ text: String) {
    let pb = NSPasteboard.general
    let previous = pb.string(forType: .string)
    pb.clearContents()
    pb.setString(text, forType: .string)

    let src = CGEventSource(stateID: .combinedSessionState)
    let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
    let vUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    vDown?.flags = .maskCommand
    vUp?.flags = .maskCommand
    vDown?.post(tap: .cghidEventTap)
    vUp?.post(tap: .cghidEventTap)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
    }
}

// MARK: - Medidor de voz (el latido)

final class LevelMeterView: NSView {
    private var levels = [Float](repeating: 0, count: 6)

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
        needsDisplay = true
    }

    func reset() {
        levels = [Float](repeating: 0, count: levels.count)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let barWidth: CGFloat = 3
        let gap: CGFloat = 2
        let midY = bounds.midY
        for (i, level) in levels.enumerated() {
            let h = max(3, CGFloat(level) * bounds.height * 0.9)
            let x = CGFloat(i) * (barWidth + gap)
            let rect = NSRect(x: x, y: midY - h / 2, width: barWidth, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.systemRed.withAlphaComponent(0.55 + 0.45 * CGFloat(level)).setFill()
            path.fill()
        }
    }
}

// MARK: - Panel flotante en el notch (no roba el foco)

final class DictationPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    let meter: LevelMeterView
    private let keycap = NSTextField(labelWithString: "fn")

    private let wing: CGFloat = 48      // alas a los lados del notch
    private let strip: CGFloat = 24     // línea de texto bajo el notch
    private var width: CGFloat = 400
    private var height: CGFloat = 60
    private var notchHeight: CGFloat = 36

    init() {
        // Geometría real del notch (áreas útiles a sus lados)
        var notchRect = NSRect(x: 0, y: 0, width: 210, height: 36)
        if let screen = NSScreen.main {
            notchHeight = max(screen.safeAreaInsets.top, 28)
            let left = screen.auxiliaryTopLeftArea
            let right = screen.auxiliaryTopRightArea
            if let left, let right {
                notchRect = NSRect(x: left.maxX, y: screen.frame.maxY - notchHeight,
                                   width: right.minX - left.maxX, height: notchHeight)
            } else {
                notchRect = NSRect(x: screen.frame.midX - 105, y: screen.frame.maxY - notchHeight,
                                   width: 210, height: notchHeight)
            }
        }
        width = notchRect.width + wing * 2
        height = notchHeight + strip
        meter = LevelMeterView(frame: NSRect(x: 8, y: strip + 7, width: wing - 16, height: notchHeight - 14))

        panel = NSPanel(contentRect: NSRect(x: notchRect.minX - wing,
                                            y: notchRect.maxY - height,
                                            width: width, height: height),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true

        // Forma negra que abraza el notch: alas arriba + tira de texto abajo
        let background = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.cgColor
        background.layer?.cornerRadius = 12
        background.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.contentView = background

        // Ala izquierda: el latido (a la altura del notch)
        background.addSubview(meter)

        // Ala derecha: tecla fn estilo keycap
        keycap.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        keycap.textColor = .white
        keycap.alignment = .center
        keycap.wantsLayer = true
        keycap.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        keycap.layer?.cornerRadius = 5
        keycap.layer?.borderWidth = 1
        keycap.layer?.borderColor = NSColor(calibratedWhite: 0.4, alpha: 1).cgColor
        let capW: CGFloat = 30, capH: CGFloat = 19
        keycap.frame = NSRect(x: width - wing + (wing - capW) / 2,
                              y: strip + (notchHeight - capH) / 2,
                              width: capW, height: capH)
        background.addSubview(keycap)

        // Tira inferior: UNA línea de texto delgadita
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.frame = NSRect(x: 10, y: 4, width: width - 20, height: 15)
        background.addSubview(label)
    }

    func show(_ text: String) {
        update(text)
        panel.orderFrontRegardless()
    }

    /// Teleprompter de una línea: siempre muestra el FINAL (lo último dicho).
    func update(_ text: String) {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        let maxChars = 58
        if clean.count > maxChars {
            label.stringValue = "…" + String(clean.suffix(maxChars))
        } else {
            label.stringValue = clean
        }
    }

    func hide(after seconds: TimeInterval = 0) {
        meter.reset()
        if seconds == 0 {
            panel.orderOut(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [panel] in
                panel.orderOut(nil)
            }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        while let viejo = menu.items.first(where: { $0.tag == 99 }) {
            menu.removeItem(viejo)
        }
        var idx = 1
        let titulo = NSMenuItem(title: "— Uso de dictado —", action: nil, keyEquivalent: "")
        titulo.tag = 99
        menu.insertItem(titulo, at: idx)
        idx += 1
        for line in UsageLog.resumen() {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.tag = 99
            menu.insertItem(item, at: idx)
            idx += 1
        }
    }

    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let panel = DictationPanel()
    private var stream: StreamClient?
    private var history: HistoryWriter?
    private var hotKeyRef: EventHotKeyRef?
    private var lastVoice = Date()
    private var silenceTimer: Timer?
    private var lastPartial = ""

    private var tecla: String { Config.hotkey() }
    private var isStreamingModel: Bool { Config.model() == "scribe_v2_realtime" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🎙"
        let menu = NSMenu()
        menu.addItem(withTitle: "BetoDicta v0.2 — \(tecla) para dictar (\(Config.model()))", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Editar configuración", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Editar keyterms", action: #selector(openKeyterms), keyEquivalent: "")
        menu.addItem(withTitle: "Editar reemplazos", action: #selector(openReplacements), keyEquivalent: "")
        menu.addItem(withTitle: "Copiar último dictado", action: #selector(copyLastDictation), keyEquivalent: "c")
        menu.addItem(withTitle: "Abrir historial", action: #selector(openHistory), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        registerHotKey()

        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.panel.meter.push(level)
                if level > 0.15 { self?.lastVoice = Date() }
            }
        }

        // Modo demo para captura de pantalla: BETODICTA_DEMO=1 abre el panel
        // con texto y latido simulado, sin grabar. Solo para el README.
        if ProcessInfo.processInfo.environment["BETODICTA_DEMO"] == "1" {
            startDemo()
        }
    }

    private func startDemo() {
        panel.show("revisé el Quipux del GAD y configuré el MikroTik")
        var phase: Double = 0
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            phase += 0.35
            let level = Float(0.4 + 0.5 * abs(sin(phase)) * abs(sin(phase * 0.6)))
            self?.panel.meter.push(level)
        }
    }

    @objc private func openConfig() { NSWorkspace.shared.open(Config.dir.appendingPathComponent("config.json")) }
    @objc private func openKeyterms() { NSWorkspace.shared.open(Config.dir.appendingPathComponent("keyterms.txt")) }
    @objc private func openReplacements() { NSWorkspace.shared.open(Config.dir.appendingPathComponent("reemplazos.json")) }
    @objc private func copyLastDictation() {
        let fm = FileManager.default
        var newest: (url: URL, date: Date)?
        if let walker = fm.enumerator(at: HistoryWriter.historyDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in walker where url.pathExtension == "txt" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if newest == nil || date > newest!.date { newest = (url, date) }
            }
        }
        guard let newest, let text = try? String(contentsOf: newest.url, encoding: .utf8), !text.isEmpty else {
            panel.show("Historial vacío — nada que copiar")
            panel.hide(after: 1.5)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        panel.show("📋 Copiado: " + text)
        panel.hide(after: 2)
    }

    @objc private func openHistory() {
        try? FileManager.default.createDirectory(at: HistoryWriter.historyDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(HistoryWriter.historyDir)
    }

    // MARK: Tecla

    private func registerHotKey() {
        if tecla.lowercased() == "fn" {
            registerFnKey()
        } else {
            registerFKey(named: tecla.lowercased())
        }
    }

    private var fnDown = false
    private var fnUsedInCombo = false

    private func registerFnKey() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        let flagsHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == 63 else { return }
            if event.modifierFlags.contains(.function) {
                self.fnDown = true
                self.fnUsedInCombo = false
            } else if self.fnDown {
                self.fnDown = false
                if !self.fnUsedInCombo {
                    DispatchQueue.main.async { self.toggle() }
                }
            }
        }
        let comboHandler: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            if self.fnDown { self.fnUsedInCombo = true }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: comboHandler)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            flagsHandler(event); return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            comboHandler(event); return event
        }
    }

    private func registerFKey(named name: String) {
        let fKeys: [String: Int] = [
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
            "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
            "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        ]
        let keyCode = fKeys[name] ?? kVK_F6

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { delegate.toggle() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x42544443), id: 1) // "BTDC"
        RegisterEventHotKey(UInt32(keyCode), 0, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: Flujo de dictado

    func toggle() {
        if recorder.isRecording {
            stopAndTranscribe()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        lastPartial = ""
        lastVoice = Date()
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.recorder.isRecording else { timer.invalidate(); return }
            let quiet = Date().timeIntervalSince(self.lastVoice)
            let limit = Config.maxSilence()
            if quiet >= limit {
                timer.invalidate()
                self.panel.update("🔇 \(Int(limit))s de silencio — cerrando dictado…")
                self.stopAndTranscribe()
            }
        }
        let history = HistoryWriter()
        self.history = history

        if isStreamingModel {
            panel.show("Conectando con Scribe…")
            let stream = StreamClient()
            self.stream = stream
            stream.onPartial = { [weak self] text in
                guard let self else { return }
                self.lastPartial = text
                let done = stream.fullText()
                let visible = done.isEmpty ? text : done + " " + text
                self.panel.update(visible)
                history.savePartial(visible)
            }
            stream.onCommitted = { [weak self] full in
                self?.panel.update(full)
                history.savePartial(full, force: true)
            }
            stream.onError = { [weak self] message in
                self?.panel.update("⚠️ \(message)")
            }
            stream.connect { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.panel.update("⚠️ \(error.localizedDescription)")
                    self.panel.hide(after: 3)
                    self.stream = nil
                    history.discard()
                    self.history = nil
                case .success:
                    self.recorder.onChunk = { [weak stream] chunk in
                        history.append(chunk: chunk)
                        stream?.send(chunk: chunk)
                    }
                    do {
                        try self.recorder.start()
                        self.panel.update("Escuchando… (\(self.tecla) para terminar)")
                    } catch {
                        self.panel.update("⚠️ Micrófono: \(error.localizedDescription)")
                        self.panel.hide(after: 3)
                    }
                }
            }
        } else {
            recorder.onChunk = { chunk in
                history.append(chunk: chunk)
            }
            do {
                try recorder.start()
                panel.show("Escuchando… (\(tecla) para terminar)")
            } catch {
                panel.show("⚠️ Micrófono: \(error.localizedDescription)")
                panel.hide(after: 3)
            }
        }
    }

    private func stopAndTranscribe() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        let wav = recorder.stop()
        let seconds = Double(wav.count - 44) / 32000.0

        if let stream {
            guard seconds > 0.4 else {
                stream.disconnect()
                self.stream = nil
                history?.discard()
                history = nil
                panel.update("Muy corto — nada que transcribir")
                panel.hide(after: 1.2)
                return
            }
            panel.update("⏳ Cerrando dictado…")
            stream.commit()
            // Esperar el committed final (con tope de 6 s y respaldo al último parcial)
            var finished = false
            let finish: (String) -> Void = { [weak self] raw in
                guard let self, !finished else { return }
                finished = true
                stream.disconnect()
                self.stream = nil
                self.deliver(raw: raw, wav: wav)
            }
            stream.onCommitted = { full in finish(full) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, !finished else { return }
                let fallback = stream.fullText().isEmpty ? self.lastPartial : stream.fullText()
                finish(fallback)
            }
        } else {
            guard seconds > 0.4 else {
                history?.discard()
                history = nil
                panel.update("Muy corto — nada que transcribir")
                panel.hide(after: 1.2)
                return
            }
            panel.update("⏳ Transcribiendo \(String(format: "%.1f", seconds))s…")
            transcribeBatch(wav: wav, model: Config.model()) { [weak self] result in
                switch result {
                case .success(let raw):
                    self?.deliver(raw: raw, wav: wav)
                case .failure(let error):
                    // Falló la nube, pero tu voz queda a salvo en el historial
                    self?.history?.finish(wav: wav, finalText: "")
                    self?.history = nil
                    self?.panel.update("⚠️ \(error.localizedDescription) — audio guardado en historial")
                    self?.panel.hide(after: 4)
                }
            }
        }
    }

    private func deliver(raw: String, wav: Data) {
        UsageLog.record(provider: Config.model(), seconds: Double(wav.count - 44) / 32000.0)
        let text = applyReplacements(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        history?.finish(wav: wav, finalText: text)
        history = nil
        if text.isEmpty {
            panel.update("(silencio)")
        } else {
            pasteText(text)
            panel.update("✓ " + text)
        }
        panel.hide(after: 1.8)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

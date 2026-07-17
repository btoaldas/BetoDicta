import Foundation
import AVFoundation

#if canImport(Speech)
import Speech
#endif

// MARK: - Preview EN VIVO de lo que dices (notch) — transcriptor nativo de Apple
//
// Mientras grabas, una COPIA del audio (el mismo chunk PCM16 16 kHz del Recorder) va al
// SpeechTranscriber nativo de macOS 26 con resultados VOLÁTILES → el notch muestra lo
// que vas diciendo EN VIVO. Es SOLO visual: la transcripción REAL sigue siendo la
// cascada elegida (Groq, Whisper local, etc.) al soltar la tecla, y esa es la que se
// pega/pule. El preview jamás se pega.
//
// Falla suave: si no es macOS 26, el idioma no tiene modelo bajado, o algo peta, no hay
// preview y nada se detiene. Solo se usa cuando el motor real NO tiene ya su propio
// texto en vivo (ElevenLabs realtime, tcpp, nube viva). Parametrizable:
// Config.previewVivo() (default ON).

final class PreviewVivo {
    private static var activo: PreviewVivo?
    private static let cola = DispatchQueue(label: "betodicta.previewvivo")

    static var disponible: Bool { AppleSpeechSTT.disponible }

    /// Arranca el preview. `onParcial` llega en MAIN con el texto dicho hasta ahora.
    static func iniciar(onParcial: @escaping (String) -> Void) {
        guard disponible, Config.previewVivo() else { return }
        detener()
        #if canImport(Speech)
        if #available(macOS 26, *) {
            let p = PreviewVivo()
            p.onParcial = onParcial
            activo = p
            p.arrancar()
        }
        #endif
    }

    /// Alimenta un chunk PCM16 mono 16 kHz (mismo formato que produce el Recorder).
    /// Barato: se encola a una cola propia; el hilo de audio no espera.
    static func alimentar(_ chunk: Data) {
        guard let p = activo else { return }
        cola.async { p.encolar(chunk) }
    }

    static func detener() {
        let p = activo; activo = nil
        cola.async { p?.cerrar() }
    }

    // MARK: instancia

    private var onParcial: ((String) -> Void)?
    private var tarea: Task<Void, Never>?
    private var cerrado = false
    private let fmt16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                      channels: 1, interleaved: true)!

    #if canImport(Speech)
    // Tipos de macOS 26 guardados como Any para poder declararlos en la clase
    // sin @available a nivel de propiedad almacenada.
    private var _continuation: Any?
    private var _analyzer: Any?
    private var _converter: AVAudioConverter?
    private var _fmtDestino: AVAudioFormat?

    private static let debug = ProcessInfo.processInfo.environment["BETODICTA_PREVIEWTEST"] != nil
    private static func dbg(_ s: String) { if debug { print("[PV] \(s)") } }

    @available(macOS 26, *)
    private func arrancar() {
        tarea = Task { [weak self] in
            guard let self else { return }
            let lang = Config.appleSpeechIdioma()
            guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: lang)) else {
                Self.dbg("sin locale para \(lang)"); return
            }
            Self.dbg("locale \(loc.identifier(.bcp47))")
            // DictationTranscriber = el módulo del DICTADO EN VIVO del sistema (el que
            // escribe mientras hablas con doble-fn). Preset progresivo largo: volátiles
            // + finalización frecuente. SpeechTranscriber (batch) NO emite en vivo.
            let transcriber = DictationTranscriber(locale: loc, preset: .progressiveLongDictation)
            // Sin el modelo del idioma instalado NO hay preview (no bajamos nada aquí;
            // la descarga la gestiona el proveedor batch cuando el usuario lo usa).
            let estado = await AssetInventory.status(forModules: [transcriber])
            Self.dbg("assets \(estado)")
            guard estado == .installed else {
                Log.log(.ia, "preview vivo: modelo de idioma no instalado — sin preview"); return
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            // Formato preferido del transcriptor; convertimos los chunks del Recorder.
            let destino = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? fmt16
            Self.dbg("formato destino \(destino)")
            let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
            _continuation = cont
            _analyzer = analyzer
            _fmtDestino = destino
            if destino != fmt16 { _converter = AVAudioConverter(from: fmt16, to: destino) }

            // Lector de resultados: los tramos FINALIZADOS se acumulan; el volátil
            // (que se va refinando) se muestra al final de lo fijo.
            let lector = Task { [weak self] in
                var fijo = ""
                do {
                    for try await r in transcriber.results {
                        let t = String(r.text.characters)
                        Self.dbg("result final=\(r.isFinal) '\(t.prefix(40))'")
                        var visible = fijo
                        if r.isFinal { fijo += t; visible = fijo } else { visible = fijo + t }
                        let limpio = visible.replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !limpio.isEmpty {
                            DispatchQueue.main.async { self?.onParcial?(limpio) }
                        }
                    }
                    Self.dbg("results terminó")
                } catch { Self.dbg("results error \(error)") }
            }
            do {
                Self.dbg("analyzer.start…")
                try await analyzer.start(inputSequence: stream)
                Self.dbg("analyzer.start retornó")
            } catch {
                Log.log(.ia, "preview vivo: no arrancó (\(error.localizedDescription))")
                Self.dbg("start error \(error)")
                lector.cancel()
            }
        }
    }
    #endif

    private var pendientes: [Data] = []   // chunks que llegan antes de que el analyzer esté listo
    private var entregados = 0

    /// Convierte el chunk PCM16→buffer del formato del transcriptor y lo entrega.
    private func encolar(_ chunk: Data) {
        #if canImport(Speech)
        guard !cerrado else { return }
        if #available(macOS 26, *) {
            guard let cont = _continuation as? AsyncStream<AnalyzerInput>.Continuation else {
                pendientes.append(chunk)   // el arranque (locale/assets/analyzer) aún no termina
                return
            }
            // Vaciar lo acumulado durante el arranque (orden preservado).
            if !pendientes.isEmpty {
                let acum = pendientes; pendientes = []
                Self.dbg("vaciando \(acum.count) chunks pendientes")
                for c in acum { entregarBuffer(c, cont) }
            }
            entregarBuffer(chunk, cont)
        }
        #endif
    }

    #if canImport(Speech)
    @available(macOS 26, *)
    private func entregarBuffer(_ chunk: Data, _ cont: AsyncStream<AnalyzerInput>.Continuation) {
            let frames = AVAudioFrameCount(chunk.count / 2)
            guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt16, frameCapacity: frames) else { return }
            buf.frameLength = frames
            chunk.withUnsafeBytes { raw in
                if let base = raw.baseAddress, let ch = buf.int16ChannelData {
                    memcpy(ch[0], base, chunk.count)
                }
            }
            var entrega = buf
            if let conv = _converter, let destino = _fmtDestino {
                let cap = AVAudioFrameCount(Double(frames) * destino.sampleRate / fmt16.sampleRate) + 64
                guard let out = AVAudioPCMBuffer(pcmFormat: destino, frameCapacity: cap) else { return }
                var served = false
                conv.convert(to: out, error: nil) { _, status in
                    if served { status.pointee = .noDataNow; return nil }
                    served = true; status.pointee = .haveData; return buf
                }
                guard out.frameLength > 0 else { return }
                entrega = out
            }
            cont.yield(AnalyzerInput(buffer: entrega))
            entregados += 1
            if entregados <= 2 || entregados % 10 == 0 { Self.dbg("entregados \(entregados)") }
    }
    #endif

    private func cerrar() {
        cerrado = true
        #if canImport(Speech)
        if #available(macOS 26, *) {
            (_continuation as? AsyncStream<AnalyzerInput>.Continuation)?.finish()
            if let a = _analyzer as? SpeechAnalyzer {
                Task { await a.cancelAndFinishNow() }
            }
        }
        #endif
        tarea?.cancel()
        onParcial = nil
    }
}

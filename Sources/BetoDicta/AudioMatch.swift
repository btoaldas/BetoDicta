import Foundation
import AVFoundation
import Accelerate

// MARK: - Coincidencia por AUDIO (experimental, opt-in)
//
// Idea de Alberto: grabar tu voz diciendo un término ("Quipux") y, al dictar,
// reconocer ese sonido aunque el motor escriba otra cosa. Es "reconocer
// tarareando": nunca hay match perfecto, se mide QUÉ TAN PARECIDO (distancia)
// y se compara contra un umbral.
//
// Motor: espectrograma mel (cómo se reparte la energía del sonido en el tiempo)
// + DTW (alinea dos audios aunque uno vaya más rápido). Todo local, sin modelos
// que descargar. Dependiente de UN hablante (tu voz) — el caso más fácil.
//
// NADA de esto corre si el flag "match_por_audio" está apagado (por defecto).

enum AudioMatch {
    static var dir: URL { Config.dir.appendingPathComponent("voces") }
    static let sr: Double = 16000
    static let frameLen = 400      // 25 ms @16k
    static let hop = 160           // 10 ms
    static let fftLen = 512
    static let nMel = 40
    /// Umbral por defecto (distancia DTW normalizada). Debajo = "es la palabra".
    /// Calibrado midiendo: misma palabra ≈2.6 (voz distinta), palabras
    /// diferentes ≈5.5+. 4.0 cae en medio, sesgado a evitar falsos positivos.
    /// Ajustable por el usuario tras medir con su propia voz.
    static let umbralDefecto: Float = 4.0

    // ---- Carpeta de muestras por término ----
    static func slug(_ s: String) -> String {
        let base = s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let limpio = base.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return String(limpio).replacingOccurrences(of: "__", with: "_")
    }
    static func carpeta(_ termino: String) -> URL { dir.appendingPathComponent(slug(termino)) }
    static func muestras(_ termino: String) -> [URL] {
        let c = carpeta(termino)
        let files = (try? FileManager.default.contentsOfDirectory(at: c, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func nuevaMuestraURL(_ termino: String) -> URL {
        let c = carpeta(termino)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        // nombre por conteo (sin depender de la fecha, que no está disponible en scripts)
        let n = muestras(termino).count + 1
        return c.appendingPathComponent(String(format: "muestra-%02d.wav", n))
    }
    static func borrar(_ url: URL) { try? FileManager.default.removeItem(at: url) }
    static func tieneMuestras(_ termino: String) -> Bool { !muestras(termino).isEmpty }

    // ---- Lectura de audio a mono 16k float ----
    static func leerSamples(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let inFmt = file.processingFormat
        guard let salida = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr,
                                         channels: 1, interleaved: false) else { return nil }
        guard let conv = AVAudioConverter(from: inFmt, to: salida) else { return nil }
        let cap = AVAudioFrameCount(file.length)
        guard cap > 0, let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: cap) else { return nil }
        do { try file.read(into: inBuf) } catch { return nil }
        let ratio = sr / inFmt.sampleRate
        let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 1024)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: salida, frameCapacity: outCap) else { return nil }
        var entregado = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if entregado { status.pointee = .noDataNow; return nil }
            entregado = true; status.pointee = .haveData; return inBuf
        }
        if err != nil { return nil }
        guard let ptr = outBuf.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
    }

    // ---- Banco de filtros mel (precalculado una vez) ----
    static let melBanco: [[Float]] = construirMel()
    private static func hzAMel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
    private static func melAHz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
    private static func construirMel() -> [[Float]] {
        let bins = fftLen / 2 + 1          // 257
        let lo = hzAMel(0), hi = hzAMel(sr / 2)
        let puntos = (0...(nMel + 1)).map { melAHz(lo + (hi - lo) * Double($0) / Double(nMel + 1)) }
        let binHz = puntos.map { Int(floor(Double(fftLen + 1) * $0 / sr)) }
        var banco = Array(repeating: [Float](repeating: 0, count: bins), count: nMel)
        for m in 1...nMel {
            let izq = binHz[m - 1], cen = binHz[m], der = binHz[m + 1]
            if cen > izq { for k in izq..<cen where k < bins { banco[m-1][k] = Float(k - izq) / Float(cen - izq) } }
            if der > cen { for k in cen..<der where k < bins { banco[m-1][k] = Float(der - k) / Float(der - cen) } }
        }
        return banco
    }

    // ---- Rasgos: secuencia de vectores log-mel, con recorte de silencio y CMN ----
    static func rasgos(_ url: URL) -> [[Float]]? {
        guard let s = leerSamples(url), s.count >= frameLen else { return nil }
        let sam = recortarSilencio(s)
        guard sam.count >= frameLen else { return nil }

        var ventana = [Float](repeating: 0, count: frameLen)
        vDSP_hamm_window(&ventana, vDSP_Length(frameLen), 0)
        let log2n = vDSP_Length(9)      // 512
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }
        let bins = fftLen / 2 + 1

        var seq: [[Float]] = []
        var i = 0
        while i + frameLen <= sam.count {
            // ventana + pad a 512
            var frame = [Float](repeating: 0, count: fftLen)
            vDSP_vmul(Array(sam[i..<i+frameLen]), 1, ventana, 1, &frame, 1, vDSP_Length(frameLen))
            // FFT real
            var realp = [Float](repeating: 0, count: fftLen/2)
            var imagp = [Float](repeating: 0, count: fftLen/2)
            realp.withUnsafeMutableBufferPointer { rp in
                imagp.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftLen/2) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(fftLen/2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            // potencia por bin (257): |X|^2, con manejo del bin de Nyquist en imagp[0]
            var pot = [Float](repeating: 0, count: bins)
            pot[0] = realp[0] * realp[0]
            pot[bins - 1] = imagp[0] * imagp[0]
            for k in 1..<(fftLen/2) { pot[k] = realp[k]*realp[k] + imagp[k]*imagp[k] }
            // mel + log
            var mel = [Float](repeating: 0, count: nMel)
            for m in 0..<nMel {
                var acc: Float = 0
                vDSP_dotpr(melBanco[m], 1, pot, 1, &acc, vDSP_Length(bins))
                mel[m] = log(acc + 1e-6)
            }
            seq.append(mel)
            i += hop
        }
        guard !seq.isEmpty else { return nil }
        return normalizarCMN(seq)
    }

    /// Cepstral mean normalization: resta la media de cada coeficiente. Ayuda a
    /// que el mismo sonido con distinto micro/volumen quede parecido.
    private static func normalizarCMN(_ seq: [[Float]]) -> [[Float]] {
        let n = seq.count, d = seq[0].count
        var media = [Float](repeating: 0, count: d)
        for v in seq { for j in 0..<d { media[j] += v[j] } }
        for j in 0..<d { media[j] /= Float(n) }
        return seq.map { v in (0..<d).map { v[$0] - media[$0] } }
    }

    /// Recorta silencio al inicio/fin por energía (deja la palabra, no el aire).
    private static func recortarSilencio(_ s: [Float]) -> [Float] {
        let win = 160
        var energias: [Float] = []
        var i = 0
        while i + win <= s.count {
            var e: Float = 0; vDSP_measqv(Array(s[i..<i+win]), 1, &e, vDSP_Length(win))
            energias.append(e); i += win
        }
        guard let maxE = energias.max(), maxE > 0 else { return s }
        let umbral = maxE * 0.02
        let ini = energias.firstIndex { $0 > umbral } ?? 0
        let fin = energias.lastIndex { $0 > umbral } ?? (energias.count - 1)
        let a = max(0, ini * win), b = min(s.count, (fin + 1) * win)
        return a < b ? Array(s[a..<b]) : s
    }

    // ---- DTW normalizado entre dos secuencias de rasgos ----
    static func dtw(_ a: [[Float]], _ b: [[Float]]) -> Float {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return .greatestFiniteMagnitude }
        let inf = Float.greatestFiniteMagnitude
        var prev = [Float](repeating: inf, count: m + 1)   // fila i-1
        var curr = [Float](repeating: inf, count: m + 1)   // fila i
        prev[0] = 0                                         // D[0][0] = 0
        for i in 1...n {
            curr[0] = inf                                  // D[i][0] = inf
            for j in 1...m {
                let d = distEuclid(a[i-1], b[j-1])
                let mejor = min(prev[j], curr[j-1], prev[j-1])
                curr[j] = d + mejor
            }
            swap(&prev, &curr)                             // curr pasa a ser i-1
        }
        return prev[m] / Float(n + m)     // normaliza por largo del camino
    }
    private static func distEuclid(_ a: [Float], _ b: [Float]) -> Float {
        var dif = [Float](repeating: 0, count: a.count)
        vDSP_vsub(b, 1, a, 1, &dif, 1, vDSP_Length(a.count))
        var s: Float = 0; vDSP_svesq(dif, 1, &s, vDSP_Length(a.count))
        return sqrt(s)
    }

    // ---- Evaluación: ¿el audio de prueba coincide con las muestras del término? ----
    /// Menor distancia entre el audio de prueba y CUALQUIER muestra del término.
    static func distancia(pruebaURL: URL, termino: String) -> Float? {
        guard let test = rasgos(pruebaURL) else { return nil }
        return distanciaRasgos(test, termino: termino)
    }
    static func distanciaRasgos(_ test: [[Float]], termino: String) -> Float? {
        let refs = muestras(termino).compactMap { rasgos($0) }
        guard !refs.isEmpty else { return nil }
        return refs.map { dtw(test, $0) }.min()
    }

    /// Umbral efectivo (el que puso el usuario, o el default).
    static func umbral() -> Float { Float(Config.umbralAudio() ?? Double(umbralDefecto)) }

    /// El término más cercano entre los que tienen muestras (para el flujo de
    /// dictado y el "probar por voz"). nil si nada supera el umbral.
    static func mejorCoincidencia(pruebaURL: URL, terminos: [String]) -> (termino: String, dist: Float)? {
        guard let test = rasgos(pruebaURL) else { return nil }
        var mejor: (String, Float)?
        for t in terminos where tieneMuestras(t) {
            if let d = distanciaRasgos(test, termino: t), mejor == nil || d < mejor!.1 { mejor = (t, d) }
        }
        guard let (t, d) = mejor, d <= umbral() else { return nil }
        return (t, d)
    }
}

// MARK: - Grabador de voz (para enrolar muestras y para "probar por voz")

final class GrabadorVoz: NSObject, ObservableObject {
    @Published var grabando = false
    private var rec: AVAudioRecorder?
    private(set) var ultimaURL: URL?

    private let ajustes: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    func iniciar(a url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        guard let r = try? AVAudioRecorder(url: url, settings: ajustes) else { return }
        rec = r; ultimaURL = url
        r.record()
        grabando = true
    }
    func detener() {
        rec?.stop(); rec = nil; grabando = false
    }
}

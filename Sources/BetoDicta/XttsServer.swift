import Foundation
import AVFoundation

// MARK: - Servidor XTTS residente (clon local RÁPIDO, sin recargar el modelo)
//
// Problema: correr `python voz_gen.py` por respuesta recarga el modelo (~2GB) cada vez
// → 10-20s de latencia → a veces timeout → failover a otra voz. Solución: un servidor
// Python que carga el modelo UNA vez (y precalcula los latentes del locutor) y responde
// por HTTP local en streaming. Cada respuesta = ~1-2s. Se levanta cuando el clon local
// es el motor activo (preactivar, parametrizable). Igual patrón que WhisperServer/Voxtral.

enum XttsServer {
    static var proceso: Process?
    static var puerto = 8791
    static var paqueteActivo = ""
    private static let salud = "http://127.0.0.1:8791/health"

    static var corriendo: Bool { proceso?.isRunning == true }

    /// Asegura el servidor levantado para ESTE paquete (lo reinicia si cambió la voz).
    /// `onListo(true)` cuando el modelo está cargado (GET /health responde).
    static func asegurar(paquete: URL, onListo: @escaping (Bool) -> Void) {
        guard VozEngine.estado() == .listo else { onListo(false); return }
        if corriendo && paqueteActivo == paquete.path { onListo(true); return }
        detener()
        VozEngine.asegurarServerPy()
        paqueteActivo = paquete.path
        let p = Process(); p.executableURL = VozEngine.pythonURL
        p.arguments = [VozEngine.serverPyURL.path, paquete.path, "\(puerto)"]
        var env = ProcessInfo.processInfo.environment; env["COQUI_TOS_AGREED"] = "1"; p.environment = env
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { onListo(false); return }
        proceso = p
        // Sondear /health hasta ~40s (la 1ª carga del modelo tarda).
        DispatchQueue.global().async {
            for _ in 0..<80 {
                Thread.sleep(forTimeInterval: 0.5)
                if !(p.isRunning) { DispatchQueue.main.async { onListo(false) }; return }
                if ping() { DispatchQueue.main.async { onListo(true) }; return }
            }
            DispatchQueue.main.async { onListo(false) }
        }
    }

    static func detener() { proceso?.terminate(); proceso = nil; paqueteActivo = "" }

    private static func ping() -> Bool {
        guard let u = URL(string: salud) else { return false }
        var r = URLRequest(url: u); r.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0); var ok = false
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            ok = (resp as? HTTPURLResponse)?.statusCode == 200; sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5); return ok
    }

    /// Habla por el servidor: manda el texto, recibe PCM float32 en streaming y lo
    /// reproduce por AVAudioEngine conforme llega. Falla suave (completion(false)).
    static func decir(texto: String, completion: @escaping (Bool) -> Void) {
        guard corriendo, let u = URL(string: "http://127.0.0.1:\(puerto)/say") else { completion(false); return }
        let player = XttsServerPlayer()
        player.reproducir(texto: texto, url: u, completion: completion)
    }
}

// Recibe el PCM float32 (24kHz mono) por HTTP en streaming y lo encola en AVAudioEngine.
private final class XttsServerPlayer: NSObject, URLSessionDataDelegate {
    static var activo: XttsServerPlayer?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var resto = Data()
    private var recibio = false
    private var done: ((Bool) -> Void)?
    private var terminado = false

    func reproducir(texto: String, url: URL, completion: @escaping (Bool) -> Void) {
        XttsServerPlayer.activo = self
        done = completion
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: fmt)
        do { try engine.start(); player.play() } catch { finish(false); return }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 120
        req.httpBody = texto.data(using: .utf8)
        let ses = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        ses.dataTask(with: req).resume()
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        recibio = true
        var buf = resto; buf.append(data)
        let usable = buf.count - (buf.count % 4)
        guard usable > 0 else { resto = buf; return }
        let bloque = buf.subdata(in: 0..<usable); resto = buf.subdata(in: usable..<buf.count)
        let n = usable / 4
        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        pcm.frameLength = AVAudioFrameCount(n)
        bloque.withUnsafeBytes { raw in
            let f = raw.bindMemory(to: Float32.self)
            guard let out = pcm.floatChannelData?[0] else { return }
            for i in 0..<n { out[i] = f[i] }
        }
        player.scheduleBuffer(pcm)
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(recibio && error == nil)
    }

    private func finish(_ ok: Bool) {
        if terminado { return }; terminado = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.done?(ok); self.done = nil }
    }
}

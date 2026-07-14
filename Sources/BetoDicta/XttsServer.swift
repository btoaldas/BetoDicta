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

    private static var player: AVAudioPlayer?
    private static let fin = XttsFin()

    /// Habla por el servidor. Genera el audio COMPLETO (el modelo ya está en RAM → rápido)
    /// y LUEGO lo reproduce de corrido. Así la reproducción NO compite con la CPU de la
    /// generación → suena parejo, sin bajones ni trabas. Falla suave (completion(false)).
    static func decir(texto: String, completion: @escaping (Bool) -> Void) {
        guard corriendo, let u = URL(string: "http://127.0.0.1:\(puerto)/say") else { completion(false); return }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 120
        req.httpBody = texto.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, (200..<300).contains(code), data.count >= 8 else {
                Log.log(.ia, "XTTS servidor: sin audio (\(err?.localizedDescription ?? "HTTP \(code)"))")
                DispatchQueue.main.async { completion(false) }; return
            }
            // PCM float32 24kHz mono → WAV → AVAudioPlayer (reproducción fluida garantizada).
            guard let wav = try? pcmFloatAWav(data) else { DispatchQueue.main.async { completion(false) }; return }
            DispatchQueue.main.async {
                do {
                    let p = try AVAudioPlayer(data: wav)
                    fin.alTerminar = completion; p.delegate = fin
                    player = p; p.prepareToPlay(); p.play()
                } catch { Log.log(.ia, "XTTS servidor: no reproduce (\(error.localizedDescription))"); completion(false) }
            }
        }.resume()
    }

    /// float32 LE (24kHz mono) → WAV int16.
    private static func pcmFloatAWav(_ f32: Data) throws -> Data {
        var pcm16 = Data(capacity: f32.count / 2)
        f32.withUnsafeBytes { raw in
            let f = raw.bindMemory(to: Float32.self)
            for i in 0..<f.count { var s = Int16(max(-1, min(1, f[i])) * 32767).littleEndian; withUnsafeBytes(of: &s) { pcm16.append(contentsOf: $0) } }
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("xtts-srv-\(abs(f32.count)).wav")
        try WavIO.escribir(pcm16: pcm16, sampleRate: 24000, a: tmp)
        let d = try Data(contentsOf: tmp); try? FileManager.default.removeItem(at: tmp); return d
    }
}

private final class XttsFin: NSObject, AVAudioPlayerDelegate {
    var alTerminar: ((Bool) -> Void)?
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        let cb = alTerminar; alTerminar = nil; DispatchQueue.main.async { cb?(true) }
    }
}

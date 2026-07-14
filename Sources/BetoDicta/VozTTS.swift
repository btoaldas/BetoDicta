import Foundation
import AVFoundation

// MARK: - Voz (texto → voz) multi-proveedor con failover — Fase 7
//
// El Modo Agente (y a futuro cualquier respuesta hablada) dice el texto por
// aquí. Hay VARIOS motores y una cascada de failover, igual idea que el STT:
//
//   1) apple       — voz de macOS (AVSpeechSynthesizer). Gratis, local, SIEMPRE
//                    disponible. Es el respaldo final: si todo lo demás falla,
//                    igual te habla.
//   2) elevenlabs  — tu voz CLONADA "Bto" (nube, tu API key). La más natural.
//   3) xtts_local  — tu clon LOCAL (XTTS de VozClonPOC, 100% offline, gratis).
//
// El usuario elige el motor PRINCIPAL (Config.ttsProveedor); si ese falla (sin
// key, sin red, sin clon entrenado), cae al siguiente y termina en Apple. Nada
// detiene el proceso. Todo parametrizable.
//
// NOTA streaming: hoy los motores de nube/local generan el audio COMPLETO y
// luego se reproduce (batch). El streaming por WebSocket (ElevenLabs
// stream-input, Kokoro local) es la siguiente sub-fase — el audio empieza a
// sonar mientras se genera. La API de `Voz.decir` no cambia cuando llegue.

enum Voz {
    /// Reproductor retenido (si se libera, se corta el audio).
    private static var player: AVAudioPlayer?

    /// Motores en orden de intento: el principal elegido + los demás como
    /// failover, y Apple SIEMPRE al final (respaldo que nunca falla).
    private static func cadena() -> [String] {
        let principal = Config.ttsProveedor()
        var orden = [principal]
        for m in ["elevenlabs", "xtts_local", "apple"] where !orden.contains(m) { orden.append(m) }
        if !orden.contains("apple") { orden.append("apple") }   // respaldo garantizado
        return orden
    }

    /// Detiene cualquier voz en curso (Apple o audio reproduciéndose).
    static func detener() {
        TTS.detener()
        player?.stop(); player = nil
    }

    /// Dice el texto con el motor configurado (con failover). `completion` al terminar.
    static func decir(_ texto: String, completion: (() -> Void)? = nil) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { completion?(); return }
        intentar(t, cadena(), 0, completion)
    }

    private static func intentar(_ texto: String, _ orden: [String], _ i: Int, _ done: (() -> Void)?) {
        guard i < orden.count else { done?(); return }
        let motor = orden[i]
        let siguiente: () -> Void = { intentar(texto, orden, i + 1, done) }
        switch motor {
        case "apple":
            // Respaldo final: no falla. Reproduce con la voz de macOS.
            TTS.hablar(texto) { done?() }
        case "elevenlabs":
            // Streaming WS (suena mientras se genera); si falla, cae al batch mp3;
            // si el batch también falla, al siguiente motor.
            if Config.ttsElevenStreaming() {
                ElevenLabsStreamTTS.hablar(texto) { ok in
                    if ok { done?() } else {
                        Log.log(.ia, "TTS ElevenLabs WS falló → batch")
                        ElevenLabsTTS.decir(texto) { data in
                            if let data { reproducir(data, done) } else {
                                Log.log(.ia, "TTS ElevenLabs batch falló → siguiente motor"); siguiente()
                            }
                        }
                    }
                }
            } else {
                ElevenLabsTTS.decir(texto) { data in
                    if let data { reproducir(data, done) } else {
                        Log.log(.ia, "TTS ElevenLabs falló → siguiente motor"); siguiente()
                    }
                }
            }
        case "xtts_local":
            XttsLocalTTS.decir(texto) { url in
                if let url, let data = try? Data(contentsOf: url) { reproducir(data, done) } else {
                    Log.log(.ia, "TTS XTTS local no disponible → siguiente motor"); siguiente()
                }
            }
        default:
            siguiente()
        }
    }

    /// Prueba UNA voz local concreta (la genera con su comando y la reproduce),
    /// sin importar cuál sea el motor activo. Para el botón "Probar" de la biblioteca.
    static func probarVozLocal(_ voz: VozLocal, _ done: (() -> Void)? = nil) {
        XttsLocalTTS.decirCon(cmd: voz.cmd, texto: "Hola, esta es la voz de \(voz.nombre).") { url in
            if let url, let data = try? Data(contentsOf: url) { reproducir(data, done) }
            else { DispatchQueue.main.async { done?() } }
        }
    }

    /// Reproduce audio (mp3/wav) ya generado.
    private static func reproducir(_ data: Data, _ done: (() -> Void)?) {
        DispatchQueue.main.async {
            do {
                let p = try AVAudioPlayer(data: data)
                p.delegate = fin
                fin.alTerminar = done
                player = p
                p.play()
            } catch {
                Log.log(.ia, "TTS: no pude reproducir el audio (\(error.localizedDescription)) → voz de macOS")
                TTS.hablar("") { done?() }   // cae a nada; el llamador ya tiene su texto pegado
                done?()
            }
        }
    }

    private static let fin = FinReproduccion()
}

private final class FinReproduccion: NSObject, AVAudioPlayerDelegate {
    var alTerminar: (() -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let cb = alTerminar; alTerminar = nil; DispatchQueue.main.async { cb?() }
    }
}

// MARK: - ElevenLabs TTS (voz clonada "Bto", nube)

enum ElevenLabsTTS {
    /// Sintetiza `texto` con la voz clonada y devuelve el mp3 (o nil si falla).
    /// https fail-closed: solo va sobre TLS con la API key en el header.
    static func decir(_ texto: String, completion: @escaping (Data?) -> Void) {
        guard let key = Config.apiKey(), !key.isEmpty else {
            Log.log(.ia, "TTS ElevenLabs: sin API key"); completion(nil); return
        }
        let voz = Config.ttsElevenVoz()
        let modelo = Config.ttsElevenModelo()
        // mp3 estándar (fácil de reproducir con AVAudioPlayer). El streaming PCM
        // por WebSocket es la sub-fase siguiente.
        let urlStr = "https://api.elevenlabs.io/v1/text-to-speech/\(voz)?output_format=mp3_44100_128"
        guard let url = URL(string: urlStr) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.timeoutInterval = 20
        let cuerpo: [String: Any] = [
            "text": texto,
            "model_id": modelo,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "speed": 1.0],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if let data, (200..<300).contains(code), !data.isEmpty {
                Log.log(.ia, "TTS ElevenLabs OK (\(data.count) bytes)")
                completion(data)
            } else {
                let motivo = err?.localizedDescription
                    ?? "HTTP \(code): \(data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(120).description ?? "")"
                Log.log(.ia, "TTS ElevenLabs falló (\(motivo))")
                completion(nil)
            }
        }.resume()
    }
}

// MARK: - XTTS local (tu clon 100% offline, VozClonPOC/clonar.sh)

enum XttsLocalTTS {
    /// Genera el audio con tu clon local y devuelve la URL del archivo (o nil).
    /// Parametrizable: Config.ttsXttsCmd es un comando de shell donde {texto} y
    /// {salida} se sustituyen (ej. `bash ~/Downloads/VozClonPOC/clonar.sh decir Bto run/ckpt.pth "{texto}" {salida}`).
    /// Vacío = motor no configurado → failover. NO bloquea la UI (corre en background).
    static func decir(_ texto: String, completion: @escaping (URL?) -> Void) {
        // La voz activa de la biblioteca manda; si no hay ninguna, el comando suelto (compat).
        let plantilla = VocesLocales.activa()?.cmd ?? Config.ttsXttsCmd()
        decirCon(cmd: plantilla, texto: texto, completion: completion)
    }

    /// Genera con un comando concreto (para probar una voz sin fijarla activa).
    static func decirCon(cmd plantilla: String, texto: String, completion: @escaping (URL?) -> Void) {
        guard !plantilla.trimmingCharacters(in: .whitespaces).isEmpty else { completion(nil); return }
        let salida = FileManager.default.temporaryDirectory
            .appendingPathComponent("betodicta-xtts-\(abs(texto.hashValue)).mp3")
        // Sustitución segura: el texto va escapado entre comillas por la plantilla.
        let escapado = texto.replacingOccurrences(of: "\"", with: "'")
        let cmd = plantilla
            .replacingOccurrences(of: "{texto}", with: escapado)
            .replacingOccurrences(of: "{salida}", with: salida.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", cmd]
            do {
                try p.run(); p.waitUntilExit()
            } catch {
                Log.log(.ia, "TTS XTTS local: no pude ejecutar (\(error.localizedDescription))")
                completion(nil); return
            }
            if p.terminationStatus == 0, FileManager.default.fileExists(atPath: salida.path) {
                completion(salida)
            } else {
                Log.log(.ia, "TTS XTTS local: el comando no generó audio (status \(p.terminationStatus))")
                completion(nil)
            }
        }
    }
}

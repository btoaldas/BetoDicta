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

    /// Motores en orden de intento: el ELEGIDO y, si falla, la voz de macOS (neutral).
    /// NUNCA cae a otra voz CLONADA (sonaría otra persona): si eliges el clon de mamá y
    /// falla, hablas con la voz de macOS, no con la de otro. Apple nunca falla.
    private static func cadena() -> [String] {
        let principal = Config.ttsProveedor()
        return principal == "apple" ? ["apple"] : [principal, "apple"]
    }

    /// Preactiva el servidor XTTS si el clon local es el motor activo (modelo en RAM →
    /// respuesta rápida). Se llama al arrancar y al cambiar de motor/voz. No bloquea.
    static func preactivarLocal() {
        guard Config.ttsActivo(), Config.ttsProveedor() == "xtts_local", Config.ttsXttsPreactivar(),
              VozEngine.estado() == .listo, let voz = VocesLocales.activa(), !voz.paquete.isEmpty else {
            XttsServer.detener(); return   // si ya no aplica, libera la RAM del modelo
        }
        XttsServer.asegurar(paquete: URL(fileURLWithPath: voz.paquete)) { listo in
            Log.log(.ia, "servidor XTTS \(listo ? "listo (modelo en RAM)" : "no arrancó")")
        }
    }

    /// Detiene cualquier voz en curso (Apple o audio reproduciéndose).
    static func detener() {
        TTS.detener()
        player?.stop(); player = nil
    }

    /// Dice el texto con el motor configurado (con failover). `empezar` se dispara cuando
    /// la voz REALMENTE arranca (para sincronizar el texto del notch con el habla);
    /// `completion` al terminar.
    static func decir(_ texto: String, empezar: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { empezar?(); completion?(); return }
        intentar(t, cadena(), 0, empezar, completion)
    }

    private static func intentar(_ texto: String, _ orden: [String], _ i: Int,
                                 _ empezar: (() -> Void)?, _ done: (() -> Void)?) {
        guard i < orden.count else { done?(); return }
        let motor = orden[i]
        let siguiente: () -> Void = { intentar(texto, orden, i + 1, empezar, done) }
        switch motor {
        case "apple":
            // Respaldo final: no falla. Reproduce con la voz de macOS.
            empezar?(); TTS.hablar(texto) { done?() }
        case "elevenlabs":
            // Streaming WS (suena mientras se genera); si falla, cae al batch mp3;
            // si el batch también falla, al siguiente motor.
            if Config.ttsElevenStreaming() {
                empezar?()
                ElevenLabsStreamTTS.hablar(texto) { ok in
                    if ok { done?() } else {
                        Log.log(.ia, "TTS ElevenLabs WS falló → batch")
                        ElevenLabsTTS.decir(texto) { data in
                            if let data { reproducir(data, empezar, done) } else {
                                Log.log(.ia, "TTS ElevenLabs batch falló → siguiente motor"); siguiente()
                            }
                        }
                    }
                }
            } else {
                ElevenLabsTTS.decir(texto) { data in
                    if let data { reproducir(data, empezar, done) } else {
                        Log.log(.ia, "TTS ElevenLabs falló → siguiente motor"); siguiente()
                    }
                }
            }
        case "xtts_local":
            // Si la voz activa es PIPER (.onnx) → carril RÁPIDO (voz fija, ~instantánea).
            if let voz = VocesLocales.activa(), !voz.onnx.isEmpty, PiperTTS.disponible {
                PiperTTS.decir(onnx: URL(fileURLWithPath: voz.onnx), texto: texto) { url in
                    if let url, let data = try? Data(contentsOf: url) { reproducir(data, empezar, done) } else {
                        Log.log(.ia, "TTS Piper falló → siguiente motor"); siguiente()
                    }
                }
                return
            }
            // Voz con PAQUETE + motor interno listo → lo corre BetoDicta solo (XTTS).
            // Si no, cae al comando (bootstrap/externo). Si nada → siguiente motor.
            if let voz = VocesLocales.activa(), !voz.paquete.isEmpty, VozEngine.estado() == .listo {
                let pkg = URL(fileURLWithPath: voz.paquete)
                let batch: () -> Void = {
                    VozEngine.correrPaquete(carpeta: pkg, texto: texto) { url in
                        if let url, let data = try? Data(contentsOf: url) { reproducir(data, empezar, done) } else {
                            Log.log(.ia, "TTS motor interno falló → siguiente motor"); siguiente()
                        }
                    }
                }
                let porStream: () -> Void = {
                    if voz.streaming {
                        empezar?()
                        XttsStreamTTS.hablar(paquete: pkg, texto: texto) { ok in
                            if ok { done?() } else { Log.log(.ia, "TTS XTTS streaming falló → batch"); batch() }
                        }
                    } else { batch() }
                }
                // RÁPIDO: si el servidor residente está listo para esta voz, úsalo (modelo
                // ya cargado → ~1-2s). Si no, arráncalo para la próxima y esta vez va por
                // streaming directo.
                if XttsServer.corriendo, XttsServer.paqueteActivo == pkg.path {
                    XttsServer.decir(texto: texto, empezar: empezar) { ok in if ok { done?() } else { porStream() } }
                } else {
                    if Config.ttsXttsPreactivar() { XttsServer.asegurar(paquete: pkg) { _ in } }
                    porStream()
                }
            } else {
                XttsLocalTTS.decir(texto) { url in
                    if let url, let data = try? Data(contentsOf: url) { reproducir(data, empezar, done) } else {
                        Log.log(.ia, "TTS XTTS local no disponible → siguiente motor"); siguiente()
                    }
                }
            }
        default:
            // Motor de NUBE del catálogo. Con WS + streaming ON → suena mientras genera;
            // si falla → batch; si el batch falla → siguiente motor.
            if let p = TTSCloud.proveedor(motor) {
                let batch: () -> Void = {
                    TTSCloud.decir(motor, texto: texto) { data in
                        if let data { reproducir(data, empezar, done) } else {
                            Log.log(.ia, "TTS \(motor) no disponible → siguiente motor"); siguiente()
                        }
                    }
                }
                if p.ws, Config.ttsCloudStreaming(motor), TTSCloudStream.soporta(motor) {
                    empezar?()
                    TTSCloudStream.hablar(motor, texto: texto) { ok in
                        if ok { done?() } else { Log.log(.ia, "TTS \(motor) WS falló → batch"); batch() }
                    }
                } else { batch() }
            } else { siguiente() }
        }
    }

    /// Prueba UNA voz local concreta (la genera con su comando y la reproduce),
    /// sin importar cuál sea el motor activo. Para el botón "Probar" de la biblioteca.
    static func probarVozLocal(_ voz: VozLocal, _ done: (() -> Void)? = nil) {
        let saludo = "Hola, esta es la voz de \(voz.nombre)."
        let cb: (URL?) -> Void = { url in
            if let url, let data = try? Data(contentsOf: url) { reproducir(data, nil, done) }
            else { DispatchQueue.main.async { done?() } }
        }
        if !voz.paquete.isEmpty, VozEngine.estado() == .listo {
            VozEngine.correrPaquete(carpeta: URL(fileURLWithPath: voz.paquete), texto: saludo, completion: cb)
        } else {
            XttsLocalTTS.decirCon(cmd: voz.cmd, texto: saludo, completion: cb)
        }
    }

    /// Reproduce audio (mp3/wav) ya generado. `empezar` justo antes de sonar (sync texto).
    private static func reproducir(_ data: Data, _ empezar: (() -> Void)?, _ done: (() -> Void)?) {
        DispatchQueue.main.async {
            do {
                let p = try AVAudioPlayer(data: data)
                p.delegate = fin
                fin.alTerminar = done
                player = p
                empezar?()
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

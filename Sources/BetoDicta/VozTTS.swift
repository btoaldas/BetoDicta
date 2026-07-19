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
//   3) xtts_local  — tu clon LOCAL gestionado por BetoDicta, 100% offline y gratis.
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

    /// Preactiva SOLO el servidor de la variante local elegida. XTTS y Qwen/MLX nunca
    /// quedan cargados a la vez: cambia calidad/velocidad sin desperdiciar RAM.
    static func preactivarLocal() {
        guard Config.ttsActivo(), Config.ttsProveedor() == "xtts_local",
              let voz = VocesLocales.activa() else {
            XttsServer.detener(); MlxVozServer.detener(); return
        }
        // La Máxima INTERNA reutiliza XTTS residente y después restaura el WAV: misma
        // identidad, sin volver a cargar 2 GB por frase. Solo el legado externo evita
        // precargar porque administra su propio proceso.
        if voz.variante == "maxima", voz.tieneMaxima {
            MlxVozServer.detener()
            if !voz.maximaInterna { XttsServer.detener(); return }
        }
        if voz.variante == "mlx", voz.tieneMlx {
            XttsServer.detener()
            guard Config.ttsMlxPreactivar(), MlxVozEngine.estado() == .listo else {
                MlxVozServer.detener(); return
            }
            MlxVozServer.asegurar(voz: voz) { listo in
                Log.log(.ia, "Qwen3-MLX \(listo ? "listo (equilibrada en RAM)" : "no arrancó")")
            }
            return
        }
        MlxVozServer.detener()
        guard Config.ttsXttsPreactivar(), VozEngine.estado() == .listo,
              !voz.paquete.isEmpty, voz.variante != "onnx" else {
            XttsServer.detener(); return
        }
        XttsServer.asegurar(paquete: URL(fileURLWithPath: voz.paquete)) { listo in
            Log.log(.ia, "servidor XTTS \(listo ? "listo (modelo en RAM)" : "no arrancó")")
        }
    }

    /// Detiene cualquier voz en curso (Apple o audio reproduciéndose).
    static func detener() {
        TTS.detener()
        player?.stop(); player = nil
        MlxVozServer.pararVoz()
    }

    /// Bandera de cancelación: corta la cascada de failover (no pasa al siguiente motor).
    private(set) static var cancelado = false
    /// ¿Hay voz sonando ahora mismo? (para saber si vale la pena cancelar).
    static var hablando: Bool {
        (player?.isPlaying ?? false) || TTS.hablando
            || ElevenLabsStreamTTS.activo != nil || XttsStreamTTS.activo != nil
            || TTSCloudStream.activo != nil || MlxVozServer.hablando
    }

    /// CANCELAR TODO lo de voz: para Apple, el audio por lotes, y TODOS los streaming
    /// (WS/local), y corta la cascada de failover. El servidor XTTS residente NO se mata
    /// (para que la próxima respuesta siga rápida), solo su reproducción.
    static func cancelar() {
        cancelado = true
        TTS.detener()
        player?.stop(); player = nil
        ElevenLabsStreamTTS.cancelar()
        XttsStreamTTS.cancelar()
        TTSCloudStream.cancelar()
        XttsServer.pararVoz()
        MlxVozServer.pararVoz()
    }

    /// Dice el texto con el motor configurado (con failover). `empezar` se dispara cuando
    /// la voz REALMENTE arranca (para sincronizar el texto del notch con el habla);
    /// `completion` al terminar. CONTRATO: ambos callbacks llegan siempre en MAIN, aunque
    /// el motor sea URLSession/WebSocket y responda desde su cola de red.
    static func decir(_ texto: String, empezar: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let inicioMain: (() -> Void)? = empezar.map { cb in { ejecutarEnMain(cb) } }
        let finMain: (() -> Void)? = completion.map { cb in { ejecutarEnMain(cb) } }
        guard !t.isEmpty else { inicioMain?(); finMain?(); return }
        ejecutarEnMain {
            cancelado = false
            intentar(t, cadena(), 0, inicioMain, finMain)
        }
    }

    private static func ejecutarEnMain(_ bloque: @escaping () -> Void) {
        if Thread.isMainThread { bloque() }
        else { DispatchQueue.main.async(execute: bloque) }
    }

    private static func intentar(_ texto: String, _ orden: [String], _ i: Int,
                                 _ empezar: (() -> Void)?, _ done: (() -> Void)?) {
        if cancelado { done?(); return }   // cancelado → cortar la cascada de failover
        guard i < orden.count else { done?(); return }
        let motor = orden[i]
        let siguiente: () -> Void = {
            ejecutarEnMain { intentar(texto, orden, i + 1, empezar, done) }
        }
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
            guard let local = VocesLocales.activa() else { siguiente(); return }
            intentarLocal(local, texto: texto, empezar: empezar, done: done,
                          alAgotar: siguiente)
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

    /// Failover ENTRE VARIANTES de la MISMA persona. Nunca cambia a otro clon: si la
    /// equilibrada falla puede probar Calidad/Rápida y solo después cae a macOS.
    private static func intentarLocal(_ voz: VozLocal, texto: String,
                                      empezar: (() -> Void)?, done: (() -> Void)?,
                                      alAgotar: @escaping () -> Void) {
        let principal = ["maxima", "xtts", "mlx", "onnx"].contains(voz.variante) ? voz.variante : "xtts"
        let resto: [String]
        switch principal {
        case "maxima": resto = ["xtts", "mlx", "onnx"]
        case "mlx": resto = ["maxima", "xtts", "onnx"]
        case "onnx": resto = ["mlx", "xtts", "maxima"]
        default: resto = ["maxima", "mlx", "onnx"]
        }
        let candidatas = Config.ttsLocalVariantesFailover() ? [principal] + resto : [principal]
        let disponibles = candidatas.filter { variante in
            switch variante {
            case "maxima":
                return voz.maximaInterna
                    ? (voz.tieneMaxima && VozMaximaEngine.estado() == .listo)
                    : voz.tieneMaxima
            case "mlx": return voz.tieneMlx && MlxVozEngine.estado() == .listo
            case "onnx": return !voz.onnx.isEmpty && PiperTTS.disponible
            default: return (!voz.paquete.isEmpty && VozEngine.estado() == .listo) || !voz.cmd.isEmpty
            }
        }

        func probar(_ indice: Int) {
            if cancelado { done?(); return }
            guard indice < disponibles.count else { alAgotar(); return }
            let variante = disponibles[indice]
            let fallo: () -> Void = {
                Log.log(.ia, "TTS local \(variante) falló → \(indice + 1 < disponibles.count ? disponibles[indice + 1] : "macOS")")
                ejecutarEnMain { probar(indice + 1) }
            }
            switch variante {
            case "maxima":
                MlxVozServer.detener()
                let generado: (@escaping (URL?) -> Void) -> Void = { cb in
                    if voz.maximaInterna { VozMaximaEngine.decir(voz: voz, texto: texto, completion: cb) }
                    else { XttsServer.detener(); XttsLocalTTS.decirCon(cmd: voz.cmd, texto: texto, completion: cb) }
                }
                generado { url in
                    if let url, let data = try? Data(contentsOf: url) {
                        reproducir(data, empezar, done)
                    } else { fallo() }
                }
            case "mlx":
                XttsServer.detener()
                MlxVozServer.decir(voz: voz, texto: texto, empezar: empezar) { ok in
                    ok ? done?() : fallo()
                }
            case "onnx":
                PiperTTS.decir(onnx: URL(fileURLWithPath: voz.onnx), texto: texto) { url in
                    if let url, let data = try? Data(contentsOf: url) {
                        reproducir(data, empezar, done)
                    } else { fallo() }
                }
            default:
                MlxVozServer.detener()
                intentarXtts(voz, texto: texto, empezar: empezar, done: done, fallo: fallo)
            }
        }
        probar(0)
    }

    private static func intentarXtts(_ voz: VozLocal, texto: String,
                                     empezar: (() -> Void)?, done: (() -> Void)?,
                                     fallo: @escaping () -> Void) {
        guard !voz.paquete.isEmpty, VozEngine.estado() == .listo else {
            guard !voz.cmd.isEmpty else { fallo(); return }
            XttsLocalTTS.decirCon(cmd: voz.cmd, texto: texto) { url in
                if let url, let data = try? Data(contentsOf: url) { reproducir(data, empezar, done) }
                else { fallo() }
            }
            return
        }
        let pkg = URL(fileURLWithPath: voz.paquete)
        let batch: () -> Void = {
            VozEngine.correrPaquete(carpeta: pkg, texto: texto) { url in
                if let url, let data = try? Data(contentsOf: url) { reproducir(data, empezar, done) }
                else { fallo() }
            }
        }
        let porStream: () -> Void = {
            if voz.streaming {
                empezar?()
                XttsStreamTTS.hablar(paquete: pkg, texto: texto) { ok in
                    if ok { done?() }
                    else { Log.log(.ia, "TTS XTTS streaming falló → batch"); batch() }
                }
            } else { batch() }
        }
        if XttsServer.corriendo, XttsServer.paqueteActivo == pkg.path {
            XttsServer.decir(texto: texto, empezar: empezar) { ok in
                if ok { done?() } else { porStream() }
            }
        } else {
            if Config.ttsXttsPreactivar() { XttsServer.asegurar(paquete: pkg) { _ in } }
            porStream()
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
        let usaPiper = !voz.onnx.isEmpty && (voz.paquete.isEmpty || voz.variante == "onnx")
        if voz.variante == "maxima", voz.tieneMaxima {
            if voz.maximaInterna { VozMaximaEngine.decir(voz: voz, texto: saludo, completion: cb) }
            else { XttsLocalTTS.decirCon(cmd: voz.cmd, texto: saludo, completion: cb) }
        } else if voz.variante == "mlx", voz.tieneMlx, MlxVozEngine.estado() == .listo {
            MlxVozServer.decir(voz: voz, texto: saludo, empezar: nil) { _ in done?() }
        } else if usaPiper, PiperTTS.disponible {
            PiperTTS.decir(onnx: URL(fileURLWithPath: voz.onnx), texto: saludo, completion: cb)
        } else if !voz.paquete.isEmpty, VozEngine.estado() == .listo {
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

// MARK: - XTTS local (tu clon 100% offline; comando externo solo por compatibilidad)

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

import AVFoundation
import Foundation

// MARK: - Bitácora continua: tanda diferida
//
// Transcribe en bloque lo que la bitácora fue grabando, y de paso comprime el
// audio crudo. Se ejecuta cuando el usuario lo pida —cada tantos minutos, a una
// hora fija, al encender, al apagar o a mano— y nunca mientras se dicta.
//
// Diferir es el punto: transcribir en caliente mantiene un modelo de voz
// ocupando CPU todo el día. En una sola pasada, con el equipo enchufado, sale
// mucho más barato y no se nota.
//
// Reanudable por construcción: el índice marca cada fragmento como procesado
// solo cuando su texto ya está guardado. Si la tanda se corta a la mitad, la
// siguiente sigue donde quedó sin repetir trabajo.

enum ContinuoLote {

    private static let cola = DispatchQueue(label: "betodicta.continuo.lote", qos: .utility)
    private static var enMarcha = false
    private static let candado = NSLock()

    /// Última vez que se vio actividad de dictado, para no arrancar encima.
    static var dictadoOcupado: (() -> Bool)?

    // MARK: Entrada

    /// Lanza una tanda si procede. `manual` salta las condiciones de energía
    /// porque lo pidió una persona mirando la pantalla.
    static func ejecutar(manual: Bool = false, alTerminar: ((String) -> Void)? = nil) {
        candado.lock()
        if enMarcha {
            candado.unlock()
            alTerminar?("Ya hay una tanda en curso.")
            return
        }
        enMarcha = true
        candado.unlock()

        cola.async {
            let resumen = trabajar(manual: manual)
            candado.lock(); enMarcha = false; candado.unlock()
            Log.log(.sistema, "bitácora: \(resumen)")
            DispatchQueue.main.async { alTerminar?(resumen) }
        }
    }

    static var ocupado: Bool {
        candado.lock(); defer { candado.unlock() }
        return enMarcha
    }

    // MARK: Trabajo

    private static func trabajar(manual: Bool) -> String {
        guard Config.continuoActivo() else { return "la bitácora está apagada" }
        if !manual, Config.continuoLoteSoloConCorriente(), !EnergiaMac.conCorriente() {
            return "tanda pospuesta: el equipo está con batería"
        }

        ContinuoIndice.shared.abrir()
        let pendientes = ContinuoIndice.shared.pendientes(material: .audio,
                                                          limite: Config.continuoLoteMaximoPorTanda())
        // Sin audio pendiente NO se sale: puede quedar pantalla por leer, y
        // saltarse el OCR por eso era un error de cableado.
        if pendientes.isEmpty {
            return leerPantallas(prefijo: "no había audio pendiente")
        }

        Log.log(.sistema, "bitácora: tanda con \(pendientes.count) fragmentos pendientes")
        var hechos = 0, fallos = 0, saltados = 0
        var comprimidos: Int64 = 0

        for p in pendientes {
            // El dictado manda también aquí: si la persona está hablando, la
            // tanda espera. Transcribir de fondo mientras se dicta compite por
            // CPU justo en el momento en que más se nota.
            if dictadoOcupado?() == true {
                Log.log(.sistema, "bitácora: tanda en pausa, hay dictado en curso")
                return "tanda detenida al empezar un dictado — \(hechos) hechos, quedan \(pendientes.count - hechos)"
            }
            guard FileManager.default.fileExists(atPath: p.ruta.path) else {
                // El archivo se borró por fuera: se marca para no reintentarlo eternamente.
                ContinuoIndice.shared.anotarTexto("", material: .audio, id: p.id)
                saltados += 1
                continue
            }

            switch transcribir(p.ruta) {
            case .success(let texto):
                ContinuoIndice.shared.anotarTexto(texto, material: .audio, id: p.id)
                guardarTexto(texto, junto: p.ruta)
                hechos += 1
                if Config.continuoLoteComprimir(), p.ruta.pathExtension == "pcm" {
                    if let ahorro = comprimir(p.ruta, id: p.id) { comprimidos += ahorro }
                }
            case .failure(let e):
                fallos += 1
                Log.log(.sistema, "bitácora: no pude transcribir \(p.ruta.lastPathComponent) — \(e.localizedDescription)")
            }
        }

        var partes = ["tanda terminada: \(hechos) transcritos"]
        if fallos > 0 { partes.append("\(fallos) con error") }
        if saltados > 0 { partes.append("\(saltados) sin archivo") }
        if comprimidos > 0 { partes.append("\(ContinuoBitacora.tamanoLegible(comprimidos)) liberados") }

        return leerPantallas(prefijo: partes.joined(separator: ", "))
    }

    /// Texto de las capturas, en la MISMA pasada que el audio: si ya pagamos el
    /// coste de despertar el equipo para transcribir, leer la pantalla sale
    /// prácticamente gratis.
    private static func leerPantallas(prefijo: String) -> String {
        guard Config.continuoOcrActivo() else { return prefijo }
        let ocr = ContinuoOCR.procesarPendientes(limite: Config.continuoLoteMaximoPorTanda()) {
            dictadoOcupado?() == true
        }
        guard ocr.hechas > 0 else { return prefijo }
        return prefijo + ", \(ocr.hechas) capturas leídas (\(ocr.conTexto) con texto)"
    }

    /// Lanza el resumen del día tras la tanda, si está activado. Separado del
    /// trabajo principal porque es lo único del módulo que puede salir del
    /// equipo: falla sin arrastrar al resto.
    static func resumirDia(_ dia: Date = Date(), alTerminar: ((String) -> Void)? = nil) {
        guard Config.continuoResumenActivo() else {
            alTerminar?("el resumen con IA está desactivado"); return
        }
        ContinuoResumen.generar(dia: dia) { r in
            switch r {
            case .success(let url): alTerminar?("resumen escrito en \(url.lastPathComponent)")
            case .failure(let e): alTerminar?("no pude resumir: \(e.localizedDescription)")
            }
        }
    }

    // MARK: Transcripción

    /// Convierte el fragmento a WAV y lo pasa por el motor elegido. Síncrono a
    /// propósito: la tanda es secuencial y así no hay que orquestar nada.
    private static func transcribir(_ url: URL) -> Result<String, Error> {
        guard let crudo = try? Data(contentsOf: url), !crudo.isEmpty else {
            return .failure(ErrorLote.archivoVacio)
        }
        // Los fragmentos propios son PCM crudo; los adoptados del dictado ya son
        // WAV con cabecera.
        let wav = url.pathExtension == "pcm" ? HistoryWriter.wavData(pcm: crudo) : crudo

        let semaforo = DispatchSemaphore(value: 0)
        var salida: Result<String, Error> = .failure(ErrorLote.sinRespuesta)

        switch Config.continuoLoteMotor() {
        case "apple_speech":
            AppleSpeechSTT.run(wav: wav) { r in salida = r; semaforo.signal() }
        case "whisper_local":
            WhisperServer.transcribe(wav: wav) { r in salida = r; semaforo.signal() }
        default:
            AppleSpeechSTT.run(wav: wav) { r in salida = r; semaforo.signal() }
        }

        // Tope generoso: un fragmento de dos minutos en local puede tardar.
        if semaforo.wait(timeout: .now() + 300) == .timedOut {
            return .failure(ErrorLote.tiempoAgotado)
        }
        return salida
    }

    /// Deja el texto junto al audio, para poder leerlo sin la app.
    private static func guardarTexto(_ texto: String, junto url: URL) {
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let destino = url.deletingPathExtension().appendingPathExtension("txt")
        try? texto.write(to: destino, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destino.path)
    }

    // MARK: Compresión

    /// PCM crudo a m4a, ahora que el fragmento ya está transcrito y cerrado.
    /// Devuelve los bytes ahorrados, o nil si no se pudo y se conserva el crudo.
    private static func comprimir(_ pcm: URL, id: Int64) -> Int64? {
        guard let crudo = try? Data(contentsOf: pcm), crudo.count > 1_024 else { return nil }
        let destino = pcm.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: destino)

        let ajustes: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000
        ]
        do {
            var archivo: AVAudioFile? = try AVAudioFile(forWriting: destino, settings: ajustes)
            guard let salida = archivo else { return nil }

            // El buffer DEBE ir en el processingFormat del archivo (Float32), no
            // en Int16: `write(from:)` lanza si el formato no coincide, y ese
            // fallo dejaba antes un contenedor de 28 bytes.
            let formato = salida.processingFormat
            let marcos = AVAudioFrameCount(crudo.count / 2)
            guard marcos > 0, let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: marcos) else {
                archivo = nil
                try? FileManager.default.removeItem(at: destino)
                return nil
            }
            buffer.frameLength = marcos
            guard let destinoCanal = buffer.floatChannelData else {
                archivo = nil
                try? FileManager.default.removeItem(at: destino)
                return nil
            }
            crudo.withUnsafeBytes { bytes in
                guard let origen = bytes.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0..<Int(marcos) {
                    destinoCanal[0][i] = Float(origen[i]) / 32768.0
                }
            }
            try salida.write(from: buffer)
            // El contenedor MPEG-4 se finaliza al liberar la instancia.
            archivo = nil

            let escrito = ((try? FileManager.default.attributesOfItem(atPath: destino.path))?[.size] as? Int64) ?? 0
            guard escrito > 1_024 else {
                try? FileManager.default.removeItem(at: destino)
                return nil
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destino.path)
            let antes = Int64(crudo.count)
            ContinuoIndice.shared.reemplazarRuta(id: id, material: .audio, por: destino, bytes: escrito)
            try? FileManager.default.removeItem(at: pcm)
            // El .txt conserva el mismo nombre base que el audio, así que no
            // hay que moverlo: sigue emparejado con el .m4a.
            return antes - escrito
        } catch {
            Log.log(.sistema, "bitácora: no pude comprimir \(pcm.lastPathComponent) — \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: destino)
            return nil
        }
    }

    enum ErrorLote: LocalizedError {
        case archivoVacio, sinRespuesta, tiempoAgotado
        var errorDescription: String? {
            switch self {
            case .archivoVacio: return "el fragmento está vacío"
            case .sinRespuesta: return "el motor no respondió"
            case .tiempoAgotado: return "se agotó el tiempo de transcripción"
            }
        }
    }
}

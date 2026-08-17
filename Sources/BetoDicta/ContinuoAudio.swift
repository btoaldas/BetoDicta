import AppKit
import AVFoundation

// MARK: - Bitácora continua: audio
//
// Graba el micrófono en segundo plano, en trozos cerrados periódicamente.
//
// REGLA INNEGOCIABLE: el dictado por doble Fn manda. Cuando arranca, esta
// bitácora suelta el micrófono y espera; cuando termina, vuelve sola. Eso NO es
// configurable a propósito — un interruptor ahí acabaría rompiendo el dictado.
//
// Y ceder no deja hueco: mientras dictas, el propio dictado ya escribe su audio
// en `historial/`, y `adoptar(...)` lo incorpora a la línea de tiempo. La
// cobertura es continua sin tocar `Recorder` ni `ActivacionVoz`.
//
// El audio se escribe PCM crudo al instante (sobrevive a cualquier cierre
// abrupto) y se comprime cuando el trozo ya está cerrado. Al revés —escribir
// m4a en vivo— un corte dejaría el contenedor sin cerrar y el trozo entero
// ilegible: `AVAudioFile` no expone `close()`, se finaliza al liberarse.

final class ContinuoAudio {

    static let shared = ContinuoAudio()

    private let cola = DispatchQueue(label: "betodicta.continuo.audio")
    private let comprimir = DispatchQueue(label: "betodicta.continuo.audio.comprimir", qos: .utility)

    private var engine: AVAudioEngine?
    private var conversor: AVAudioConverter?
    private let formatoSalida = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                              sampleRate: 16000, channels: 1, interleaved: true)!

    private var mano: FileHandle?
    private var rutaTrozo: URL?
    private var inicioTrozo = Date()
    private var bytesTrozo = 0

    /// Cedido al dictado. Distinto de "apagado": aquí volvemos solos.
    private var cedido = false
    /// Evita que dos arranques concurrentes se pisen el trozo abierto.
    private var montando = false
    /// Intentos de arranque encadenados (micrófono ocupado).
    private var intentos = 0
    /// Solo para diagnóstico: cuántos buffers ha entregado el tap.
    private var buffersVistos = 0
    private(set) var activo = false

    /// Modo `voz`: colchón previo para no cortar la primera sílaba.
    private var colchon = Data()
    private var hablando = false
    private var ultimaVoz = Date.distantPast

    private init() {}

    // MARK: Ciclo de vida

    /// Enciende la bitácora si el ajuste lo permite. Idempotente.
    func arrancar() {
        guard Config.continuoActivo(), Config.continuoAudioModo() != "manual" else { return }
        cola.async { [weak self] in self?.arrancarEnCola() }
    }

    func detener() {
        cola.async { [weak self] in self?.detenerEnCola(cerrandoTrozo: true) }
    }

    /// El dictado pide el micrófono. Suelta TODO y avisa cuando esté libre —
    /// misma semántica que `ActivacionVoz.suspender`, para que `AppDelegate`
    /// encadene las dos igual.
    func suspender(completion: @escaping () -> Void) {
        cola.async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion() }; return }
            self.cedido = true
            self.detenerEnCola(cerrandoTrozo: true)
            DispatchQueue.main.async { completion() }
        }
    }

    /// El dictado terminó: recuperamos el micrófono si seguimos encendidos.
    func reanudar() {
        cola.async { [weak self] in
            guard let self else { return }
            self.cedido = false
            guard Config.continuoActivo(), Config.continuoAudioModo() != "manual" else { return }
            self.arrancarEnCola()
        }
    }

    // MARK: Arranque real

    private func arrancarEnCola() {
        // `montando` cierra una reentrada real: `reconciliarActivacionVoz` llama
        // a `reanudar()` cada vez que cambia el estado del micrófono, y mientras
        // el montaje espera en `main.sync` la bandera `activo` todavía es falsa.
        // Sin esto, el segundo arranque abría otro trozo y dejaba al tap del
        // primero escribiendo en un descriptor ya cerrado: 0 bytes en disco.
        guard !activo, !cedido, !montando else { return }
        montando = true
        defer { montando = false }
        if Config.continuoSoloConCorriente(), !EnergiaMac.conCorriente() {
            Log.log(.sistema, "bitácora: con batería y el ajuste pide corriente — no arranco el audio")
            return
        }

        // TODO el montaje del motor va en el hilo principal, no solo el
        // constructor: `inputNode`, `installTap` y `start()` incluidos. Montarlo
        // desde una cola de fondo deja un nodo que arranca sin quejarse pero
        // nunca entrega un solo buffer — el tap no se dispara y el archivo queda
        // en 0 bytes. Es el mismo requisito que respeta `ActivacionVoz`.
        // El archivo NO se abre aquí. Se abre solo cuando llega el primer trozo
        // de audio de verdad (`escribir`), porque el motor puede no arrancar:
        // abrirlo antes dejaba un .pcm de 0 bytes por cada intento fallido.
        var arrancado = false
        DispatchQueue.main.sync { arrancado = self.montarEnMain() }
        guard arrancado else { reintentar(); return }
        intentos = 0
        activo = true
        Log.log(.sistema, "bitácora: audio en marcha (modo \(Config.continuoAudioModo()), eco \(Config.continuoAudioCancelacionEco() ? "sí" : "no"))")
    }

    /// El dispositivo de entrada puede estar ocupado al arrancar la app: la
    /// propia BetoDicta monta su audio en esos primeros segundos y CoreAudio
    /// devuelve -10875. No es un fallo definitivo, es "todavía no". Se reintenta
    /// con espera creciente y se abandona tras varios intentos para no dejar un
    /// bucle eterno pidiendo un micrófono que otro tiene.
    private func reintentar() {
        intentos += 1
        guard intentos <= 6 else {
            Log.log(.sistema, "bitácora: el micrófono sigue ocupado tras \(intentos) intentos — lo dejo hasta el próximo cambio de estado")
            intentos = 0
            return
        }
        let espera = Double(intentos) * 2.5
        Log.log(.sistema, "bitácora: micrófono ocupado, reintento \(intentos) en \(espera) s")
        cola.asyncAfter(deadline: .now() + espera) { [weak self] in self?.arrancarEnCola() }
    }

    /// Monta el motor de captura. SOLO desde el hilo principal.
    private func montarEnMain() -> Bool {
        let motor = AVAudioEngine()
        let entrada = motor.inputNode
        entrada.removeTap(onBus: 0)

        // ORDEN CRÍTICO. `setVoiceProcessingEnabled` sustituye la AudioUnit que
        // hay debajo del nodo (pasa de HAL a VoiceProcessingIO), así que cualquier
        // propiedad fijada antes se descarta. Si fijamos el micrófono primero,
        // se pierde y macOS nos enchufa el de por defecto. Por eso: eco primero,
        // luego volver a pedir la unidad, luego el dispositivo, y solo entonces
        // leer el formato.
        if Config.continuoAudioCancelacionEco() {
            do {
                try entrada.setVoiceProcessingEnabled(true)
            } catch {
                Log.log(.sistema, "bitácora: no pude activar la cancelación de eco (\(error.localizedDescription)) — sigo sin ella")
            }
        }
        if let dev = Microfono.elegido(), let au = entrada.audioUnit {
            var id = dev
            AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &id,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        let formatoEntrada = entrada.outputFormat(forBus: 0)
        guard formatoEntrada.sampleRate > 0 else {
            Log.log(.sistema, "bitácora: el micrófono no entregó formato válido — no arranco")
            return false
        }
        let conv = AVAudioConverter(from: formatoEntrada, to: formatoSalida)
        // El nodo de entrada puede exponer VARIOS canales (aquí llega con 9 tras
        // activar la cancelación de eco). Sin mapa de canales, la conversión a
        // mono devuelve 0 marcos y el audio se pierde sin decir nada. `[0]` toma
        // el primer canal, que es el del micrófono.
        if formatoEntrada.channelCount > 1 {
            conv?.channelMap = [0]
            Log.log(.sistema, "bitácora: entrada de \(formatoEntrada.channelCount) canales — tomo el canal 0")
        }
        conversor = conv

        Log.log(.sistema, "bitácora: formato de entrada \(formatoEntrada.sampleRate) Hz, \(formatoEntrada.channelCount) can, \(formatoEntrada.commonFormat.rawValue)")

        entrada.installTap(onBus: 0, bufferSize: 4096, format: formatoEntrada) { [weak self] buffer, _ in
            guard let self else { return }
            self.buffersVistos += 1
            if self.buffersVistos == 1 {
                Log.log(.sistema, "bitácora: el micrófono entrega audio (\(buffer.frameLength) marcos por buffer)")
            } else if self.buffersVistos % 600 == 0 {
                Log.debug("bitácora: tap #\(self.buffersVistos)")
            }
            guard let conv = self.conversor else { return }
            let razon = self.formatoSalida.sampleRate / formatoEntrada.sampleRate
            let capacidad = AVAudioFrameCount(Double(buffer.frameLength) * razon) + 64
            guard let salida = AVAudioPCMBuffer(pcmFormat: self.formatoSalida, frameCapacity: capacidad) else { return }
            var servido = false
            var fallo: NSError?
            conv.convert(to: salida, error: &fallo) { _, estado in
                if servido { estado.pointee = .noDataNow; return nil }
                servido = true
                estado.pointee = .haveData
                return buffer
            }
            if let fallo, self.buffersVistos <= 3 {
                Log.log(.sistema, "bitácora: la conversión falló — \(fallo.localizedDescription)")
            }
            guard salida.frameLength > 0, let ch = salida.int16ChannelData else { return }
            let trozo = Data(bytes: ch[0], count: Int(salida.frameLength) * 2)

            var suma: Double = 0
            let n = Int(salida.frameLength)
            for i in 0..<n {
                let v = Double(ch[0][i]) / 32768.0
                suma += v * v
            }
            let rms = (suma / Double(max(n, 1))).squareRoot()

            self.cola.async { self.recibir(trozo, rms: rms) }
        }

        motor.prepare()
        do {
            try motor.start()
        } catch {
            entrada.removeTap(onBus: 0)
            Log.log(.sistema, "bitácora: el motor de audio no arrancó (\(error.localizedDescription))")

            return false
        }
        engine = motor
        return true
    }

    private func detenerEnCola(cerrandoTrozo: Bool) {
        guard activo || engine != nil else { return }
        if let motor = engine {
            motor.inputNode.removeTap(onBus: 0)
            motor.stop()
        }
        engine = nil
        conversor = nil
        activo = false
        colchon.removeAll()
        hablando = false
        if cerrandoTrozo { cerrarTrozo() }
    }

    // MARK: Escritura

    private func recibir(_ trozo: Data, rms: Double) {
        guard activo else { return }

        if Config.continuoAudioModo() == "voz" {
            // Puerta por energía (no es un detector neuronal: es un umbral sobre
            // la señal ya tratada por la cancelación de eco). Con colchón previo
            // para no comerse el arranque de la frase, y cola de 1,5 s para no
            // cortar en cada pausa.
            let umbral = 0.004
            if rms >= umbral {
                if !hablando {
                    hablando = true
                    escribir(colchon)
                    colchon.removeAll()
                }
                ultimaVoz = Date()
            } else if hablando, Date().timeIntervalSince(ultimaVoz) > 1.5 {
                hablando = false
            }
            guard hablando else {
                colchon.append(trozo)
                // Colchón de ~1 s a 16 kHz mono 16 bits.
                if colchon.count > 32_000 { colchon.removeFirst(colchon.count - 32_000) }
                return
            }
        }

        escribir(trozo)
    }

    private func escribir(_ datos: Data) {
        guard !datos.isEmpty else { return }
        if mano == nil { abrirTrozo() }
        mano?.write(datos)
        bytesTrozo += datos.count
        if Date().timeIntervalSince(inicioTrozo) >= Double(Config.continuoAudioSegmentoSegundos()) {
            cerrarTrozo()
            abrirTrozo()
        }
    }

    private func abrirTrozo() {
        // Si ya hay un trozo abierto, ciérralo antes: abrir dos veces seguidas
        // dejaba el archivo anterior huérfano y en 0 bytes, porque `rutaTrozo`
        // se sobrescribía sin pasar por `cerrarTrozo`.
        if mano != nil { cerrarTrozo() }
        let ahora = Date()
        let carpeta = Self.carpetaDelDia(ahora, sub: "audio")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let url = carpeta.appendingPathComponent(Self.sello(ahora) + ".pcm")
        FileManager.default.createFile(atPath: url.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
        mano = try? FileHandle(forWritingTo: url)
        rutaTrozo = url
        inicioTrozo = ahora
        bytesTrozo = 0
    }

    private func cerrarTrozo() {
        try? mano?.close()
        mano = nil
        guard let url = rutaTrozo else { return }
        rutaTrozo = nil
        let inicio = inicioTrozo
        let bytes = bytesTrozo

        // Un trozo de menos de medio segundo no aporta nada.
        guard bytes > 16_000 else { try? FileManager.default.removeItem(at: url); return }

        let duracion = Double(bytes) / 32_000.0
        // Se registra el PCM crudo tal cual. La compresión NO se hace aquí a
        // propósito: la tanda diferida ya va a leer este audio para transcribirlo
        // y ese es el momento barato de comprimirlo, en una sola pasada y con el
        // equipo enchufado. Comprimir en caliente solo añadía un camino que podía
        // dejar contenedores a medias.
        comprimir.async {
            ContinuoIndice.shared.registrarAudio(ruta: url, instante: inicio,
                                                 duracion: duracion, origen: "continuo")
        }
    }

    // MARK: Adopción del audio del dictado

    /// Incorpora a la bitácora el `.wav` que el dictado acaba de guardar. Así,
    /// ceder el micrófono no abre un hueco en la línea de tiempo.
    static func adoptar(wav url: URL, instante: Date) {
        guard Config.continuoActivo(), Config.continuoAudioAdoptarDictado() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64) ?? 0
        let duracion = Double(bytes) / 32_000.0
        ContinuoIndice.shared.registrarAudio(ruta: url, instante: instante,
                                             duracion: duracion, origen: "dictado")
    }

    // MARK: Utilidades

    static func carpetaDelDia(_ fecha: Date, sub: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return Config.continuoCarpeta()
            .appendingPathComponent(f.string(from: fecha))
            .appendingPathComponent(sub)
    }

    static func sello(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH-mm-ss"
        return f.string(from: fecha)
    }

}

// MARK: - Energía

enum EnergiaMac {
    /// `true` si el equipo está enchufado. Con batería, la bitácora puede
    /// pausarse si el usuario lo pidió.
    static func conCorriente() -> Bool {
        let salida = Process()
        salida.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        salida.arguments = ["-g", "batt"]
        let tuberia = Pipe()
        salida.standardOutput = tuberia
        salida.standardError = FileHandle.nullDevice
        do { try salida.run() } catch { return true }
        let datos = tuberia.fileHandleForReading.readDataToEndOfFile()
        salida.waitUntilExit()
        let texto = String(data: datos, encoding: .utf8) ?? ""
        // Un portátil sin batería (o un sobremesa) no imprime 'Battery Power'.
        return !texto.contains("'Battery Power'")
    }
}

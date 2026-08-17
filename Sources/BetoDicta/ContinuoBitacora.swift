import AppKit

// MARK: - Bitácora continua: coordinador y retención
//
// Un único punto de encendido y apagado para audio + pantalla, y la purga.
//
// La purga NUNCA borra a ciegas material sin procesar. Si hay audio sin
// transcribir o capturas sin texto reconocido, `revisarPurga` lo devuelve y
// quien llame decide: eso es información que todavía no se extrajo y, una vez
// borrada, no se recupera.

enum ContinuoBitacora {

    // MARK: Encendido

    /// Arranca lo que el usuario haya dejado activado. Seguro de llamar varias
    /// veces y con el módulo apagado (no hace nada).
    static func arrancar() {
        guard Config.continuoActivo() else { return }
        ContinuoIndice.shared.abrir()
        ContinuoAudio.shared.arrancar()
        if #available(macOS 14.0, *) { ContinuoPantalla.shared.arrancar() }
        Log.log(.sistema, "bitácora: encendida")
    }

    static func detener() {
        ContinuoAudio.shared.detener()
        if #available(macOS 14.0, *) { ContinuoPantalla.shared.detener() }
        Log.log(.sistema, "bitácora: apagada")
    }

    /// Relee los ajustes en caliente tras tocar la pestaña.
    static func reconfigurar() {
        detener()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { arrancar() }
    }

    // MARK: Cesión al dictado
    //
    // Estos dos los llama AppDelegate alrededor del dictado. No son ajustes:
    // el dictado siempre gana.

    static func cederMicrofono(completion: @escaping () -> Void) {
        ContinuoAudio.shared.suspender(completion: completion)
    }

    static func recuperarMicrofono() {
        ContinuoAudio.shared.reanudar()
    }

    // MARK: Carpeta

    /// Abre la bitácora en el Finder. Acceso rápido desde la pestaña.
    static func abrirCarpeta() {
        let carpeta = Config.continuoCarpeta()
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([carpeta])
    }

    // MARK: Retención

    /// Fecha límite según el ajuste de días. `nil` = conservar para siempre.
    static func limiteRetencion() -> Date? {
        let dias = Config.continuoRetencionDias()
        guard dias > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -dias, to: Date())
    }

    /// Qué se llevaría la purga. Se consulta ANTES de borrar para poder avisar.
    static func revisarPurga(limite: Date? = nil) -> BalancePurga? {
        guard let corte = limite ?? limiteRetencion() else { return nil }
        ContinuoIndice.shared.abrir()
        return ContinuoIndice.shared.balanceAnteriorA(corte)
    }

    /// Ejecuta la purga. `forzar` es obligatorio cuando hay material sin
    /// procesar y el aviso está activado: sin él, no se borra nada.
    @discardableResult
    static func purgar(limite: Date? = nil, forzar: Bool = false) -> (borradas: Int, bloqueada: Bool) {
        guard let corte = limite ?? limiteRetencion() else { return (0, false) }
        ContinuoIndice.shared.abrir()
        let balance = ContinuoIndice.shared.balanceAnteriorA(corte)
        if balance.hayMaterialSinProcesar, Config.continuoRetencionAvisarSinProcesar(), !forzar {
            Log.log(.sistema, "bitácora: purga detenida — \(balance.sinProcesar) elementos sin transcribir ni reconocer")
            return (0, true)
        }
        let n = ContinuoIndice.shared.purgarAnteriorA(corte)
        Log.log(.sistema, "bitácora: purgados \(n) elementos anteriores a \(corte)")
        limpiarCarpetasVacias()
        return (n, false)
    }

    /// La purga automática solo corre si el usuario la pidió Y no hay nada
    /// pendiente de procesar: en cuanto lo hay, exige decisión humana.
    static func purgaAutomaticaSiCorresponde() {
        guard Config.continuoActivo(), Config.continuoRetencionAutomatica() else { return }
        DispatchQueue.global(qos: .utility).async {
            let r = purgar()
            if r.bloqueada {
                Log.log(.sistema, "bitácora: la purga automática quedó a la espera de tu visto bueno")
            }
        }
    }

    /// Quita los directorios de día que quedaron sin archivos tras purgar.
    private static func limpiarCarpetasVacias() {
        let raiz = Config.continuoCarpeta()
        guard let e = FileManager.default.enumerator(at: raiz,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return }
        var carpetas: [URL] = []
        for caso in e {
            guard let url = caso as? URL,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            carpetas.append(url)
        }
        // De más profundo a menos, para que al vaciar un día se pueda vaciar el mes.
        for url in carpetas.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            let hijos = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            if hijos.isEmpty { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: Presentación

    static func tamanoLegible(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

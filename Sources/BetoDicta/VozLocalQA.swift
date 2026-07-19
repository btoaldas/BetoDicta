import Foundation

/// Hooks reproducibles del perfil de voz local. Corren antes de AppKit para poder
/// reparar una biblioteca aun desde SSH/sandbox, usando exactamente las APIs de la GUI.
enum VozLocalQA {
    static func ejecutarSiSePidio() {
        let env = ProcessInfo.processInfo.environment
        if let variante = env["BETODICTA_VOZVARIANTTEST"], !variante.isEmpty {
            guard let voz = VocesLocales.activa() else {
                print("VOZVARIANTTEST sin voz activa"); exit(2)
            }
            VocesLocales.fijarVariante(voz.id, variante)
            let final = VocesLocales.todas().first { $0.id == voz.id }
            print("VOZVARIANTTEST id=\(voz.id) pedida=\(variante) activa=\(final?.variante ?? "nil")")
            exit(final?.variante == variante ? 0 : 3)
        }
        guard let pkg = env["BETODICTA_VOZRECOVERTEST"], !pkg.isEmpty else { return }

        let importada: VozLocal
        switch VocesLocales.importarPaquete(desde: URL(fileURLWithPath: pkg)) {
        case .ok(let v), .faltaMuestras(let v): importada = v
        case .faltaModelo:
            print("VOZRECOVERTEST faltaModelo"); exit(2)
        }
        if let onnx = env["BETODICTA_VOZRECOVER_ONNX"], !onnx.isEmpty {
            guard VocesLocales.vincularPiper(desde: URL(fileURLWithPath: onnx),
                                             a: importada.id, activar: false) != nil else {
                print("VOZRECOVERTEST piper falló"); exit(3)
            }
        }
        if let ref = env["BETODICTA_VOZRECOVER_MLXREF"], !ref.isEmpty,
           let texto = env["BETODICTA_VOZRECOVER_MLXTEXT"], !texto.isEmpty {
            let modelo = env["BETODICTA_VOZRECOVER_MLXMODEL"] ?? MlxVozEngine.modeloDefault
            guard VocesLocales.vincularMlx(referencia: URL(fileURLWithPath: ref),
                                           transcripcion: texto, modelo: modelo,
                                           a: importada.id, activar: false) != nil else {
                print("VOZRECOVERTEST mlx falló"); exit(4)
            }
        }
        if let cmd = env["BETODICTA_VOZRECOVER_CMD"], !cmd.isEmpty {
            guard VocesLocales.vincularMaxima(cmd: cmd, a: importada.id) != nil else {
                print("VOZRECOVERTEST máxima falló"); exit(5)
            }
        }
        VocesLocales.fijarActiva(importada.id)
        Config.set("tts_proveedor", to: "xtts_local")
        Config.set("tts_local_variantes_failover", to: true)
        let final = VocesLocales.todas().first { $0.id == importada.id }
        let ok = final?.tieneMaxima == true && !((final?.paquete ?? "").isEmpty)
            && final?.tieneMlx == true && !((final?.onnx ?? "").isEmpty)
            && final?.variante == "maxima"
        print("VOZRECOVERTEST id=\(importada.id) máxima=\(final?.tieneMaxima == true) xtts=\(!(final?.paquete ?? "").isEmpty) mlx=\(final?.tieneMlx == true) onnx=\(!(final?.onnx ?? "").isEmpty) activa=\(final?.variante ?? "nil")")
        exit(ok ? 0 : 6)
    }
}

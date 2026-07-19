// BetoDicta v0.2 — dictado por voz de Alberto Aldás
// <tecla>: abre panel y graba · <tecla> otra vez: transcribe y pega
// Streaming en vivo (scribe_v2_realtime) o batch (scribe_v1 / scribe_v2)
//
// Config ~/.betodicta/config.json: {"tecla": "fn", "modelo": "scribe_v2_realtime"}
//   tecla: fn | F1..F12
//   modelo: scribe_v2_realtime (texto en vivo) | scribe_v2 | scribe_v1 (batch)
// ~/.betodicta/keyterms.txt — una palabra por línea (streaming usa las primeras 50)
// ~/.betodicta/reemplazos.json — [{"original":"a, b","replacement":"X"}]
// API keys: en ~/.betodicta/.env — se ponen desde Configuración → Modelos

import AppKit

// Puente para UN Atajo universal de macOS:
//   BetoDicta --universal-input orden.json --universal-output respuesta.json
// Corre antes de crear NSApplication, devuelve evidencia JSON y termina. El
// Atajo puede usar el archivo de entrada/salida sin acceder a claves de la app.
let argumentos = CommandLine.arguments
if let i = argumentos.firstIndex(of: "--universal-input"), i + 1 < argumentos.count,
   let o = argumentos.firstIndex(of: "--universal-output"), o + 1 < argumentos.count {
    let entrada = URL(fileURLWithPath: argumentos[i + 1])
    let salida = URL(fileURLWithPath: argumentos[o + 1])
    let respuesta: RespuestaUniversalBeto
    do {
        let orden = try AtajoUniversalBetoDicta.decodificar(desde: entrada)
        var recibida: RespuestaUniversalBeto?
        AtajoUniversalBetoDicta.ejecutar(orden) { recibida = $0 }
        let limite = Date().addingTimeInterval(120)
        while recibida == nil, Date() < limite {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        respuesta = recibida ?? .init(ok: false,
            mensaje: "La acción universal excedió 120 segundos.",
            evidencia: ["timeout": "true"])
    } catch {
        respuesta = .init(ok: false, mensaje: error.localizedDescription,
                          evidencia: ["entrada_valida": "false"])
    }
    do {
        try AtajoUniversalBetoDicta.respuestaJSON(respuesta).write(to: salida, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: salida.path)
    } catch {
        FileHandle.standardError.write(Data("No pude escribir la evidencia: \(error.localizedDescription)\n".utf8))
        exit(3)
    }
    print(respuesta.mensaje); exit(respuesta.ok ? 0 : 2)
}

// Hooks puros del pipeline de release. Corren antes de crear NSApplication para
// que también funcionen con la app instalada cerrada y en una sesión sin GUI.
if let dmg = ProcessInfo.processInfo.environment["BETODICTA_DMGVERIFYTEST"],
   let sig = ProcessInfo.processInfo.environment["BETODICTA_DMGVERIFY_SIG"],
   let firma = try? Data(contentsOf: URL(fileURLWithPath: sig)) {
    let ok = Updater.firmaDMGValida(URL(fileURLWithPath: dmg), firma: firma)
    print("DMGVERIFYTEST \(ok ? "OK" : "FALLA")")
    exit(ok ? 0 : 3)
}
if let appPath = ProcessInfo.processInfo.environment["BETODICTA_VERIFYTEST"] {
    // El hook del pipeline se ejecuta después de verificar la firma Ed25519
    // del DMG, igual que el actualizador real.
    let ok = Updater.firmaConfiable(URL(fileURLWithPath: appPath), contenidoAutenticado: true)
    print("VERIFYTEST \(appPath) -> identidadConfiable=\(ok)")
    exit(ok ? 0 : 3)
}

ModoPlanQA.ejecutarSiSePidio()
ModoRegressionQA.ejecutarSiSePidio()
ModoAudioQA.ejecutarSiSePidio()
ModoIAQA.ejecutarSiSePidio()
AplicacionesMacQA.ejecutarSiSePidio()
AgenteCoreQA.ejecutarSiSePidio()
RecetasQA.ejecutarSiSePidio()
AgenteCodex.ejecutarPruebaSiSePidio()
DocumentosMac.ejecutarPruebaSiSePidio()
NotasApple.ejecutarPruebaSiSePidio()
VozLocalQA.ejecutarSiSePidio()
TareasNotasQA.ejecutarSiSePidio()

// Sin sesión gráfica (SSH, sandbox de un agente, launchd de fondo) AppKit
// aborta en _RegisterApplication al crear NSApplication. Los modos QA de
// arriba ya corrieron; aquí toca avisar y salir limpio en vez de crashear.
guard SesionGUI.disponible else {
    let mensaje = "BetoDicta: no hay sesión gráfica; la interfaz no puede arrancar en este contexto.\n" +
        "Los modos QA (variables BETODICTA_*) sí funcionan aquí.\n"
    FileHandle.standardError.write(Data(mensaje.utf8))
    exit(78) // EX_CONFIG
}

let app = NSApplication.shared
app.setActivationPolicy(Config.showInDock() ? .regular : .accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

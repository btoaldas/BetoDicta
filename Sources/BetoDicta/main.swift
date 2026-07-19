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
AgenteCodex.ejecutarPruebaSiSePidio()
DocumentosMac.ejecutarPruebaSiSePidio()
NotasApple.ejecutarPruebaSiSePidio()
VozLocalQA.ejecutarSiSePidio()

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

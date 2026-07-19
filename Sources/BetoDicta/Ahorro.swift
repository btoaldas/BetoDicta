import Foundation

// MARK: - Modo AHORRO global (Alberto: si no lo usas, ¿para qué gasta recursos?)
//
// Un solo reloj de inactividad. Si BetoDicta no se usa en N minutos, DUERME lo pesado:
//   • el clon local (mata el server → libera ~2 GB de RAM),
//   • el latido de red (deja de pinguear cada 15s).
// Al grabar (fn) se DESPIERTA todo. La tecla es el latido que revive el sistema.
//
// Umbral = ttsXttsDormirMin (los "minutos de inactividad", parametrizables). Cada pieza
// respeta su propio toggle (ttsXttsDormir para el clon), pero el master es ahorroGlobal.
// Extensible: aquí se agregan más subsistemas que consuman recursos.

enum Ahorro {
    private static var ultimaActividad = Date()
    private static var dormido = false
    private static var reloj: Timer?

    static func iniciar() {
        reloj?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { _ in revisar() }
        RunLoop.main.add(t, forMode: .common); reloj = t
    }

    /// Se llama al usar BetoDicta (grabar/fn): resetea el reloj y DESPIERTA si dormía.
    static func marcarActividad() {
        ultimaActividad = Date()
        if dormido { despertar() }
    }

    private static func revisar() {
        guard Config.ahorroGlobal(), !dormido else { return }
        let umbral = max(1, Config.ttsXttsDormirMin()) * 60
        if Date().timeIntervalSince(ultimaActividad) > umbral { dormir() }
    }

    private static func dormir() {
        dormido = true
        Log.log(.config, "modo ahorro: durmiendo lo pesado (libera RAM/CPU); fn despierta")
        CalientaRed.detenerLatido()
        if Config.ttsXttsDormir() { XttsServer.detener() }
        if Config.ttsMlxDormir() { MlxVozServer.detener() }
        // (futuro: aquí se sueltan más subsistemas — embeddings locales, etc.)
    }

    private static func despertar() {
        dormido = false
        Log.log(.config, "modo ahorro: despertando (fn)")
        if Config.calentarRed() { CalientaRed.iniciarLatido() }
        Voz.preactivarLocal()
    }
}

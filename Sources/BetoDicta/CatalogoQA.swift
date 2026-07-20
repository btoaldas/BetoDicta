import Foundation

// MARK: - QA del Catálogo de capacidades (Fase 1)
//   BETODICTA_CATALOGOQA=1 → pruebas PURAS del ensamblado (sin tocar los datos
//   del usuario). Verifica sobre todo que el catálogo se AUTOACTUALIZA.

enum CatalogoQA {
    static func ejecutarSiSePidio() {
        // Volcado del catálogo REAL en vivo (solo lectura; para ver qué conoce
        // el agente HOY en este equipo). No modifica nada.
        if ProcessInfo.processInfo.environment["BETODICTA_CATALOGODUMP"] == "1" {
            let caps = CatalogoCapacidades.todas()
            print("CATÁLOGO EN VIVO — \(caps.count) capacidades:")
            for c in caps {
                let h = c.hijos.isEmpty ? "" : " · \(c.hijos.count) endpoint(s)"
                print("  [\(c.tipo)] \(c.nombre) — \(String(c.descripcion.prefix(60)))\(h)")
            }
            fflush(stdout); exit(0)
        }
        guard ProcessInfo.processInfo.environment["BETODICTA_CATALOGOQA"] == "1" else { return }
        var fallos = 0
        func check(_ nombre: String, _ ok: @autoclosure () -> Bool) {
            let pasa = ok(); if !pasa { fallos += 1 }
            print("CATALOGOQA \(pasa ? "OK" : "✗") \(nombre)")
        }
        func tiene(_ caps: [Capacidad], tipo: String, clave: String) -> Bool {
            caps.contains { $0.tipo == tipo && $0.clave == clave }
        }

        // Fuentes de prueba controladas (no la biblioteca real del usuario).
        var modoCorreo = Modo(id: "correo", nombre: "Correo", icono: "envelope", base: "pulir",
                              esFijo: true, palabraVoz: "modo correo")
        modoCorreo.prompt = "Reescribe como correo."
        var modoUEA = Modo(id: "propio-uea", nombre: "Actividades UEA", icono: "bolt",
                           base: "accion", esFijo: false, palabraVoz: "modo actividades", accion: "conexion")
        modoUEA.conexion = ConexionAPI(baseURL: "https://x.ejemplo.com",
            endpoints: [EndpointAPI(clave: "registrar", metodo: "POST", ruta: "/r", esEscritura: true),
                        EndpointAPI(clave: "hoy", metodo: "GET", ruta: "/h")])
        var rutina = RutinaAgente(nombre: "Empezar jornada")
        rutina.pasos = [PasoRutinaAgente(tipo: "app", valor: "Word")]
        rutina.frases = ["empezar jornada"]
        let atajoOn = AtajoAppleDescubierto(id: "a1", nombre: "Enfoque", habilitado: true)
        let atajoOff = AtajoAppleDescubierto(id: "a2", nombre: "Secreto", habilitado: false)

        let base = CatalogoCapacidades.ensamblar(
            modos: [Modo(id: "dictado", nombre: "Dictado", icono: "mic", base: "pulir"),
                    modoCorreo, modoUEA],
            rutinas: [rutina], atajos: [atajoOn, atajoOff], herramientas: true)

        check("incluye el modo correo", tiene(base, tipo: "modo", clave: "correo"))
        check("dictado NO se cataloga", !tiene(base, tipo: "modo", clave: "dictado"))
        check("el modo con conexión es tipo conexion", tiene(base, tipo: "conexion", clave: "propio-uea"))
        check("la conexión trae sus endpoints como hijos",
              base.first { $0.clave == "propio-uea" }?.hijos.count == 2)
        check("incluye la rutina activa", tiene(base, tipo: "rutina", clave: rutina.id))
        check("incluye el atajo habilitado", tiene(base, tipo: "atajo", clave: "Enfoque"))
        check("NO incluye el atajo deshabilitado", !tiene(base, tipo: "atajo", clave: "Secreto"))
        check("incluye herramientas específicas (clima)", tiene(base, tipo: "herramienta", clave: "clima"))
        check("incluye el cerebro como último recurso", tiene(base, tipo: "cerebro", clave: "cerebro"))
        check("la conexión hereda su riesgo (escritura → externo)",
              base.first { $0.clave == "propio-uea" }?.riesgo == .externo)

        // AUTOACTUALIZACIÓN: agregar un modo NUEVO a las fuentes → aparece solo.
        var modoNuevo = Modo(id: "propio-inventado", nombre: "Mi modo nuevo", icono: "star",
                             base: "pulir", esFijo: false, palabraVoz: "modo inventado")
        modoNuevo.prompt = "Haz algo nuevo."
        let conNuevo = CatalogoCapacidades.ensamblar(
            modos: [modoCorreo, modoNuevo], rutinas: [], atajos: [], herramientas: false)
        check("un modo recién creado aparece sin tocar código",
              tiene(conNuevo, tipo: "modo", clave: "propio-inventado"))
        check("quitar fuentes reduce el catálogo (no hay lista fija)",
              conNuevo.filter { $0.tipo == "rutina" }.isEmpty)

        // El menú para la IA es un catálogo cerrado legible.
        let menu = CatalogoCapacidades.paraIA(base)
        check("paraIA lista con tipo:clave",
              menu.contains("[modo:correo]") && menu.contains("[conexion:propio-uea]"))
        check("paraIA no filtra secretos ni vacíos", !menu.contains("[atajo:Secreto]"))

        print(fallos == 0 ? "CATALOGOQA TODO OK" : "CATALOGOQA ✗ \(fallos) FALLOS")
        fflush(stdout); exit(fallos == 0 ? 0 : 3)
    }
}

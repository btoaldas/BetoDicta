import Foundation

// MARK: - QA de Conexiones API (espejo puro, sin tocar la config del usuario)
//
//   BETODICTA_CONEXIONTEST=1     → pruebas puras (modelo, motor, invariantes)
//   BETODICTA_CONEXIONTEST_RED=1 → además, un GET real a una API pública
//     (separado a propósito: el QA base debe pasar sin internet)

enum ConexionesQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BETODICTA_CONEXIONTEST"] == "1" else { return }
        var fallos = 0
        func check(_ nombre: String, _ ok: @autoclosure () -> Bool) {
            let pasa = ok(); if !pasa { fallos += 1 }
            print("CONEXIONTEST \(pasa ? "OK" : "✗") \(nombre)")
        }

        // 1. Decode tolerante: un modos.json VIEJO (sin `conexion`) sigue cargando.
        let modoViejo = #"{"id":"propio-x","nombre":"Viejo","icono":"bolt","base":"pulir"}"#
        let viejo = try? JSONDecoder().decode(Modo.self, from: Data(modoViejo.utf8))
        check("modo viejo sin conexion decodifica", viejo != nil && viejo?.conexion == nil)

        // 2. Round-trip: un modo CON conexión persiste y vuelve completo.
        var modo = Modo(id: "propio-qa", nombre: "Clima QA", icono: "bolt", base: "accion",
                        esFijo: false, accion: "conexion")
        modo.conexion = ConexionAPI(
            baseURL: "https://api.open-meteo.com",
            auth: AuthConexion(tipo: "ninguna"),
            headers: ["Accept": "application/json"],
            endpoints: [EndpointAPI(clave: "clima", metodo: "GET", ruta: "/v1/forecast",
                                    descripcion: "clima actual",
                                    query: "latitude=-1.49&longitude=-78.0&current_weather=true")])
        let data = try? JSONEncoder().encode(modo)
        let vuelto = data.flatMap { try? JSONDecoder().decode(Modo.self, from: $0) }
        check("round-trip conserva la conexión",
              vuelto?.conexion?.baseURL == "https://api.open-meteo.com"
              && vuelto?.conexion?.endpoints.first?.clave == "clima"
              && vuelto?.conexion?.headers["Accept"] == "application/json")

        // 3. URL segura: mismo criterio fail-closed de toda la casa.
        check("https válida", ConexionesMotor.urlSegura("https://api.ejemplo.com/v1"))
        check("http localhost válida", ConexionesMotor.urlSegura("http://localhost:8080"))
        check("http remota RECHAZADA", !ConexionesMotor.urlSegura("http://api.ejemplo.com"))
        check("ftp RECHAZADA", !ConexionesMotor.urlSegura("ftp://ejemplo.com"))
        check("sin host RECHAZADA", !ConexionesMotor.urlSegura("https://"))

        // 4. Valores de ruta: nada que cambie de endpoint.
        check("valor de ruta simple", ConexionesMotor.valorSeguroParaRuta("Quito"))
        check("valor con / RECHAZADO", !ConexionesMotor.valorSeguroParaRuta("a/b"))
        check("valor con .. RECHAZADO", !ConexionesMotor.valorSeguroParaRuta("..%2f"))
        check("valor vacío RECHAZADO", !ConexionesMotor.valorSeguroParaRuta("  "))

        // 5. Plantillas: extracción de {variables}.
        check("variables de plantilla",
              ConexionesMotor.variablesEnPlantilla("/w/{ciudad}?q={texto}") == ["ciudad", "texto"])

        // 6. Construcción de URL: encode de tildes/espacios, query con {texto}.
        let ep = EndpointAPI(clave: "w", metodo: "GET", ruta: "/{ciudad}", query: "format=3&q={texto}")
        let url = ConexionesMotor.construirURL(base: "https://wttr.in/",
                                               endpoint: ep,
                                               valores: ["ciudad": "Baños de Agua Santa", "texto": "¿qué?"])
        check("URL construida y codificada",
              url?.absoluteString == "https://wttr.in/Ba%C3%B1os%20de%20Agua%20Santa?format=3&q=%C2%BFqu%C3%A9%3F")
        check("ruta con variable insegura → nil",
              ConexionesMotor.construirURL(base: "https://wttr.in",
                                           endpoint: ep,
                                           valores: ["ciudad": "../admin", "texto": "x"]) == nil)
        check("base http remota → nil",
              ConexionesMotor.construirURL(base: "http://wttr.in", endpoint: ep,
                                           valores: ["ciudad": "Quito", "texto": "x"]) == nil)

        // 7. Body JSON-aware: tipos reales, nada de pegar strings.
        let plantilla = #"{"nota":"{texto}","minutos":"{min}","items":"{items}","fijo":1}"#
        let valores: [String: Any] = [
            "texto": "dijo: \"hola\"\ncon tilde á",
            "min": 90,
            "items": [["detalle": "uno", "min": 30], ["detalle": "dos", "min": 60]],
        ]
        let body = ConexionesMotor.sustituirBody(plantilla, valores: valores)
        let obj = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        check("body: string con comillas/salto/tilde intacto",
              (obj?["nota"] as? String) == "dijo: \"hola\"\ncon tilde á")
        check("body: número tipado (no string)", (obj?["minutos"] as? Int) == 90)
        check("body: lista tipada con 2 ítems", (obj?["items"] as? [[String: Any]])?.count == 2)
        check("body: campo fijo intacto", (obj?["fijo"] as? Int) == 1)
        check("plantilla inválida → nil", ConexionesMotor.sustituirBody("{no es json", valores: [:]) == nil)
        let mixto = ConexionesMotor.sustituirBody(#"{"saludo":"hola {texto}"}"#, valores: ["texto": "Beto"])
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        check("body: interpolación en string mixto", (mixto?["saludo"] as? String) == "hola Beto")

        // 8. Validación de valores contra el esquema del endpoint.
        var epVars = EndpointAPI(clave: "reg", metodo: "POST", ruta: "/x", esEscritura: true)
        epVars.variables = [VariableAPI(nombre: "min", tipo: "numero", requerida: true),
                            VariableAPI(nombre: "items", tipo: "lista")]
        check("falta requerida detectada",
              !ConexionesMotor.validarValores(endpoint: epVars, valores: [:]).isEmpty)
        check("no declarada detectada",
              !ConexionesMotor.validarValores(endpoint: epVars, valores: ["min": 5, "otra": 1]).isEmpty)
        check("número inválido detectado",
              !ConexionesMotor.validarValores(endpoint: epVars, valores: ["min": "noesnum"]).isEmpty)
        check("lista inválida detectada",
              !ConexionesMotor.validarValores(endpoint: epVars, valores: ["min": 5, "items": "plano"]).isEmpty)
        check("valores correctos pasan",
              ConexionesMotor.validarValores(endpoint: epVars,
                                             valores: ["min": 5, "items": [1, 2]]).isEmpty)

        // 9. Evidencia sin secretos.
        check("token enmascarado",
              !ConexionesMotor.enmascarar("Bearer abc123xyz falló", secretos: ["abc123xyz"]).contains("abc123xyz"))

        // 10. Riesgo/escritura: método manda aunque la casilla mienta.
        check("POST es escritura aunque no esté marcado",
              EndpointAPI(clave: "p", metodo: "POST").efectivamenteEscritura)
        check("GET lectura no es escritura", !EndpointAPI(clave: "g", metodo: "GET").efectivamenteEscritura)
        check("conexión de lectura = reversible",
              ConexionesMotor.riesgo(modo.conexion) == .reversible)
        var conEscritura = modo.conexion!
        conEscritura.endpoints.append(EndpointAPI(clave: "pub", metodo: "POST"))
        check("conexión con escritura = externo", ConexionesMotor.riesgo(conEscritura) == .externo)
        check("conexión ausente = externo (prudencia)", ConexionesMotor.riesgo(nil) == .externo)

        // 11. Catálogo y descripciones.
        check("acción conexion existe en el catálogo", Acciones.valido("conexion"))
        check("descripción de etapa legible",
              ModoPlanificador.descripcionEtapa(modo).lowercased().contains("conexión api"))

        // 12. INVARIANTE del árbitro IA: una acción sintética "accion:conexion"
        // (sin API embebida) se rechaza; solo el MODO del usuario la lleva.
        let jsonArbitro = #"{"intent":true,"confidence":0.95,"prefix_words":0,"suffix_words":0,"stages":[{"key":"accion:conexion","idioma":null,"destinatario":null}],"alternatives":[]}"#
        check("árbitro rechaza accion:conexion sintética",
              ModoIAEnrutador.interpretar(jsonArbitro, textoOriginal: "consulta el clima de hoy",
                                          catalogo: ModoCatalogo(modos: ModosStore.base)) == nil)

        // 13. Runner fail-closed sin red: cada camino de error responde claro.
        func esperar(_ arranca: (@escaping (ResultadoHerramientaApple) -> Void) -> Void)
            -> ResultadoHerramientaApple? {
            var r: ResultadoHerramientaApple?
            arranca { r = $0 }
            let limite = Date().addingTimeInterval(5)
            while r == nil, Date() < limite {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            return r
        }
        var sinConexion = modo; sinConexion.conexion = nil
        let r1 = esperar { ConexionesRunner.ejecutar(modo: sinConexion, texto: "hola",
                                                     ignorarInterruptor: true, completion: $0) }
        check("runner sin conexión configurada falla claro",
              r1?.ok == false && r1?.mensaje.lowercased().contains("conexión") == true)
        var urlMala = modo; urlMala.conexion?.baseURL = "http://remoto.ejemplo.com"
        let r2 = esperar { ConexionesRunner.ejecutar(modo: urlMala, texto: "hola",
                                                     ignorarInterruptor: true, completion: $0) }
        check("runner con URL insegura falla claro",
              r2?.ok == false && r2?.mensaje.lowercased().contains("segura") == true)
        var soloEscritura = modo
        soloEscritura.conexion?.endpoints = [EndpointAPI(clave: "pub", metodo: "POST", ruta: "/p")]
        let r3 = esperar { ConexionesRunner.ejecutar(modo: soloEscritura, texto: "hola",
                                                     ignorarInterruptor: true, completion: $0) }
        check("runner nunca ejecuta escritura en fase 1",
              r3?.ok == false && r3?.mensaje.lowercased().contains("escritura") == true)
        // Con el interruptor RESPETADO y apagado, el gate responde apagado.
        if !Config.agenteHerramientaConexiones() {
            let r4 = esperar { ConexionesRunner.ejecutar(modo: modo, texto: "hola", completion: $0) }
            check("interruptor apagado bloquea el runner",
                  r4?.ok == false && r4?.mensaje.lowercased().contains("apagadas") == true)
        }

        // 14. Selección de endpoint sin IA: clave dictada gana; si no, primer GET.
        var multi = modo.conexion!
        multi.endpoints = [EndpointAPI(clave: "clima", metodo: "GET", ruta: "/a"),
                           EndpointAPI(clave: "noticias", metodo: "GET", ruta: "/b"),
                           EndpointAPI(clave: "pub", metodo: "POST", ruta: "/c")]
        check("clave dictada elige endpoint",
              ConexionesRunner.endpointPara(multi, texto: "noticias de hoy")?.clave == "noticias")
        check("sin clave usa el primer GET",
              ConexionesRunner.endpointPara(multi, texto: "cualquier cosa")?.clave == "clima")

        // 15. (Opcional) GET real a una API pública — exige internet.
        if ProcessInfo.processInfo.environment["BETODICTA_CONEXIONTEST_RED"] == "1" {
            let rReal = esperar { done in
                ConexionesRunner.probar(modo.conexion!, modoId: "qa-red") { ok, msg in
                    done(.init(ok: ok, mensaje: msg))
                }
            }
            check("GET real a Open-Meteo responde", rReal?.ok == true)
            print("CONEXIONTEST red: \(String((rReal?.mensaje ?? "sin respuesta").prefix(160)))")
        }

        print(fallos == 0 ? "CONEXIONTEST TODO OK" : "CONEXIONTEST ✗ \(fallos) FALLOS")
        fflush(stdout); exit(fallos == 0 ? 0 : 4)
    }
}

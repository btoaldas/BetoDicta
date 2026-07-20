import Foundation

// MARK: - Conexiones API definidas por el usuario (acción "conexion")
//
// Un modo con base "accion" y accion "conexion" lleva embebida una CONEXIÓN API
// declarada por el usuario: URL base, autenticación, endpoints con variables
// tipadas y (fase 2) instrucciones para la IA en el prompt del modo. Nada del
// dominio (p. ej. un sistema institucional concreto) vive en el código: todo es
// configuración del usuario, igual que un buscador propio o una IA personalizada.
//
// Principios:
//   - La IA NUNCA ejecuta HTTP ni ve credenciales: el runner Swift valida y llama.
//   - Fail-closed: solo https (o http en loopback), sin redirects fuera del host,
//     secretos en Keychain (SecretosKeychain), evidencia sin credenciales.
//   - Fase 1: ejecución directa de endpoints GET de lectura. Los flujos con
//     escritura/confirmación (proponer → confirmar) llegan en fases siguientes
//     y por eso el runner los rechaza hoy en vez de ejecutarlos a medias.

/// Variable declarada de un endpoint. La IA (fase 2) llenará estos valores; en
/// fase 1 solo {texto} (el dictado) se llena automáticamente.
struct VariableAPI: Codable, Identifiable, Equatable {
    var id: String
    var nombre: String        // cómo se cita en plantillas: {nombre}
    var tipo: String          // "texto" | "numero" | "fecha" | "lista"
    var requerida: Bool
    var descripcion: String   // una línea que verá la IA
    var itemCampos: [VariableAPI]   // solo tipo "lista": esquema de cada ítem

    init(nombre: String = "", tipo: String = "texto", requerida: Bool = false,
         descripcion: String = "", itemCampos: [VariableAPI] = []) {
        id = UUID().uuidString
        self.nombre = nombre; self.tipo = tipo; self.requerida = requerida
        self.descripcion = descripcion; self.itemCampos = itemCampos
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nombre = (try? c.decode(String.self, forKey: .nombre)) ?? ""
        tipo = (try? c.decode(String.self, forKey: .tipo)) ?? "texto"
        requerida = (try? c.decode(Bool.self, forKey: .requerida)) ?? false
        descripcion = (try? c.decode(String.self, forKey: .descripcion)) ?? ""
        itemCampos = (try? c.decode([VariableAPI].self, forKey: .itemCampos)) ?? []
    }
}

/// Endpoint declarado. `clave` es el nombre estable que la IA y las plantillas
/// usan; `ruta` y `query` admiten {variables}; `bodyPlantilla` es JSON con
/// {variables} y se sustituye de forma JSON-aware (nunca pegado de strings).
struct EndpointAPI: Codable, Identifiable, Equatable {
    var id: String
    var clave: String
    var metodo: String        // GET | POST | PUT | DELETE
    var ruta: String          // "/v1/clima" o "/{ciudad}" (variables solo en segmentos)
    var descripcion: String   // una línea que verá la IA
    var query: String         // "q={texto}&formato=json" (se codifica al sustituir)
    var bodyPlantilla: String // JSON con {variables}; vacío en GET
    var esEscritura: Bool     // true ⇒ jamás se ejecuta sin confirmación (fase 3)
    var variables: [VariableAPI]

    init(clave: String = "", metodo: String = "GET", ruta: String = "/",
         descripcion: String = "", query: String = "", bodyPlantilla: String = "",
         esEscritura: Bool = false, variables: [VariableAPI] = []) {
        id = UUID().uuidString
        self.clave = clave; self.metodo = metodo; self.ruta = ruta
        self.descripcion = descripcion; self.query = query
        self.bodyPlantilla = bodyPlantilla; self.esEscritura = esEscritura
        self.variables = variables
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        clave = (try? c.decode(String.self, forKey: .clave)) ?? ""
        metodo = (try? c.decode(String.self, forKey: .metodo)) ?? "GET"
        ruta = (try? c.decode(String.self, forKey: .ruta)) ?? "/"
        descripcion = (try? c.decode(String.self, forKey: .descripcion)) ?? ""
        query = (try? c.decode(String.self, forKey: .query)) ?? ""
        bodyPlantilla = (try? c.decode(String.self, forKey: .bodyPlantilla)) ?? ""
        esEscritura = (try? c.decode(Bool.self, forKey: .esEscritura)) ?? false
        variables = (try? c.decode([VariableAPI].self, forKey: .variables)) ?? []
    }

    /// Un método distinto de GET se trata como escritura aunque el usuario no
    /// haya marcado la casilla: techo de seguridad, no depende de su memoria.
    var efectivamenteEscritura: Bool { esEscritura || metodo.uppercased() != "GET" }
}

/// Autenticación de la conexión. El SECRETO jamás se guarda aquí (va a
/// SecretosKeychain, cuenta = id del modo); solo la forma de presentarlo.
struct AuthConexion: Codable, Equatable {
    var tipo: String          // "ninguna" | "apikey"  ("login" llega en fase 3)
    var header: String        // ej. "Authorization" / "X-Api-Key"
    var prefijo: String       // ej. "Bearer " o "" (una API key pelada va sin prefijo)
    var usuario: String       // solo "login" (fase 3); visible, nunca es el secreto

    init(tipo: String = "ninguna", header: String = "Authorization",
         prefijo: String = "Bearer ", usuario: String = "") {
        self.tipo = tipo; self.header = header; self.prefijo = prefijo
        self.usuario = usuario
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        tipo = (try? c.decode(String.self, forKey: .tipo)) ?? "ninguna"
        header = (try? c.decode(String.self, forKey: .header)) ?? "Authorization"
        prefijo = (try? c.decode(String.self, forKey: .prefijo)) ?? "Bearer "
        usuario = (try? c.decode(String.self, forKey: .usuario)) ?? ""
    }
}

/// La conexión completa embebida en un Modo (campo opcional `conexion`).
struct ConexionAPI: Codable, Equatable {
    var baseURL: String
    var auth: AuthConexion
    var headers: [String: String]   // encabezados extra (Accept, X-Requested-With…)
    var endpoints: [EndpointAPI]
    var timeoutSegundos: Int
    var vozResumen: Bool            // leer un resumen del resultado por TTS
    var usarIA: Bool                // la IA arma el plan (endpoint+variables) desde lo dictado

    init(baseURL: String = "", auth: AuthConexion = AuthConexion(),
         headers: [String: String] = [:], endpoints: [EndpointAPI] = [],
         timeoutSegundos: Int = 15, vozResumen: Bool = false, usarIA: Bool = true) {
        self.baseURL = baseURL; self.auth = auth; self.headers = headers
        self.endpoints = endpoints; self.timeoutSegundos = timeoutSegundos
        self.vozResumen = vozResumen; self.usarIA = usarIA
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        baseURL = (try? c.decode(String.self, forKey: .baseURL)) ?? ""
        auth = (try? c.decode(AuthConexion.self, forKey: .auth)) ?? AuthConexion()
        headers = (try? c.decode([String: String].self, forKey: .headers)) ?? [:]
        endpoints = (try? c.decode([EndpointAPI].self, forKey: .endpoints)) ?? []
        timeoutSegundos = (try? c.decode(Int.self, forKey: .timeoutSegundos)) ?? 15
        vozResumen = (try? c.decode(Bool.self, forKey: .vozResumen)) ?? false
        usarIA = (try? c.decode(Bool.self, forKey: .usarIA)) ?? true
    }

    var tieneEscritura: Bool { endpoints.contains { $0.efectivamenteEscritura } }
}

// MARK: - Motor puro (sin red): validación y sustitución. Todo testeable en QA.

enum ConexionesMotor {

    /// Criterio único de URL admisible: https con host, o http SOLO en loopback
    /// (mismo criterio que Acciones.plantillaURLSegura / RutinasAgenteRunner).
    static func urlSegura(_ s: String) -> Bool {
        guard let c = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = c.scheme?.lowercased() else { return false }
        if scheme == "https" { return c.host?.isEmpty == false }
        if scheme == "http" {
            return ["localhost", "127.0.0.1", "::1"].contains((c.host ?? "").lowercased())
        }
        return false
    }

    /// Percent-encode de un valor para ruta o query (criterio de la casa).
    static func codificar(_ s: String) -> String {
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
    }

    /// Un valor que viaja en un SEGMENTO de ruta no puede cambiar de endpoint:
    /// sin "/", sin "..", sin vacío. (El percent-encode ya neutraliza el resto.)
    static func valorSeguroParaRuta(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.contains("/") && !t.contains("..")
    }

    /// Extrae los nombres {var} presentes en una plantilla.
    static func variablesEnPlantilla(_ plantilla: String) -> Set<String> {
        var out = Set<String>()
        var resto = Substring(plantilla)
        while let a = resto.firstIndex(of: "{") {
            guard let b = resto[a...].firstIndex(of: "}") else { break }
            let nombre = String(resto[resto.index(after: a)..<b])
            if !nombre.isEmpty, !nombre.contains(" ") { out.insert(nombre) }
            resto = resto[resto.index(after: b)...]
        }
        return out
    }

    /// Valida los valores contra el esquema del endpoint. Devuelve la lista de
    /// problemas (vacía = válido). No conoce la red: puro.
    static func validarValores(endpoint: EndpointAPI, valores: [String: Any]) -> [String] {
        var errores: [String] = []
        for v in endpoint.variables where v.requerida && valores[v.nombre] == nil {
            errores.append("falta la variable requerida «\(v.nombre)»")
        }
        let declaradas = Set(endpoint.variables.map(\.nombre) + ["texto"])
        for (k, valor) in valores {
            guard declaradas.contains(k) else {
                errores.append("variable no declarada «\(k)»"); continue
            }
            guard let esquema = endpoint.variables.first(where: { $0.nombre == k }) else { continue }
            switch esquema.tipo {
            case "numero":
                if !(valor is NSNumber) && Double("\(valor)") == nil {
                    errores.append("«\(k)» debe ser un número")
                }
            case "lista":
                if !(valor is [Any]) { errores.append("«\(k)» debe ser una lista") }
            default: break   // texto/fecha viajan como texto
            }
        }
        // Variables que la RUTA usa: su valor no puede alterar los segmentos.
        for nombre in variablesEnPlantilla(endpoint.ruta) {
            if let s = valores[nombre] as? String, !valorSeguroParaRuta(s) {
                errores.append("«\(nombre)» no es válida para la ruta (sin «/» ni «..», no vacía)")
            }
        }
        return errores
    }

    /// Construye la URL final: base + ruta con {vars} + query con {vars}, todo
    /// percent-encoded. nil si la URL resultante no es segura o no parsea.
    static func construirURL(base: String, endpoint: EndpointAPI,
                             valores: [String: Any]) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b = String(b.dropLast()) }
        guard urlSegura(b) else { return nil }
        var ruta = endpoint.ruta.trimmingCharacters(in: .whitespaces)
        if !ruta.isEmpty, !ruta.hasPrefix("/") { ruta = "/" + ruta }
        for nombre in variablesEnPlantilla(ruta) {
            guard let valor = valores[nombre].map({ "\($0)" }), valorSeguroParaRuta(valor) else { return nil }
            ruta = ruta.replacingOccurrences(of: "{\(nombre)}", with: codificar(valor))
        }
        var query = endpoint.query.trimmingCharacters(in: .whitespaces)
        for nombre in variablesEnPlantilla(query) {
            let valor = valores[nombre].map { "\($0)" } ?? ""
            query = query.replacingOccurrences(of: "{\(nombre)}", with: codificar(valor))
        }
        let s = b + ruta + (query.isEmpty ? "" : "?" + query)
        guard urlSegura(s), let url = URL(string: s) else { return nil }
        return url
    }

    /// Sustitución JSON-AWARE del body: la plantilla se parsea como JSON y los
    /// {placeholders} se reemplazan NODO a NODO — un string que es exactamente
    /// "{var}" recibe el valor con su TIPO (número, lista, texto); un string
    /// mixto "hola {var}" interpola como texto. Nunca se pega texto crudo en el
    /// JSON: comillas, tildes y saltos de línea dictados no pueden romperlo.
    static func sustituirBody(_ plantilla: String, valores: [String: Any]) -> Data? {
        let t = plantilla.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard let data = t.data(using: .utf8),
              let raiz = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil   // la plantilla misma no es JSON válido: error de config
        }
        func sustituir(_ nodo: Any) -> Any {
            if let s = nodo as? String {
                let nombres = variablesEnPlantilla(s)
                if nombres.count == 1, let n = nombres.first, s == "{\(n)}" {
                    return valores[n] ?? NSNull()   // valor TIPADO tal cual
                }
                var out = s
                for n in nombres {
                    out = out.replacingOccurrences(of: "{\(n)}", with: valores[n].map { "\($0)" } ?? "")
                }
                return out
            }
            if let a = nodo as? [Any] { return a.map(sustituir) }
            if let d = nodo as? [String: Any] { return d.mapValues(sustituir) }
            return nodo
        }
        let final = sustituir(raiz)
        return try? JSONSerialization.data(withJSONObject: final, options: [.sortedKeys])
    }

    /// Enmascara secretos en un texto destinado a logs/evidencia. Se aplica a
    /// TODO lo que salga del runner; un token jamás debe llegar a AgenteLog.
    static func enmascarar(_ texto: String, secretos: [String]) -> String {
        var out = texto
        for s in secretos where s.count >= 4 {
            out = out.replacingOccurrences(of: s, with: "•••")
        }
        return out
    }

    /// Riesgo para la política del agente: leer es reversible; cualquier
    /// endpoint de escritura vuelve TODA la conexión externa (confirmación).
    static func riesgo(_ conexion: ConexionAPI?) -> RiesgoAgente {
        guard let c = conexion else { return .externo }   // sin declarar = prudencia
        return c.tieneEscritura ? .externo : .reversible
    }
}

// MARK: - Delegate de red: sin redirects fuera del host declarado ni https→http

final class ConexionRedDelegate: NSObject, URLSessionTaskDelegate {
    private let hostPermitido: String
    private let esquemaOriginal: String
    init(url: URL) {
        hostPermitido = url.host?.lowercased() ?? ""
        esquemaOriginal = url.scheme?.lowercased() ?? "https"
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let nuevoHost = request.url?.host?.lowercased() ?? ""
        let nuevoEsquema = request.url?.scheme?.lowercased() ?? ""
        // Cross-host se rechaza siempre; https puede degradar a http jamás.
        let degrada = esquemaOriginal == "https" && nuevoEsquema != "https"
        completionHandler(nuevoHost == hostPermitido && !degrada ? request : nil)
    }
}

// MARK: - Runner (fase 1): GET directo de lectura, con evidencia sin secretos

enum ConexionesRunner {

    /// Elige el endpoint a ejecutar sin IA (fase 1): si el dictado empieza con
    /// la clave de un endpoint la usa; si no, el primer GET de lectura.
    static func endpointPara(_ conexion: ConexionAPI, texto: String) -> EndpointAPI? {
        let lecturas = conexion.endpoints.filter { !$0.efectivamenteEscritura }
        let n = texto.lowercased().trimmingCharacters(in: .whitespaces)
        if let porClave = lecturas.first(where: { !$0.clave.isEmpty && n.hasPrefix($0.clave.lowercased()) }) {
            return porClave
        }
        return lecturas.first
    }

    /// Ejecuta la conexión de un modo para el texto dictado. Fase 1: llena solo
    /// {texto}; el resto de variables requeridas produce un error claro (la IA
    /// las llenará en la fase siguiente, no las inventamos aquí).
    static func ejecutar(modo: Modo, texto: String, ignorarInterruptor: Bool = false,
                         completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard ignorarInterruptor || Config.agenteHerramientaConexiones() else {
            completion(.init(ok: false, mensaje: "Las conexiones API están apagadas en Ajustes → Asistente.")); return
        }
        guard let conexion = modo.conexion else {
            completion(.init(ok: false, mensaje: "El modo «\(modo.nombre)» no tiene una conexión API configurada.")); return
        }
        guard ConexionesMotor.urlSegura(conexion.baseURL) else {
            completion(.init(ok: false, mensaje: "La URL base no es segura. Usa HTTPS, o HTTP únicamente para localhost.")); return
        }
        guard conexion.endpoints.contains(where: { !$0.efectivamenteEscritura }) else {
            completion(.init(ok: false, mensaje: conexion.tieneEscritura
                ? "Esta conexión solo tiene endpoints de escritura; la propuesta con confirmación llega en la siguiente fase."
                : "La conexión «\(modo.nombre)» no tiene endpoints configurados.")); return
        }
        // FASE 2: si el usuario lo quiere y hay una IA, ELLA arma el plan
        // (endpoint + variables desde el dictado libre). El plan vuelve como
        // texto y se valida estricto; ante fallo se cae al camino determinista.
        if conexion.usarIA, ConexionesIA.iaDisponible(modo) != nil {
            ConexionesIA.resolver(modo: modo, conexion: conexion, texto: texto) { r in
                switch r {
                case .plan(let plan):
                    ejecutarEndpoint(modo: modo, conexion: conexion, endpoint: plan.endpoint,
                                     valores: plan.valores, resumen: plan.resumen, completion: completion)
                case .faltan(let nombres):
                    let lista = nombres.joined(separator: ", ")
                    completion(.init(ok: false,
                        mensaje: "Me falta saber: \(lista). Dímelo de nuevo incluyendo ese dato.",
                        evidencia: ["faltan": lista]))
                case .invalido(let motivo):
                    // Fallback determinista (fase 1) SOLO si es viable sin IA;
                    // si no, el motivo real — jamás un endpoint adivinado.
                    if let ep = endpointPara(conexion, texto: texto),
                       ep.variables.allSatisfy({ !$0.requerida }) {
                        var valores: [String: Any] = [:]
                        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { valores["texto"] = t }
                        ejecutarEndpoint(modo: modo, conexion: conexion, endpoint: ep,
                                         valores: valores, resumen: "", completion: completion)
                    } else {
                        completion(.init(ok: false, mensaje: "No pude armar el plan: \(motivo)."))
                    }
                }
            }
            return
        }
        // Camino determinista (fase 1): clave dictada o primer GET, solo {texto}.
        guard let endpoint = endpointPara(conexion, texto: texto) else {
            completion(.init(ok: false, mensaje: "La conexión «\(modo.nombre)» no tiene endpoints de lectura.")); return
        }
        var valores: [String: Any] = [:]
        let contenido = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contenido.isEmpty { valores["texto"] = contenido }
        ejecutarEndpoint(modo: modo, conexion: conexion, endpoint: endpoint,
                         valores: valores, resumen: "", completion: completion)
    }

    /// Tramo común validar→construir→llamar. `valores` ya viene del plan de la
    /// IA (tipados) o del camino determinista ({texto}); la validación contra
    /// el esquema se repite aquí SIEMPRE — nadie salta el validador.
    private static func ejecutarEndpoint(modo: Modo, conexion: ConexionAPI,
                                         endpoint: EndpointAPI, valores: [String: Any],
                                         resumen: String,
                                         completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard !endpoint.efectivamenteEscritura else {
            completion(.init(ok: false, mensaje: "El endpoint «\(endpoint.clave)» es de escritura y requiere confirmación (disponible en la siguiente fase).")); return
        }
        let problemas = ConexionesMotor.validarValores(endpoint: endpoint, valores: valores)
        guard problemas.isEmpty else {
            completion(.init(ok: false, mensaje: "No puedo llamar «\(endpoint.clave)»: " + problemas.joined(separator: "; ") + ".")); return
        }
        guard let url = ConexionesMotor.construirURL(base: conexion.baseURL,
                                                     endpoint: endpoint, valores: valores) else {
            completion(.init(ok: false, mensaje: "No pude armar una URL segura para «\(endpoint.clave)». Revisa la ruta y las variables.")); return
        }
        llamar(url: url, conexion: conexion, modoId: modo.id, endpoint: endpoint,
               resumen: resumen) { r in
            DispatchQueue.main.async { completion(r) }
        }
    }

    /// «Probar conexión» del editor: llama el primer GET de lectura (o solo la
    /// base) y reporta el estado. JAMÁS toca un endpoint de escritura.
    static func probar(_ conexion: ConexionAPI, modoId: String,
                       _ done: @escaping (Bool, String) -> Void) {
        guard ConexionesMotor.urlSegura(conexion.baseURL) else {
            done(false, "URL base no segura (usa https, o http solo en localhost)"); return
        }
        let endpoint = conexion.endpoints.first { !$0.efectivamenteEscritura }
            ?? EndpointAPI(clave: "base", metodo: "GET", ruta: "/")
        var valores: [String: Any] = [:]
        // Una prueba no tiene dictado: las variables van con su nombre visible,
        // suficiente para ver si el servidor responde y cómo.
        for v in endpoint.variables { valores[v.nombre] = v.nombre }
        valores["texto"] = "prueba"
        guard let url = ConexionesMotor.construirURL(base: conexion.baseURL,
                                                     endpoint: endpoint, valores: valores) else {
            done(false, "no pude armar la URL de prueba (revisa ruta/variables)"); return
        }
        llamar(url: url, conexion: conexion, modoId: modoId, endpoint: endpoint) { r in
            DispatchQueue.main.async { done(r.ok, r.mensaje) }
        }
    }

    // El HTTP común de fase 1. Sesión propia por llamada con delegate anti-
    // redirect; se invalida al terminar (patrón de la casa para no fugar).
    private static func llamar(url: URL, conexion: ConexionAPI, modoId: String,
                               endpoint: EndpointAPI, resumen: String = "",
                               _ completion: @escaping (ResultadoHerramientaApple) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = TimeInterval(min(120, max(3, conexion.timeoutSegundos)))
        req.setValue("close", forHTTPHeaderField: "Connection")
        var secretos: [String] = []
        // Fail-closed: el secreto solo viaja si la URL final cifra (o loopback).
        if conexion.auth.tipo == "apikey",
           let secreto = SecretosKeychain.leer(cuenta: modoId), !secreto.isEmpty {
            let h = conexion.auth.header.isEmpty ? "Authorization" : conexion.auth.header
            req.setValue(conexion.auth.prefijo + secreto, forHTTPHeaderField: h)
            secretos.append(secreto)
        }
        for (h, v) in conexion.headers { req.setValue(v, forHTTPHeaderField: h) }
        let delegado = ConexionRedDelegate(url: url)
        let sesion = URLSession(configuration: .ephemeral, delegate: delegado, delegateQueue: nil)
        let inicio = Date()
        let tarea = sesion.dataTask(with: req) { data, resp, error in
            defer { sesion.finishTasksAndInvalidate() }
            let ms = Int(Date().timeIntervalSince(inicio) * 1000)
            if let error {
                let msg = ConexionesMotor.enmascarar(error.localizedDescription, secretos: secretos)
                completion(.init(ok: false, mensaje: "La conexión falló: \(msg)",
                                 evidencia: ["endpoint": endpoint.clave, "ms": "\(ms)"]))
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let cuerpoCrudo = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let cuerpo = ConexionesMotor.enmascarar(String(cuerpoCrudo.prefix(2_000)), secretos: secretos)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            AgenteLog.registrar("conexion_api", [
                "modo": modoId, "endpoint": endpoint.clave, "metodo": "GET",
                "host": url.host ?? "", "estado": code, "ms": ms,
            ])   // deliberadamente SIN url completa ni headers: cero secretos en logs
            guard (200..<300).contains(code) else {
                completion(.init(ok: false,
                    mensaje: "El servidor respondió HTTP \(code)." + (cuerpo.isEmpty ? "" : " \(String(cuerpo.prefix(200)))"),
                    evidencia: ["endpoint": endpoint.clave, "estado": "\(code)", "ms": "\(ms)"]))
                return
            }
            var evidencia = ["endpoint": endpoint.clave, "estado": "\(code)", "ms": "\(ms)",
                             "salida": cuerpo]
            if !resumen.isEmpty { evidencia["plan"] = resumen }
            completion(.init(ok: true,
                mensaje: cuerpo.isEmpty ? "«\(endpoint.clave)» respondió sin contenido (HTTP \(code))." : cuerpo,
                evidencia: evidencia))
        }
        tarea.resume()
    }
}

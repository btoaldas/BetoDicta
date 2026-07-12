import Foundation

// MARK: - IA de chat para pulido y traducción (cualquier proveedor conectado)

/// Proveedores de chat compatibles con la API de OpenAI (mismo /chat/completions).
/// Nube (con key), LOCAL (LM Studio/Ollama autodetectados) o PERSONALIZADA
/// (gateway propio con esquema de auth y encabezados a medida).
struct ChatIA {
    let id: String, nombre: String, base: String, modelo: String, keyEnv: String, local: Bool
    // Auth flexible (para gateways): encabezado, prefijo y extras.
    var authHeader: String = "Authorization"      // o "x-api-key" o cualquiera
    var authPrefix: String = "Bearer "            // "Bearer " o "" (X-API-Key va sin prefijo)
    var headersExtra: [String: String] = [:]
    var keyDirecta: String? = nil                 // personalizadas guardan su key aparte
    var paraPulido: Bool = true

    var key: String? {
        if let d = keyDirecta { return d.isEmpty ? nil : d }
        if local { return "local" }                               // servidores locales: sin auth
        if id == "groq", let g = Config.groqKey() { return g }    // groq también por env
        let k = ApiKeys.get(keyEnv); return k.isEmpty ? nil : k
    }
    /// Aplica auth + encabezados extra a la request.
    /// ¿La base cifra el tráfico? (https, o localhost donde no sale a la red).
    /// No mandamos la API key en claro por http público — fail-closed.
    var baseSegura: Bool {
        if base.lowercased().hasPrefix("https://") { return true }
        // Solo loopback REAL cuenta como seguro (el tráfico no sale de la Mac).
        // Comparar el HOST exacto, no un substring: "localhost.attacker.com" o
        // "127.0.0.1.evil.com" contienen "://localhost"/"://127.0.0.1" pero
        // resuelven a un host externo y NO deben tratarse como seguros.
        guard let host = URL(string: base)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
    func aplicarAuth(_ req: inout URLRequest) {
        // Fail-closed: no mandes NINGÚN secreto por http público — ni la API key
        // ni los encabezados extra (suelen llevar cookies/tokens x-api-key).
        guard local || baseSegura else { return }
        if !local, let k = key { req.setValue(authPrefix + k, forHTTPHeaderField: authHeader) }
        for (h, v) in headersExtra { req.setValue(v, forHTTPHeaderField: h) }
    }
    /// Modelo a usar de VERDAD: local usa el que tenga cargado el servidor;
    /// un gateway trae su modelo activo en `modelo`; un proveedor fijo usa el
    /// que el usuario eligió (Config.pulidoModelo) o su default.
    var modeloEfectivo: String {
        if local { return Config.pulidoModelo(id) ?? Self.modelosLocales[id] ?? modelo }
        if id.hasPrefix("custom:") { return modelo }
        return Config.pulidoModelo(id) ?? modelo
    }
    /// Nombre corto del proveedor (sin el " · modelo" que traen algunos).
    var proveedorCorto: String { nombre.components(separatedBy: " · ").first ?? nombre }
    /// Etiqueta para el selector: "Proveedor · modelo-activo".
    var etiqueta: String { "\(proveedorCorto) · \(modeloEfectivo)" }

    /// Proveedores fijos (nube + locales). Constantes.
    static let fijos: [ChatIA] = [
        ChatIA(id: "groq",       nombre: "Groq · Llama 3.3 70B", base: "https://api.groq.com/openai/v1", modelo: "llama-3.3-70b-versatile", keyEnv: "GROQ_API_KEY",       local: false),
        ChatIA(id: "openai",     nombre: "OpenAI · gpt-4o-mini", base: "https://api.openai.com/v1",      modelo: "gpt-4o-mini",             keyEnv: "OPENAI_API_KEY",     local: false),
        ChatIA(id: "mistral",    nombre: "Mistral · small",      base: "https://api.mistral.ai/v1",      modelo: "mistral-small-latest",    keyEnv: "MISTRAL_API_KEY",    local: false),
        ChatIA(id: "openrouter", nombre: "OpenRouter",           base: "https://openrouter.ai/api/v1",   modelo: "openai/gpt-4o-mini",      keyEnv: "OPENROUTER_API_KEY", local: false),
        ChatIA(id: "deepseek",   nombre: "DeepSeek · chat",      base: "https://api.deepseek.com",       modelo: "deepseek-chat",           keyEnv: "DEEPSEEK_API_KEY",   local: false),
        ChatIA(id: "xai",        nombre: "xAI · Grok",           base: "https://api.x.ai/v1",            modelo: "grok-2-latest",           keyEnv: "XAI_API_KEY",        local: false),
        ChatIA(id: "lmstudio",   nombre: "LM Studio (local)",    base: "http://localhost:1234/v1",       modelo: "local",                   keyEnv: "",                   local: true),
        ChatIA(id: "ollama",     nombre: "Ollama (local)",       base: "http://localhost:11434/v1",      modelo: "local",                   keyEnv: "",                   local: true),
    ]
    /// Catálogo COMPUTADO: relee las personalizadas del disco en cada acceso,
    /// para que cambiar el modelo/URL de un gateway (o agregar/quitar uno)
    /// tenga efecto AL VUELO en el pulido, sin reiniciar la app.
    static var catalogo: [ChatIA] { fijos + PersonalizadaStore.comoChatIA() }
    /// Modelo detectado de cada servidor local (vacío si no está corriendo).
    static var modelosLocales: [String: String] = [:]
    /// Modelos descubiertos por proveedor (id → lista), para el selector de
    /// modelo de CUALQUIER proveedor (no solo gateways). Se llena al pulsar
    /// "Descubrir" en Ajustes → Pulido.
    static var modelosPorProveedor: [String: [String]] = [:]
    /// Precio por modelo si el proveedor lo expone (proveedorId → modeloId →
    /// etiqueta, ej. "gratis" o "$0.15/$0.60 1M"). OpenRouter lo trae; otros no.
    static var precios: [String: [String: String]] = [:]

    /// Descubre los modelos de un proveedor conectado (fijo o local) usando su
    /// base + key, y los cachea en modelosPorProveedor[id].
    static func descubrirProveedor(_ ia: ChatIA, _ done: @escaping ([String], String) -> Void) {
        PersonalizadaStore.descubrirEn(base: ia.base, apiKey: ia.key ?? "",
                                       authHeader: ia.authHeader, authPrefix: ia.authPrefix,
                                       headers: ia.headersExtra, proveedorId: ia.id) { ids, msg in
            if !ids.isEmpty { modelosPorProveedor[ia.id] = ids }
            done(ids, msg)
        }
    }

    /// Conectadas: nube con key + locales corriendo + personalizadas con base.
    static var conectadas: [ChatIA] {
        catalogo.filter { $0.local ? (modelosLocales[$0.id] != nil) : ($0.key != nil) }
    }
    /// Solo las que sirven para pulir (para el selector del pulido).
    static var conectadasPulido: [ChatIA] { conectadas.filter { $0.paraPulido } }
    /// La elegida por el usuario; si esa no está disponible, la primera con pulido.
    static func seleccionada() -> ChatIA? {
        if let c = catalogo.first(where: { $0.id == Config.pulidoProveedor() && $0.paraPulido }),
           conectadas.contains(where: { $0.id == c.id }) { return c }
        return conectadasPulido.first
    }
    /// Sondea LM Studio / Ollama y cachea su modelo cargado (si responden).
    static func detectarLocales(_ done: (() -> Void)? = nil) {
        let grupo = DispatchGroup()
        for c in catalogo where c.local {
            guard let url = URL(string: "\(c.base)/models") else { continue }
            grupo.enter()
            var req = URLRequest(url: url); req.timeoutInterval = 1.2
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { grupo.leave() }
                let modelo = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?
                    .flatMap { ($0["data"] as? [[String: Any]])?.first?["id"] as? String }
                DispatchQueue.main.async { modelosLocales[c.id] = modelo }
            }.resume()
        }
        grupo.notify(queue: .main) { done?() }
    }
}

// MARK: - IAs personalizadas (gateways propios: base URL, auth y encabezados a medida)

struct IAPersonalizada: Codable, Identifiable {
    var id = UUID().uuidString
    var nombre = ""
    var base = ""                 // URL base (…/v1)
    var apiKey = ""
    var authHeader = "Authorization"   // "Authorization" | "x-api-key" | cualquiera
    var authPrefix = "Bearer "         // "Bearer " o "" (X-API-Key va sin prefijo)
    var headers: [String: String] = [:]   // encabezados extra
    var modelo = ""               // ID del modelo ACTIVO (manual o elegido)
    var modelos: [String] = []    // catálogo descubierto: se elige cualquiera "afuera"
    var paraPulido = true
    var paraVoz = false           // reconocer voz (transcripción) — pendiente de cablear
}

// Decodificación TOLERANTE: Swift no aplica los valores por defecto a claves
// ausentes en Codable sintetizado, así que un JSON viejo (sin `modelos`, por
// ej.) reventaba TODO el decode y "perdía" los gateways. Con decodeIfPresent,
// cada campo nuevo simplemente cae a su default y nada se pierde.
extension IAPersonalizada {
    private enum CK: String, CodingKey {
        case id, nombre, base, apiKey, authHeader, authPrefix, headers, modelo, modelos, paraPulido, paraVoz
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        self.init()   // arranca con todos los defaults
        if let v = try? c.decode(String.self, forKey: .id), !v.isEmpty { id = v }
        nombre     = (try? c.decode(String.self, forKey: .nombre)) ?? nombre
        base       = (try? c.decode(String.self, forKey: .base)) ?? base
        apiKey     = (try? c.decode(String.self, forKey: .apiKey)) ?? apiKey
        authHeader = (try? c.decode(String.self, forKey: .authHeader)) ?? authHeader
        authPrefix = (try? c.decode(String.self, forKey: .authPrefix)) ?? authPrefix
        headers    = (try? c.decode([String: String].self, forKey: .headers)) ?? headers
        modelo     = (try? c.decode(String.self, forKey: .modelo)) ?? modelo
        modelos    = (try? c.decode([String].self, forKey: .modelos)) ?? modelos
        paraPulido = (try? c.decode(Bool.self, forKey: .paraPulido)) ?? paraPulido
        paraVoz    = (try? c.decode(Bool.self, forKey: .paraVoz)) ?? paraVoz
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        try c.encode(id, forKey: .id)
        try c.encode(nombre, forKey: .nombre)
        try c.encode(base, forKey: .base)
        try c.encode(apiKey, forKey: .apiKey)
        try c.encode(authHeader, forKey: .authHeader)
        try c.encode(authPrefix, forKey: .authPrefix)
        try c.encode(headers, forKey: .headers)
        try c.encode(modelo, forKey: .modelo)
        try c.encode(modelos, forKey: .modelos)
        try c.encode(paraPulido, forKey: .paraPulido)
        try c.encode(paraVoz, forKey: .paraVoz)
    }
}

enum PersonalizadaStore {
    static var url: URL { Config.dir.appendingPathComponent("ia_personalizadas.json") }
    static func cargar() -> [IAPersonalizada] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([IAPersonalizada].self, from: $0) } ?? []
    }
    static func guardar(_ arr: [IAPersonalizada]) {
        if let d = try? JSONEncoder().encode(arr) {
            Config.asegurarDirSeguro()
            try? d.write(to: url)
            Config.protegerSecreto(url)   // 0600: guarda las API keys de los gateways
        }
    }
    /// Las personalizadas como ChatIA (para el catálogo y el selector).
    static func comoChatIA() -> [ChatIA] {
        cargar().filter { !$0.base.isEmpty && !$0.modelo.isEmpty }.map { p in
            ChatIA(id: "custom:\(p.id)", nombre: p.nombre.isEmpty ? "Personalizada" : p.nombre,
                   base: p.base, modelo: p.modelo, keyEnv: "", local: false,
                   authHeader: p.authHeader.isEmpty ? "Authorization" : p.authHeader,
                   authPrefix: p.authPrefix, headersExtra: p.headers,
                   keyDirecta: p.apiKey, paraPulido: p.paraPulido)
        }
    }
    /// Extrae ids de modelos de las formas comunes: {data:[{id}]}, {models:
    /// [{id|name}]}, arreglo de strings, o arreglo de objetos.
    static func extraerModelos(_ j: Any) -> [String] { extraerModelosPreciados(j).map { $0.0 } }

    /// Como extraerModelos pero además saca el PRECIO si viene (campo `pricing`
    /// de OpenRouter y compatibles): (id, etiqueta-de-precio?).
    static func extraerModelosPreciados(_ j: Any) -> [(String, String?)] {
        func etiquetaPrecio(_ d: [String: Any]) -> String? {
            guard let p = d["pricing"] as? [String: Any] else { return nil }
            func num(_ k: String) -> Double? {
                if let s = p[k] as? String { return Double(s) }
                if let n = p[k] as? Double { return n }
                return nil
            }
            guard let inp = num("prompt"), let out = num("completion") else { return nil }
            if inp < 0 || out < 0 { return "variable" }   // OpenRouter usa -1 (auto/fusion) = precio dinámico
            if inp == 0 && out == 0 { return "gratis" }
            return String(format: "$%.2f/$%.2f 1M", inp * 1_000_000, out * 1_000_000)
        }
        func deArreglo(_ a: [Any]) -> [(String, String?)] {
            a.compactMap { el in
                if let s = el as? String { return (s, nil) }
                if let d = el as? [String: Any],
                   let id = (d["id"] as? String) ?? (d["name"] as? String) ?? (d["model"] as? String) {
                    return (id, etiquetaPrecio(d))
                }
                return nil
            }
        }
        if let d = j as? [String: Any] {
            if let a = d["data"] as? [Any] { return deArreglo(a) }
            if let a = d["models"] as? [Any] { return deArreglo(a) }
        }
        if let a = j as? [Any] { return deArreglo(a) }
        return []
    }
    /// Descubre modelos de un gateway. Prueba base/models y, si la base no
    /// trae /v1 y ahí no hay lista JSON (muchos gateways sirven una PÁGINA en
    /// /models y la API real bajo /v1), reintenta en base/v1/models.
    /// Devuelve (ids, mensaje).
    static func descubrirModelos(_ ia: IAPersonalizada, rutaManual: String? = nil,
                                 _ done: @escaping ([String], String) -> Void) {
        descubrirEn(base: ia.base, apiKey: ia.apiKey, authHeader: ia.authHeader,
                    authPrefix: ia.authPrefix, headers: ia.headers, rutaManual: rutaManual,
                    proveedorId: "custom:\(ia.id)", done)
    }

    /// Núcleo de descubrimiento (OpenAI-compat). Prueba varias formas de ruta
    /// porque cada proveedor/gateway sirve la lista distinto: /models, /v1/models,
    /// /openai/v1/models, /api/v1/models. `rutaManual` (URL completa o ruta) se
    /// prueba PRIMERO — para "con esta URL, probar el descubrimiento". Si se pasa
    /// `proveedorId`, cachea los PRECIOS descubiertos en ChatIA.precios[id].
    static func descubrirEn(base: String, apiKey: String, authHeader: String, authPrefix: String,
                            headers: [String: String], rutaManual: String? = nil,
                            proveedorId: String? = nil,
                            _ done: @escaping ([String], String) -> Void) {
        var b = base.trimmingCharacters(in: .whitespaces)
        while b.hasSuffix("/") { b = String(b.dropLast()) }
        let bl = b.lowercased()
        var rutas: [String] = []
        if let rm = rutaManual?.trimmingCharacters(in: .whitespaces), !rm.isEmpty {
            rutas.append(rm.hasPrefix("http") ? rm : "\(b)/\(rm.hasPrefix("/") ? String(rm.dropFirst()) : rm)")
        }
        rutas.append("\(b)/models")
        if !bl.contains("/v1") && !bl.contains("/v2") { rutas.append("\(b)/v1/models") }
        if !bl.contains("/openai") { rutas.append("\(b)/openai/v1/models") }
        rutas.append("\(b)/api/v1/models")
        var vistos = Set<String>(); rutas = rutas.filter { vistos.insert($0).inserted }   // dedup, mantiene orden
        func intentar(_ i: Int, _ code: Int, _ err: String?) {
            guard i < rutas.count else {
                let m = err ?? (code >= 400
                    ? "HTTP \(code): revisa URL o auth"
                    : "sin lista de modelos (prueba una ruta manual, ej: /v1/models)")
                DispatchQueue.main.async { done([], m) }; return
            }
            // URL candidata inválida (ej: ruta manual con espacio): salta a la
            // siguiente, no abortes todo el descubrimiento.
            guard let url = URL(string: rutas[i]) else { intentar(i + 1, code, err); return }
            var req = URLRequest(url: url); req.timeoutInterval = 10
            // Fail-closed: no adjuntes secretos si la ruta candidata no cifra
            // (misma garantía que el pulido; soporta rutaManual con http).
            let h0 = url.host?.lowercased() ?? ""
            let segura = url.scheme?.lowercased() == "https" || h0 == "localhost" || h0 == "127.0.0.1" || h0 == "::1"
            if segura {
                if !apiKey.isEmpty { req.setValue(authPrefix + apiKey, forHTTPHeaderField: authHeader.isEmpty ? "Authorization" : authHeader) }
                for (h, v) in headers { req.setValue(v, forHTTPHeaderField: h) }
            }
            URLSession.shared.dataTask(with: req) { data, resp, e in
                var preciados: [(String, String?)] = []
                let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if e == nil, let data, let j = try? JSONSerialization.jsonObject(with: data) { preciados = extraerModelosPreciados(j) }
                if !preciados.isEmpty {
                    let ids = preciados.map { $0.0 }
                    let ruta = URL(string: rutas[i])?.path ?? rutas[i]
                    let via = rutas[i] == "\(b)/models" ? "" : " (\(ruta))"
                    DispatchQueue.main.async {
                        if let pid = proveedorId {
                            var mp: [String: String] = [:]
                            for (id, pr) in preciados { if let pr { mp[id] = pr } }
                            if !mp.isEmpty { ChatIA.precios[pid] = mp }
                        }
                        done(ids, "\(ids.count) modelos\(via)")
                    }
                } else {
                    intentar(i + 1, c, e?.localizedDescription)
                }
            }.resume()
        }
        intentar(0, 0, nil)
    }
    /// Prueba la conexión (descubre modelos; ok si responde algo o 200).
    static func probar(_ ia: IAPersonalizada, _ done: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "\(ia.base)/models") else { done(false, "URL inválida"); return }
        var req = URLRequest(url: url); req.timeoutInterval = 8
        let h0 = url.host?.lowercased() ?? ""
        let segura = url.scheme?.lowercased() == "https" || h0 == "localhost" || h0 == "127.0.0.1" || h0 == "::1"
        if segura {   // fail-closed: no mandar secretos por http
            if !ia.apiKey.isEmpty { req.setValue(ia.authPrefix + ia.apiKey, forHTTPHeaderField: ia.authHeader.isEmpty ? "Authorization" : ia.authHeader) }
            for (h, v) in ia.headers { req.setValue(v, forHTTPHeaderField: h) }
        }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err { done(false, err.localizedDescription); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                done((200..<300).contains(code), "HTTP \(code)")
            }
        }.resume()
    }
}

// MARK: - Post-proceso con IA (opcional): pule puntuación y nombres por contexto

/// Manda el texto a Groq (llama-3.3-70b) con el glosario del usuario.
/// REGLA DE ORO: si algo falla (sin key, sin red, timeout), devuelve el
/// texto original intacto — el post-proceso jamás rompe un dictado.
enum LLMPostProcess {

    static func enhance(_ text: String, completion: @escaping (String) -> Void) {
        guard let ia = ChatIA.seleccionada() else {
            Log.write("pulido: SIN IA de chat conectada (pon una key en Modelos) — texto original")
            completion(text)
            return
        }
        // Sin contenido real no hay nada que pulir: mandar "- -" al LLM
        // hace que responda meta-frases ("No hay transcripción…") que se
        // pegarían como si fueran el dictado.
        guard text.unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).count >= 4 else {
            Log.write("pulido: texto sin contenido — se entrega tal cual")
            completion(text)
            return
        }
        let inicio = Date()

        let glosario = Config.keyterms().prefix(80).joined(separator: ", ")
        let estilo = Config.customPrompt().map { "\n        - ESTILO pedido por el usuario: \($0)" } ?? ""
        let prompt = """
        Limpia esta transcripción dictada en español latino:
        - Corrige puntuación, mayúsculas y ortografía.
        - Elimina muletillas (eh, este, "o sea" de relleno) y repeticiones de tartamudeo.
        - GLOSARIO — estos términos se escriben exactamente así cuando aparecen: \(glosario).
        - REGLA ESTRICTA: solo corrige a un término del glosario si la palabra NO es español válido y suena inequívocamente igual. Palabras normales del español se quedan intactas.
        - Conserva el significado y el orden exactos. No parafrasees, no resumas, no agregues nada.\(estilo)
        Devuelve ÚNICAMENTE la transcripción limpia, sin comentarios.

        Transcripción:

        \(text)
        """

        var request = URLRequest(url: URL(string: "\(ia.base)/chat/completions")!)
        request.httpMethod = "POST"
        // Timeout DINÁMICO: base configurable (Avanzado) + extra por largo del
        // texto (más texto = la IA genera más = tarda más). Tope 120s.
        request.timeoutInterval = min(120, Config.pulidoTimeout() + Double(text.count) / 40)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ia.aplicarAuth(&request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": ia.modeloEfectivo,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0,
        ])
        hacer(request, textoOriginal: text, inicio: inicio, intento: 1, completion: completion)
    }

    /// Ejecuta la llamada con hasta 1 REINTENTO ante fallos de red/timeout
    /// (transitorios). En error de servidor (HTTP 4xx/5xx) no reintenta.
    private static func hacer(_ request: URLRequest, textoOriginal text: String,
                              inicio: Date, intento: Int, completion: @escaping (String) -> Void) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let data,
                   let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let pulido = (message["content"] as? String)?
                       .trimmingCharacters(in: .whitespacesAndNewlines),
                   !pulido.isEmpty {
                    let ms = Int(Date().timeIntervalSince(inicio) * 1000)
                    Log.write("pulido: OK en \(ms)ms — \(text.count)→\(pulido.count) chars\(intento > 1 ? " (reintento)" : "")")
                    completion(pulido)
                    return
                }
                // Falló. ¿Es de RED (transitorio) o del servidor?
                let esRed = error != nil                  // timeout/conexión → error != nil
                let motivo = error?.localizedDescription
                    ?? data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(150).description
                    ?? "sin respuesta"
                if esRed, intento < 2 {
                    Log.write("pulido: fallo de red (\(motivo)) — reintento…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        hacer(request, textoOriginal: text, inicio: inicio, intento: intento + 1, completion: completion)
                    }
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Log.write("pulido: FALLÓ (HTTP \(code)) → texto original. Detalle: \(motivo)")
                completion(text)
            }
        }.resume()
    }
}

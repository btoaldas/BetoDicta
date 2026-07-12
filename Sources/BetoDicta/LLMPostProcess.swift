import Foundation

// MARK: - IA de chat para pulido y traducción (cualquier proveedor conectado)

/// Proveedores de chat compatibles con la API de OpenAI (mismo /chat/completions).
/// Nube (con key) o LOCAL (LM Studio / Ollama, autodetectados si están arriba).
struct ChatIA {
    let id: String, nombre: String, base: String, modelo: String, keyEnv: String, local: Bool

    var key: String? {
        if local { return "local" }                               // servidores locales: sin auth
        if id == "groq", let g = Config.groqKey() { return g }    // groq también por env
        let k = ApiKeys.get(keyEnv); return k.isEmpty ? nil : k
    }
    /// Modelo a usar: local usa el que tenga cargado el servidor (detectado).
    var modeloEfectivo: String { local ? (Self.modelosLocales[id] ?? modelo) : modelo }

    static let catalogo: [ChatIA] = [
        ChatIA(id: "groq",       nombre: "Groq · Llama 3.3 70B", base: "https://api.groq.com/openai/v1", modelo: "llama-3.3-70b-versatile", keyEnv: "GROQ_API_KEY",       local: false),
        ChatIA(id: "openai",     nombre: "OpenAI · gpt-4o-mini", base: "https://api.openai.com/v1",      modelo: "gpt-4o-mini",             keyEnv: "OPENAI_API_KEY",     local: false),
        ChatIA(id: "mistral",    nombre: "Mistral · small",      base: "https://api.mistral.ai/v1",      modelo: "mistral-small-latest",    keyEnv: "MISTRAL_API_KEY",    local: false),
        ChatIA(id: "openrouter", nombre: "OpenRouter",           base: "https://openrouter.ai/api/v1",   modelo: "openai/gpt-4o-mini",      keyEnv: "OPENROUTER_API_KEY", local: false),
        ChatIA(id: "lmstudio",   nombre: "LM Studio (local)",    base: "http://localhost:1234/v1",       modelo: "local",                   keyEnv: "",                   local: true),
        ChatIA(id: "ollama",     nombre: "Ollama (local)",       base: "http://localhost:11434/v1",      modelo: "local",                   keyEnv: "",                   local: true),
    ]
    /// Modelo detectado de cada servidor local (vacío si no está corriendo).
    static var modelosLocales: [String: String] = [:]

    /// Conectadas: nube con key + locales detectados corriendo.
    static var conectadas: [ChatIA] {
        catalogo.filter { $0.local ? (modelosLocales[$0.id] != nil) : ($0.key != nil) }
    }
    /// La elegida por el usuario; si esa no está disponible, la primera que sí.
    static func seleccionada() -> ChatIA? {
        if let c = catalogo.first(where: { $0.id == Config.pulidoProveedor() }),
           conectadas.contains(where: { $0.id == c.id }) { return c }
        return conectadas.first
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
        request.setValue("Bearer \(ia.key ?? "")", forHTTPHeaderField: "Authorization")
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

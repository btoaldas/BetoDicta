import Foundation

// MARK: - IA de chat para pulido y traducción (cualquier proveedor conectado)

/// Proveedores de chat compatibles con la API de OpenAI (mismo /chat/completions).
struct ChatIA {
    let id: String, nombre: String, base: String, modelo: String, keyEnv: String
    var key: String? {
        if id == "groq", let g = Config.groqKey() { return g }   // groq también por env
        let k = ApiKeys.get(keyEnv); return k.isEmpty ? nil : k
    }
    static let catalogo: [ChatIA] = [
        ChatIA(id: "groq",    nombre: "Groq · Llama 3.3 70B",  base: "https://api.groq.com/openai/v1", modelo: "llama-3.3-70b-versatile", keyEnv: "GROQ_API_KEY"),
        ChatIA(id: "openai",  nombre: "OpenAI · gpt-4o-mini",  base: "https://api.openai.com/v1",      modelo: "gpt-4o-mini",             keyEnv: "OPENAI_API_KEY"),
        ChatIA(id: "mistral", nombre: "Mistral · small",       base: "https://api.mistral.ai/v1",      modelo: "mistral-small-latest",    keyEnv: "MISTRAL_API_KEY"),
    ]
    /// Las que tienen key puesta (para el selector).
    static var conectadas: [ChatIA] { catalogo.filter { $0.key != nil } }
    /// La elegida por el usuario; si esa no tiene key, la primera que sí.
    static func seleccionada() -> ChatIA? {
        if let c = catalogo.first(where: { $0.id == Config.pulidoProveedor() }), c.key != nil { return c }
        return conectadas.first
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
            "model": ia.modelo,
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

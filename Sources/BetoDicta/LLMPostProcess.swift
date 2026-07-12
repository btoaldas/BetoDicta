import Foundation

// MARK: - Post-proceso con IA (opcional): pule puntuación y nombres por contexto

/// Manda el texto a Groq (llama-3.3-70b) con el glosario del usuario.
/// REGLA DE ORO: si algo falla (sin key, sin red, timeout), devuelve el
/// texto original intacto — el post-proceso jamás rompe un dictado.
enum LLMPostProcess {

    static func enhance(_ text: String, completion: @escaping (String) -> Void) {
        guard let key = Config.groqKey() else {
            Log.write("pulido: SIN GROQ_API_KEY — texto original")
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

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20                      // Groq a veces tarda bajo carga
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "llama-3.3-70b-versatile",
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

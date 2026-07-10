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
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "llama-3.3-70b-versatile",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0,
        ])

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                guard let data,
                      let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let pulido = (message["content"] as? String)?
                          .trimmingCharacters(in: .whitespacesAndNewlines),
                      !pulido.isEmpty else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let cuerpo = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(150) ?? "sin respuesta"
                    Log.write("pulido: FALLÓ (HTTP \(code)) → texto original. Detalle: \(cuerpo)")
                    completion(text)
                    return
                }
                let ms = Int(Date().timeIntervalSince(inicio) * 1000)
                Log.write("pulido: OK en \(ms)ms — \(text.count)→\(pulido.count) chars")
                completion(pulido)
            }
        }.resume()
    }
}

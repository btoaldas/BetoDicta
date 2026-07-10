import Foundation

// MARK: - Traducir al dictar (vía Groq)

/// Traduce el texto dictado al idioma configurado, conservando los términos
/// del glosario intactos (nombres propios no se traducen). Si algo falla,
/// devuelve el texto original — nunca rompe un dictado.
enum Translate {

    static func to(_ idioma: String, text: String, completion: @escaping (String) -> Void) {
        guard let key = Config.groqKey() else {
            Log.log(.ia, "traducir: sin GROQ_API_KEY, texto sin traducir")
            completion(text); return
        }
        let glosario = Config.keyterms().prefix(80).joined(separator: ", ")
        let prompt = """
        Traduce el siguiente texto al \(idioma).
        - Mantén sin traducir estos nombres propios y términos técnicos: \(glosario).
        - Conserva el significado y el tono. No agregues comentarios ni notas.
        Devuelve ÚNICAMENTE la traducción.

        Texto:

        \(text)
        """

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "llama-3.3-70b-versatile",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.2,
        ])

        let inicio = Date()
        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                guard let data,
                      let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let out = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !out.isEmpty else {
                    Log.log(.ia, "traducir: falló, texto sin traducir")
                    completion(text); return
                }
                let ms = Int(Date().timeIntervalSince(inicio) * 1000)
                Log.log(.ia, "traducir a \(idioma): OK en \(ms)ms")
                completion(out)
            }
        }.resume()
    }
}

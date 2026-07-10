import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Cliente batch (scribe_v1 / scribe_v2 + keyterms)

func transcribeBatch(wav: Data, model: String, completion: @escaping (Result<String, Error>) -> Void) {
    guard let key = Config.apiKey() else {
        completion(.failure(ScribeError.sinApiKey))
        return
    }
    let boundary = "BetoDicta-\(UUID().uuidString)"
    var body = Data()
    func field(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }
    field("model_id", model)
    field("language_code", "es")
    field("tag_audio_events", "false")
    for term in Config.keyterms().prefix(1000) { field("keyterms", term) }
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictado.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
    body.append(wav)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "xi-api-key")

    URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
        DispatchQueue.main.async {
            if let error { completion(.failure(error)); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data else { completion(.failure(ScribeError.sinTexto)); return }
            guard (200..<300).contains(code) else {
                completion(.failure(ScribeError.http(code, String(data: data, encoding: .utf8) ?? "")))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                completion(.failure(ScribeError.sinTexto))
                return
            }
            completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }.resume()
}


import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Cliente streaming (scribe_v2_realtime, texto en vivo)

final class StreamClient: NSObject {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var committedPieces: [String] = []

    var onPartial: ((String) -> Void)?
    var onCommitted: ((String) -> Void)?
    var onError: ((String) -> Void)?

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let key = Config.apiKey() else {
            completion(.failure(ScribeError.sinApiKey))
            return
        }
        committedPieces = []

        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var items = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
            URLQueryItem(name: "language_code", value: "es"),
        ]
        // El WS acepta máx. 50 keyterms de hasta 20 caracteres
        var seen = Set<String>()
        for term in Config.keyterms() {
            let t = term.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.count <= 20, !seen.contains(t.lowercased()) else { continue }
            seen.insert(t.lowercased())
            items.append(URLQueryItem(name: "keyterms", value: t))
            if seen.count == 50 { break }
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()

        task.receive { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    completion(.failure(ScribeError.ws(error.localizedDescription)))
                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["message_type"] as? String {
                        if type == "session_started" {
                            self?.receiveLoop()
                            completion(.success(()))
                        } else {
                            let msg = json["message"] as? String ?? type
                            completion(.failure(ScribeError.ws(msg)))
                        }
                    } else {
                        self?.receiveLoop()
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func send(chunk: Data) {
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": chunk.base64EncodedString(),
            "commit": false,
            "sample_rate": 16000,
        ]
        sendJSON(message)
    }

    func commit() {
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": true,
            "sample_rate": 16000,
        ]
        sendJSON(message)
    }

    func fullText() -> String {
        committedPieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }
        task.send(.string(string)) { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.onError?(error.localizedDescription) }
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                return // conexión cerrada
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["message_type"] as? String else { return }
        DispatchQueue.main.async {
            switch type {
            case "partial_transcript":
                if let t = json["text"] as? String { self.onPartial?(t) }
            case "committed_transcript", "committed_transcript_with_timestamps":
                if let t = json["text"] as? String, !t.isEmpty {
                    self.committedPieces.append(t)
                    self.onCommitted?(self.fullText())
                }
            case "error", "auth_error", "quota_exceeded", "rate_limited",
                 "resource_exhausted", "session_time_limit_exceeded",
                 "input_error", "chunk_size_exceeded", "transcriber_error":
                self.onError?(json["message"] as? String ?? type)
            default:
                break
            }
        }
    }
}


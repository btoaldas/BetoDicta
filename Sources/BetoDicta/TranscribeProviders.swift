import Foundation

// MARK: - Clientes de transcripción por proveedor + failover

/// Transcribe con Groq (whisper-large-v3, nube). API compatible OpenAI.
enum GroqTranscribe {
    static func run(wav: Data, model: String = "whisper-large-v3", completion: @escaping (Result<String, Error>) -> Void) {
        guard let key = Config.groqKey() else { completion(.failure(ScribeError.sinApiKey)); return }
        let boundary = "BetoDicta-\(UUID().uuidString)"
        var body = Data()
        func field(_ n: String, _ v: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("language", "es")
        field("response_format", "json")
        // Glosario: Whisper acepta un "prompt" que sesga el vocabulario (igual que keyterms en ElevenLabs)
        let glosario = Config.glosarioPrompt()
        if !glosario.isEmpty { field("prompt", glosario) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        req.httpMethod = "POST"; req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        URLSession.shared.uploadTask(with: req, from: body) { data, resp, err in
            DispatchQueue.main.async {
                if let err { completion(.failure(err)); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code) else {
                    completion(.failure(ScribeError.http((resp as? HTTPURLResponse)?.statusCode ?? 0,
                                                          data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = json["text"] as? String else { completion(.failure(ScribeError.sinTexto)); return }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }.resume()
    }
}

/// Transcribe con Whisper LOCAL (whisper-cli + modelo ggml). 100% offline.
enum WhisperLocal {
    static var modelsDir: URL { Config.dir.appendingPathComponent("models") }
    /// Archivo del modelo activo (lo fija la pestaña Modelos).
    static var modeloArchivo: String {
        get { Providers.modelo(de: "whisper_local") ?? "ggml-large-v3-turbo.bin" }
        set {
            var lista = Providers.load()
            if let i = lista.firstIndex(where: { $0.id == "whisper_local" }) {
                lista[i].modelo = newValue; Providers.save(lista)
            }
        }
    }
    static var modelURL: URL { modelsDir.appendingPathComponent(modeloArchivo) }
    static var cliURL: URL? {
        // 1) binario bundleado en la app  2) build local de whisper.cpp
        if let p = Bundle.main.path(forResource: "whisper-cli", ofType: nil) { return URL(fileURLWithPath: p) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dev = home.appendingPathComponent("whisper.cpp/build/bin/whisper-cli")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    static var disponible: Bool {
        cliURL != nil && FileManager.default.fileExists(atPath: modelURL.path)
    }

    static func run(wav: Data, completion: @escaping (Result<String, Error>) -> Void) {
        // Vía rápida: server residente ya precalentado (modelo en memoria).
        if WhisperServer.corriendo {
            WhisperServer.transcribe(wav: wav) { r in
                switch r {
                case .success(let texto): completion(.success(texto))
                case .failure:
                    Log.log(.ia, "server local falló → whisper-cli de respaldo")
                    runCLI(wav: wav, completion: completion)
                }
            }
            return
        }
        runCLI(wav: wav, completion: completion)
    }

    /// Vía clásica: proceso whisper-cli efímero (carga modelo, transcribe, muere).
    private static func runCLI(wav: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard let cli = cliURL else { completion(.failure(ScribeError.ws("whisper-cli no encontrado"))); return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            completion(.failure(ScribeError.ws("Falta el modelo local — descárgalo en Modelos"))); return
        }
        DispatchQueue.global().async {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("beto-\(UUID().uuidString).wav")
            try? wav.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let task = Process()
            task.executableURL = cli
            var args = ["-m", modelURL.path, "-l", "es", "-nt", "-otxt", "-f", tmp.path,
                        "-of", tmp.deletingPathExtension().path]
            // Glosario: whisper.cpp acepta --prompt para sesgar el vocabulario
            let glosario = Config.glosarioPrompt()
            if !glosario.isEmpty { args += ["--prompt", glosario] }
            task.arguments = args
            let pipe = Pipe(); task.standardError = pipe; task.standardOutput = Pipe()
            do {
                try task.run(); task.waitUntilExit()
                let txtURL = tmp.deletingPathExtension().appendingPathExtension("txt")
                let texto = (try? String(contentsOf: txtURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                try? FileManager.default.removeItem(at: txtURL)
                DispatchQueue.main.async {
                    texto.isEmpty ? completion(.failure(ScribeError.sinTexto)) : completion(.success(texto))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

// MARK: - Orquestador de failover (batch)

enum Failover {
    /// Intenta transcribir el WAV recorriendo la cadena de proveedores activos.
    /// Devuelve el primer éxito, o el último error si todos fallan.
    static func transcribe(wav: Data, completion: @escaping (Result<(String, String), Error>) -> Void) {
        let cadena = Providers.cadena()
        intentar(wav: wav, cadena: cadena, idx: 0, ultimoError: nil, completion: completion)
    }

    private static func intentar(wav: Data, cadena: [Provider], idx: Int,
                                 ultimoError: Error?, completion: @escaping (Result<(String, String), Error>) -> Void) {
        guard idx < cadena.count else {
            completion(.failure(ultimoError ?? ScribeError.sinTexto)); return
        }
        let p = cadena[idx]
        Log.log(.ia, "failover: intentando \(p.nombre) (#\(idx + 1))")

        let siguiente: (Result<String, Error>) -> Void = { r in
            switch r {
            case .success(let texto):
                Log.log(.ia, "failover: \(p.nombre) OK")
                completion(.success((texto, p.nombre)))
            case .failure(let e):
                Log.log(.ia, "failover: \(p.nombre) falló (\(e.localizedDescription)) → siguiente")
                intentar(wav: wav, cadena: cadena, idx: idx + 1, ultimoError: e, completion: completion)
            }
        }
        switch p.id {
        case "elevenlabs": transcribeBatch(wav: wav, model: elevenModel(p)) { siguiente($0) }
        case "groq": GroqTranscribe.run(wav: wav, model: p.modelo ?? "whisper-large-v3") { siguiente($0) }
        case "whisper_local": WhisperLocal.run(wav: wav) { siguiente($0) }
        default: siguiente(.failure(ScribeError.sinTexto))
        }
    }

    private static func elevenModel(_ p: Provider) -> String {
        let m = p.modelo ?? "scribe_v2"
        return m == "scribe_v2_realtime" ? "scribe_v2" : m
    }
}

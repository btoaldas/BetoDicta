import Foundation

// MARK: - Búsqueda SEMÁNTICA del historial (por significado, con embeddings)
//
// La búsqueda normal del Historial es por TEXTO exacto (folding). Esta busca por
// SIGNIFICADO: convierte cada dictado y tu consulta en un vector (embedding) y
// los ordena por cercanía (coseno). Así "reunión de plata" encuentra un dictado
// sobre "presupuesto", aunque no compartan palabras.
//
// Motor por defecto: Ollama local (bge-m3) — gratis, privado, sin salir del Mac.
// Parametrizable: base + modelo (Config). Soporta Ollama (/api/embeddings) y
// cualquier API OpenAI-compat (/v1/embeddings). Opt-in (default OFF).
//
// Caché en disco (~/.betodicta/embeddings.json) por ruta+fecha: un dictado solo
// se embebe UNA vez; las siguientes búsquedas reusan el vector.

enum EmbeddingSearch {
    struct Entrada { let vec: [Double]; let mtime: Double }
    /// path del .txt → vector cacheado (+ mtime para invalidar si cambió).
    private static var cache: [String: Entrada] = [:]
    private static var cargado = false
    private static var cacheURL: URL { Config.dir.appendingPathComponent("embeddings.json") }

    static func cargarCache() {
        guard !cargado else { return }
        cargado = true
        guard let data = try? Data(contentsOf: cacheURL),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        for (k, v) in j {
            if let vec = v["v"] as? [Double], let m = v["m"] as? Double {
                cache[k] = Entrada(vec: vec, mtime: m)
            }
        }
    }

    private static func guardarCache() {
        var out: [String: [String: Any]] = [:]
        for (k, e) in cache { out[k] = ["v": e.vec, "m": e.mtime] }
        if let d = try? JSONSerialization.data(withJSONObject: out) {
            Config.asegurarDirSeguro()
            try? d.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: Motor (parametrizable)
    private static var base: String {
        let b = Config.embeddingBase()
        return b.isEmpty ? "http://localhost:11434" : b
    }
    private static var modelo: String {
        let m = Config.embeddingModelo()
        return m.isEmpty ? "bge-m3" : m
    }
    /// http/localhost permitido (Ollama local); nube exige https (fail-closed).
    private static func esSeguro(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")
    }

    /// Embebe un texto. Detecta el formato por la base: si contiene "/v1" usa
    /// OpenAI-compat (/embeddings, {model,input}→data[0].embedding); si no, usa
    /// Ollama (/api/embeddings, {model,prompt}→embedding).
    static func embed(_ texto: String, completion: @escaping (Result<[Double], Error>) -> Void) {
        let openai = base.contains("/v1")
        let endpoint = openai ? "\(base)/embeddings" : "\(base)/api/embeddings"
        guard let url = URL(string: endpoint) else { completion(.failure(ScribeError.ws("URL de embeddings inválida"))); return }
        guard esSeguro(url) else { completion(.failure(ScribeError.ws("Embeddings en la nube exige https"))); return }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Auth solo para nube OpenAI-compat (Ollama local no la necesita).
        let key = ApiKeys.get(Config.embeddingKeyEnv())
        if openai, !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let cuerpo: [String: Any] = openai ? ["model": modelo, "input": texto] : ["model": modelo, "prompt": texto]
        req.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(.failure(err)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, (200..<300).contains(code),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? ""))); return
            }
            // Ollama: {embedding:[...]}. OpenAI: {data:[{embedding:[...]}]}.
            let vec = (j["embedding"] as? [Double])
                ?? ((j["data"] as? [[String: Any]])?.first?["embedding"] as? [Double])
            guard let v = vec, !v.isEmpty else { completion(.failure(ScribeError.sinTexto)); return }
            completion(.success(v))
        }.resume()
    }

    static func coseno(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let den = (na.squareRoot() * nb.squareRoot())
        return den == 0 ? 0 : dot / den
    }

    /// Asegura el vector de un texto (ruta+mtime como clave de caché). Devuelve
    /// el vector por el callback (desde caché o recién calculado).
    static func vectorDe(path: String, mtime: Double, texto: String,
                         completion: @escaping ([Double]?) -> Void) {
        if let e = cache[path], e.mtime == mtime { completion(e.vec); return }
        embed(texto) { r in
            switch r {
            case .success(let v):
                cache[path] = Entrada(vec: v, mtime: mtime)
                completion(v)
            case .failure:
                completion(nil)
            }
        }
    }

    /// Estado de una búsqueda semántica (progreso + resultados).
    struct Resultado { let path: String; let score: Double }

    private static let lock = NSLock()

    /// Indexa (si hace falta) y ordena las entradas por cercanía a la consulta.
    /// `items`: (path, mtime, texto). Llama `progreso(hechos, total)` mientras
    /// embebe los que faltan, y `done` con los pares (path, score) ordenados.
    /// Embebe hasta 6 a la vez (rápido, sin reventar el servidor); el primer
    /// indexado de un historial grande tarda, luego TODO queda cacheado.
    static func buscar(consulta: String, items: [(path: String, mtime: Double, texto: String)],
                       progreso: @escaping (Int, Int) -> Void,
                       done: @escaping (Result<[Resultado], Error>) -> Void) {
        cargarCache()
        embed(consulta) { r in
            switch r {
            case .failure(let e): DispatchQueue.main.async { done(.failure(e)) }
            case .success(let qv):
                DispatchQueue.global(qos: .userInitiated).async {
                    let total = items.count
                    var resultados: [Resultado] = []
                    var hechos = 0
                    let sem = DispatchSemaphore(value: 6)   // hasta 6 embeds en vuelo
                    let grupo = DispatchGroup()
                    func avanzar() {
                        lock.lock(); hechos += 1; let h = hechos; lock.unlock()
                        DispatchQueue.main.async { progreso(h, total) }
                    }
                    for it in items {
                        lock.lock(); let cacheado = cache[it.path]; lock.unlock()
                        if let e = cacheado, e.mtime == it.mtime {
                            let s = coseno(qv, e.vec)
                            lock.lock(); resultados.append(Resultado(path: it.path, score: s)); lock.unlock()
                            avanzar(); continue
                        }
                        sem.wait(); grupo.enter()
                        embed(it.texto) { r in
                            if case .success(let v) = r {
                                let s = coseno(qv, v)
                                lock.lock()
                                cache[it.path] = Entrada(vec: v, mtime: it.mtime)
                                resultados.append(Resultado(path: it.path, score: s))
                                lock.unlock()
                            }
                            avanzar(); sem.signal(); grupo.leave()
                        }
                    }
                    grupo.wait()
                    guardarCache()
                    lock.lock(); resultados.sort { $0.score > $1.score }; let out = resultados; lock.unlock()
                    DispatchQueue.main.async { done(.success(out)) }
                }
            }
        }
    }
}

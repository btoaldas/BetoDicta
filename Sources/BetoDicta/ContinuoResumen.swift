import Foundation

// MARK: - Bitácora continua: resumen del día
//
// Toma lo transcrito y lo leído de las capturas y pide a la IA configurada un
// relato de la jornada. Se guarda como Markdown junto a la bitácora del día,
// legible sin la aplicación.
//
// Apagado de fábrica: a diferencia del resto del módulo, esto SÍ manda texto
// fuera del equipo si el cerebro elegido es de nube. Es una decisión que la
// persona tiene que tomar a sabiendas, no un valor por defecto.

enum ContinuoResumen {

    /// Genera un documento del día con el prompt indicado (o el activo).
    /// `completion` siempre se llama una vez.
    static func generar(dia: Date = Date(), promptId: String? = nil,
                        completion: @escaping (Result<URL, Error>) -> Void) {
        guard Config.continuoActivo() else {
            completion(.failure(ErrorResumen.apagado)); return
        }
        ContinuoIndice.shared.abrir()
        let material = ContinuoIndice.shared.materialDelDia(dia,
                                                            incluirPantalla: Config.continuoResumenIncluirPantalla())
        guard !material.isEmpty else {
            completion(.failure(ErrorResumen.sinMaterial)); return
        }
        guard let ia = cerebro() else {
            completion(.failure(ErrorResumen.sinCerebro)); return
        }

        let plantilla = promptId.flatMap { ContinuoPrompts.porId($0) } ?? ContinuoPrompts.activo()
        let cuerpo = armarCuerpo(material)
        let prompt = armarPrompt(dia: dia, cuerpo: cuerpo, plantilla: plantilla)

        llamar(ia, prompt: prompt, textLen: cuerpo.count) { texto in
            guard let texto, !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(.failure(ErrorResumen.sinRespuesta)); return
            }
            do {
                let url = try guardar(texto, dia: dia, piezas: material.count, prefijo: plantilla.id)
                Log.log(.sistema, "bitácora: resumen del día escrito en \(url.lastPathComponent)")
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Cerebro elegido para redactar. `seleccionada` sigue al resto de la app;
    /// cualquier otro id fija esa IA entre las conectadas — nube con clave,
    /// cuenta de sesión o local (Ollama, LM Studio) da igual.
    private static func cerebro() -> ChatIA? {
        let elegido = Config.continuoResumenIA()
        if elegido != "seleccionada",
           let c = ChatIA.conectadas.first(where: { $0.id == elegido }) { return c }
        return ChatIA.seleccionada()
    }

    // MARK: Preparación

    /// Compone la línea de tiempo del día, recortada al tope configurado. Se
    /// recorta por el PRINCIPIO: lo último de la jornada suele ser lo que más
    /// interesa recordar.
    private static func armarCuerpo(_ material: [(Date, MaterialContinuo, String, String)]) -> String {
        let hora = DateFormatter()
        hora.dateFormat = "HH:mm:ss"
        var lineas: [String] = []
        for (instante, tipo, fuente, texto) in material {
            let limpio = texto.replacingOccurrences(of: "\n", with: " · ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard limpio.count > 3 else { continue }
            let t = hora.string(from: instante)
            switch tipo {
            case .audio:
                // De dónde salió la voz: el micrófono continuo, un dictado o el
                // audio del propio equipo.
                let canal: String
                switch fuente {
                case "dictado": canal = "dictado"
                case "sistema": canal = "audio del sistema"
                default: canal = "micrófono"
                }
                lineas.append("[\(t)] (\(canal)) \(limpio)")
            case .pantalla:
                // Anotación de contexto, no habla: va entre paréntesis para que
                // el modelo no la confunda con algo que alguien dijo.
                let app = fuente.isEmpty ? "" : " en \(fuente)"
                lineas.append("[\(t)] (en pantalla\(app) se ve: \(limpio))")
            }
        }
        var cuerpo = lineas.joined(separator: "\n")
        let tope = Config.continuoResumenMaxCaracteres()
        if cuerpo.count > tope {
            cuerpo = "[…recorte del principio…]\n" + String(cuerpo.suffix(tope))
        }
        return cuerpo
    }

    private static func armarPrompt(dia: Date, cuerpo: String, plantilla: PromptContinuo) -> String {
        let fecha = DateFormatter()
        fecha.dateFormat = "EEEE d 'de' MMMM 'de' yyyy"
        fecha.locale = Locale(identifier: "es_ES")

        // La instrucción suelta de los ajustes, si existe, manda sobre la
        // plantilla: es el atajo para una pasada puntual sin tocar la biblioteca.
        let suelta = Config.continuoResumenInstruccion()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let instruccion = suelta.isEmpty ? plantilla.texto : suelta

        return """
        \(instruccion)

        Fecha: \(fecha.string(from: dia))

        A continuación va la línea de tiempo cruda del día, con la hora entre
        corchetes al inicio de cada línea.

        - `(micrófono)`, `(dictado)` y `(audio del sistema)` marcan de dónde
          salió la voz. Son transcripciones automáticas: pueden traer errores de
          reconocimiento, así que no cites como literal lo que parezca uno.
        - Las líneas del tipo `(en pantalla … se ve: …)` NO son habla. Son texto
          leído de una captura, como contexto de qué se estaba mirando en ese
          momento. Puede venir cortado o desordenado; úsalo para situar, no para
          citar.

        ---
        \(cuerpo)
        ---
        """
    }

    // MARK: Llamada a la IA

    /// Mismo camino que el resto de la app: si el cerebro es la cuenta de Codex
    /// va por su cliente; si no, petición HTTP normal.
    private static func llamar(_ ia: ChatIA, prompt: String, textLen: Int,
                               _ completion: @escaping (String?) -> Void) {
        if ia.esCuentaCodex {
            AgenteCodex.transformar(prompt, modelo: ia.modeloEfectivo, timeout: 180) { contenido in
                DispatchQueue.main.async { completion(contenido) }
            }
            return
        }
        guard var req = ia.requestChat(prompt: prompt, temperatura: 0.3, textLen: textLen) else {
            DispatchQueue.main.async { completion(nil) }; return
        }
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.timeoutInterval = 180
        URLSession.shared.dataTask(with: req) { data, resp, error in
            let contenido: String? = {
                guard error == nil, let data,
                      let code = (resp as? HTTPURLResponse)?.statusCode,
                      (200..<300).contains(code) else { return nil }
                return ia.extraerContenido(data)
            }()
            DispatchQueue.main.async { completion(contenido) }
        }.resume()
    }

    // MARK: Escritura

    private static func guardar(_ texto: String, dia: Date, piezas: Int,
                                prefijo: String = "resumen") throws -> URL {
        let carpeta = ContinuoAudio.carpetaDelDia(dia, sub: "")
            .deletingLastPathComponent()
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let url = carpeta.appendingPathComponent("\(prefijo)-\(f.string(from: dia)).md")

        let sello = DateFormatter(); sello.dateFormat = "yyyy-MM-dd HH:mm"
        let encabezado = """
        ---
        fecha: \(f.string(from: dia))
        generado: \(sello.string(from: Date()))
        piezas: \(piezas)
        ---

        """
        try (encabezado + texto + "\n").write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    enum ErrorResumen: LocalizedError {
        case apagado, sinMaterial, sinCerebro, sinRespuesta
        var errorDescription: String? {
            switch self {
            case .apagado: return "la bitácora está apagada"
            case .sinMaterial: return "no hay nada transcrito ni leído para ese día"
            case .sinCerebro: return "no hay ninguna IA de chat configurada"
            case .sinRespuesta: return "la IA no devolvió texto"
            }
        }
    }
}

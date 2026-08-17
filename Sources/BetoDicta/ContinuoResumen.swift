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

    /// Genera el resumen de un día. `completion` siempre se llama una vez.
    static func generar(dia: Date = Date(), completion: @escaping (Result<URL, Error>) -> Void) {
        guard Config.continuoActivo() else {
            completion(.failure(ErrorResumen.apagado)); return
        }
        ContinuoIndice.shared.abrir()
        let material = ContinuoIndice.shared.materialDelDia(dia,
                                                            incluirPantalla: Config.continuoResumenIncluirPantalla())
        guard !material.isEmpty else {
            completion(.failure(ErrorResumen.sinMaterial)); return
        }
        guard let ia = ChatIA.seleccionada() else {
            completion(.failure(ErrorResumen.sinCerebro)); return
        }

        let cuerpo = armarCuerpo(material)
        let prompt = armarPrompt(dia: dia, cuerpo: cuerpo)

        llamar(ia, prompt: prompt, textLen: cuerpo.count) { texto in
            guard let texto, !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(.failure(ErrorResumen.sinRespuesta)); return
            }
            do {
                let url = try guardar(texto, dia: dia, piezas: material.count)
                Log.log(.sistema, "bitácora: resumen del día escrito en \(url.lastPathComponent)")
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: Preparación

    /// Compone la línea de tiempo del día, recortada al tope configurado. Se
    /// recorta por el PRINCIPIO: lo último de la jornada suele ser lo que más
    /// interesa recordar.
    private static func armarCuerpo(_ material: [(Date, MaterialContinuo, String, String)]) -> String {
        let hora = DateFormatter()
        hora.dateFormat = "HH:mm"
        var lineas: [String] = []
        for (instante, tipo, app, texto) in material {
            let limpio = texto.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard limpio.count > 3 else { continue }
            let etiqueta = tipo == .audio ? "dicho" : "en pantalla"
            let donde = app.isEmpty || app == "continuo" ? "" : " [\(app)]"
            lineas.append("\(hora.string(from: instante)) · \(etiqueta)\(donde): \(limpio)")
        }
        var cuerpo = lineas.joined(separator: "\n")
        let tope = Config.continuoResumenMaxCaracteres()
        if cuerpo.count > tope {
            cuerpo = "[…recorte del principio…]\n" + String(cuerpo.suffix(tope))
        }
        return cuerpo
    }

    private static func armarPrompt(dia: Date, cuerpo: String) -> String {
        let fecha = DateFormatter()
        fecha.dateFormat = "EEEE d 'de' MMMM 'de' yyyy"
        fecha.locale = Locale(identifier: "es_ES")

        let personalizada = Config.continuoResumenInstruccion()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let instruccion = personalizada.isEmpty ? instruccionDeFabrica : personalizada

        return """
        \(instruccion)

        Fecha: \(fecha.string(from: dia))

        A continuación va la línea de tiempo cruda del día. Las líneas marcadas
        «dicho» son transcripciones automáticas de voz y pueden traer errores de
        reconocimiento; las marcadas «en pantalla» son texto leído de capturas y
        pueden venir cortadas o desordenadas. Interpreta con criterio y no cites
        literalmente lo que parezca un error de transcripción.

        ---
        \(cuerpo)
        ---
        """
    }

    private static let instruccionDeFabrica = """
    Eres el cronista del día de trabajo de una persona. Con el material de
    abajo, redacta un resumen en español, en Markdown, con esta estructura:

    ## Resumen
    Dos o tres frases sobre en qué se fue la jornada.

    ## En qué se trabajó
    Lista de los temas o proyectos reales, con lo que se avanzó en cada uno.

    ## Decisiones
    Qué se decidió y por qué, si se decidió algo.

    ## Pendientes
    Lo que quedó a medias o se mencionó como siguiente paso.

    Reglas: no inventes nada que no esté en el material. Si algo no se puede
    determinar, omítelo en vez de rellenar. Sé concreto y breve; nombra
    proyectos, archivos y personas solo si aparecen con claridad.
    """

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

    private static func guardar(_ texto: String, dia: Date, piezas: Int) throws -> URL {
        let carpeta = ContinuoAudio.carpetaDelDia(dia, sub: "")
            .deletingLastPathComponent()
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let url = carpeta.appendingPathComponent("resumen-\(f.string(from: dia)).md")

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

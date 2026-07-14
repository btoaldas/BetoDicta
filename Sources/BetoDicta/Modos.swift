import Foundation

// MARK: - Modos: qué hacer con lo dictado (pulir / correo / oficio / traducir…)
//
// Un MODO es una receta con nombre para transformar el texto dictado DESPUÉS de
// transcribir. Cada uno lleva su propia IA + modelo + prompt. El modo activo se
// elige en caliente (notch / menú), igual que el proveedor. "Dictado" es el
// default y hace lo de siempre (solo pulir). "Traducir" traduce.
//
// base:
//   "pulir"     — limpia/transforma el texto según `prompt` (Dictado = prompt vacío = limpieza estándar).
//   "traducir"  — traduce al `idiomaDestino`.
//   "responder" — trata el dictado como una instrucción y redacta la respuesta.

struct Modo: Codable, Identifiable {
    var id: String
    var nombre: String
    var icono: String            // SF Symbol
    var base: String             // "pulir" | "traducir" | "responder"
    var prompt: String           // instrucción del modo (vacío en Dictado)
    var proveedorId: String      // "" = usa el proveedor global de pulido
    var modelo: String           // "" = default del proveedor elegido
    var idiomaDestino: String    // solo "traducir"
    var esFijo: Bool             // base (no se borra) vs propio del usuario
    var palabraVoz: String       // frase al inicio del dictado que activa este modo

    init(id: String, nombre: String, icono: String, base: String, prompt: String = "",
         proveedorId: String = "", modelo: String = "", idiomaDestino: String = "inglés",
         esFijo: Bool = true, palabraVoz: String = "") {
        self.id = id; self.nombre = nombre; self.icono = icono; self.base = base
        self.prompt = prompt; self.proveedorId = proveedorId; self.modelo = modelo
        self.idiomaDestino = idiomaDestino; self.esFijo = esFijo; self.palabraVoz = palabraVoz
    }
    // Decodificación tolerante (JSON viejo sin un campo nuevo no revienta).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nombre = (try? c.decode(String.self, forKey: .nombre)) ?? "Modo"
        icono = (try? c.decode(String.self, forKey: .icono)) ?? "wand.and.stars"
        base = (try? c.decode(String.self, forKey: .base)) ?? "pulir"
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        proveedorId = (try? c.decode(String.self, forKey: .proveedorId)) ?? ""
        modelo = (try? c.decode(String.self, forKey: .modelo)) ?? ""
        idiomaDestino = (try? c.decode(String.self, forKey: .idiomaDestino)) ?? "inglés"
        esFijo = (try? c.decode(Bool.self, forKey: .esFijo)) ?? false
        palabraVoz = (try? c.decode(String.self, forKey: .palabraVoz)) ?? ""
    }
}

enum ModosStore {
    private static var url: URL { Config.dir.appendingPathComponent("modos.json") }

    /// Modos BASE (siempre presentes; el usuario edita su prompt/IA pero no los borra).
    static let base: [Modo] = [
        Modo(id: "dictado", nombre: "Dictado", icono: "mic.fill", base: "pulir", prompt: ""),
        Modo(id: "correo", nombre: "Correo", icono: "envelope.fill", base: "pulir",
             prompt: "Reescribe el dictado como un CORREO ELECTRÓNICO claro y bien estructurado: saludo, cuerpo y despedida. Conserva el significado; ajusta el tono (formal por defecto) según lo dictado. Devuelve solo el correo.",
             palabraVoz: "modo correo"),
        Modo(id: "oficio", nombre: "Oficio", icono: "doc.text.fill", base: "pulir",
             prompt: "Reescribe el dictado como un OFICIO o memorando FORMAL e institucional, en registro correcto y respetuoso. Conserva el fondo. Devuelve solo el texto del oficio.",
             palabraVoz: "modo oficio"),
        Modo(id: "tarea", nombre: "Tarea", icono: "checklist", base: "pulir",
             prompt: "Convierte el dictado en una TAREA breve y accionable: una sola línea, empieza con un verbo en infinitivo, sin relleno. Devuelve solo la tarea.",
             palabraVoz: "modo tarea"),
        Modo(id: "nota", nombre: "Nota", icono: "note.text", base: "pulir",
             prompt: "Ordena el dictado como una NOTA clara y legible: puntuación correcta, sin muletillas; usa viñetas si hay varios puntos. Conserva todo el contenido. Devuelve solo la nota.",
             palabraVoz: "modo nota"),
        Modo(id: "traducir", nombre: "Traducir", icono: "globe", base: "traducir", idiomaDestino: "inglés",
             palabraVoz: "modo traducir"),
        Modo(id: "asistente", nombre: "Asistente", icono: "sparkles", base: "responder",
             prompt: "El dictado es una instrucción o pregunta. Responde o redacta lo pedido de forma útil, directa y concisa, en español (salvo que se pida otro idioma). Devuelve solo la respuesta, sin preámbulos.",
             palabraVoz: "modo asistente"),
    ]

    static func todos() -> [Modo] {
        guard let data = try? Data(contentsOf: url),
              var list = try? JSONDecoder().decode([Modo].self, from: data), !list.isEmpty else {
            return base
        }
        // Sumar modos base nuevos que un JSON viejo no conozca (sin duplicar).
        let faltan = base.filter { b in !list.contains { $0.id == b.id } }
        if !faltan.isEmpty { list.append(contentsOf: faltan); guardar(list) }
        return list
    }

    static func guardar(_ modos: [Modo]) {
        if let d = try? JSONEncoder().encode(modos) {
            Config.asegurarDirSeguro()
            try? d.write(to: url, options: .atomic)
        }
    }

    static func modo(_ id: String) -> Modo {
        todos().first { $0.id == id } ?? base[0]
    }

    /// El modo ACTIVO (se elige en caliente). Default: Dictado.
    static func activo() -> Modo { modo(Config.modoActivo()) }
    static func fijarActivo(_ id: String) {
        Config.set("modo_activo", to: id)
        Log.log(.config, "modo activo → \(modo(id).nombre)")
    }

    // MARK: Modos propios (crear / borrar)
    static func crear(nombre: String) -> Modo {
        let m = Modo(id: "propio-\(UUID().uuidString.prefix(8))",
                     nombre: nombre.isEmpty ? "Mi modo" : nombre,
                     icono: "wand.and.stars", base: "pulir", esFijo: false)
        var lista = todos(); lista.append(m); guardar(lista)
        return m
    }
    static func borrar(_ id: String) {
        var lista = todos()
        lista.removeAll { $0.id == id && !$0.esFijo }   // los base no se borran
        guardar(lista)
        if Config.modoActivo() == id { fijarActivo("dictado") }
    }

    // MARK: Activación por VOZ
    private static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Si el dictado EMPIEZA con la palabra de voz de algún modo, devuelve ese
    /// modo y el texto SIN la frase disparadora. nil si ninguno coincide. El
    /// modo con la frase más LARGA gana (evita que "modo" choque con "modo correo").
    static func detectarPorVoz(_ texto: String) -> (Modo, String)? {
        let t = normalizar(texto)
        var mejor: (Modo, Int)? = nil
        for m in todos() where !m.palabraVoz.isEmpty {
            let frase = normalizar(m.palabraVoz)
            guard !frase.isEmpty, t.hasPrefix(frase) else { continue }
            if mejor == nil || frase.count > mejor!.1 { mejor = (m, frase.count) }
        }
        guard let (modo, len) = mejor else { return nil }
        // Recorta la frase del texto original (trimmeado; folding conserva el
        // largo, así que dropFirst(len) quita justo la frase disparadora).
        let orig = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let sinFrase = String(orig.dropFirst(min(len, orig.count)))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;\n").union(.whitespaces))
        return (modo, sinFrase)
    }
}

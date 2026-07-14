import Foundation
import AppKit   // NSWorkspace / NSAppleScript para los triggers por contexto

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
    var apps: [String]           // apps (nombre o bundle id) que activan este modo
    var sitios: [String]         // dominios/URLs que activan este modo (en navegador)

    init(id: String, nombre: String, icono: String, base: String, prompt: String = "",
         proveedorId: String = "", modelo: String = "", idiomaDestino: String = "inglés",
         esFijo: Bool = true, palabraVoz: String = "", apps: [String] = [], sitios: [String] = []) {
        self.id = id; self.nombre = nombre; self.icono = icono; self.base = base
        self.prompt = prompt; self.proveedorId = proveedorId; self.modelo = modelo
        self.idiomaDestino = idiomaDestino; self.esFijo = esFijo; self.palabraVoz = palabraVoz
        self.apps = apps; self.sitios = sitios
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
        apps = (try? c.decode([String].self, forKey: .apps)) ?? []
        sitios = (try? c.decode([String].self, forKey: .sitios)) ?? []
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
        var cambio = false
        if !faltan.isEmpty { list.append(contentsOf: faltan); cambio = true }
        // Auto-sanado de la frase de voz: si un app de versión ANTERIOR reescribió
        // modos.json sin el campo palabraVoz (lo borra al no conocerlo), lo
        // restauramos desde la definición base. Solo si está VACÍO (no pisa lo que
        // tú edites) y solo la frase (prompt/IA/apps/sitios se respetan tal cual).
        for (i, m) in list.enumerated() where m.palabraVoz.isEmpty {
            if let b = base.first(where: { $0.id == m.id }), !b.palabraVoz.isEmpty {
                list[i].palabraVoz = b.palabraVoz; cambio = true
            }
        }
        if cambio { guardar(list) }
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

    /// El modo POR DEFECTO (sticky): al que se vuelve tras cada dictado.
    static func defecto() -> Modo { modo(Config.modoDefecto()) }
    /// Fija el modo por defecto (Ajustes → Modos) y lo aplica ya.
    static func fijarDefecto(_ id: String) {
        Config.set("modo_defecto", to: id)
        Config.set("modo_activo", to: id)
        Log.log(.config, "modo por defecto → \(modo(id).nombre)")
    }
    /// El modo ACTIVO ahora (transitorio; el notch/menú lo cambia al vuelo).
    static func activo() -> Modo { modo(Config.modoActivo()) }
    /// Cambio en caliente (notch/menú): de un solo uso si modoRevertir (default).
    static func fijarActivo(_ id: String) {
        Config.set("modo_activo", to: id)
        Log.log(.config, "modo activo → \(modo(id).nombre)")
    }
    /// Vuelve al modo por defecto si el usuario tiene el "un solo uso" activo.
    /// Se llama tras entregar cada dictado y al arrancar (limpia un transitorio viejo).
    static func revertirADefecto() {
        guard Config.modoRevertir(), Config.modoActivo() != Config.modoDefecto() else { return }
        Config.set("modo_activo", to: Config.modoDefecto())
        Log.log(.config, "modo vuelve al defecto → \(defecto().nombre)")
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
        // No dejar modo_activo NI modo_defecto colgando en un id inexistente.
        if Config.modoDefecto() == id { Config.set("modo_defecto", to: "dictado") }
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

    // MARK: Activación por CONTEXTO (app / sitio web al frente)
    /// El modo cuyo app o sitio coincide con dónde estás (app al frente / URL del
    /// navegador). nil si ninguno. El activo/dictado no cuenta como trigger.
    static func detectarPorContexto(bundleId: String, nombre: String, url: String?) -> Modo? {
        coincidePorContexto(todos(), bundleId: bundleId, nombre: nombre, url: url)
    }
    /// Matcher puro (sin disco) — testeable sin tocar la config real.
    static func coincidePorContexto(_ modos: [Modo], bundleId: String, nombre: String, url: String?) -> Modo? {
        let bid = bundleId.lowercased(), nom = normalizar(nombre), u = url?.lowercased()
        for m in modos where m.id != "dictado" {
            for a in m.apps {
                let an = normalizar(a)
                if !an.isEmpty, bid.contains(an) || nom.contains(an) { return m }
            }
            if let u {
                for s in m.sitios {
                    let sn = normalizar(s)
                    if !sn.isEmpty, u.contains(sn) { return m }
                }
            }
        }
        return nil
    }
}

// MARK: - Contexto: app al frente y URL del navegador (para los triggers)

enum ContextoApp {
    static func alFrente() -> (bundleId: String, nombre: String) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier ?? "", app?.localizedName ?? "")
    }
    /// URL del navegador al frente (best-effort, vía AppleScript). Requiere
    /// permiso de Automatización (lo pide macOS la 1ª vez). nil si no aplica.
    static func urlNavegador(_ bundleId: String) -> String? {
        let scripts: [String: String] = [
            "com.apple.safari": "tell application \"Safari\" to return URL of current tab of front window",
            "com.google.chrome": "tell application \"Google Chrome\" to return URL of active tab of front window",
            "com.microsoft.edgemac": "tell application \"Microsoft Edge\" to return URL of active tab of front window",
            "com.brave.browser": "tell application \"Brave Browser\" to return URL of active tab of front window",
            "company.thebrowser.browser": "tell application \"Arc\" to return URL of active tab of front window",
        ]
        guard let src = scripts[bundleId.lowercased()], let s = NSAppleScript(source: src) else { return nil }
        var err: NSDictionary?
        let out = s.executeAndReturnError(&err)
        return err == nil ? out.stringValue : nil
    }
}

// MARK: - Idiomas para el modo "Traducir" (con banderita + agregar propios)

enum Idiomas {
    /// Idiomas comunes con la bandera que MÁS los representa (aprox: idioma≠país).
    /// kichwa/shuar → 🇪🇨 (Amazonía ecuatoriana, contexto UEA).
    static let base: [(nombre: String, bandera: String)] = [
        ("inglés", "🇬🇧"), ("español", "🇪🇸"), ("portugués", "🇧🇷"), ("francés", "🇫🇷"),
        ("alemán", "🇩🇪"), ("italiano", "🇮🇹"), ("chino", "🇨🇳"), ("japonés", "🇯🇵"),
        ("coreano", "🇰🇷"), ("ruso", "🇷🇺"), ("árabe", "🇸🇦"), ("hindi", "🇮🇳"),
        ("neerlandés", "🇳🇱"), ("turco", "🇹🇷"), ("polaco", "🇵🇱"), ("ucraniano", "🇺🇦"),
        ("griego", "🇬🇷"), ("hebreo", "🇮🇱"), ("vietnamita", "🇻🇳"), ("tailandés", "🇹🇭"),
        ("indonesio", "🇮🇩"), ("sueco", "🇸🇪"), ("noruego", "🇳🇴"), ("danés", "🇩🇰"),
        ("finés", "🇫🇮"), ("checo", "🇨🇿"), ("rumano", "🇷🇴"), ("húngaro", "🇭🇺"),
        ("kichwa", "🇪🇨"), ("shuar", "🇪🇨"),
    ]
    /// Todos: base + los que el usuario agregó (bandera genérica para los propios).
    static func todos() -> [(nombre: String, bandera: String)] {
        var vistos = Set(base.map { $0.nombre.lowercased() })
        var lista = base
        for p in Config.idiomasPersonales() where !p.isEmpty && !vistos.contains(p.lowercased()) {
            lista.append((p, "🏳️")); vistos.insert(p.lowercased())
        }
        return lista
    }
    static func bandera(_ nombre: String) -> String {
        base.first { $0.nombre.caseInsensitiveCompare(nombre) == .orderedSame }?.bandera ?? "🏳️"
    }
    /// Agrega un idioma propio (idempotente; no pisa los base). Devuelve el nombre
    /// CANÓNICO: si ya existe (aunque difiera en mayúsculas/acentos), devuelve el
    /// que está en la lista para que el Picker lo empareje por tag exacto.
    @discardableResult static func agregar(_ nombre: String) -> String {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return "" }
        if let existente = todos().first(where: { $0.nombre.caseInsensitiveCompare(n) == .orderedSame }) {
            return existente.nombre   // ya está: usa el canónico, no el tecleado
        }
        var props = Config.idiomasPersonales(); props.append(n)
        Config.set("idiomas_personales", to: props)
        return n
    }
}

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
    var buscador: String         // solo base "buscar": google/bing/duckduckgo/…/spotlight/personalizado
    var almacen: String          // "tarea"|"nota"|"" — guarda lo procesado en la lista local
    var accion: String           // solo base "accion": id del preset (correo/outlook/whatsapp/…/url)

    init(id: String, nombre: String, icono: String, base: String, prompt: String = "",
         proveedorId: String = "", modelo: String = "", idiomaDestino: String = "inglés",
         esFijo: Bool = true, palabraVoz: String = "", apps: [String] = [], sitios: [String] = [],
         buscador: String = "google", almacen: String = "", accion: String = "correo") {
        self.id = id; self.nombre = nombre; self.icono = icono; self.base = base
        self.prompt = prompt; self.proveedorId = proveedorId; self.modelo = modelo
        self.idiomaDestino = idiomaDestino; self.esFijo = esFijo; self.palabraVoz = palabraVoz
        self.apps = apps; self.sitios = sitios; self.buscador = buscador; self.almacen = almacen
        self.accion = accion
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
        buscador = (try? c.decode(String.self, forKey: .buscador)) ?? "google"
        almacen = (try? c.decode(String.self, forKey: .almacen)) ?? ""
        accion = (try? c.decode(String.self, forKey: .accion)) ?? "correo"
    }
}

enum ModosStore {
    private static var url: URL { Config.dir.appendingPathComponent("modos.json") }

    /// Modos BASE (siempre presentes; el usuario edita su prompt/IA pero no los borra).
    static let base: [Modo] = [
        Modo(id: "dictado", nombre: "Dictado", icono: "mic.fill", base: "pulir", prompt: ""),
        Modo(id: "correo", nombre: "Correo", icono: "envelope.fill", base: "pulir",
             prompt: "Reescribe el dictado como un CORREO ELECTRÓNICO claro y bien estructurado: saludo, cuerpo y despedida. Conserva el significado; ajusta el tono (formal por defecto) según lo dictado. Devuelve solo el correo.",
             palabraVoz: "modo correo, modo correos, modo carreo"),
        Modo(id: "oficio", nombre: "Oficio", icono: "doc.text.fill", base: "pulir",
             prompt: "Reescribe el dictado como un OFICIO o memorando FORMAL e institucional, en registro correcto y respetuoso. Conserva el fondo. Devuelve solo el texto del oficio.",
             palabraVoz: "modo oficio, modo oficios"),
        Modo(id: "tarea", nombre: "Tarea", icono: "checklist", base: "pulir",
             prompt: "Convierte el dictado en una TAREA breve y accionable: una sola línea, empieza con un verbo en infinitivo, sin relleno. Devuelve solo la tarea.",
             palabraVoz: "modo tarea, modo tareas, mudo tarea, molde tarea, moto tarea, modo tare", almacen: "tarea"),
        Modo(id: "nota", nombre: "Nota", icono: "note.text", base: "pulir",
             prompt: "Ordena el dictado como una NOTA clara y legible: puntuación correcta, sin muletillas; usa viñetas si hay varios puntos. Conserva todo el contenido. Devuelve solo la nota.",
             palabraVoz: "modo nota, modo notas, moda nota, modo note", almacen: "nota"),
        Modo(id: "traducir", nombre: "Traducir", icono: "globe", base: "traducir", idiomaDestino: "inglés",
             palabraVoz: "modo traducir, modo traduce, modo traducción"),
        Modo(id: "asistente", nombre: "Asistente", icono: "sparkles", base: "responder",
             prompt: "El dictado es una instrucción o pregunta. Responde o redacta lo pedido de forma útil, directa y concisa, en español (salvo que se pida otro idioma). Devuelve solo la respuesta, sin preámbulos.",
             palabraVoz: "modo asistente, modo asistentes"),
        Modo(id: "buscar", nombre: "Buscar", icono: "magnifyingglass", base: "buscar",
             palabraVoz: "modo buscar, modo busca, modo búsqueda, modo buscador", buscador: "google"),
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
        for (i, m) in list.enumerated() {
            guard let b = base.first(where: { $0.id == m.id }) else { continue }
            // UNIÓN de frases de voz: suma las del base que falten (así los alias
            // nuevos llegan a configs viejos) sin borrar las que el usuario agregó.
            var frases = frasesVoz(m)
            for f in frasesVoz(b) where !frases.contains(where: { normalizar($0) == normalizar(f) }) {
                frases.append(f); cambio = true
            }
            let unido = frases.joined(separator: ", ")
            if unido != m.palabraVoz { list[i].palabraVoz = unido; cambio = true }
            if m.almacen.isEmpty, !b.almacen.isEmpty { list[i].almacen = b.almacen; cambio = true }
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
    /// Cada modo puede tener VARIAS frases (separadas por coma) como failover ante
    /// mal-escuchas del STT ("mudo tarea", "molde tarea" = "modo tarea"). Gana la
    /// frase más LARGA que haga prefijo (entre TODAS las frases de TODOS los modos).
    static func frasesVoz(_ m: Modo) -> [String] {
        m.palabraVoz.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static func detectarPorVoz(_ texto: String) -> (Modo, String)? {
        let t = normalizar(texto)
        var mejor: (Modo, Int)? = nil
        for m in todos() {
            for fr in frasesVoz(m) {
                let frase = normalizar(fr)
                guard !frase.isEmpty, t.hasPrefix(frase) else { continue }
                if mejor == nil || frase.count > mejor!.1 { mejor = (m, frase.count) }
            }
        }
        guard let (modo, len) = mejor else { return nil }
        // Recorta la frase del texto original (trimmeado; folding conserva el
        // largo, así que dropFirst(len) quita justo la frase disparadora).
        let orig = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        var sinFrase = String(orig.dropFirst(min(len, orig.count)))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;\n").union(.whitespaces))
        // ARGUMENTO tras la frase mágica: parametriza el modo SOLO por este dictado.
        //   "modo traducir quichua <texto>" → traduce al quichua (no al default).
        //   "modo buscar google <consulta>" → busca en Google.
        // Si el 1er token no es idioma/buscador conocido, todo es el texto/consulta.
        var m = modo
        if m.base == "traducir" {
            if let (idioma, resto) = tomarArg(sinFrase, fillers: ["a", "al"], reconocer: Idiomas.reconocer) {
                m.idiomaDestino = idioma; sinFrase = resto
            }
        } else if m.base == "buscar" {
            if let (eng, resto) = tomarArg(sinFrase, fillers: ["en"], reconocer: Buscadores.reconocer) {
                m.buscador = eng; sinFrase = resto
            }
        }
        return (m, sinFrase)
    }

    /// Separa un filler opcional + el 1er token; si `reconocer` lo acepta, devuelve
    /// (valor canónico, resto). nil si no matchea (el texto queda intacto).
    private static func tomarArg(_ texto: String, fillers: [String],
                                 reconocer: (String) -> String?) -> (String, String)? {
        var tokens = texto.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        if tokens.count > 1, fillers.contains(normalizar(tokens[0])) { tokens.removeFirst() }  // "al", "en"
        guard let primero = tokens.first, let canon = reconocer(primero) else { return nil }
        let resto = tokens.dropFirst().joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;\n"))
        return (canon, resto)
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
        ("kichwa", "🇪🇨"), ("quichua", "🇪🇨"), ("shuar", "🇪🇨"),
    ]
    private static func norm(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Si `token` nombra un idioma conocido (base o propio), devuelve su nombre
    /// canónico; si no, nil (para el argumento por voz de "modo traducir <idioma>").
    static func reconocer(_ token: String) -> String? {
        let n = norm(token)
        return todos().first { norm($0.nombre) == n }?.nombre
    }
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

// MARK: - Buscadores para el modo "Buscar"

enum Buscadores {
    /// id, nombre visible, plantilla URL con {q} (nil = Spotlight local ⌘Espacio).
    static let base: [(id: String, nombre: String, url: String?)] = [
        ("google", "Google", "https://www.google.com/search?q={q}"),
        ("bing", "Bing", "https://www.bing.com/search?q={q}"),
        ("duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q={q}"),
        ("youtube", "YouTube", "https://www.youtube.com/results?search_query={q}"),
        ("maps", "Google Maps", "https://www.google.com/maps/search/{q}"),
        ("spotlight", "Spotlight (⌘Espacio en la Mac)", nil),
        ("personalizado", "Personalizado (URL con {q})", nil),
    ]
    static func nombre(_ id: String) -> String { base.first { $0.id == id }?.nombre ?? id }
    static func plantilla(_ id: String) -> String? { base.first { $0.id == id }?.url }
    /// Si `token` nombra un buscador (id o 1ª palabra del nombre), devuelve su id;
    /// si no, nil (para "modo buscar <buscador> <consulta>"). Alias comunes incluidos.
    static func reconocer(_ token: String) -> String? {
        let n = token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = ["ddg": "duckduckgo", "duck": "duckduckgo", "yt": "youtube",
                     "mapas": "maps", "spot": "spotlight"]
        if let a = alias[n] { return a }
        return base.first { $0.id == n || $0.nombre.lowercased().hasPrefix(n) && !n.isEmpty }?.id
    }
    /// URL final para la consulta. nil = Spotlight (no es URL). `custom` = plantilla
    /// del modo cuando id=="personalizado" (debe tener {q}; si no, cae a Google).
    static func url(_ id: String, query: String, custom: String = "") -> String? {
        guard id != "spotlight" else { return nil }
        let tpl = id == "personalizado"
            ? (custom.contains("{q}") ? custom : "https://www.google.com/search?q={q}")
            : (plantilla(id) ?? "https://www.google.com/search?q={q}")
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let enc = query.addingPercentEncoding(withAllowedCharacters: cs) ?? query
        return tpl.replacingOccurrences(of: "{q}", with: enc)
    }
}

// MARK: - Acciones para el modo "Acción" (abrir app / correo / web con el texto)

enum Acciones {
    /// id, nombre, esquema URL con {q} ("" = solo abrir la app, sin texto en URL;
    /// "{q}" = URL propia del usuario en `prompt`), bundle id de la app.
    static let base: [(id: String, nombre: String, esquema: String, bundle: String)] = [
        ("correo",        "Correo / Mail (nuevo correo)",    "mailto:?body={q}", "com.apple.mail"),
        ("outlook",       "Outlook: nuevo correo",           "ms-outlook://compose?body={q}", "com.microsoft.Outlook"),
        ("whatsapp",      "WhatsApp (con el texto)",         "whatsapp://send?text={q}", "net.whatsapp.WhatsApp"),
        ("mensajes",      "Mensajes (copia el texto)",       "", "com.apple.MobileSMS"),
        ("notas",         "Notas de Mac (copia el texto)",   "", "com.apple.Notes"),
        ("recordatorios", "Recordatorios (copia el texto)",  "", "com.apple.reminders"),
        ("calendario",    "Calendario",                      "", "com.apple.iCal"),
        ("finder",        "Finder",                          "", "com.apple.finder"),
        ("safari",        "Safari",                          "", "com.apple.Safari"),
        ("musica",        "Música",                          "", "com.apple.Music"),
        ("terminal",      "Terminal (copia el texto)",       "", "com.apple.Terminal"),
        ("mapas",         "Mapas",                           "", "com.apple.Maps"),
        ("fotos",         "Fotos",                           "", "com.apple.Photos"),
        ("contactos",     "Contactos",                       "", "com.apple.AddressBook"),
        ("textedit",      "TextEdit (copia el texto)",       "", "com.apple.TextEdit"),
        ("vistaprevia",   "Vista Previa",                    "", "com.apple.Preview"),
        ("ajustes",       "Ajustes del Sistema",             "", "com.apple.systempreferences"),
        ("appstore",      "App Store",                       "", "com.apple.AppStore"),
        ("facetime",      "FaceTime",                        "", "com.apple.FaceTime"),
        ("spotlight",     "Spotlight (⌘Espacio, pega el texto)", "", ""),
        ("url",           "Abrir web (tu URL con {q})",      "{q}", ""),
    ]
    static func nombre(_ id: String) -> String { base.first { $0.id == id }?.nombre ?? id }
    static func bundle(_ id: String) -> String { base.first { $0.id == id }?.bundle ?? "" }
    static func valido(_ id: String) -> Bool { base.contains { $0.id == id } }
    /// WhatsApp con FAILOVER: app de escritorio (whatsapp://) si está instalada,
    /// si no la web wa.me. El llamador decide `app` (¿hay app de escritorio?).
    static func whatsapp(texto: String, app: Bool) -> String {
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let enc = texto.addingPercentEncoding(withAllowedCharacters: cs) ?? texto
        return app ? "whatsapp://send?text=\(enc)" : "https://wa.me/?text=\(enc)"
    }
    /// URL/esquema final con el texto (nil = acción de SOLO abrir app, sin URL).
    /// `custom` = plantilla del usuario cuando id=="url" (debe tener {q}).
    static func url(_ id: String, texto: String, custom: String = "") -> String? {
        guard let e = base.first(where: { $0.id == id }), !e.esquema.isEmpty else { return nil }
        let tpl = id == "url"
            ? (custom.contains("{q}") ? custom : "https://www.google.com/search?q={q}")
            : e.esquema
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let enc = texto.addingPercentEncoding(withAllowedCharacters: cs) ?? texto
        return tpl.replacingOccurrences(of: "{q}", with: enc)
    }
}

// MARK: - Modos ENCADENADOS por voz (pipeline: transforms + acción final) — Fase 6
//
// "modo traducir quichua a correo outlook <texto>" → traduce a quichua, luego abre
// Outlook con ese texto. Orden-independiente ("modo correo y traducir quichua …"):
// los transforms se aplican en orden y la ACCIÓN final abre app/URL con el resultado.
// Solo se activa con 2+ etapas; 1 etapa la maneja detectarPorVoz normal (sin regresión).

extension ModosStore {
    private static let conectores: Set<String> = [
        "a", "al", "y", "e", "en", "para", "con", "de", "la", "el", "lo", "los", "las",
        "modo"   // el usuario repite "modo" por etapa ("modo traducir modo buscar")
    ]
    /// Normaliza un token para MATCHEAR verbos: sin acentos/mayúsculas y SIN la
    /// puntuación pegada ("traducir," "Google." → "traducir" "google").
    private static func limpioTok(_ s: String) -> String {
        normalizar(s).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?¡¿\"'«»()-—"))
    }
    // verbo (1 palabra tras "modo") → id de modo TRANSFORM
    private static let verbosTransform: [String: String] = [
        "traducir": "traducir", "traduce": "traducir", "traduccion": "traducir",
        "oficio": "oficio", "tarea": "tarea", "nota": "nota",
        "asistente": "asistente", "responde": "asistente", "resume": "asistente", "resumir": "asistente",
    ]
    // verbo → preset de ACCIÓN ("buscar" es especial: lleva buscador)
    private static let verbosAccion: [String: String] = [
        "correo": "correo", "email": "correo", "enviar": "correo", "mail": "correo", "mailto": "correo",
        "outlook": "outlook",
        "whatsapp": "whatsapp", "wasap": "whatsapp", "guasap": "whatsapp", "wasa": "whatsapp",
        "notas": "notas", "finder": "finder", "recordatorios": "recordatorios",
        "calendario": "calendario", "mensajes": "mensajes",
        "buscar": "buscar", "busca": "buscar", "google": "buscar", "bing": "buscar",
        "duckduckgo": "buscar", "youtube": "buscar", "maps": "buscar", "mapas": "buscar",
    ]

    /// Parsea una CADENA de voz. nil si no empieza con "modo" o si hay <2 etapas.
    static func detectarCadena(_ texto: String) -> (transforms: [Modo], accion: Modo?, contenido: String)? {
        var tokens = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard let f = tokens.first, normalizar(f) == "modo" else { return nil }
        tokens.removeFirst()
        var transforms: [Modo] = []
        var accion: Modo? = nil
        var i = 0
        while i < tokens.count {
            let w = limpioTok(tokens[i])
            if w.isEmpty || conectores.contains(w) { i += 1; continue }
            if let tid = verbosTransform[w] {
                var m = modo(tid); i += 1
                if m.base == "traducir", i < tokens.count, let idi = Idiomas.reconocer(limpioTok(tokens[i])) {
                    m.idiomaDestino = idi; i += 1
                }
                transforms.append(m); continue
            }
            if let acc = verbosAccion[w] {
                i += 1
                if acc == "buscar" {
                    var b = modo("buscar")
                    if let eng = Buscadores.reconocer(w) { b.buscador = eng }
                    else if i < tokens.count, let eng = Buscadores.reconocer(limpioTok(tokens[i])) { b.buscador = eng; i += 1 }
                    accion = b
                } else {
                    accion = Modo(id: "cadena-\(acc)", nombre: Acciones.nombre(acc),
                                  icono: "bolt.fill", base: "accion", accion: acc)
                }
                continue
            }
            break   // token desconocido → aquí empieza el contenido
        }
        guard transforms.count + (accion != nil ? 1 : 0) >= 2 else { return nil }
        let contenido = tokens[i...].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;\n"))
        return (transforms, accion, contenido)
    }
}

import AppKit
import Foundation

// MARK: - Modo Música con cascada
//
// No promete controlar catálogos privados. Primero intenta la app elegida; si no
// existe o el enlace falla, salta al siguiente proveedor y termina en web. Apple
// Music puede reproducir un resultado de la biblioteca local mediante su interfaz
// de automatización; para el catálogo abre la búsqueda para que el usuario elija.

struct ProveedorMusica: Identifiable, Hashable {
    let id: String
    let nombre: String
    let bundle: String
    let plantilla: String
    let esWeb: Bool
}

struct ResultadoMusica {
    let ok: Bool
    let proveedor: String
    let mensaje: String
    let estado: EstadoMusica
}

enum EstadoMusica: String {
    case reproduciendo, busqueda, abierto, fallo
}

enum IntencionMusica: String {
    case reproducir, buscar
}

enum Musica {
    static let base: [ProveedorMusica] = [
        ProveedorMusica(id: "apple_music", nombre: "Apple Music", bundle: "com.apple.Music",
                        plantilla: "music://music.apple.com/search?term={q}", esWeb: false),
        ProveedorMusica(id: "spotify", nombre: "Spotify", bundle: "com.spotify.client",
                        plantilla: "spotify:search:{q}", esWeb: false),
        ProveedorMusica(id: "youtube_music", nombre: "YouTube Music", bundle: "",
                        plantilla: "https://music.youtube.com/search?q={q}", esWeb: true),
        ProveedorMusica(id: "youtube", nombre: "YouTube", bundle: "",
                        plantilla: "https://www.youtube.com/results?search_query={q}", esWeb: true),
        ProveedorMusica(id: "soundcloud", nombre: "SoundCloud", bundle: "",
                        plantilla: "https://soundcloud.com/search?q={q}", esWeb: true),
        ProveedorMusica(id: "bandcamp", nombre: "Bandcamp", bundle: "",
                        plantilla: "https://bandcamp.com/search?q={q}", esWeb: true),
    ]

    static func personales() -> [ProveedorMusica] {
        Config.musicaProveedoresPersonales().compactMap { d in
            guard let nombre = d["nombre"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = d["url"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !nombre.isEmpty, plantillaSegura(url) else { return nil }
            let firma = PerfilAgente.normalizar(nombre).replacingOccurrences(of: " ", with: "-")
            return ProveedorMusica(id: "personal:\(firma)", nombre: nombre, bundle: "",
                                   plantilla: url, esWeb: true)
        }
    }

    /// Los proveedores propios nunca reciben credenciales, pero aun así evitamos
    /// esquemas ejecutables. HTTP solo se acepta en loopback para un servicio local.
    static func plantillaSegura(_ plantilla: String) -> Bool {
        guard plantilla.contains("{q}"),
              let u = URL(string: plantilla.replacingOccurrences(of: "{q}", with: "prueba")),
              let esquema = u.scheme?.lowercased(), let host = u.host?.lowercased() else { return false }
        if esquema == "https" { return true }
        return esquema == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    static func catalogo() -> [ProveedorMusica] { base + personales() }
    static func proveedor(_ id: String) -> ProveedorMusica? { catalogo().first { $0.id == id } }
    static func nombre(_ id: String) -> String {
        proveedor(id)?.nombre ?? (["", "auto"].contains(id) ? "Automático" : id)
    }

    static func disponible(_ p: ProveedorMusica) -> Bool {
        p.esWeb || p.bundle.isEmpty
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundle) != nil
    }

    static func reconocerProveedor(en texto: String) -> String? {
        let s = PerfilAgente.normalizar(texto)
        let alias: [(String, String)] = [
            ("youtube music", "youtube_music"), ("apple music", "apple_music"),
            ("musica de apple", "apple_music"), ("apple", "apple_music"),
            ("spotify", "spotify"),
            ("youtube", "youtube"), ("soundcloud", "soundcloud"), ("bandcamp", "bandcamp")
        ]
        if let a = alias.first(where: { s.contains($0.0) }) { return a.1 }
        return personales().first { s.contains(PerfilAgente.normalizar($0.nombre)) }?.id
    }

    static func quitarNombreProveedor(_ texto: String, id: String) -> String {
        guard id != "auto", let p = proveedor(id) else { return texto }
        var s = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let nombres = [p.nombre, id.replacingOccurrences(of: "_", with: " ")]
        for nombre in nombres {
            let e = NSRegularExpression.escapedPattern(for: nombre)
            guard let re = try? NSRegularExpression(pattern: "^(?:en\\s+)?\(e)[,;:]?\\s*",
                                                    options: [.caseInsensitive]) else { continue }
            let ns = s as NSString
            if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
                s = ns.substring(from: NSMaxRange(m.range)); break
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Diferencia una orden de reproducción de una búsqueda deliberada. Solo
    /// mira la cabecera: una palabra como “buscar” dentro del título no cambia
    /// accidentalmente la acción. Si el planificador ya consumió el verbo, la
    /// operación musical normal sigue siendo reproducir.
    static func intencion(_ texto: String) -> IntencionMusica {
        let patronesBusqueda = [
            #"^(?:por\s+favor[,;:]?\s*)?(?:modo\s+)?m[uú]sica[,;:]?\s*(?:por\s+favor[,;:]?\s*)?(?:b[uú]sca(?:me|r|lo|la)?|encuentra(?:me|r)?|mu[eé]stra(?:me|r)?)(?:\b|\s)"#,
            #"^(?:por\s+favor[,;:]?\s*)?(?:b[uú]sca(?:me|r|lo|la)?|encuentra(?:me|r)?|mu[eé]stra(?:me|r)?)\s+(?:en\s+)?(?:apple\s+music|youtube\s+music|spotify|youtube|soundcloud|bandcamp|m[uú]sica|canci[oó]n(?:es)?)\b"#,
            #"^(?:por\s+favor[,;:]?\s*)?(?:b[uú]sca(?:me|r|lo|la)?|encuentra(?:me|r)?|mu[eé]stra(?:me|r)?)(?:\b|\s)"#,
        ]
        for patron in patronesBusqueda {
            guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { continue }
            let ns = texto as NSString
            if re.firstMatch(in: texto, range: NSRange(location: 0, length: ns.length)) != nil {
                return .buscar
            }
        }
        return .reproducir
    }

    /// Convierte una orden hablada en una consulta limpia. Sirve tanto para el
    /// modo explícito ("modo música, pon Jessy Uribe") como para una petición
    /// natural ("reproduce en Spotify música de Jessy Uribe").
    static func extraerConsulta(_ texto: String, proveedor: String) -> String {
        var s = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let patrones = [
            #"^(?:por\s+favor[,;:]?\s*)?(?:modo\s+)?m[uú]sica[,;:]?\s*"#,
            #"^(?:por\s+favor[,;:]?\s*)?(?:pon(?:me)?|poner|reproduce|reproducir|toca(?:me)?|escucha(?:me)?|b[uú]sca(?:me|r|lo|la)?|encuentra(?:me|r)?|mu[eé]stra(?:me|r)?)\s*"#,
            #"^(?:en|por|con)\s+(?:apple\s+music|youtube\s+music|spotify|youtube|soundcloud|bandcamp)[,;:]?\s*"#,
            #"^(?:(?:una|la|alguna|cualquier|cualquiera)\s+)?(?:m[uú]sica|canci[oó]n(?:es)?|tema|playlist|radio|[aá]lbum)\s*(?:(?:cualquiera|cualquier)\s+)?(?:de\s+)?"#,
            #"^(?:algo|alguna|cualquiera|cualquier)\s+(?:de\s+)?"#,
        ]
        var cambio = true
        while cambio {
            cambio = false
            for patron in patrones {
                guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { continue }
                let ns = s as NSString
                guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
                      m.range.length > 0 else { continue }
                s = ns.substring(from: NSMaxRange(m.range))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-\n\t"))
                cambio = true
                break
            }
        }
        if s.lowercased().hasPrefix("de ") { s.removeFirst(3) }
        return quitarNombreProveedor(s, id: proveedor)
    }

    private static func codificar(_ texto: String) -> String {
        var permitidos = CharacterSet.urlQueryAllowed
        permitidos.remove(charactersIn: "+&=?#")
        return texto.addingPercentEncoding(withAllowedCharacters: permitidos) ?? texto
    }

    private static func url(_ p: ProveedorMusica, consulta: String) -> URL? {
        let q = codificar(consulta)
        return URL(string: p.plantilla.replacingOccurrences(of: "{q}", with: q))
    }

    private static func escaparAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Sin consulta reproduce una pista aleatoria de la biblioteca (valor por
    /// defecto) o reanuda, según el ajuste del usuario. Con consulta reproduce
    /// la primera coincidencia REAL de la biblioteca local. El catálogo remoto
    /// de Apple Music no expone una búsqueda+play arbitraria por AppleScript.
    private static func reproducirApple(_ consulta: String) -> Bool {
        guard Config.musicaIntentarReproducir() else { return false }
        let source: String
        if consulta.isEmpty {
            if Config.musicaSinConsulta() == "reanudar" {
                source = """
                tell application "Music"
                    activate
                    play
                    if player state is playing then return "OK"
                    return "NO"
                end tell
                """
            } else {
                source = """
                tell application "Music"
                    activate
                    set candidatas to every track of library playlist 1 whose enabled is true and duration > 60 and artist is not ""
                    if (count of candidatas) is 0 then set candidatas to every track of library playlist 1 whose enabled is true and duration > 60
                    if (count of candidatas) is 0 then set candidatas to every track of library playlist 1 whose enabled is true
                    set totalPistas to count of candidatas
                    if totalPistas is 0 then return "NO"
                    set indice to random number from 1 to totalPistas
                    play item indice of candidatas
                    delay 0.15
                    if player state is playing then return "OK"
                    return "NO"
                end tell
                """
            }
        } else {
            let q = escaparAppleScript(consulta)
            source = """
            tell application "Music"
                set encontrados to search library playlist 1 for "\(q)"
                if (count of encontrados) is 0 then return "NO"
                play item 1 of encontrados
                return "OK"
            end tell
            """
        }
        var error: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { return false }
        return r?.stringValue == "OK"
    }

    private static func reproducirSpotifySinConsulta() -> Bool {
        guard Config.musicaIntentarReproducir() else { return false }
        let accion = Config.musicaSinConsulta() == "reanudar"
            ? "play"
            : "set shuffling to true\n            next track\n            play"
        let source = """
            tell application id "com.spotify.client"
                activate
                \(accion)
                if player state is playing then return "OK"
                return "NO"
            end tell
            """
        var error: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && r?.stringValue == "OK"
    }

    private static func abrir(_ p: ProveedorMusica, consulta: String,
                              intencion: IntencionMusica) -> EstadoMusica? {
        if intencion == .reproducir, p.id == "apple_music", reproducirApple(consulta) {
            return .reproduciendo
        }
        if intencion == .reproducir, p.id == "spotify", consulta.isEmpty,
           reproducirSpotifySinConsulta() { return .reproduciendo }
        if p.id == "apple_music", !consulta.isEmpty,
           AppleMusicCatalogo.abrirBusqueda(consulta) { return .busqueda }
        if consulta.isEmpty, !p.bundle.isEmpty,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundle) {
            NSWorkspace.shared.openApplication(at: app, configuration: .init(), completionHandler: nil)
            return .abierto
        }
        guard let u = url(p, consulta: consulta) else { return nil }
        if NSWorkspace.shared.open(u) { return consulta.isEmpty ? .abierto : .busqueda }
        // Algunos macOS no aceptan el esquema music:// para una búsqueda. El
        // universal-link web conserva la consulta como failover del mismo motor.
        if p.id == "apple_music",
           let web = URL(string: "https://music.apple.com/search?term=\(codificar(consulta))") {
            return NSWorkspace.shared.open(web) ? .busqueda : nil
        }
        return nil
    }

    static func mensaje(estado: EstadoMusica, proveedor: ProveedorMusica,
                        consulta: String, intencion: IntencionMusica) -> String {
        switch estado {
        case .reproduciendo:
            return consulta.isEmpty
                ? (Config.musicaSinConsulta() == "reanudar"
                    ? "Listo, reanudé la música en \(proveedor.nombre)."
                    : "Listo, estoy poniendo una canción aleatoria en \(proveedor.nombre).")
                : "Listo, estoy reproduciendo «\(consulta)» en \(proveedor.nombre)."
        case .busqueda:
            if intencion == .buscar {
                return "Listo, te abrí la búsqueda de «\(consulta)» en \(proveedor.nombre)."
            }
            return "No pude reproducir «\(consulta)» automáticamente; te abrí la búsqueda en \(proveedor.nombre)."
        case .abierto:
            if intencion == .buscar { return "Abrí \(proveedor.nombre) para que busques música." }
            return "Abrí \(proveedor.nombre), pero no encontré una reproducción disponible."
        case .fallo:
            return "No pude abrir ningún servicio de música."
        }
    }

    static func orden(solicitado: String) -> [ProveedorMusica] {
        var ids: [String] = []
        if solicitado != "auto", !solicitado.isEmpty { ids.append(solicitado) }
        ids.append(contentsOf: Config.musicaCascada())
        ids.append(contentsOf: ["youtube_music", "youtube"])
        var vistos = Set<String>()
        return ids.compactMap { id in
            guard vistos.insert(id).inserted, let p = proveedor(id), disponible(p) else { return nil }
            return p
        }
    }

    static func ejecutar(_ consulta: String, solicitado: String = "auto",
                         intencion: IntencionMusica = .reproducir,
                         simular: Bool = false,
                         completion: @escaping (ResultadoMusica) -> Void) {
        let cascada: () -> Void = {
            // Reanudar el reproductor global sigue disponible, pero es una
            // preferencia explícita. El valor predeterminado recorre la cascada
            // y pide una pista aleatoria al primer motor que pueda demostrarlo.
            if intencion == .reproducir, Config.musicaSinConsulta() == "reanudar",
               !simular, consulta.isEmpty, ["", "auto"].contains(solicitado),
               Config.musicaIntentarReproducir(), MediaControl.reproducirActual() {
                let mensaje = "Listo, reanudé tu reproductor actual."
                AgenteLog.registrar("musica", ["proveedor": "sistema", "consulta": "",
                                                  "simular": false, "ok": true,
                                                  "intencion": intencion.rawValue,
                                                  "estado": EstadoMusica.reproduciendo.rawValue])
                completion(ResultadoMusica(ok: true, proveedor: "sistema",
                                           mensaje: mensaje, estado: .reproduciendo)); return
            }
            let candidatos = orden(solicitado: solicitado)
            guard !candidatos.isEmpty else {
                completion(ResultadoMusica(ok: false, proveedor: "",
                    mensaje: "No hay un servicio de música disponible.", estado: .fallo)); return
            }
            for p in candidatos {
                let estado: EstadoMusica? = simular
                    ? (intencion == .buscar ? (consulta.isEmpty ? .abierto : .busqueda) : .reproduciendo)
                    : abrir(p, consulta: consulta, intencion: intencion)
                if let estado {
                    let accion = mensaje(estado: estado, proveedor: p,
                                         consulta: consulta, intencion: intencion)
                    AgenteLog.registrar("musica", ["proveedor": p.id, "consulta": consulta,
                                                    "simular": simular, "ok": true,
                                                    "intencion": intencion.rawValue,
                                                    "estado": estado.rawValue])
                    completion(ResultadoMusica(ok: true, proveedor: p.id,
                                               mensaje: accion, estado: estado)); return
                }
            }
            AgenteLog.registrar("musica", ["consulta": consulta, "ok": false,
                                            "intencion": intencion.rawValue])
            completion(ResultadoMusica(ok: false, proveedor: "",
                                       mensaje: "No pude abrir ningún servicio de música.",
                                       estado: .fallo))
        }

        let trabajo = {
            let puedeUsarApple = ["", "auto", "apple_music"].contains(solicitado)
            let catalogoOCascada: () -> Void = {
                guard intencion == .reproducir, !simular, !consulta.isEmpty, puedeUsarApple else {
                    cascada(); return
                }
                // La biblioteca local es instantánea y no necesita red.
                if reproducirApple(consulta) {
                    let m = proveedor("apple_music").map {
                        mensaje(estado: .reproduciendo, proveedor: $0,
                                consulta: consulta, intencion: intencion)
                    } ?? "Listo, estoy reproduciendo «\(consulta)» en Apple Music."
                    AgenteLog.registrar("musica", ["proveedor": "apple_music_local",
                                                    "consulta": consulta, "ok": true,
                                                    "intencion": intencion.rawValue,
                                                    "estado": EstadoMusica.reproduciendo.rawValue])
                    completion(.init(ok: true, proveedor: "apple_music_local",
                                     mensaje: m, estado: .reproduciendo)); return
                }
                AppleMusicCatalogo.reproducirPrimera(consulta) { r in
                    if r.ok {
                        completion(.init(ok: true, proveedor: "apple_music_catalogo",
                                         mensaje: r.motivo, estado: .reproduciendo)); return
                    }
                    AgenteLog.registrar("musica_failover", ["de": "apple_music_catalogo",
                                                            "motivo": r.motivo])
                    cascada()
                }
            }
            // Apple no expone una API pública para inyectar órdenes en Siri. El
            // Atajo incluido usa acciones oficiales de Música, pero BetoDicta no
            // confía solo en que macOS acepte abrirlo: verifica título/artista y,
            // si no coinciden,
            // continúa por la cascada sin anunciar un éxito falso.
            // Una búsqueda explícita jamás dispara reproducción. El Atajo se
            // reserva para “pon/reproduce” con una consulta concreta.
            if intencion == .reproducir, !simular, !consulta.isEmpty,
               Config.musicaAtajoPrimero() {
                let atajo = Config.musicaAtajoApple()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !atajo.isEmpty {
                    AppleAtajos.ejecutarMusica(nombre: atajo, texto: consulta) { r in
                        if r.ok {
                            AgenteLog.registrar("musica", ["proveedor": "atajo_apple",
                                                            "atajo": atajo,
                                                            "consulta": consulta, "ok": true,
                                                            "intencion": intencion.rawValue,
                                                            "estado": EstadoMusica.reproduciendo.rawValue])
                            completion(ResultadoMusica(ok: true, proveedor: "atajo_apple",
                                                       mensaje: r.mensaje,
                                                       estado: .reproduciendo)); return
                        }
                        AgenteLog.registrar("musica_failover", ["de": "atajo_apple",
                                                                "motivo": r.mensaje])
                        catalogoOCascada()
                    }
                    return
                }
            }
            catalogoOCascada()
        }
        if Thread.isMainThread { trabajo() } else { DispatchQueue.main.async(execute: trabajo) }
    }
}

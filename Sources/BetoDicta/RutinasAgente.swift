import AppKit
import Foundation

struct PasoRutinaAgente: Codable, Identifiable, Equatable {
    var id: String
    var tipo: String       // musica|app|url|atajo|tarea|nota|recordatorio|calendario|archivo|captura|grabacion
    var valor: String      // admite {texto}

    init(tipo: String = "musica", valor: String = "{texto}") {
        id = UUID().uuidString; self.tipo = tipo; self.valor = valor
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        tipo = (try? c.decode(String.self, forKey: .tipo)) ?? "musica"
        valor = (try? c.decode(String.self, forKey: .valor)) ?? "{texto}"
    }
}

struct RutinaAgente: Codable, Identifiable, Equatable {
    var id: String
    var nombre: String
    var frases: [String]
    var activa: Bool
    var pasos: [PasoRutinaAgente]

    init(nombre: String = "Mi rutina") {
        id = UUID().uuidString; self.nombre = nombre
        frases = ["rutina \(nombre.lowercased())"]; activa = true; pasos = []
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nombre = (try? c.decode(String.self, forKey: .nombre)) ?? "Rutina"
        frases = (try? c.decode([String].self, forKey: .frases)) ?? []
        activa = (try? c.decode(Bool.self, forKey: .activa)) ?? true
        pasos = (try? c.decode([PasoRutinaAgente].self, forKey: .pasos)) ?? []
    }
}

struct DeteccionRutinaAgente {
    let rutina: RutinaAgente
    let contenido: String
}

enum RutinasAgenteStore {
    private static var url: URL { Config.dir.appendingPathComponent("agente_rutinas.json") }
    private static let lock = NSLock()

    private static func leerSinLock() -> [RutinaAgente] {
        guard let d = try? Data(contentsOf: url),
              let r = try? JSONDecoder().decode([RutinaAgente].self, from: d) else { return [] }
        return r
    }

    static func todas() -> [RutinaAgente] {
        lock.lock(); defer { lock.unlock() }; return leerSinLock()
    }

    static func guardar(_ rutinas: [RutinaAgente]) {
        lock.lock(); defer { lock.unlock() }
        Config.asegurarDirSeguro()
        if let d = try? JSONEncoder().encode(rutinas) {
            try? d.write(to: url, options: .atomic); Config.protegerSecreto(url)
        }
    }

    static func detectar(_ texto: String) -> DeteccionRutinaAgente? {
        detectar(texto, en: todas())
    }

    static func detectar(_ texto: String, en lista: [RutinaAgente]) -> DeteccionRutinaAgente? {
        let originales = texto.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let normal = originales.map(PerfilAgente.normalizar)
        let rutinas = lista.filter { $0.activa && !$0.pasos.isEmpty }
        var candidatos: [(RutinaAgente, Int)] = []
        for r in rutinas {
            var frases = r.frases
            frases.append("rutina \(r.nombre)")
            for f in frases {
                let ft = PerfilAgente.normalizar(f).split(separator: " ").map(String.init)
                guard !ft.isEmpty, ft.count <= normal.count,
                      Array(normal.prefix(ft.count)) == ft else { continue }
                candidatos.append((r, ft.count))
            }
        }
        guard let mejor = candidatos.max(by: { $0.1 < $1.1 }) else { return nil }
        let contenido = originales.dropFirst(mejor.1).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-"))
        return DeteccionRutinaAgente(rutina: mejor.0, contenido: contenido)
    }

    static func riesgo(id: String) -> RiesgoAgente {
        guard let r = todas().first(where: { $0.id == id }) else { return .externo }
        return riesgo(r)
    }

    static func riesgo(_ r: RutinaAgente) -> RiesgoAgente {
        var maximo: RiesgoAgente = .lectura
        for p in r.pasos {
            let x: RiesgoAgente
            switch p.tipo {
            case "musica", "app", "url", "archivo": x = .reversible
            case "tarea", "nota", "recordatorio", "calendario", "captura", "grabacion": x = .cambioLocal
            case "atajo": x = .externo
            default: x = .externo
            }
            if x > maximo { maximo = x }
        }
        return maximo
    }
}

enum RutinasAgenteRunner {
    private static func interpolar(_ plantilla: String, texto: String) -> String {
        let p = plantilla.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty || p == "{texto}" { return texto }
        return p.replacingOccurrences(of: "{texto}", with: texto)
    }

    private static func abrirApp(_ nombre: String, simular: Bool) -> ResultadoHerramientaApple {
        let toks = PerfilAgente.normalizar(nombre).split(separator: " ").map(String.init)
        guard case .encontrada(let m) = AplicacionesMac.resolverPrefijo(toks) else {
            return .init(ok: false, mensaje: "No encontré la aplicación «\(nombre)».")
        }
        if !simular {
            NSWorkspace.shared.openApplication(at: m.app.url, configuration: .init(), completionHandler: nil)
        }
        return .init(ok: true, mensaje: "Abrí \(m.app.nombre).")
    }

    private static func abrirURL(_ raw: String, texto: String, simular: Bool) -> ResultadoHerramientaApple {
        var c = CharacterSet.urlQueryAllowed; c.remove(charactersIn: "&=+#")
        let q = texto.addingPercentEncoding(withAllowedCharacters: c) ?? texto
        let s = raw.replacingOccurrences(of: "{texto}", with: q)
        guard let u = URL(string: s), let esquema = u.scheme?.lowercased(),
              let host = u.host?.lowercased(),
              esquema == "https" || (esquema == "http"
                && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            return .init(ok: false, mensaje: "La URL de la rutina no es válida.")
        }
        if !simular, !NSWorkspace.shared.open(u) {
            return .init(ok: false, mensaje: "No pude abrir \(u.host ?? "la URL").")
        }
        return .init(ok: true, mensaje: "Abrí \(u.host ?? "la URL").")
    }

    static func ejecutar(id: String, texto: String, simular: Bool = false,
                         completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard let rutina = RutinasAgenteStore.todas().first(where: { $0.id == id && $0.activa }) else {
            completion(.init(ok: false, mensaje: "La rutina ya no existe o está apagada.")); return
        }
        var mensajes: [String] = []
        var todoOK = true

        func siguiente(_ i: Int) {
            guard i < rutina.pasos.count else {
                let prefijo = todoOK ? "Rutina «\(rutina.nombre)» completada." : "Rutina «\(rutina.nombre)» terminó con avisos."
                AgenteLog.registrar("rutina", ["id": rutina.id, "nombre": rutina.nombre,
                                               "ok": todoOK, "pasos": rutina.pasos.count,
                                               "simular": simular])
                completion(.init(ok: todoOK, mensaje: prefijo + (mensajes.isEmpty ? "" : " " + mensajes.joined(separator: " ")))); return
            }
            let paso = rutina.pasos[i]
            let valor = interpolar(paso.valor, texto: texto)
            func listo(_ r: ResultadoHerramientaApple) {
                todoOK = todoOK && r.ok; mensajes.append(r.mensaje); siguiente(i + 1)
            }
            switch paso.tipo {
            case "musica":
                guard Config.agenteHerramientaMusica() else {
                    listo(.init(ok: false, mensaje: "La herramienta Música está apagada.")); break
                }
                Musica.ejecutar(valor, simular: simular) { listo(.init(ok: $0.ok, mensaje: $0.mensaje)) }
            case "app":
                listo(Config.agenteHerramientaAplicaciones()
                    ? abrirApp(valor, simular: simular)
                    : .init(ok: false, mensaje: "La herramienta Aplicaciones está apagada."))
            case "url": listo(abrirURL(paso.valor, texto: texto, simular: simular))
            case "atajo":
                guard Config.agenteHerramientaAtajos() else {
                    listo(.init(ok: false, mensaje: "La pasarela de Atajos está apagada.")); break
                }
                listo(simular ? .init(ok: true, mensaje: "Ejecutaría el atajo «\(paso.valor)».")
                               : AppleAtajos.ejecutar(nombre: paso.valor, texto: texto))
            case "tarea":
                if !simular { NotasStore.agregar(tipo: "tarea", texto: valor) }
                listo(.init(ok: true, mensaje: "Agregué una tarea local."))
            case "nota":
                if !simular { NotasStore.agregar(tipo: "nota", texto: valor) }
                listo(.init(ok: true, mensaje: "Agregué una nota local."))
            case "recordatorio":
                guard Config.agenteHerramientaRecordatorios() else {
                    listo(.init(ok: false, mensaje: "La herramienta Recordatorios está apagada.")); break
                }
                if simular { listo(.init(ok: true, mensaje: "Crearía un recordatorio.")) }
                else { AppleAgenda.crearRecordatorio(valor, completion: listo) }
            case "calendario":
                guard Config.agenteHerramientaCalendario() else {
                    listo(.init(ok: false, mensaje: "La herramienta Calendario está apagada.")); break
                }
                if simular { listo(.init(ok: true, mensaje: "Crearía un evento.")) }
                else { AppleAgenda.crearEvento(valor, completion: listo) }
            case "archivo":
                guard Config.agenteHerramientaArchivos() else {
                    listo(.init(ok: false, mensaje: "La herramienta Archivos está apagada.")); break
                }
                if simular { listo(.init(ok: true, mensaje: "Buscaría el archivo «\(valor)».")) }
                else {
                    ArchivosMac.buscar(valor) { urls in
                        if let u = urls.first { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                        listo(.init(ok: !urls.isEmpty, mensaje: urls.isEmpty
                            ? "No encontré el archivo «\(valor)»." : "Encontré \(urls.count) archivo(s)."))
                    }
                }
            case "captura", "grabacion":
                guard Config.agenteHerramientaCapturas() else {
                    listo(.init(ok: false, mensaje: "La herramienta Capturas está apagada.")); break
                }
                let pedido = paso.tipo == "grabacion" ? "graba la pantalla \(valor)" : "captura de pantalla \(valor)"
                CapturaMac.ejecutar(SolicitudCapturaMac.interpretar(pedido), simular: simular) {
                    listo(.init(ok: $0.ok, mensaje: $0.mensaje))
                }
            default: listo(.init(ok: false, mensaje: "El paso «\(paso.tipo)» no es compatible."))
            }
        }
        siguiente(0)
    }
}

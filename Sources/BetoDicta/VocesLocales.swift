import Foundation

// MARK: - Biblioteca de voces LOCALES clonadas (Fase 7)
//
// El usuario entrena voces con VozClonPOC (XTTS, 100% local) y aquí las
// REGISTRA para poder ELEGIRLAS ("quiero hablar con la voz que cloné"). Nada de
// esto viaja en el Git: la app viene VACÍA y cada quien sube/agrega las suyas
// (tu voz, la de tu mamá, quien sea). Parametrizable.
//
// Cada voz = un comando de shell donde {texto} y {salida} se sustituyen. Para
// las voces de VozClonPOC el comando es:
//   bash <base>/clonar.sh decir <proyecto> <ckpt> "{texto}" {salida}
// El botón "Detectar" arma ese comando solo escaneando los proyectos entrenados.

struct VozLocal: Codable, Identifiable, Equatable {
    var id: String
    var nombre: String        // lo que ve el usuario ("Mamá Rafaela", "Mi voz Bto")
    var cmd: String           // comando con {texto} y {salida}
    var persona: String = ""  // 2º parámetro: PROMPT de cómo habla esa persona. Cuando
                              // el Agente responde con esta voz, la IA redacta en ESE estilo.

    // Decode tolerante: JSON viejos sin `persona` siguen cargando.
    enum CodingKeys: String, CodingKey { case id, nombre, cmd, persona }
    init(id: String, nombre: String, cmd: String, persona: String = "") {
        self.id = id; self.nombre = nombre; self.cmd = cmd; self.persona = persona
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nombre = try c.decode(String.self, forKey: .nombre)
        cmd = try c.decode(String.self, forKey: .cmd)
        persona = (try? c.decode(String.self, forKey: .persona)) ?? ""
    }
}

enum VocesLocales {
    private static var url: URL { Config.dir.appendingPathComponent("voces_locales.json") }

    static func todas() -> [VozLocal] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([VozLocal].self, from: data) else { return [] }
        return list
    }

    static func guardar(_ list: [VozLocal]) {
        Config.asegurarDirSeguro()
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
    }

    @discardableResult
    static func agregar(nombre: String, cmd: String, persona: String = "") -> VozLocal {
        var list = todas()
        // id estable a partir del nombre (evita duplicar la misma voz).
        let base = nombre.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        var id = base.isEmpty ? "voz" : base
        var n = 2
        while list.contains(where: { $0.id == id }) { id = "\(base)-\(n)"; n += 1 }
        let v = VozLocal(id: id, nombre: nombre, cmd: cmd, persona: persona)
        list.append(v); guardar(list)
        // Si es la primera, queda activa.
        if Config.ttsVozLocal().isEmpty { Config.set("tts_voz_local", to: id) }
        return v
    }

    static func borrar(_ id: String) {
        guardar(todas().filter { $0.id != id })
        if Config.ttsVozLocal() == id { Config.set("tts_voz_local", to: todas().first?.id ?? "") }
    }

    /// La voz seleccionada (o la primera, o nil si no hay ninguna).
    static func activa() -> VozLocal? {
        let sel = Config.ttsVozLocal()
        return todas().first { $0.id == sel } ?? todas().first
    }

    static func fijarActiva(_ id: String) { Config.set("tts_voz_local", to: id) }

    /// Escanea los proyectos entrenados de VozClonPOC y arma un comando listo por
    /// cada uno (proyecto + su mejor checkpoint slim). Para el botón "Detectar".
    /// Devuelve [(nombreSugerido, cmd)]. No agrega nada: el usuario confirma.
    static func detectarDeVozClon() -> [(nombre: String, cmd: String)] {
        let base = (Config.vozClonBase() as NSString).expandingTildeInPath
        let fm = FileManager.default
        var out: [(String, String)] = []

        // (a) Scripts de voz LISTOS en la base (voz_*.sh, como voz_mama_rapid.sh):
        //     ya envuelven un clon entrenado. Comando: bash <base>/<script> "{texto}" {salida} 1.0
        if let archivos = try? fm.contentsOfDirectory(atPath: base) {
            for f in archivos.sorted() where f.hasPrefix("voz_") && f.hasSuffix(".sh") {
                let nombre = f.dropFirst(4).dropLast(3)          // sin "voz_" ni ".sh"
                    .replacingOccurrences(of: "_", with: " ").capitalized
                let cmd = "bash \(base)/\(f) \"{texto}\" {salida} 1.0"
                out.append((nombre, cmd))
            }
        }

        // (b) Proyectos ENTRENADOS en proyectos/ (usa su mejor checkpoint slim).
        let proyDir = base + "/proyectos"
        guard let proyectos = try? fm.contentsOfDirectory(atPath: proyDir) else { return out }
        for p in proyectos.sorted() where !p.hasPrefix("_") && !p.hasPrefix(".") {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: proyDir + "/" + p, isDirectory: &isDir), isDir.boolValue else { continue }
            // Buscar el checkpoint slim (o cualquier .pth) del proyecto. Ruta
            // ABSOLUTA: gen.py resuelve el ckpt relativo a la base, no al proyecto.
            let slimDir = proyDir + "/" + p + "/slim"
            let ckpt: String?
            if let slims = try? fm.contentsOfDirectory(atPath: slimDir),
               let mejor = slims.filter({ $0.hasSuffix(".pth") }).sorted().last {
                ckpt = slimDir + "/" + mejor
            } else if let runs = try? fm.contentsOfDirectory(atPath: proyDir + "/" + p + "/run"),
                      let mejor = runs.filter({ $0.hasSuffix(".pth") }).sorted().last {
                ckpt = proyDir + "/" + p + "/run/" + mejor
            } else { ckpt = nil }
            guard let ck = ckpt else { continue }
            // nombre visible: sin el sufijo _fecha si lo tiene.
            let nombre = p.replacingOccurrences(of: #"_\d{8}-\d{4}$"#, with: "", options: .regularExpression)
            let cmd = "bash \(base)/clonar.sh decir \(p) \(ck) \"{texto}\" {salida}"
            out.append((nombre.capitalized, cmd))
        }
        return out
    }
}

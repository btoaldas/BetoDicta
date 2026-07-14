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
    var cmd: String           // comando con {texto} y {salida} (modo bootstrap/externo)
    var persona: String = ""  // 2º parámetro: PROMPT de cómo habla esa persona. Cuando
                              // el Agente responde con esta voz, la IA redacta en ESE estilo.
    var paquete: String = ""  // ruta a un PAQUETE portable (carpeta con voz_gen.py). Si
                              // está, se corre con el MOTOR interno (VozEngine), no con cmd.
    var streaming: Bool = true // POR VOZ (no global): suena por trozos mientras genera
                               // (XTTS inference_stream). Si off → genera completo y suena.

    // Decode tolerante: JSON viejos sin campos nuevos siguen cargando.
    enum CodingKeys: String, CodingKey { case id, nombre, cmd, persona, paquete, streaming }
    init(id: String, nombre: String, cmd: String, persona: String = "", paquete: String = "", streaming: Bool = true) {
        self.id = id; self.nombre = nombre; self.cmd = cmd; self.persona = persona
        self.paquete = paquete; self.streaming = streaming
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nombre = try c.decode(String.self, forKey: .nombre)
        cmd = try c.decode(String.self, forKey: .cmd)
        persona = (try? c.decode(String.self, forKey: .persona)) ?? ""
        paquete = (try? c.decode(String.self, forKey: .paquete)) ?? ""
        streaming = (try? c.decode(Bool.self, forKey: .streaming)) ?? true
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
    static func agregar(nombre: String, cmd: String, persona: String = "", paquete: String = "") -> VozLocal {
        var list = todas()
        // id estable a partir del nombre (evita duplicar la misma voz).
        let base = nombre.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        var id = base.isEmpty ? "voz" : base
        var n = 2
        while list.contains(where: { $0.id == id }) { id = "\(base)-\(n)"; n += 1 }
        let v = VozLocal(id: id, nombre: nombre, cmd: cmd, persona: persona, paquete: paquete)
        list.append(v); guardar(list)
        // Si es la primera, queda activa.
        if Config.ttsVozLocal().isEmpty { Config.set("tts_voz_local", to: id) }
        return v
    }

    static func borrar(_ id: String) {
        // Si la voz tenía un paquete GESTIONADO (bajo voces/<id>), bórralo también.
        if let v = todas().first(where: { $0.id == id }), !v.paquete.isEmpty,
           v.paquete.hasPrefix(vocesDir.path) {
            try? FileManager.default.removeItem(atPath: v.paquete)
        }
        guardar(todas().filter { $0.id != id })
        if Config.ttsVozLocal() == id { Config.set("tts_voz_local", to: todas().first?.id ?? "") }
    }

    /// La voz seleccionada (o la primera, o nil si no hay ninguna).
    static func activa() -> VozLocal? {
        let sel = Config.ttsVozLocal()
        return todas().first { $0.id == sel } ?? todas().first
    }

    static func fijarActiva(_ id: String) { Config.set("tts_voz_local", to: id) }

    /// Streaming ON/OFF por VOZ (no global). Con paquete + motor: suena mientras genera.
    static func fijarStreaming(_ id: String, _ on: Bool) {
        var list = todas()
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].streaming = on; guardar(list) }
    }

    /// Carpeta donde BetoDicta guarda los paquetes de voz importados (gestionados).
    static var vocesDir: URL { Config.dir.appendingPathComponent("voces") }

    /// Resultado del import inteligente.
    enum ResultadoImport {
        case ok(VozLocal)                 // listo para hablar
        case faltaModelo                  // no hay checkpoint .pth → no es un clon
        case faltaMuestras(VozLocal)      // registrado, pero sin refs → pide muestras de voz
    }

    /// Runner genérico que BetoDicta escribe en CADA paquete: lee el manifest para
    /// hallar modelo/config/vocab/refs. Así controla el runner (no el subido) y funciona
    /// aunque el paquete venga de fuera.
    private static let runnerBatch = """
    import os, sys, json, warnings
    warnings.filterwarnings("ignore")
    os.environ["COQUI_TOS_AGREED"]="1"; os.environ.setdefault("CUDA_VISIBLE_DEVICES","")
    import torch, torchaudio
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import Xtts
    PKG=os.path.dirname(os.path.abspath(__file__)); TXT=sys.argv[1]; OUT=sys.argv[2] if len(sys.argv)>2 else "voz.wav"
    man=json.load(open(os.path.join(PKG,"betodicta-voz.json"))).get("archivos",{})
    def rel(k,d): return os.path.join(PKG, man.get(k,d))
    config=XttsConfig(); config.load_json(rel("config","config.json"))
    model=Xtts.init_from_config(config)
    model.load_checkpoint(config, checkpoint_path=rel("modelo","model.pth"), vocab_path=rel("vocab","vocab.json"), use_deepspeed=False)
    model.cpu(); model.train(False)
    refs=[os.path.join(PKG,l.strip()) for l in open(rel("ref_list","ref_list.txt")) if l.strip()]
    g,s=model.get_conditioning_latents(audio_path=refs)
    o=model.inference(TXT,"es",g,s,temperature=0.55,enable_text_splitting=True)
    torchaudio.save(OUT, torch.tensor(o["wav"]).unsqueeze(0), 24000)
    print("OK", OUT)
    """

    /// SUBIR un paquete de voz — TOLERANTE: si viene incompleto (de fuera), BetoDicta
    /// arma lo que falta (voz_gen.py, vocab/config del base, manifest) y solo pide lo
    /// que NO puede generar: el modelo (.pth) y, si no hay, las muestras de voz (refs).
    static func importarPaquete(desde origen: URL) -> ResultadoImport {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: origen, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        // 1) Modelo: el .pth (prefiere 'slim'; si no, el más pesado). Sin él no es un clon.
        let pths = items.filter { $0.pathExtension.lowercased() == "pth" }
        guard let modelo = pths.first(where: { $0.lastPathComponent.lowercased().contains("slim") })
            ?? pths.max(by: { (tam($0)) < (tam($1)) }) else { return .faltaModelo }
        // 2) Nombre + persona (si vienen).
        var nombre = origen.lastPathComponent, persona = ""
        if let mData = try? Data(contentsOf: origen.appendingPathComponent("betodicta-voz.json")),
           let j = try? JSONSerialization.jsonObject(with: mData) as? [String: Any] {
            if let n = j["nombre"] as? String, !n.isEmpty { nombre = n }
        }
        if let t = try? String(contentsOf: origen.appendingPathComponent("persona.txt"), encoding: .utf8) {
            persona = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 3) Registrar + carpeta gestionada.
        let v = agregar(nombre: nombre, cmd: "", persona: persona, paquete: "")
        try? fm.createDirectory(at: vocesDir, withIntermediateDirectories: true)
        let dst = vocesDir.appendingPathComponent(v.id)
        try? fm.removeItem(at: dst)
        try? fm.createDirectory(at: dst.appendingPathComponent("refs"), withIntermediateDirectories: true)
        // 4) Copiar modelo.
        try? fm.copyItem(at: modelo, to: dst.appendingPathComponent(modelo.lastPathComponent))
        // 5) config/vocab: del paquete si vienen, si no del BASE de Coqui (comunes a todo XTTS).
        func poner(_ nombreArch: String, base: URL?) {
            let enOrigen = origen.appendingPathComponent(nombreArch)
            if fm.fileExists(atPath: enOrigen.path) { try? fm.copyItem(at: enOrigen, to: dst.appendingPathComponent(nombreArch)) }
            else if let base { try? fm.copyItem(at: base, to: dst.appendingPathComponent(nombreArch)) }
        }
        poner("config.json", base: VozEngine.baseConfig())
        poner("vocab.json", base: VozEngine.baseVocab())
        // 6) Refs: cualquier wav del paquete (raíz o refs/). Si no hay → pedir muestras.
        var refWavs = items.filter { $0.pathExtension.lowercased() == "wav" }
        if let sub = try? fm.contentsOfDirectory(at: origen.appendingPathComponent("refs"), includingPropertiesForKeys: nil) {
            refWavs += sub.filter { $0.pathExtension.lowercased() == "wav" }
        }
        var refLines: [String] = []
        for w in refWavs.prefix(8) {
            let d = dst.appendingPathComponent("refs/" + w.lastPathComponent)
            try? fm.copyItem(at: w, to: d); refLines.append("refs/" + w.lastPathComponent)
        }
        try? refLines.joined(separator: "\n").write(to: dst.appendingPathComponent("ref_list.txt"), atomically: true, encoding: .utf8)
        // 7) Runner genérico + manifest (BetoDicta los controla).
        try? runnerBatch.write(to: dst.appendingPathComponent("voz_gen.py"), atomically: true, encoding: .utf8)
        if !persona.isEmpty { try? persona.write(to: dst.appendingPathComponent("persona.txt"), atomically: true, encoding: .utf8) }
        let manifest: [String: Any] = ["formato": "betodicta-voz-clonada/1", "nombre": nombre, "idioma": "es",
            "motor": "xtts", "persona_archivo": "persona.txt",
            "archivos": ["modelo": modelo.lastPathComponent, "config": "config.json", "vocab": "vocab.json",
                         "ref_list": "ref_list.txt", "refs_dir": "refs"]]
        if let mj = try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted) {
            try? mj.write(to: dst.appendingPathComponent("betodicta-voz.json"))
        }
        // 8) Fijar ruta + estado.
        var list = todas()
        if let i = list.firstIndex(where: { $0.id == v.id }) { list[i].paquete = dst.path; guardar(list) }
        let voz = todas().first { $0.id == v.id } ?? v
        return refLines.isEmpty ? .faltaMuestras(voz) : .ok(voz)
    }

    private static func tam(_ u: URL) -> Int { (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }

    /// Auto-genera la PERSONA de una voz (si está vacía) transcribiendo sus refs con
    /// Whisper. Para clones de fuera sin persona. Actualiza la voz + persona.txt.
    @discardableResult
    static func autogenerarPersona(_ id: String, stamp: String) -> Bool {
        guard let v = todas().first(where: { $0.id == id }), v.persona.isEmpty, !v.paquete.isEmpty else { return false }
        let refs = URL(fileURLWithPath: v.paquete).appendingPathComponent("refs")
        guard FileManager.default.fileExists(atPath: refs.path) else { return false }
        let persona = Entrenador.personaDesdeAudios(carpetaAudios: refs, nombre: v.nombre, stamp: stamp)
        guard !persona.isEmpty else { return false }
        var list = todas()
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].persona = persona; guardar(list) }
        try? persona.write(to: URL(fileURLWithPath: v.paquete).appendingPathComponent("persona.txt"), atomically: true, encoding: .utf8)
        return true
    }

    /// Agrega muestras de voz (wavs) a una voz que quedó sin refs. Reconstruye ref_list.
    static func agregarMuestras(_ id: String, wavs: [URL]) {
        guard let v = todas().first(where: { $0.id == id }), !v.paquete.isEmpty else { return }
        let dst = URL(fileURLWithPath: v.paquete)
        let fm = FileManager.default
        try? fm.createDirectory(at: dst.appendingPathComponent("refs"), withIntermediateDirectories: true)
        var lineas = (try? String(contentsOf: dst.appendingPathComponent("ref_list.txt"), encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        for w in wavs where w.pathExtension.lowercased() == "wav" {
            let d = dst.appendingPathComponent("refs/" + w.lastPathComponent)
            try? fm.copyItem(at: w, to: d)
            let rel = "refs/" + w.lastPathComponent
            if !lineas.contains(rel) { lineas.append(rel) }
        }
        try? lineas.joined(separator: "\n").write(to: dst.appendingPathComponent("ref_list.txt"), atomically: true, encoding: .utf8)
    }

    /// DESCARGAR/exportar el paquete de una voz a una carpeta destino (para llevarlo).
    @discardableResult
    static func exportarPaquete(_ voz: VozLocal, a carpetaDestino: URL) -> URL? {
        guard !voz.paquete.isEmpty else { return nil }
        let origen = URL(fileURLWithPath: voz.paquete)
        let fm = FileManager.default
        guard fm.fileExists(atPath: origen.path) else { return nil }
        let nombreCarpeta = "Voz-" + voz.id
        let destino = carpetaDestino.appendingPathComponent(nombreCarpeta)
        try? fm.removeItem(at: destino)
        do { try fm.copyItem(at: origen, to: destino); return destino }
        catch { return nil }
    }

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

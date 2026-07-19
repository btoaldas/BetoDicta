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
    var onnx: String = ""      // ruta a una voz PIPER (.onnx). Si está, se usa el motor
                               // PIPER (voz FIJA, ~5x tiempo real, casi instantánea) en vez
                               // de XTTS. Es el carril RÁPIDO. XTTS se queda para lo demás.
    var mlxRef: String = ""    // muestra + transcripción para Qwen3-TTS/MLX (equilibrada)
    var mlxRefText: String = ""
    var mlxModelo: String = MlxVozEngine.modeloDefault
    var variante: String = "xtts" // "xtts" (calidad), "mlx" (equilibrada), "onnx" (rápida)
    var tieneMlx: Bool {
        !mlxRef.isEmpty && !mlxRefText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && FileManager.default.fileExists(atPath: mlxRef)
    }

    // Decode tolerante: JSON viejos sin campos nuevos siguen cargando.
    enum CodingKeys: String, CodingKey {
        case id, nombre, cmd, persona, paquete, streaming, onnx, mlxRef, mlxRefText, mlxModelo, variante
    }
    init(id: String, nombre: String, cmd: String, persona: String = "", paquete: String = "", streaming: Bool = true,
         onnx: String = "", mlxRef: String = "", mlxRefText: String = "",
         mlxModelo: String = MlxVozEngine.modeloDefault, variante: String = "") {
        self.id = id; self.nombre = nombre; self.cmd = cmd; self.persona = persona
        self.paquete = paquete; self.streaming = streaming; self.onnx = onnx
        self.mlxRef = mlxRef; self.mlxRefText = mlxRefText
        self.mlxModelo = MlxVozEngine.modeloSeguro(mlxModelo)
        let pedida = variante.isEmpty ? (paquete.isEmpty && !onnx.isEmpty ? "onnx" : "xtts") : variante
        self.variante = ["xtts", "mlx", "onnx"].contains(pedida) ? pedida : "xtts"
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nombre = try c.decode(String.self, forKey: .nombre)
        cmd = try c.decode(String.self, forKey: .cmd)
        persona = (try? c.decode(String.self, forKey: .persona)) ?? ""
        paquete = (try? c.decode(String.self, forKey: .paquete)) ?? ""
        streaming = (try? c.decode(Bool.self, forKey: .streaming)) ?? true
        onnx = (try? c.decode(String.self, forKey: .onnx)) ?? ""
        mlxRef = (try? c.decode(String.self, forKey: .mlxRef)) ?? ""
        mlxRefText = (try? c.decode(String.self, forKey: .mlxRefText)) ?? ""
        mlxModelo = MlxVozEngine.modeloSeguro(
            (try? c.decode(String.self, forKey: .mlxModelo)) ?? MlxVozEngine.modeloDefault)
        let guardada = (try? c.decode(String.self, forKey: .variante)) ?? ""
        variante = ["xtts", "mlx", "onnx"].contains(guardada)
            ? guardada : (paquete.isEmpty && !onnx.isEmpty ? "onnx" : "xtts")
    }
}

enum VocesLocales {
    private static var url: URL { Config.dir.appendingPathComponent("voces_locales.json") }

    static func todas() -> [VozLocal] {
        guard let data = try? Data(contentsOf: url),
              var list = try? JSONDecoder().decode([VozLocal].self, from: data) else { return [] }
        // Autorreparación ante downgrade: una versión vieja puede reescribir el JSON sin
        // conocer mlxRef/mlxModelo. El manifiesto de la propia voz es la segunda copia.
        var reparada = false
        for i in list.indices {
            guard let cfg = leerMlx(list[i].id) else { continue }
            let ref = vocesDir.appendingPathComponent(list[i].id)
                .appendingPathComponent("equilibrada/referencia.wav")
            guard FileManager.default.fileExists(atPath: ref.path) else { continue }
            if list[i].mlxRef != ref.path || list[i].mlxRefText != cfg.texto
                || list[i].mlxModelo != cfg.modelo {
                list[i].mlxRef = ref.path; list[i].mlxRefText = cfg.texto
                list[i].mlxModelo = cfg.modelo; reparada = true
            }
            if cfg.activa, list[i].variante != "mlx" {
                list[i].variante = "mlx"; reparada = true
            }
        }
        if reparada { guardar(list) }
        return list
    }

    static func guardar(_ list: [VozLocal]) {
        Config.asegurarDirSeguro()
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url, options: .atomic)
            // Incluye persona y transcripción de una muestra privada: no debe quedar 0644.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
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
        // Borra la carpeta gestionada de esta voz (paquete XTTS o .onnx Piper), si existe.
        let carpeta = vocesDir.appendingPathComponent(id)
        if FileManager.default.fileExists(atPath: carpeta.path) {
            try? FileManager.default.removeItem(at: carpeta)
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

    /// Una persona conserva Calidad (XTTS), Equilibrada (Qwen3/MLX) y Rápida
    /// (Piper/ONNX). La elección es por voz, no global, y nunca borra otra variante.
    static func fijarVariante(_ id: String, _ variante: String) {
        var list = todas()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let pedida = ["xtts", "mlx", "onnx"].contains(variante) ? variante : "xtts"
        guard (pedida == "onnx" && !list[i].onnx.isEmpty)
                || (pedida == "mlx" && list[i].tieneMlx)
                || (pedida == "xtts" && !list[i].paquete.isEmpty) else { return }
        list[i].variante = pedida
        if list[i].tieneMlx { guardarMlx(list[i]) }
        guardar(list)
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
        if let i = list.firstIndex(where: { $0.id == v.id }) {
            list[i].paquete = dst.path; list[i].variante = "xtts"; guardar(list)
        }
        // Un paquete portable puede traer también la variante rápida vinculada.
        let rapida = origen.appendingPathComponent("rapida/voz.onnx")
        if fm.fileExists(atPath: rapida.path) { _ = vincularPiper(desde: rapida, a: v.id, activar: false) }
        // Y la variante equilibrada: solo viajan la referencia + su texto/modelo. Las
        // pesas comunes de Qwen se descargan una vez en cada Mac, no se duplican por voz.
        let eqDir = origen.appendingPathComponent("equilibrada")
        let eqRef = eqDir.appendingPathComponent("referencia.wav")
        let eqCfg = eqDir.appendingPathComponent("config.json")
        if fm.fileExists(atPath: eqRef.path), let data = try? Data(contentsOf: eqCfg),
           let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let texto = cfg["texto"] as? String, !texto.isEmpty {
            let modelo = MlxVozEngine.modeloSeguro(
                (cfg["modelo"] as? String) ?? MlxVozEngine.modeloDefault)
            _ = vincularMlx(referencia: eqRef, transcripcion: texto, modelo: modelo,
                            a: v.id, activar: false)
        }
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

    /// SUBIR una voz PIPER (.onnx) — carril rápido. Copia el .onnx (+ su .json) a
    /// voces/<id>/ y la registra. Devuelve la voz o nil.
    @discardableResult
    static func importarPiper(desde onnx: URL, nombre: String? = nil) -> VozLocal? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: onnx.path) else { return nil }
        let nom = nombre ?? onnx.deletingPathExtension().lastPathComponent
        let v = agregar(nombre: nom, cmd: "", persona: "", paquete: "")
        try? fm.createDirectory(at: vocesDir, withIntermediateDirectories: true)
        let dst = vocesDir.appendingPathComponent(v.id); try? fm.removeItem(at: dst)
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let onnxDst = dst.appendingPathComponent("voz.onnx")
        do { try fm.copyItem(at: onnx, to: onnxDst) } catch { borrar(v.id); return nil }
        // el .json de config (mismo nombre + .json) es necesario para Piper.
        let json = URL(fileURLWithPath: onnx.path + ".json")
        if fm.fileExists(atPath: json.path) { try? fm.copyItem(at: json, to: URL(fileURLWithPath: onnxDst.path + ".json")) }
        var list = todas()
        if let i = list.firstIndex(where: { $0.id == v.id }) {
            list[i].onnx = onnxDst.path; list[i].variante = "onnx"; guardar(list)
        }
        return todas().first { $0.id == v.id }
    }

    /// Vincula un Piper/ONNX a una voz XTTS YA existente. Es la salida de la destilación:
    /// una sola persona, dos carriles intercambiables, sin duplicarla en la biblioteca.
    @discardableResult
    static func vincularPiper(desde onnx: URL, a id: String, activar: Bool = true) -> VozLocal? {
        let fm = FileManager.default
        var list = todas()
        guard let i = list.firstIndex(where: { $0.id == id }), fm.fileExists(atPath: onnx.path) else { return nil }
        let json = URL(fileURLWithPath: onnx.path + ".json")
        guard fm.fileExists(atPath: json.path) else { return nil }
        let dstDir = vocesDir.appendingPathComponent(id).appendingPathComponent("rapida")
        try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        let dst = dstDir.appendingPathComponent("voz.onnx")
        let dstJSON = URL(fileURLWithPath: dst.path + ".json")
        do {
            try? fm.removeItem(at: dst); try? fm.removeItem(at: dstJSON)
            try fm.copyItem(at: onnx, to: dst)
            try fm.copyItem(at: json, to: dstJSON)
        } catch { return nil }
        list[i].onnx = dst.path
        if activar { list[i].variante = "onnx" }
        guardar(list)
        return list[i]
    }

    /// Vincula la variante local equilibrada (Qwen3-TTS/MLX) a una persona existente.
    /// Solo copia una muestra WAV y su transcripción; el modelo base es común y descargable.
    @discardableResult
    static func vincularMlx(referencia: URL, transcripcion: String,
                            modelo: String = MlxVozEngine.modeloDefault,
                            a id: String, activar: Bool = true) -> VozLocal? {
        let fm = FileManager.default
        let texto = transcripcion.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = todas()
        guard let i = list.firstIndex(where: { $0.id == id }), !texto.isEmpty,
              referencia.pathExtension.lowercased() == "wav",
              fm.fileExists(atPath: referencia.path),
              (try? referencia.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        let dstDir = vocesDir.appendingPathComponent(id).appendingPathComponent("equilibrada")
        try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dstDir.path)
        let dst = dstDir.appendingPathComponent("referencia.wav")
        do {
            if referencia.standardizedFileURL != dst.standardizedFileURL {
                try? fm.removeItem(at: dst); try fm.copyItem(at: referencia, to: dst)
            }
        } catch { return nil }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dst.path)
        list[i].mlxRef = dst.path
        list[i].mlxRefText = texto
        list[i].mlxModelo = MlxVozEngine.modeloSeguro(modelo)
        if activar { list[i].variante = "mlx" }
        guardarMlx(list[i])
        guardar(list)
        return list[i]
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
        do {
            try fm.copyItem(at: origen, to: destino)
            // El portable conserva todas las variantes de ESA persona. Qwen/MLX solo
            // requiere muestra+texto; el modelo común (~2,6 GB) no se duplica en el paquete.
            if !voz.onnx.isEmpty, fm.fileExists(atPath: voz.onnx) {
                let rapida = destino.appendingPathComponent("rapida")
                try? fm.removeItem(at: rapida)
                try fm.createDirectory(at: rapida, withIntermediateDirectories: true)
                let src = URL(fileURLWithPath: voz.onnx)
                try fm.copyItem(at: src, to: rapida.appendingPathComponent("voz.onnx"))
                let js = URL(fileURLWithPath: voz.onnx + ".json")
                if fm.fileExists(atPath: js.path) {
                    try fm.copyItem(at: js, to: rapida.appendingPathComponent("voz.onnx.json"))
                }
            }
            if voz.tieneMlx {
                let eq = destino.appendingPathComponent("equilibrada")
                try? fm.removeItem(at: eq)
                try fm.createDirectory(at: eq, withIntermediateDirectories: true)
                try fm.copyItem(at: URL(fileURLWithPath: voz.mlxRef),
                                to: eq.appendingPathComponent("referencia.wav"))
                let cfg: [String: Any] = ["formato": "betodicta-qwen-mlx/1",
                                          "modelo": MlxVozEngine.modeloSeguro(voz.mlxModelo),
                                          "texto": voz.mlxRefText,
                                          "activa": voz.variante == "mlx"]
                let data = try JSONSerialization.data(withJSONObject: cfg, options: .prettyPrinted)
                try data.write(to: eq.appendingPathComponent("config.json"), options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600],
                                     ofItemAtPath: eq.appendingPathComponent("config.json").path)
            }
            return destino
        }
        catch { return nil }
    }

    private struct MlxGuardada {
        let modelo: String
        let texto: String
        let activa: Bool
    }

    private static func mlxConfigURL(_ id: String) -> URL {
        vocesDir.appendingPathComponent(id).appendingPathComponent("equilibrada/config.json")
    }

    private static func guardarMlx(_ voz: VozLocal) {
        guard voz.tieneMlx else { return }
        let u = mlxConfigURL(voz.id)
        let d = u.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: d.path)
        let cfg: [String: Any] = ["formato": "betodicta-qwen-mlx/1",
                                  "modelo": MlxVozEngine.modeloSeguro(voz.mlxModelo),
                                  "texto": voz.mlxRefText,
                                  "activa": voz.variante == "mlx"]
        guard let data = try? JSONSerialization.data(withJSONObject: cfg, options: .prettyPrinted) else { return }
        try? data.write(to: u, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
    }

    private static func leerMlx(_ id: String) -> MlxGuardada? {
        guard let data = try? Data(contentsOf: mlxConfigURL(id)),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let texto = cfg["texto"] as? String,
              !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return MlxGuardada(modelo: MlxVozEngine.modeloSeguro(
            (cfg["modelo"] as? String) ?? MlxVozEngine.modeloDefault),
                          texto: texto,
                          activa: (cfg["activa"] as? Bool) ?? false)
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

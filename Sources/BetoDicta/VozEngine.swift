import Foundation

// MARK: - Motor de voz interno y AISLADO (corre paquetes de voz clonada, 100% local)
//
// BetoDicta trae su PROPIO runtime de clonación de voz bajo ~/.betodicta/voz-engine/,
// sin tocar el Python del sistema ni Homebrew. Así cualquier usuario puede subir un
// paquete de voz portable y usarlo, sin tener que instalar nada a mano.
//
//   • Intérprete propio: `uv` crea un Python standalone (python-build-standalone) en
//     voz-engine/venv, y ahí instala torch + torchaudio + coqui-tts (versiones
//     PROBADAS que funcionan con XTTS). Todo bajo el home del usuario → sin permisos
//     de macOS, sin admin. Borrable de un tirón (desinstalar()).
//   • Correr un paquete: python <paquete>/voz_gen.py "texto" salida.wav → BetoDicta
//     reproduce el wav (sin ffmpeg: coqui ya entrega wav).
//
// La descarga (~3-4 GB: torch/coqui) se hace UNA vez, con permiso explícito del
// usuario y progreso. Si no está instalado, la voz local degrada suave (failover).

enum VozEngine {
    static var dir: URL { Config.dir.appendingPathComponent("voz-engine") }
    static var pythonURL: URL { dir.appendingPathComponent("venv/bin/python") }
    private static var marcador: URL { dir.appendingPathComponent(".listo") }

    // Versiones PROBADAS (mismas que el venv que funciona). No subir a ciegas:
    // transformers 5.x rompe coqui-tts (isin_mps_friendly); setuptools 81+ quita pkg_resources.
    private static let pins = ["torch==2.5.1", "torchaudio==2.5.1",
                               "coqui-tts==0.27.5", "transformers==4.57.6", "setuptools<81"]

    // Deps EXTRA para ENTRENAR (además de las de inferencia): Whisper (transcribir),
    // Resemblyzer (elegir el mejor checkpoint por d-vector), librosa/soundfile (audio),
    // matplotlib (gráficas). Todo cacheable → instalación rápida tras la 1ª vez.
    private static let pinsEntreno = ["mlx-whisper", "resemblyzer", "librosa", "soundfile", "matplotlib"]

    /// Carpeta del pipeline internalizado (scripts de clonación + xtts_base).
    static var pipelineDir: URL { dir.appendingPathComponent("pipeline") }
    static var entrenoListo: Bool {
        FileManager.default.fileExists(atPath: pipelineDir.appendingPathComponent("clonar/train.py").path)
            && FileManager.default.fileExists(atPath: pipelineDir.appendingPathComponent("xtts_base/dvae.pth").path)
    }

    enum Estado { case noInstalado, instalando, listo }
    private(set) static var instalando = false

    static func estado() -> Estado {
        if instalando { return .instalando }
        return (FileManager.default.fileExists(atPath: pythonURL.path)
                && FileManager.default.fileExists(atPath: marcador.path)) ? .listo : .noInstalado
    }

    // MARK: Instalación (bootstrap del runtime)

    /// Instala el motor: localiza/baja `uv`, crea el venv con Python propio e instala
    /// las dependencias. `onProgreso` recibe líneas legibles; `completion(ok, msg)`.
    /// Idempotente: si ya está, responde listo al toque.
    static func instalar(onProgreso: @escaping (String) -> Void,
                         completion: @escaping (Bool, String) -> Void) {
        if estado() == .listo { completion(true, "El motor ya está instalado."); return }
        guard !instalando else { completion(false, "Ya se está instalando."); return }
        instalando = true
        Config.asegurarDirSeguro()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                onProgreso("Preparando el instalador de Python (uv)…")
                let uv = try localizarObajarUv(onProgreso)
                onProgreso("Creando un Python propio y aislado…")
                try correr(uv, ["venv", "--python", "3.11", dir.appendingPathComponent("venv").path],
                           onProgreso)
                onProgreso("Descargando la IA de voz (torch + coqui, ~3-4 GB). Esto tarda…")
                try correr(uv, ["pip", "install", "--python", pythonURL.path] + pins, onProgreso)
                FileManager.default.createFile(atPath: marcador.path, contents: Data())
                instalando = false
                DispatchQueue.main.async { completion(true, "Motor de voz instalado.") }
            } catch {
                instalando = false
                DispatchQueue.main.async { completion(false, "Falló la instalación: \(error.localizedDescription)") }
            }
        }
    }

    /// Localiza `uv` (motor propio → ~/.local/bin → Homebrew → PATH). Si no hay, lo
    /// BAJA (binario estático, ~15 MB) a voz-engine/bin/uv. Nada de instalar global.
    private static func localizarObajarUv(_ onProgreso: @escaping (String) -> Void) throws -> String {
        let candidatos = [dir.appendingPathComponent("bin/uv").path,
                          (NSHomeDirectory() + "/.local/bin/uv"),
                          "/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
        for c in candidatos where FileManager.default.isExecutableFile(atPath: c) { return c }
        // Descargar el binario estático de uv para arm64-apple-darwin.
        onProgreso("Descargando uv (instalador de Python)…")
        let bin = dir.appendingPathComponent("bin"); try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let url = "https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-apple-darwin.tar.gz"
        let tgz = dir.appendingPathComponent("uv.tar.gz")
        try correr("/usr/bin/curl", ["-LsSf", url, "-o", tgz.path], onProgreso)
        try correr("/usr/bin/tar", ["xzf", tgz.path, "-C", bin.path, "--strip-components=1"], onProgreso)
        try? FileManager.default.removeItem(at: tgz)
        let uv = bin.appendingPathComponent("uv").path
        // Quitar quarantine (Gatekeeper) y permiso de ejecución.
        try? correr("/usr/bin/xattr", ["-d", "com.apple.quarantine", uv]) { _ in }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uv)
        guard FileManager.default.isExecutableFile(atPath: uv) else { throw Err.uv }
        return uv
    }

    // MARK: Correr un paquete de voz

    /// Corre `<carpeta>/voz_gen.py "texto" salida.wav` con el Python del motor.
    /// Devuelve la URL del wav (o nil si falla → el llamador hace failover).
    static func correrPaquete(carpeta: URL, texto: String, completion: @escaping (URL?) -> Void) {
        guard estado() == .listo else { completion(nil); return }
        let gen = carpeta.appendingPathComponent("voz_gen.py")
        guard FileManager.default.fileExists(atPath: gen.path) else {
            Log.log(.ia, "VozEngine: el paquete no tiene voz_gen.py"); completion(nil); return
        }
        let salida = FileManager.default.temporaryDirectory
            .appendingPathComponent("betodicta-engine-\(abs(texto.hashValue)).wav")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try correr(pythonURL.path, [gen.path, texto, salida.path]) { _ in }
                if FileManager.default.fileExists(atPath: salida.path) {
                    DispatchQueue.main.async { completion(salida) }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                Log.log(.ia, "VozEngine: falló correr el paquete (\(error.localizedDescription))")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: Entrenamiento (instala deps extra + pipeline internalizado)

    /// Prepara el motor para ENTRENAR: instala las deps extra y deja el pipeline
    /// (scripts + xtts_base) bajo voz-engine/pipeline/. Requiere el motor base listo.
    /// Nota: hoy el pipeline y xtts_base se copian de la carpeta VozClonPOC del usuario
    /// (bootstrap de Alberto); en el producto se EMPAQUETAN en la app o se descargan.
    static func instalarEntrenamiento(onProgreso: @escaping (String) -> Void,
                                      completion: @escaping (Bool, String) -> Void) {
        guard estado() == .listo else { completion(false, "Primero instala el motor de voz."); return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                onProgreso("Instalando herramientas de entrenamiento (Whisper, Resemblyzer, gráficas)…")
                let uv = try localizarObajarUv(onProgreso)
                try correr(uv, ["pip", "install", "--python", pythonURL.path] + pinsEntreno, onProgreso)
                onProgreso("Copiando el pipeline de clonación…")
                try prepararPipeline()
                guard entrenoListo else { throw Err.proceso(0, "faltan scripts/xtts_base del pipeline") }
                DispatchQueue.main.async { completion(true, "Entrenamiento listo.") }
            } catch {
                DispatchQueue.main.async { completion(false, "Falló: \(error.localizedDescription)") }
            }
        }
    }

    /// Deja los scripts del pipeline + xtts_base bajo voz-engine/pipeline/.
    private static func prepararPipeline() throws {
        let fm = FileManager.default
        try? fm.createDirectory(at: pipelineDir.appendingPathComponent("clonar"), withIntermediateDirectories: true)
        // Fuente bootstrap: la carpeta VozClonPOC del usuario (parametrizable).
        let base = (Config.vozClonBase() as NSString).expandingTildeInPath
        let srcClonar = base + "/clonar"
        let srcXtts = base + "/xtts_base"
        if let scripts = try? fm.contentsOfDirectory(atPath: srcClonar) {
            for f in scripts where f.hasSuffix(".py") {
                let dst = pipelineDir.appendingPathComponent("clonar/" + f)
                try? fm.removeItem(at: dst)
                try? fm.copyItem(atPath: srcClonar + "/" + f, toPath: dst.path)
            }
        }
        let xttsDst = pipelineDir.appendingPathComponent("xtts_base")
        if !fm.fileExists(atPath: xttsDst.path), fm.fileExists(atPath: srcXtts) {
            try? fm.copyItem(atPath: srcXtts, toPath: xttsDst.path)
        }
    }

    // MARK: Streaming (XTTS inference_stream → PCM float32 por stdout)

    static var streamRunnerURL: URL { dir.appendingPathComponent("stream_runner.py") }

    /// Runner genérico de streaming: lee el manifest del paquete (betodicta-voz.json)
    /// para hallar modelo/config/vocab/refs y emite PCM float32 (24000Hz mono) por
    /// stdout conforme genera. Se escribe una vez; sirve para CUALQUIER paquete.
    private static let runnerPy = """
    import os, sys, json, warnings
    warnings.filterwarnings("ignore")
    os.environ["COQUI_TOS_AGREED"] = "1"; os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
    import torch
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import Xtts
    PKG = sys.argv[1]; TXT = sys.argv[2]
    man = {}
    p = os.path.join(PKG, "betodicta-voz.json")
    if os.path.exists(p):
        man = json.load(open(p)).get("archivos", {})
    def rel(k, d): return os.path.join(PKG, man.get(k, d))
    config = XttsConfig(); config.load_json(rel("config", "config.json"))
    model = Xtts.init_from_config(config)
    model.load_checkpoint(config, checkpoint_path=rel("modelo", "xtts_mama_3000_slim.pth"),
                          vocab_path=rel("vocab", "vocab.json"), use_deepspeed=False)
    model.cpu(); model.train(False)
    refs = [os.path.join(PKG, l.strip()) for l in open(rel("ref_list", "ref_list.txt")) if l.strip()]
    gpt_lat, spk = model.get_conditioning_latents(audio_path=refs)
    out = sys.stdout.buffer
    for chunk in model.inference_stream(TXT, "es", gpt_lat, spk, temperature=0.55, enable_text_splitting=True):
        out.write(chunk.cpu().numpy().astype("<f4").tobytes()); out.flush()
    """

    static func asegurarStreamRunner() {
        try? runnerPy.data(using: .utf8)?.write(to: streamRunnerURL)
    }

    static var serverPyURL: URL { dir.appendingPathComponent("xtts_server.py") }

    /// Servidor XTTS residente: carga el modelo UNA vez + precalcula los latentes del
    /// locutor, y sirve por HTTP local streaming PCM float32. Mata la latencia (no
    /// recarga el modelo por respuesta). Lo levanta BetoDicta cuando el clon local es
    /// el motor activo (preactivar).
    private static let serverPy = """
    import os, sys, json, warnings
    warnings.filterwarnings("ignore")
    os.environ["COQUI_TOS_AGREED"]="1"; os.environ.setdefault("CUDA_VISIBLE_DEVICES","")
    import torch
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import Xtts
    PKG=sys.argv[1]; PORT=int(sys.argv[2])
    man={}
    p=os.path.join(PKG,"betodicta-voz.json")
    if os.path.exists(p): man=json.load(open(p)).get("archivos",{})
    def rel(k,d): return os.path.join(PKG, man.get(k,d))
    config=XttsConfig(); config.load_json(rel("config","config.json"))
    model=Xtts.init_from_config(config)
    model.load_checkpoint(config, checkpoint_path=rel("modelo","model.pth"), vocab_path=rel("vocab","vocab.json"), use_deepspeed=False)
    model.cpu(); model.train(False)
    refs=[os.path.join(PKG,l.strip()) for l in open(rel("ref_list","ref_list.txt")) if l.strip()]
    GPT,SPK=model.get_conditioning_latents(audio_path=refs)   # una sola vez
    class H(BaseHTTPRequestHandler):
        def log_message(self,*a): pass
        def do_GET(self):
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
        def do_POST(self):
            n=int(self.headers.get("Content-Length",0)); txt=self.rfile.read(n).decode("utf-8")
            self.send_response(200); self.send_header("Content-Type","application/octet-stream"); self.end_headers()
            try:
                for ch in model.inference_stream(txt,"es",GPT,SPK,temperature=0.55,enable_text_splitting=True):
                    self.wfile.write(ch.cpu().numpy().astype("<f4").tobytes()); self.wfile.flush()
            except Exception: pass
    print("READY", flush=True); sys.stdout.flush()
    HTTPServer(("127.0.0.1",PORT), H).serve_forever()
    """

    static func asegurarServerPy() { try? serverPy.data(using: .utf8)?.write(to: serverPyURL) }

    /// Cache del modelo BASE de Coqui XTTS v2 (vocab.json/config.json comunes a TODO
    /// clon XTTS). Sirve para rellenar paquetes traídos de fuera que llegan incompletos.
    static var coquiCache: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/tts/tts_models--multilingual--multi-dataset--xtts_v2")
    }
    static func baseVocab() -> URL? { existe(coquiCache.appendingPathComponent("vocab.json")) }
    static func baseConfig() -> URL? { existe(coquiCache.appendingPathComponent("config.json")) }
    private static func existe(_ u: URL) -> URL? { FileManager.default.fileExists(atPath: u.path) ? u : nil }

    static func desinstalar() { try? FileManager.default.removeItem(at: dir) }

    // MARK: Utilidades

    enum Err: Error, LocalizedError {
        case proceso(Int32, String), uv
        var errorDescription: String? {
            switch self {
            case .proceso(let c, let m): return "salió \(c): \(m)"
            case .uv: return "no pude preparar uv"
            }
        }
    }

    /// Corre un proceso y transmite su salida línea a línea. Lanza si sale != 0.
    @discardableResult
    private static func correr(_ exe: String, _ args: [String],
                              _ onLinea: @escaping (String) -> Void) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        // uv y el Python propio viven en el home; PATH mínimo, sin depender del sistema.
        var env = ProcessInfo.processInfo.environment
        env["COQUI_TOS_AGREED"] = "1"
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        var salida = ""
        let h = pipe.fileHandleForReading
        h.readabilityHandler = { fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            salida += s
            for l in s.split(separator: "\n") where !l.trimmingCharacters(in: .whitespaces).isEmpty {
                onLinea(String(l))
            }
        }
        try p.run(); p.waitUntilExit()
        h.readabilityHandler = nil
        if p.terminationStatus != 0 {
            throw Err.proceso(p.terminationStatus, String(salida.suffix(300)))
        }
        return salida
    }
}

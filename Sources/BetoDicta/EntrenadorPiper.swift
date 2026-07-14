import Foundation
import AVFoundation

// MARK: - Entrenador PIPER (voz fija .onnx, RÁPIDA) — fine-tune en CPU, background, resumible
//
// El carril veloz: el usuario suelta una carpeta de audios de UNA persona; BetoDicta
// arma el dataset (Whisper transcribe + resample a 22050Hz), hace FINE-TUNE de Piper
// (VITS) sobre un checkpoint base en español, y al final EXPORTA un .onnx que corre
// rapidísimo (~5x tiempo real, sin torch). XTTS se queda para clonar al vuelo con más
// calidad; Piper es la voz fija veloz.
//
// EL FONDO (verificado por ejecución, esta máquina):
//   • El error ".view size not compatible" del backward era un BUG SOLO-MPS de PyTorch
//     (pytorch#142344). Se arregla FORZANDO CPU en el Trainer (--trainer.accelerator cpu).
//     Con eso torch 2.5.1 entrena sin tocar nada (la voz XTTS de mamá queda intacta).
//   • Fine-tune desde la base con contador en 0: train_wrap.py + PIPER_FINETUNE_RESET=1.
//   • Export ONNX funciona en Apple Silicon; el config del entreno = <modelo>.onnx.json.
//   • Resumible: si se apaga la compu, se reanuda desde el último checkpoint del proyecto.
//
// Todo corre en el motor AISLADO (~/.betodicta/voz-engine). Nada pesado en el Git: la
// base y las deps se descargan bajo demanda con permiso.

enum EntrenadorPiper {
    static var raizDir: URL { VozEngine.dir.appendingPathComponent("piper-train") }
    static var proyectosDir: URL { raizDir.appendingPathComponent("proyectos") }
    static var wrapURL: URL { raizDir.appendingPathComponent("train_wrap.py") }
    static var dsScriptURL: URL { raizDir.appendingPathComponent("piper_ds.py") }
    static var setupURL: URL { raizDir.appendingPathComponent("piper_setup.py") }
    private static var proc: Process?
    private static var sitePackages: URL {
        VozEngine.dir.appendingPathComponent("venv/lib/python3.11/site-packages")
    }

    // MARK: Calidad (parametrizable) — high / medium / low
    //
    // La "calidad" de Piper NO es un preset: es un set de params de arquitectura + sample
    // rate (verificado en piper1-gpl vits/config.py). El fine-tune necesita una BASE de ESA
    // calidad. Para ESPAÑOL solo existe base `medium` (davefx/sharvard); high y low solo
    // existen en INGLÉS (lessac) → se usan como base y el entreno los ADAPTA al español
    // (piper soporta fine-tune cross-idioma; TRAINING.md). Params/URLs/tamaños CONFIRMADOS.

    struct Calidad {
        let id: String            // "medium" | "high" | "low"
        let etiqueta: String
        let sampleRate: Int
        let archivoBase: String   // nombre local del .ckpt
        let url: String           // fuente de descarga (rhasspy/piper-checkpoints)
        let modelArgs: [String]   // flags --model.* extra (medium = vacío = defaults)
        let nota: String
    }

    static let calidades: [Calidad] = [
        Calidad(id: "medium", etiqueta: "Media (recomendada)", sampleRate: 22050,
                archivoBase: "es-medium.ckpt",
                url: "https://huggingface.co/datasets/rhasspy/piper-checkpoints/resolve/main/es/es_ES/davefx/medium/epoch=5629-step=1605020.ckpt",
                modelArgs: [],
                nota: "Base en ESPAÑOL (davefx). Rápida y natural. La mejor relación calidad/velocidad para español."),
        Calidad(id: "high", etiqueta: "Alta", sampleRate: 22050,
                archivoBase: "en-high.ckpt",
                url: "https://huggingface.co/datasets/rhasspy/piper-checkpoints/resolve/main/en/en_US/lessac/high/epoch=2218-step=838782.ckpt",
                modelArgs: ["--model.resblock", "1",
                            "--model.resblock_kernel_sizes", "[3,7,11]",
                            "--model.resblock_dilation_sizes", "[[1,3,5],[1,3,5],[1,3,5]]",
                            "--model.upsample_rates", "[8,8,2,2]",
                            "--model.upsample_initial_channel", "512",
                            "--model.upsample_kernel_sizes", "[16,16,4,4]"],
                nota: "Red MÁS grande (más nítida) pero MÁS lenta al hablar. Base en INGLÉS (lessac): el entreno la adapta al español; requiere más etapas. ~1 GB de descarga."),
        Calidad(id: "low", etiqueta: "Baja (veloz)", sampleRate: 16000,
                archivoBase: "en-low.ckpt",
                url: "https://huggingface.co/datasets/rhasspy/piper-checkpoints/resolve/main/en/en_US/lessac/low/epoch=2307-step=558536.ckpt",
                modelArgs: [],
                nota: "16 kHz: la más liviana y veloz, con menor fidelidad de audio. Base en INGLÉS (lessac), se adapta al español."),
    ]

    static func calidad(_ id: String) -> Calidad { calidades.first { $0.id == id } ?? calidades[0] }
    static func baseCkpt(_ id: String) -> URL { raizDir.appendingPathComponent("base/\(calidad(id).archivoBase)") }
    static func baseListo(_ id: String) -> Bool { FileManager.default.fileExists(atPath: baseCkpt(id).path) }

    // MARK: Estado

    /// ¿El vits está vendorizado en el venv? (piper.train NO trae el módulo de entreno en
    /// el wheel de pip; hay que copiarlo + compilar monotonic_align).
    static var vitsListo: Bool {
        let fm = FileManager.default
        let lightning = sitePackages.appendingPathComponent("piper/train/vits/lightning.py")
        let mono = sitePackages.appendingPathComponent("piper/train/vits/monotonic_align")
        let tieneSo = ((try? fm.contentsOfDirectory(atPath: mono.path)) ?? []).contains { $0.hasSuffix(".so") }
        return fm.fileExists(atPath: lightning.path) && tieneSo
    }
    /// Listo para entrenar Piper: motor + vits vendorizado (la base se baja por calidad).
    static var listo: Bool { VozEngine.estado() == .listo && vitsListo }

    // MARK: Plan (reusa el cerebro de Entrenador: minutos → etapas recomendadas)

    static func duracionMinutos(_ carpeta: URL) -> Double { Entrenador.duracionMinutos(carpeta) }
    static func recomendar(minutos: Double) -> PlanEntrenamiento { Entrenador.recomendar(minutos: minutos) }
    /// Piper en CPU ~1.5 s/paso (fine-tune sobre base). Estimación para avisar.
    static func horasEstimadas(etapas: Int) -> Double { Double(etapas) * 1.5 / 3600.0 }

    struct Progreso { var paso: Int; var total: Int; var epoca: Int; var texto: String }

    // MARK: Preparar (deps de entreno + vendorizar vits + escribir scripts)

    /// Deja el motor listo para ENTRENAR Piper. Reusa instalarEntrenamiento (Whisper) y
    /// añade las deps de Piper-train; vendoriza el vits + compila monotonic_align si falta
    /// (fresh install). Idempotente: si ya está, no rehace nada pesado.
    static func preparar(onProgreso: @escaping (String) -> Void,
                         completion: @escaping (Bool, String) -> Void) {
        guard VozEngine.estado() == .listo else { completion(false, "Primero instala el motor de voz."); return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try? FileManager.default.createDirectory(at: raizDir, withIntermediateDirectories: true)
                escribirScripts()
                // Deps de entrenamiento de Piper (además de Whisper/librosa ya instaladas
                // por instalarEntrenamiento de XTTS, que compartimos).
                onProgreso("Instalando herramientas de Piper (lightning, cython, onnx)…")
                let uv = try VozEngine.uvBin(onProgreso)
                try VozEngine.correrUv(uv, ["pip", "install", "--python", VozEngine.pythonURL.path] + pinsPiper, onProgreso)
                if !vitsListo {
                    guard compiladorListo() else {
                        throw Err.compilador
                    }
                    onProgreso("Preparando el entrenador de Piper (vits + monotonic_align)…")
                    let p = Process(); p.executableURL = VozEngine.pythonURL
                    p.arguments = [setupURL.path, sitePackages.path]
                    p.environment = ProcessInfo.processInfo.environment
                    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                    pipe.fileHandleForReading.readabilityHandler = { fh in
                        if let s = String(data: fh.availableData, encoding: .utf8), !s.isEmpty {
                            for l in s.split(separator: "\n") { onProgreso(String(l)) }
                        }
                    }
                    try p.run(); p.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    guard vitsListo else { throw Err.setup }
                }
                // La base se descarga por calidad en la pantalla; aquí basta con vits listo.
                DispatchQueue.main.async { completion(vitsListo, "Entrenador de Piper listo. Elige la calidad y (si falta) descarga su base.") }
            } catch {
                DispatchQueue.main.async { completion(false, "Falló: \(error.localizedDescription)") }
            }
        }
    }

    static func escribirScripts() {
        try? FileManager.default.createDirectory(at: raizDir, withIntermediateDirectories: true)
        try? piperDsPy.data(using: .utf8)?.write(to: dsScriptURL)
        try? trainWrapPy.data(using: .utf8)?.write(to: wrapURL)
        try? setupPy.data(using: .utf8)?.write(to: setupURL)
    }

    // MARK: Descargar la base (fine-tune) — bajo demanda con permiso

    /// URL del checkpoint base es (medium). Parametrizable; si está vacía, se informa al
    /// usuario que la coloque (política: nada pesado forzado, descarga con permiso).
    /// URL de la base para una calidad. Para `medium` respeta el override Config si existe.
    static func baseURL(_ id: String) -> String {
        if id == "medium", !Config.piperBaseURL().isEmpty { return Config.piperBaseURL() }
        return calidad(id).url
    }

    static func descargarBase(calidadId: String, onProgreso: @escaping (String) -> Void,
                              completion: @escaping (Bool, String) -> Void) {
        if baseListo(calidadId) { completion(true, "La base ya está."); return }
        let dst = baseCkpt(calidadId)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                onProgreso("Descargando la base de calidad \(calidad(calidadId).etiqueta) (una sola vez)…")
                // A archivo temporal y luego mover: si se corta, no deja un .ckpt a medias.
                let tmp = dst.path + ".part"
                try VozEngine.correrUv("/usr/bin/curl", ["-Lf", "--retry", "3", baseURL(calidadId), "-o", tmp], onProgreso)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(atPath: tmp, toPath: dst.path)
                let ok = baseListo(calidadId)
                DispatchQueue.main.async { completion(ok, ok ? "Base lista." : "No pude descargar la base.") }
            } catch {
                DispatchQueue.main.async { completion(false, "Falló la descarga: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: Entrenar (dataset → fit en background, resumible)

    /// Lanza el entrenamiento. FASE 1 dataset (piper_ds.py: Whisper + resample 22050).
    /// FASE 2 fit en BACKGROUND (fine-tune CPU sobre la base, contador en 0). Guarda
    /// checkpoints periódicos para elegir el mejor. `reanudar` = continuar un proyecto
    /// existente desde su último checkpoint (recuperación tras apagón).
    static func entrenar(carpeta: URL?, nombre: String, stamp: String, etapas: Int,
                         calidadId: String = "medium", reanudar: Bool = false,
                         onProgreso: @escaping (Progreso) -> Void,
                         onArranco: @escaping (Bool, String, URL) -> Void) {
        guard listo else { onArranco(false, "El entrenador de Piper no está listo.", raizDir); return }
        escribirScripts()
        let proyecto = proyectosDir.appendingPathComponent("\(Entrenador.slug(nombre))_\(stamp)")
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            try? fm.createDirectory(at: proyecto, withIntermediateDirectories: true)
            // La calidad se FIJA al crear el proyecto (la arquitectura debe coincidir al
            // reanudar). Proyecto nuevo → usa calidadId; reanudar → lee la guardada.
            let calFile = proyecto.appendingPathComponent("calidad.txt")
            let cal: Calidad
            if reanudar, let g = try? String(contentsOf: calFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                cal = calidad(g)
            } else {
                cal = calidad(calidadId)
                try? cal.id.write(to: calFile, atomically: true, encoding: .utf8)
            }
            guard baseListo(cal.id) else {
                DispatchQueue.main.async { onArranco(false, "Falta la base de calidad \(cal.etiqueta). Descárgala primero.", proyecto) }; return
            }
            let dsDir = proyecto.appendingPathComponent("dataset")
            let meta = dsDir.appendingPathComponent("metadata.csv")
            cancelado = false
            // Reentreno FRESCO (no reanudar): limpia checkpoints/run viejos para NO mezclar
            // cortes de una sesión anterior (con audios distintos) con los nuevos.
            if !reanudar {
                try? fm.removeItem(at: proyecto.appendingPathComponent("ckpts"))
                try? fm.removeItem(at: proyecto.appendingPathComponent("run"))
            }

            // FASE 1 — dataset. Se construye SOLO si aún no existe uno usable (así reintentar
            // el mismo proyecto NO re-transcribe los 452 min: reusa el dataset ya hecho).
            let dsHecho = (try? String(contentsOf: meta, encoding: .utf8))?.split(separator: "\n").count ?? 0
            if dsHecho <= 3 {
                guard ffmpegListo() else {
                    DispatchQueue.main.async { onArranco(false, "Falta ffmpeg (necesario para preparar el audio). Instálalo: brew install ffmpeg", proyecto) }; return
                }
                DispatchQueue.main.async { onProgreso(Progreso(paso: 0, total: 0, epoca: 0, texto: "Transcribiendo y preparando audios (Whisper)…")) }
                guard let carpeta else { DispatchQueue.main.async { onArranco(false, "Falta la carpeta de audios.", proyecto) }; return }
                try? fm.createDirectory(at: dsDir, withIntermediateDirectories: true)
                let ds = Process(); ds.executableURL = VozEngine.pythonURL
                ds.arguments = [dsScriptURL.path, carpeta.path, dsDir.path]
                var dsEnv = entorno()
                // Rutas ABSOLUTAS de ffmpeg/ffprobe → piper_ds no depende del PATH.
                if let ff = rutaBin("ffmpeg") { dsEnv["FFMPEG"] = ff }
                if let fp = rutaBin("ffprobe") { dsEnv["FFPROBE"] = fp }
                ds.environment = dsEnv
                let dsLog = proyecto.appendingPathComponent("dataset.log")
                fm.createFile(atPath: dsLog.path, contents: nil)
                if let fh = try? FileHandle(forWritingTo: dsLog) { ds.standardOutput = fh; ds.standardError = fh }
                proc = ds   // para que "Detener" mate también la transcripción (Fase 1)
                do { try ds.run(); ds.waitUntilExit() } catch {
                    DispatchQueue.main.async { onArranco(false, "Falló el dataset: \(error.localizedDescription)", proyecto) }; return
                }
                if cancelado { DispatchQueue.main.async { onArranco(false, "Detenido.", proyecto) }; return }
                let n = (try? String(contentsOf: meta, encoding: .utf8))?.split(separator: "\n").count ?? 0
                guard ds.terminationStatus == 0, n > 3 else {
                    let pista = pistaDataset(proyecto)
                    DispatchQueue.main.async {
                        onArranco(false, "El dataset quedó vacío o muy corto (\(n) clips)." + (pista.isEmpty ? "" : " · \(pista)"), proyecto)
                    }; return
                }
            }

            if cancelado { DispatchQueue.main.async { onArranco(false, "Detenido.", proyecto) }; return }
            // FASE 2 — fit en background.
            DispatchQueue.main.async { onProgreso(Progreso(paso: 0, total: etapas, epoca: 0, texto: "Arrancando el entrenamiento…")) }
            let ckptsDir = proyecto.appendingPathComponent("ckpts")
            try? fm.createDirectory(at: ckptsDir, withIntermediateDirectories: true)
            // ¿Reanudar? → último checkpoint del proyecto (sin reset). Si no → base (con reset a 0).
            let reanuda = ultimoCheckpoint(proyecto)
            let ckptPath = (reanudar && reanuda != nil) ? reanuda!.path : baseCkpt(cal.id).path
            let cada = max(200, etapas / 5)
            let tr = Process(); tr.executableURL = VozEngine.pythonURL
            tr.arguments = [
                wrapURL.path, "fit",
                "--data.csv_path", meta.path,
                "--data.audio_dir", dsDir.appendingPathComponent("audio").path,
                "--data.cache_dir", proyecto.appendingPathComponent("cache").path,
                "--data.config_path", proyecto.appendingPathComponent("config.json").path,
                "--data.voice_name", Entrenador.slug(nombre),
                "--data.espeak_voice", "es",
                "--model.sample_rate", "\(cal.sampleRate)",
                "--data.batch_size", "\(Config.piperBatch())",
                "--data.num_workers", "0",
                "--trainer.default_root_dir", proyecto.appendingPathComponent("run").path,
                "--trainer.accelerator", "cpu", "--trainer.devices", "1", "--trainer.precision", "32",
                "--trainer.max_steps", "\(etapas)",
                "--trainer.num_sanity_val_steps", "0",
                "--trainer.callbacks+=lightning.pytorch.callbacks.ModelCheckpoint",
                "--trainer.callbacks.dirpath", ckptsDir.path,
                "--trainer.callbacks.every_n_train_steps", "\(cada)",
                "--trainer.callbacks.save_top_k", "-1",
                "--trainer.callbacks.filename", "paso{step}",
                "--ckpt_path", ckptPath,
            ] + cal.modelArgs   // params de arquitectura de la calidad (high/low); medium = vacío
            var env = entorno()
            // Reset del contador SOLO cuando arrancamos desde la base (proyecto nuevo).
            if !(reanudar && reanuda != nil) { env["PIPER_FINETUNE_RESET"] = "1" }
            // Limitar torch a los núcleos RÁPIDOS (performance): en Apple Silicon incluir los
            // efficiency frena cada op al ritmo del más lento (CPU 100% sin avanzar).
            let pc = "\(nucleosRapidos())"
            env["PIPER_THREADS"] = pc; env["OMP_NUM_THREADS"] = pc
            env["MKL_NUM_THREADS"] = pc; env["VECLIB_MAXIMUM_THREADS"] = pc
            tr.environment = env
            let trLog = proyecto.appendingPathComponent("piper.log")
            fm.createFile(atPath: trLog.path, contents: nil)
            if let fh = try? FileHandle(forWritingTo: trLog) { tr.standardOutput = fh; tr.standardError = fh }
            do { try tr.run() } catch {
                DispatchQueue.main.async { onArranco(false, "No pude lanzar el entrenamiento.", proyecto) }; return
            }
            proc = tr
            // Espera a que el LOOP de entrenamiento arranque (la barra/época aparece) o muera.
            // OJO: el 1er checkpoint recién sale a ~200 pasos, así que NO esperamos "paso>=1".
            var arranco = false
            for _ in 0..<240 {
                Thread.sleep(forTimeInterval: 1)
                if logEntrenando(proyecto) { arranco = true; break }
                if !tr.isRunning { break }
            }
            DispatchQueue.main.async {
                onArranco(arranco && tr.isRunning,
                          arranco ? "Entrenando en \(proyecto.lastPathComponent)" : "El entrenamiento no arrancó (mira piper.log).",
                          proyecto)
            }
        }
    }

    private static var cancelado = false
    static func detener() { cancelado = true; proc?.terminate(); proc = nil }
    static func esActivo() -> Bool { proc?.isRunning ?? false }

    /// Detiene el entrenamiento de un proyecto AUNQUE la app se haya reabierto (el proceso
    /// quedó huérfano y `proc` es nil): lo mata por pkill sobre la ruta del proyecto.
    static func detenerProyecto(_ proyecto: URL) {
        detener()
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", proyecto.lastPathComponent + "/run"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    /// Extrae una PISTA legible del dataset.log para decirle al usuario qué pasó
    /// (ffmpeg faltante, sin audios, errores por archivo). Alberto lo pidió: ver el porqué.
    static func pistaDataset(_ proyecto: URL) -> String {
        let log = (try? String(contentsOf: proyecto.appendingPathComponent("dataset.log"), encoding: .utf8)) ?? ""
        let lineas = log.split(separator: "\n").map(String.init)
        if let x = lineas.last(where: { $0.contains("[X]") }) { return String(x.dropFirst(3).prefix(120)).trimmingCharacters(in: .whitespaces) }
        if lineas.contains(where: { $0.contains("No such file or directory: 'ffmpeg'") || $0.contains("ffmpeg") && $0.contains("[!]") }) {
            return "no se encontró ffmpeg al procesar (instala: brew install ffmpeg)"
        }
        if let bang = lineas.last(where: { $0.contains("[!]") }) { return "error al procesar audios: " + String(bang.dropFirst(3).prefix(100)) }
        if let ok = lineas.last(where: { $0.contains("[OK]") }) { return String(ok.dropFirst(4).prefix(120)).trimmingCharacters(in: .whitespaces) }
        return ""
    }

    /// Entorno para subprocesos con PATH AMPLIADO. Una app lanzada desde Finder (LSUIElement)
    /// trae PATH mínimo y NO vería ffmpeg de Homebrew → el dataset fallaría. Añadimos las
    /// rutas típicas (mismo patrón que AgenteHermes).
    static func entorno() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "")
        return env
    }

    /// Ruta ABSOLUTA de ffmpeg/ffprobe (nil si no hay). Una app de Finder no ve el PATH de
    /// Homebrew, así que buscamos en las rutas típicas y, si no, vía `which` con PATH ampliado.
    static func rutaBin(_ nombre: String) -> String? {
        for base in ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"]
            where FileManager.default.isExecutableFile(atPath: base + nombre) { return base + nombre }
        let w = Process(); w.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        w.arguments = ["which", nombre]; w.environment = entorno()
        let pipe = Pipe(); w.standardOutput = pipe; w.standardError = FileHandle.nullDevice
        do { try w.run() } catch { return nil }; w.waitUntilExit()
        guard w.terminationStatus == 0 else { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }
    static func ffmpegListo() -> Bool { rutaBin("ffmpeg") != nil }

    /// Núcleos RÁPIDOS (performance) del Mac. En Apple Silicon usar solo estos evita que los
    /// efficiency (lentos) frenen el entrenamiento. Fallback: mitad de los lógicos.
    static func nucleosRapidos() -> Int {
        var n: Int32 = 0; var sz = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &n, &sz, nil, 0) == 0, n > 0 { return Int(n) }
        return max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    }

    /// ¿El loop de entrenamiento ya arrancó? (la barra/época o los params aparecen en el
    /// log). Señal de "arranco" fiable: el 1er checkpoint recién sale a ~200 pasos.
    private static func logEntrenando(_ proyecto: URL) -> Bool {
        let log = (try? String(contentsOf: proyecto.appendingPathComponent("piper.log"), encoding: .utf8)) ?? ""
        return log.contains("Epoch 0") || log.contains("it/s") || log.contains("Trainable params")
    }
    /// ¿El fit terminó de verdad? (Lightning imprime el motivo de parada).
    static func termino(_ proyecto: URL) -> Bool {
        let log = (try? String(contentsOf: proyecto.appendingPathComponent("piper.log"), encoding: .utf8)) ?? ""
        return log.contains("max_steps=") && log.contains("reached") || log.contains("`Trainer.fit` stopped")
    }

    // MARK: Progreso VIVO + re-enganche al reabrir la app
    //
    // El entrenamiento corre como proceso HIJO. Si el usuario cierra la ventana o incluso
    // BetoDicta, el proceso queda HUÉRFANO y SIGUE (launchd lo adopta) escribiendo su log.
    // Al reabrir, detectamos ese proceso vivo (pgrep) y re-enganchamos el progreso. Si de
    // plano se apagó la compu, no hay proceso: se ofrece REANUDAR desde el último checkpoint.

    struct Vivo { var fase: Int; var faseTotal: Int; var pct: Double; var texto: String; var activo: Bool; var termino: Bool }

    private static func mtime(_ u: URL) -> Date {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// ¿Sigue vivo un proceso de entrenamiento de ESTE proyecto? (aunque la app se cerró y
    /// reabrió: lo detecta por pgrep sobre la ruta del proyecto).
    static func procesoVivo(_ proyecto: URL) -> Bool {
        if esActivo() { return true }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", proyecto.lastPathComponent + "/run"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }; p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// El proyecto que está trabajando AHORA (entrenando o preparando dataset), para
    /// re-enganchar el progreso al reabrir. Basado en proceso vivo o log recién escrito.
    static func proyectoActivo() -> URL? {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: proyectosDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for d in dirs.sorted(by: { mtime($0) > mtime($1) }) {
            if procesoVivo(d) { return d }
            let dl = d.appendingPathComponent("dataset.log")
            let pl = d.appendingPathComponent("piper.log")
            // dataset en curso: dataset.log fresco y aún sin fase de entrenamiento.
            if FileManager.default.fileExists(atPath: dl.path), !FileManager.default.fileExists(atPath: pl.path),
               Date().timeIntervalSince(mtime(dl)) < 90 { return d }
        }
        return nil
    }

    private static func ultimoPar(_ s: String, _ pat: String) -> (Int, Int)? {
        guard let re = try? NSRegularExpression(pattern: pat) else { return nil }
        let ms = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        guard let m = ms.last, let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s) else { return nil }
        return (Int(s[r1]) ?? 0, Int(s[r2]) ?? 0)
    }
    private static func ultimoEntero(_ s: String, _ pat: String, primero: Bool = false) -> Int {
        guard let re = try? NSRegularExpression(pattern: pat) else { return 0 }
        let ms = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        guard let m = (primero ? ms.first : ms.last), let r = Range(m.range(at: 1), in: s) else { return 0 }
        return Int(s[r]) ?? 0
    }

    /// Progreso VIVO combinado con % y texto dinámico. Sabe en qué FASE va (1 dataset,
    /// 2 entrenamiento), calcula el % de cada una y dice qué está pasando ahora mismo.
    static func progresoVivo(_ proyecto: URL, etapas: Int) -> Vivo {
        let piLog = (try? String(contentsOf: proyecto.appendingPathComponent("piper.log"), encoding: .utf8))?
            .replacingOccurrences(of: "\r", with: "\n") ?? ""
        let dsLog = (try? String(contentsOf: proyecto.appendingPathComponent("dataset.log"), encoding: .utf8))?
            .replacingOccurrences(of: "\r", with: "\n") ?? ""
        let vivo = procesoVivo(proyecto)
        let fin = termino(proyecto)
        // piper.log con contenido = ya estamos en FASE 2 (aunque aún esté armando la caché).
        if !piLog.isEmpty || fin {
            // OJO: la barra de Lightning "X/Y m:ss" es el LOTE dentro de la ÉPOCA (X) sobre
            // los lotes-por-época (Y); se REINICIA cada época. NO es el paso global. El paso
            // GLOBAL = época × lotes_por_época + lote. Piso fiable: el último checkpoint.
            let bar = ultimoPar(piLog, "(\\d+)/(\\d+) \\d+:\\d+")
            let ep = ultimoEntero(piLog, "Epoch (\\d+)")
            var paso = checkpoints(proyecto).last?.paso ?? 0
            if let (lote, lotesEp) = bar, lotesEp > 0 {
                paso = max(paso, ep * lotesEp + lote)   // estimación fina + piso del checkpoint
            }
            let total = etapas > 0 ? etapas : 0
            paso = total > 0 ? min(paso, total) : paso
            let pct = total > 0 ? min(1.0, Double(paso) / Double(total)) : 0
            let arrancoPasos = bar != nil || paso > 0
            let txt: String
            if fin { txt = "✓ Terminó — escucha y elige el mejor checkpoint abajo." }
            else if !arrancoPasos { txt = "Fase 2/2 · Preparando el modelo y la caché de audio (arranca en breve)…" }
            else { txt = "Fase 2/2 · Entrenando: paso \(paso) de \(total) (\(Int(pct*100))%) · época \(ep)" }
            return Vivo(fase: 2, faseTotal: 2, pct: pct, texto: txt, activo: vivo && !fin, termino: fin)
        }
        // Fase 1 — dataset (Whisper): archivos hechos / total + fragmentos.
        let tot = ultimoEntero(dsLog, "(\\d+) audios en", primero: true)
        let hechos = ultimoPar(dsLog, "(\\d+)/(\\d+) \\| clips")?.0 ?? 0
        let clips = ultimoEntero(dsLog, "clips=(\\d+)")
        let pct = tot > 0 ? Double(hechos) / Double(tot) : 0
        let txt = tot > 0
            ? "Fase 1/2 · Transcribiendo audios (Whisper): \(hechos) de \(tot) (\(Int(pct*100))%) · \(clips) fragmentos"
            : "Fase 1/2 · Preparando audios (Whisper)…"
        return Vivo(fase: 1, faseTotal: 2, pct: pct, texto: txt, activo: vivo || !dsLog.isEmpty, termino: false)
    }

    /// Nombre "bonito" (para reconstruir el campo Nombre al re-enganchar) desde la carpeta.
    static func nombreDeProyecto(_ proyecto: URL) -> String {
        proyecto.lastPathComponent.replacingOccurrences(of: "_run", with: "").replacingOccurrences(of: "-", with: " ")
    }
    /// Etapas objetivo de un proyecto (del piper.log "max_steps=N") para el % al reabrir.
    static func etapasDe(_ proyecto: URL) -> Int {
        let log = (try? String(contentsOf: proyecto.appendingPathComponent("piper.log"), encoding: .utf8)) ?? ""
        let n = ultimoEntero(log, "max_steps=(\\d+)")
        return n > 0 ? n : 3000
    }

    // MARK: Resumible + progreso + checkpoints

    /// El último checkpoint (mayor paso) de un proyecto — para reanudar tras apagón.
    static func ultimoCheckpoint(_ proyecto: URL) -> URL? { checkpoints(proyecto).last?.url }

    /// Checkpoints periódicos guardados (paso ascendente). El usuario elige el mejor.
    static func checkpoints(_ proyecto: URL) -> [(paso: Int, url: URL)] {
        let dir = proyecto.appendingPathComponent("ckpts")
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [(Int, URL)] = []
        for u in items where u.pathExtension == "ckpt" {
            // nombre "pasostep=NNN.ckpt" o "...step=NNN...".
            if let r = u.lastPathComponent.range(of: "step=") {
                let cola = u.lastPathComponent[r.upperBound...]
                let num = cola.prefix { $0.isNumber }
                if let n = Int(num) { out.append((n, u)) }
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// ¿Hay un proyecto a medio entrenar? (para ofrecer "reanudar"). Devuelve el más
    /// reciente con checkpoints pero sin voz emitida.
    static func proyectoReanudable() -> URL? {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: proyectosDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let conCkpt = dirs.filter { !checkpoints($0).isEmpty }
        return conCkpt.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.first
    }

    /// Progreso EN VIVO. El paso global fiable = el MAYOR checkpoint guardado (Lightning
    /// no imprime "step=N" en el log, solo la barra "época N · lote X/Y"). El "lote" de la
    /// barra da movimiento fino entre checkpoints. `total` lo compone el caller (etapas).
    static func progreso(_ proyecto: URL) -> Progreso {
        let raw = (try? String(contentsOf: proyecto.appendingPathComponent("piper.log"), encoding: .utf8)) ?? ""
        let log = raw.replacingOccurrences(of: "\r", with: "\n")
        func ultimoInt(_ patron: String, _ grupo: Int = 1) -> Int {
            guard let re = try? NSRegularExpression(pattern: patron) else { return 0 }
            let ms = re.matches(in: log, range: NSRange(log.startIndex..., in: log))
            guard let m = ms.last, let r = Range(m.range(at: grupo), in: log) else { return 0 }
            return Int(log[r]) ?? 0
        }
        let epoca = ultimoInt("Epoch (\\d+)")
        let paso = checkpoints(proyecto).last?.paso ?? 0
        // Barra rica: "… 2/4 0:00:04 • …" → lote actual / total del tramo.
        let lote = ultimoInt("(\\d+)/(\\d+) \\d+:\\d+", 1)
        let loteTot = ultimoInt("\\d+/(\\d+) \\d+:\\d+", 1)
        var texto = "Preparando…"
        if paso > 0 {
            texto = "paso \(paso) · época \(epoca)" + (lote > 0 ? " · lote \(lote)/\(loteTot)" : "")
        } else if lote > 0 {
            texto = "época \(epoca) · lote \(lote)/\(loteTot)"
        }
        return Progreso(paso: paso, total: 0, epoca: epoca, texto: texto)
    }

    // MARK: Exportar ONNX + registrar como voz ⚡

    /// Exporta el checkpoint elegido a .onnx (+ .onnx.json = config del entreno) y lo
    /// registra en la biblioteca como voz Piper rápida, con su persona (prompt). `prompt`
    /// = cómo habla la persona (parámetro del usuario). Pesado; corre en background.
    static func exportarYregistrar(proyecto: URL, checkpoint: URL, nombre: String, prompt: String,
                                   stamp: String, completion: @escaping (VozLocal?, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("piperexp_\(stamp)")
            try? fm.removeItem(at: tmp); try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            let onnx = tmp.appendingPathComponent("voz.onnx")
            let exp = Process(); exp.executableURL = VozEngine.pythonURL
            exp.arguments = ["-m", "piper.train.export_onnx", "--checkpoint", checkpoint.path, "--output-file", onnx.path]
            exp.environment = ProcessInfo.processInfo.environment
            exp.standardOutput = FileHandle.nullDevice; exp.standardError = FileHandle.nullDevice
            do { try exp.run(); exp.waitUntilExit() } catch {
                DispatchQueue.main.async { completion(nil, "No pude exportar el ONNX.") }; return
            }
            guard exp.terminationStatus == 0, fm.fileExists(atPath: onnx.path) else {
                DispatchQueue.main.async { completion(nil, "El export falló (revisa el checkpoint).") }; return
            }
            // <modelo>.onnx.json = config del entreno (Piper lo necesita para hablar).
            let cfg = proyecto.appendingPathComponent("config.json")
            if fm.fileExists(atPath: cfg.path) {
                try? fm.copyItem(at: cfg, to: URL(fileURLWithPath: onnx.path + ".json"))
            }
            // Registrar (VocesLocales copia el .onnx + .json a la carpeta gestionada).
            guard var voz = VocesLocales.importarPiper(desde: onnx, nombre: nombre) else {
                DispatchQueue.main.async { completion(nil, "No pude registrar la voz.") }; return
            }
            try? fm.removeItem(at: tmp)
            // Persona (cómo habla) — la que el usuario escribió, o autogenerada de los audios.
            var persona = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if persona.isEmpty {
                persona = Entrenador.personaDesdeAudios(
                    carpetaAudios: proyecto.appendingPathComponent("dataset/audio"),
                    nombre: nombre, stamp: stamp)
            }
            if !persona.isEmpty {
                var list = VocesLocales.todas()
                if let i = list.firstIndex(where: { $0.id == voz.id }) {
                    list[i].persona = persona; VocesLocales.guardar(list); voz = list[i]
                }
            }
            DispatchQueue.main.async { completion(voz, "✓ Voz “\(nombre)” lista (Piper rápida) y agregada a tu biblioteca.") }
        }
    }

    /// Genera una muestra hablada de un checkpoint (export temporal → piper) para que el
    /// usuario ESCUCHE antes de elegir. Devuelve el wav.
    static func muestra(proyecto: URL, checkpoint: URL, texto: String, stamp: String,
                        completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("pipersamp_\(stamp)")
            try? fm.removeItem(at: tmp); try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            let onnx = tmp.appendingPathComponent("m.onnx")
            let exp = Process(); exp.executableURL = VozEngine.pythonURL
            exp.arguments = ["-m", "piper.train.export_onnx", "--checkpoint", checkpoint.path, "--output-file", onnx.path]
            exp.environment = ProcessInfo.processInfo.environment
            exp.standardOutput = FileHandle.nullDevice; exp.standardError = FileHandle.nullDevice
            do { try exp.run(); exp.waitUntilExit() } catch { DispatchQueue.main.async { completion(nil) }; return }
            let cfg = proyecto.appendingPathComponent("config.json")
            if fm.fileExists(atPath: cfg.path) { try? fm.copyItem(at: cfg, to: URL(fileURLWithPath: onnx.path + ".json")) }
            PiperTTS.decir(onnx: onnx, texto: texto) { wav in completion(wav) }
        }
    }

    // MARK: Errores

    /// ¿Hay un compilador C? (Xcode CLT) — necesario SOLO en fresh-install para compilar
    /// monotonic_align. En Mac de desarrollo siempre está; en Mac limpio: xcode-select --install.
    static func compiladorListo() -> Bool {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/cc") { return true }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["-p"]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }; p.waitUntilExit()
        return p.terminationStatus == 0
    }

    enum Err: Error, LocalizedError {
        case setup, compilador
        var errorDescription: String? {
            switch self {
            case .setup: return "no pude preparar el entrenador de Piper (vits/monotonic)"
            case .compilador: return "falta el compilador de Apple. Abre Terminal y corre: xcode-select --install, luego reintenta"
            }
        }
    }

    // Deps de Piper-train (setup.py extra [train] de piper1-gpl v1.4.2). Sin pin de torch:
    // se usa el torch 2.5.1 del motor (funciona en CPU). lightning = paquete unificado.
    private static let pinsPiper = [
        "piper-tts", "lightning>=2,<3", "cython>=3,<4",
        "jsonargparse[signatures]>=4.27.7", "onnx", "tensorboardx",
    ]

    // MARK: Scripts embebidos (nada depende de carpetas del usuario)

    /// Dataset Piper: carpeta de audios → 22050Hz mono + metadata.csv "archivo.wav|texto".
    /// Reusa ffmpeg (denoise/loudnorm) + mlx-whisper (turbo, ya descargado por XTTS).
    private static let piperDsPy = #"""
    #!/usr/bin/env python3
    import os, re, subprocess, sys, glob
    FOLDER=sys.argv[1]; OUT=sys.argv[2]
    AUD=os.path.join(OUT,"audio"); os.makedirs(AUD,exist_ok=True)
    SR=22050; MODEL="mlx-community/whisper-large-v3-turbo"; MIN_S,MAX_S=1.5,15.0
    # ffmpeg/ffprobe por ruta ABSOLUTA (una app de Finder no ve el PATH de Homebrew).
    FFMPEG=os.environ.get("FFMPEG","ffmpeg"); FFPROBE=os.environ.get("FFPROBE","ffprobe")
    EXTS=(".mp3",".ogg",".wav",".opus",".m4a",".aac",".flac")
    files=sorted(f for f in glob.glob(os.path.join(FOLDER,"**","*"),recursive=True) if f.lower().endswith(EXTS))
    print(f"[i] {len(files)} audios en {FOLDER} | ffmpeg={FFMPEG}",flush=True)
    if not files: print("[X] NO se hallaron audios (mp3/wav/m4a/opus/aac/flac/ogg) en la carpeta.",flush=True); sys.exit(0)
    try:
        import mlx_whisper
    except Exception as e:
        print("[X] mlx_whisper no disponible:",e,flush=True); sys.exit(0)
    rej={"dur":0,"txt":0,"cps":0,"reprobe":0}
    def dn(s,d): subprocess.run([FFMPEG,"-y","-v","error","-i",s,"-af","highpass=f=60,afftdn=nr=10:nf=-25,loudnorm=I=-20:TP=-2","-ar",str(SR),"-ac","1",d],check=True)
    def cut(s,a,b,d): subprocess.run([FFMPEG,"-y","-v","error","-ss",f"{a:.3f}","-to",f"{b:.3f}","-i",s,"-ar",str(SR),"-ac","1","-sample_fmt","s16",d],check=True)
    def dur(w):
        try: return float(subprocess.run([FFPROBE,"-v","error","-show_entries","format=duration","-of","csv=p=0",w],capture_output=True,text=True).stdout or 0)
        except: return 0.0
    meta=open(os.path.join(OUT,"metadata.csv"),"w"); tmp=os.path.join(OUT,"_t.wav"); kept=0; tot=0.0
    for i,f in enumerate(files):
        base=re.sub(r'[^A-Za-z0-9]','_',os.path.splitext(os.path.basename(f))[0])[:36]+f"_{i}"
        try:
            dn(f,tmp); r=mlx_whisper.transcribe(tmp,path_or_hf_repo=MODEL,language="es")
        except Exception as e: print("[!]",os.path.basename(f),repr(e),flush=True); continue
        for j,sg in enumerate(r.get("segments",[])):
            s,e2,txt=sg["start"],sg["end"],re.sub(r'\s+',' ',sg["text"].strip()); d=e2-s
            if d<MIN_S or d>MAX_S: rej["dur"]+=1; continue
            if len(txt)<4 or not re.search(r'[a-zA-ZáéíóúñÁÉÍÓÚÑ]',txt): rej["txt"]+=1; continue
            cps=len(txt)/d
            if cps<3 or cps>25: rej["cps"]+=1; continue
            cid=f"{base}_{j:02d}"; w=os.path.join(AUD,cid+".wav"); cut(tmp,s,e2,w)
            if MIN_S<=dur(w)<=MAX_S: meta.write(f"{cid}.wav|{txt}\n"); kept+=1; tot+=d
            else:
                rej["reprobe"]+=1
                try: os.remove(w)
                except OSError: pass
        meta.flush(); print(f"[i] {i+1}/{len(files)} | clips={kept} | {tot/60:.1f}min | rechazos {rej}",flush=True)
    meta.close()
    if os.path.exists(tmp):
        try: os.remove(tmp)
        except OSError: pass
    print(f"[OK] clips={kept} {tot/60:.1f}min | rechazados: {rej}",flush=True)
    """#

    /// Wrapper del fit: arregla torch 2.5 (weights_only) + hparams viejos, y con
    /// PIPER_FINETUNE_RESET=1 arranca el contador en 0 (fine-tune de pesos, no resume).
    private static let trainWrapPy = #"""
    import inspect, os, torch, sys
    # Apple Silicon: torch reparte cada op entre TODOS los núcleos, pero los efficiency
    # (lentos) frenan al ritmo del más lento → CPU al 100% pero sin avanzar. Limitar a los
    # núcleos RÁPIDOS (performance) acelera muchísimo. PIPER_THREADS lo fija BetoDicta.
    _thr = int(os.environ.get("PIPER_THREADS", "6") or "6")
    if _thr > 0:
        torch.set_num_threads(_thr)
        try: torch.set_num_interop_threads(max(1, _thr // 2))
        except Exception: pass
    from piper.train.vits.lightning import VitsModel
    from piper.train.vits.dataset import VitsDataModule
    _m_keys = set(inspect.signature(VitsModel.__init__).parameters) - {"self"}
    _d_keys = set(inspect.signature(VitsDataModule.__init__).parameters) - {"self"}
    _reset = os.environ.get("PIPER_FINETUNE_RESET", "0") == "1"
    _orig = torch.load
    def _load(*a, **k):
        k["weights_only"] = False
        ck = _orig(*a, **k)
        if isinstance(ck, dict):
            hp = ck.get("hyper_parameters")
            if isinstance(hp, dict):
                ck["hyper_parameters"] = {x: hp[x] for x in list(hp) if x in _m_keys}
            dhp = ck.get("datamodule_hyper_parameters")
            if isinstance(dhp, dict):
                ck["datamodule_hyper_parameters"] = {x: dhp[x] for x in list(dhp) if x in _d_keys}
            if _reset:
                ck["global_step"] = 0; ck["epoch"] = 0
                for kk in ("loops", "callbacks"): ck.pop(kk, None)
        return ck
    torch.load = _load
    from piper.train.__main__ import main
    sys.argv[0] = "piper.train"
    main()
    """#

    /// Fresh-install: vendoriza el módulo vits de piper1-gpl v1.4.2 (el wheel de pip no lo
    /// trae) y compila monotonic_align REPLICANDO el build_monotonic_align.sh OFICIAL
    /// (cythonize -i + mover el .so a la subcarpeta anidada). Probado en Mac ARM. Solo
    /// corre si falta (idempotente).
    private static let setupPy = #"""
    import os, sys, subprocess, tarfile, tempfile, urllib.request, shutil, glob
    SP = sys.argv[1]  # site-packages
    dst = os.path.join(SP, "piper", "train", "vits")
    tag = "v1.4.2"
    url = f"https://github.com/OHF-Voice/piper1-gpl/archive/refs/tags/{tag}.tar.gz"
    tmp = tempfile.mkdtemp()
    tgz = os.path.join(tmp, "src.tar.gz")
    print("[i] descargando fuente piper1-gpl", tag, flush=True)
    urllib.request.urlretrieve(url, tgz)
    with tarfile.open(tgz) as t: t.extractall(tmp)
    root = glob.glob(os.path.join(tmp, "piper1-gpl-*"))[0]
    srcv = os.path.join(root, "src", "piper", "train", "vits")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst): shutil.rmtree(dst)
    shutil.copytree(srcv, dst)
    print("[i] vits copiado a", dst, flush=True)
    # Parche: comparación de resblock robusta (int/str). Sin esto, la calidad 'high'
    # (resblock tipo "1") NO carga: el CLI pasa 1 como int y models.py compara con "1".
    try:
        mp = os.path.join(dst, "models.py"); s = open(mp).read()
        s2 = s.replace('modules.ResBlock1 if resblock == "1" else modules.ResBlock2',
                       'modules.ResBlock1 if str(resblock) == "1" else modules.ResBlock2')
        if s != s2: open(mp, "w").write(s2); print("[i] models.py: resblock int/str", flush=True)
    except Exception as e: print("[!] parche models.py:", e, flush=True)
    # Compilar monotonic_align tal como el build_monotonic_align.sh oficial:
    #   cd monotonic_align; mkdir -p monotonic_align; rm -f core.c; cythonize -i core.pyx;
    #   mv core*.so monotonic_align/   (estructura anidada que __init__.py espera)
    mono = os.path.join(dst, "monotonic_align")
    if os.path.isdir(mono):
        nested = os.path.join(mono, "monotonic_align"); os.makedirs(nested, exist_ok=True)
        try: os.remove(os.path.join(mono, "core.c"))
        except OSError: pass
        cythonize = os.path.join(os.path.dirname(sys.executable), "cythonize")
        cmd = [cythonize, "-i", "core.pyx"] if os.path.exists(cythonize) \
              else [sys.executable, "-m", "Cython.Build.Cythonize", "-i", "core.pyx"]
        r = subprocess.run(cmd, cwd=mono, capture_output=True, text=True)
        if r.returncode != 0: print("[!] cythonize:", r.stderr[-400:], flush=True)
        for s in glob.glob(os.path.join(mono, "core*.so")):
            shutil.move(s, os.path.join(nested, os.path.basename(s)))
        ok = bool(glob.glob(os.path.join(nested, "core*.so")))
        print("[i] monotonic_align compilado:", ok, flush=True)
    print("[OK] setup vits listo", flush=True)
    """#
}

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
    // transformers 5.x rompe coqui-tts (isin_mps_friendly).
    private static let pins = ["torch==2.5.1", "torchaudio==2.5.1",
                               "coqui-tts==0.27.5", "transformers==4.57.6"]

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

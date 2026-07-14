import Foundation

// MARK: - Motor de agente HERMES (BetoDicta = pasarela)
//
// El cerebro del agente vive en HERMES: BetoDicta captura la voz, la manda a Hermes
// (CLI one-shot `hermes chat -q "<texto>" --quiet`), Hermes procesa con SU LLM y SUS
// herramientas (crear carpetas, abrir web, lo que sea = dominio de Hermes), y devuelve
// SOLO el texto de la respuesta. BetoDicta lo muestra en el notch y lo HABLA con la voz
// elegida. Continuidad de conversación con --resume <session_id> (canal de voz propio).
//
// Sin infra extra (no MCP/plugin que instalar): Hermes ya sabe hacer lo suyo. A futuro,
// vías más ricas: ACP (`hermes acp`, streaming) o el MCP de Hermes. Igual para OpenClaw
// (`hermes claw`). Todo parametrizable; sin Hermes → cae al agente local.

enum AgenteHermes {
    private(set) static var sesion = ""     // session_id para mantener la conversación

    /// Ruta del binario hermes (parametrizable; por defecto ~/.local/bin/hermes).
    static func binario() -> String {
        let c = Config.hermesBin()
        if !c.isEmpty { return (c as NSString).expandingTildeInPath }
        let d = (NSHomeDirectory() + "/.local/bin/hermes")
        return FileManager.default.isExecutableFile(atPath: d) ? d : "/usr/local/bin/hermes"
    }

    static var disponible: Bool { FileManager.default.isExecutableFile(atPath: binario()) }

    /// Manda el texto a Hermes y devuelve SU respuesta (o nil si falla → agente local).
    static func preguntar(_ texto: String, completion: @escaping (String?) -> Void) {
        guard disponible else { Log.log(.ia, "Hermes: no encuentro el binario"); completion(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binario())
            var args = ["chat", "-q", texto, "--quiet"]
            if !sesion.isEmpty { args += ["--resume", sesion] }   // continuidad de conversación
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (NSHomeDirectory() + "/.local/bin") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            p.environment = env
            // stdout = respuesta limpia; stderr = info de sesión (session_id). Se leen los
            // dos para sacar la respuesta Y el session_id (continuidad).
            let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
            do { try p.run() } catch { DispatchQueue.main.async { completion(nil) }; return }
            let dOut = out.fileHandleForReading.readDataToEndOfFile()
            let dErr = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let stdoutTxt = String(data: dOut, encoding: .utf8) ?? ""
            let stderrTxt = String(data: dErr, encoding: .utf8) ?? ""
            let salida = stdoutTxt + "\n" + stderrTxt
            let (resp, sid) = parsear(salida)
            if let sid, !sid.isEmpty { sesion = sid }
            DispatchQueue.main.async { completion(resp.isEmpty ? nil : resp) }
        }
    }

    /// Nueva conversación (olvida la sesión).
    static func reiniciar() { sesion = "" }

    /// Separa el session_id de la respuesta. La salida trae una línea "session_id: <id>"
    /// y el resto es la respuesta.
    private static func parsear(_ salida: String) -> (String, String?) {
        var sid: String?
        var lineas: [String] = []
        for l in salida.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(l)
            if let r = s.range(of: "session_id:") {
                sid = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
            } else {
                lineas.append(s)
            }
        }
        return (lineas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), sid)
    }
}

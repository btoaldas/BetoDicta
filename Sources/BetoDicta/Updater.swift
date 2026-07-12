import AppKit
import Foundation

// MARK: - Actualización desde la app (GitHub Releases)
//
// "Verificar actualización" consulta el último release del repo; si hay
// versión nueva descarga el DMG, lo monta, se reemplaza en /Applications
// y se relanza. Si no, avisa que ya estás al día.

enum Updater {
    static let repo = "btoaldas/BetoDicta"

    enum Estado: Equatable {
        case reposo
        case buscando
        case alDia
        case disponible(version: String, dmg: URL, notas: String)
        case descargando(Double)     // 0..1
        case error(String)
    }

    /// Consulta el último release publicado.
    static func verificar(completion: @escaping (Estado) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard err == nil, let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    completion(.error("no pude consultar GitHub")); return
                }
                let remota = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                guard esMasNueva(remota, que: Version.numero) else {
                    Log.log(.sistema, "actualización: ya en la última (v\(Version.numero))")
                    completion(.alDia); return
                }
                guard let assets = json["assets"] as? [[String: Any]],
                      let dmg = assets.compactMap({ $0["browser_download_url"] as? String })
                          .first(where: { $0.hasSuffix(".dmg") }),
                      let url = URL(string: dmg) else {
                    completion(.error("el release v\(remota) no trae DMG")); return
                }
                let notas = (json["body"] as? String) ?? ""
                Log.log(.sistema, "actualización disponible: v\(remota)")
                completion(.disponible(version: remota, dmg: url, notas: notas))
            }
        }.resume()
    }

    /// Descarga el DMG y se auto-reemplaza: monta, copia a /Applications,
    /// desmonta y relanza. El último paso lo hace un script externo que
    /// sobrevive al cierre de la app.
    private static var obsDescarga: NSKeyValueObservation?
    static func actualizar(dmg: URL, completion: @escaping (Estado) -> Void) {
        let task = URLSession.shared.downloadTask(with: dmg) { tmp, _, err in
            DispatchQueue.main.async {
                guard let tmp, err == nil else {
                    completion(.error("descarga falló: \(err?.localizedDescription ?? "")")); return
                }
                let dmgLocal = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BetoDicta-update.dmg")
                try? FileManager.default.removeItem(at: dmgLocal)
                do { try FileManager.default.moveItem(at: tmp, to: dmgLocal) } catch {
                    completion(.error("no pude guardar el DMG")); return
                }

                // Script que corre DESPUÉS de que la app se cierre.
                let script = """
                sleep 1.5
                VOL=$(hdiutil attach -nobrowse -readonly "\(dmgLocal.path)" | tail -1 | awk -F'\\t' '{print $NF}')
                if [ -d "$VOL/BetoDicta.app" ]; then
                    rm -rf /Applications/BetoDicta.app
                    ditto "$VOL/BetoDicta.app" /Applications/BetoDicta.app
                    xattr -dr com.apple.quarantine /Applications/BetoDicta.app 2>/dev/null
                fi
                hdiutil detach "$VOL" >/dev/null 2>&1
                rm -f "\(dmgLocal.path)"
                open /Applications/BetoDicta.app
                """
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = ["-c", script]
                do {
                    try p.run()
                    Log.log(.sistema, "actualización: instalando y reiniciando…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApp.terminate(nil)
                    }
                } catch {
                    completion(.error("no pude lanzar el instalador"))
                }
            }
        }
        // Progreso de descarga → % en la UI ("Descargando 42%").
        obsDescarga = task.progress.observe(\.fractionCompleted) { prog, _ in
            DispatchQueue.main.async { completion(.descargando(prog.fractionCompleted)) }
        }
        task.resume()
    }

    /// Comparación de versiones numéricas ("0.16.0" > "0.15.0").
    static func esMasNueva(_ a: String, que b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

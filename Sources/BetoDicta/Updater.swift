import AppKit
import CryptoKit
import Foundation
import Security

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

    /// Resultado de la búsqueda al arrancar (si hubo). Lo lee el pie del panel
    /// de Ajustes (para mostrar "Actualización disponible" sin volver a buscar)
    /// y el menú de la barra (para el ítem "Actualización disponible"). Se
    /// setea solo cuando hay versión nueva.
    static var disponibleAlArrancar: Estado?
    /// Aviso a la UI de que cambió `disponibleAlArrancar` (menú/panel refrescan).
    static let notificacion = Notification.Name("betoUpdateDisponible")
    /// ¿Hay un dictado en curso? Lo inyecta AppDelegate. Sirve para NO
    /// auto-instalar (que reinicia la app) a mitad de una grabación.
    static var estaGrabando: () -> Bool = { false }

    /// Búsqueda al abrir la app (silenciosa). Todo esto corre en el hilo main
    /// (verificar completa en main), así que `disponibleAlArrancar` no compite
    /// con las lecturas de la UI/menú.
    static func buscarAlArrancar() {
        guard Config.buscarUpdateAlAbrir() else { return }
        verificar { estado in
            guard case .disponible(let v, let dmg, _) = estado else { return }
            // Autoactualizar: instala sola, PERO nunca a mitad de un dictado
            // (cortaría la grabación). Si está grabando, difiere y avisa.
            if Config.autoactualizar() && !estaGrabando() {
                Log.log(.sistema, "autoactualizar: bajando e instalando v\(v)…")
                actualizar(dmg: dmg) { _ in }
                return
            }
            // Cachea + avisa para que el usuario actualice a mano (botón abajo-izq
            // y ítem del menú). Al auto-instalar no cachea, para no ofrecer un
            // botón redundante mientras ya se instala.
            disponibleAlArrancar = estado
            NotificationCenter.default.post(name: notificacion, object: nil)
            if Config.autoactualizar() {
                Log.log(.sistema, "autoactualizar diferido: hay un dictado en curso; te aviso para instalar al terminar")
            } else {
                Log.log(.sistema, "actualización v\(v) disponible (activa Autoactualizar para instalarla sola)")
            }
        }
    }

    /// Consulta el último release publicado. 100% asíncrono: sin internet,
    /// URLSession falla rápido (no espera el timeout) y esto NO bloquea la UI
    /// — buscarAlArrancar ignora el error, así que abrir sin red es instantáneo.
    static func verificar(completion: @escaping (Estado) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.timeoutInterval = 10
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
    /// Candado de reentrancia: si ya hay una descarga/instalación en curso,
    /// una segunda llamada (p.ej. clic manual mientras autoactualizar baja) no
    /// arranca otra (evita dos scripts y sobrescribir obsDescarga).
    private static var instalando = false
    static func actualizar(dmg: URL, completion: @escaping (Estado) -> Void) {
        guard !instalando else { return }
        instalando = true
        let task = URLSession.shared.downloadTask(with: dmg) { tmp, _, err in
            DispatchQueue.main.async {
                guard let tmp, err == nil else {
                    instalando = false
                    completion(.error("descarga falló: \(err?.localizedDescription ?? "")")); return
                }
                let dmgLocal = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BetoDicta-update.dmg")
                try? FileManager.default.removeItem(at: dmgLocal)
                do { try FileManager.default.moveItem(at: tmp, to: dmgLocal) } catch {
                    instalando = false
                    completion(.error("no pude guardar el DMG")); return
                }

                // SEGURIDAD (revisión adversarial): antes de instalar, montar el
                // DMG y VERIFICAR que la app venga firmada con el MISMO
                // certificado que esta app. Como la clave privada de ese cert
                // NO está en GitHub, un release troyanizado (cuenta/CI
                // comprometidos) no puede firmarse igual y se rechaza aquí.
                guard let vol = montarDMG(dmgLocal) else {
                    instalando = false; try? FileManager.default.removeItem(at: dmgLocal)
                    completion(.error("no pude montar el DMG")); return
                }
                let appNueva = URL(fileURLWithPath: vol).appendingPathComponent("BetoDicta.app")
                guard firmaConfiable(appNueva) else {
                    desmontarDMG(vol)
                    instalando = false; try? FileManager.default.removeItem(at: dmgLocal)
                    Log.log(.sistema, "actualización RECHAZADA: la firma del DMG no coincide con la de esta app (posible manipulación del release)")
                    completion(.error("firma no válida — actualización cancelada por seguridad")); return
                }

                // Firma OK: copia desde el volumen YA montado y verificado (sin
                // re-montar y sin quitar quarantine). Rutas por argv (no
                // interpolación en el shell).
                let script = """
                sleep 1.5
                rm -rf /Applications/BetoDicta.app
                ditto "$1/BetoDicta.app" /Applications/BetoDicta.app
                hdiutil detach "$1" >/dev/null 2>&1
                rm -f "$2"
                open /Applications/BetoDicta.app
                """
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = ["-c", script, "betodicta-update", vol, dmgLocal.path]
                do {
                    try p.run()
                    Log.log(.sistema, "actualización: firma verificada ✓ — instalando y reiniciando…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApp.terminate(nil)
                    }
                } catch {
                    desmontarDMG(vol)
                    instalando = false
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

    // MARK: - Verificación de firma e integridad del DMG

    /// Monta un DMG de solo lectura y devuelve su punto de montaje (o nil).
    private static func montarDMG(_ dmg: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["attach", "-nobrowse", "-readonly", "-plist", dmg.path]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let ents = plist["system-entities"] as? [[String: Any]] else { return nil }
        return ents.compactMap { $0["mount-point"] as? String }.first
    }

    private static func desmontarDMG(_ vol: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["detach", vol]
        try? p.run(); p.waitUntilExit()
    }

    /// SHA-256 del certificado LÍDER (hoja) que firma un bundle. Anclar por el
    /// SHA del cert (no por su Common Name, que es falsificable) es lo que da
    /// la garantía: solo quien tiene la clave privada puede producir una firma
    /// válida contra ese certificado.
    private static func certLiderSHA(_ code: SecStaticCode) -> Data? {
        var infoCF: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any],
              let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certs.first else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return Data(SHA256.hash(data: der))
    }

    private static func staticCodeDeMiApp() -> SecStaticCode? {
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me else { return nil }
        var st: SecStaticCode?
        guard SecCodeCopyStaticCode(me, [], &st) == errSecSuccess else { return nil }
        return st
    }

    /// ¿El bundle está firmado de forma VÁLIDA (no manipulado) y con el MISMO
    /// certificado que esta app? Si esta app es ad-hoc (sin cert, no debería en
    /// releases) cae a un chequeo más débil: firma válida + mismo bundle id.
    static func firmaConfiable(_ app: URL) -> Bool {
        var nuevoCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &nuevoCode) == errSecSuccess,
              let nuevo = nuevoCode else { return false }
        // 1) Firma íntegra (código no manipulado tras firmar).
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(nuevo, flags, nil) == errSecSuccess else { return false }
        // 2) Mismo certificado líder que esta app.
        if let mio = staticCodeDeMiApp(), let shaMio = certLiderSHA(mio) {
            guard let shaNuevo = certLiderSHA(nuevo) else { return false }
            return shaMio == shaNuevo
        }
        // Fallback (esta app ad-hoc, sin cert): al menos exige el bundle id.
        let req = "identifier \"ec.bto.betodicta\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(req as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(nuevo, flags, requirement) == errSecSuccess
    }
}

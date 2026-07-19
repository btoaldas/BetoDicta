import AppKit
import CoreServices
import Foundation

/// Creación verificable en Notas de Apple.
///
/// Notes no ofrece un framework Swift público para crear notas, pero sí publica
/// un diccionario de automatización oficial. Esta ruta usa ese diccionario y
/// vuelve a leer el `plaintext` de la nota antes de anunciar éxito. El camino
/// anterior (abrir → esperar → ⌘N → ⌘V) se conserva únicamente como respaldo
/// manual: jamás declara que creó una nota si solo abrió la aplicación.
enum NotasApple {
    private static let cola = DispatchQueue(label: "ec.bto.betodicta.notas-apple",
                                            qos: .userInitiated)
    struct Plan: Equatable {
        let original: String
        let titulo: String
        let cuerpo: String
        let cuerpoHTML: String
    }

    private static func normalizarSaltos(_ texto: String) -> String {
        texto.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tituloCorto(_ texto: String, maximo: Int = 72) -> String {
        let unaLinea = texto.replacingOccurrences(of: #"\s+"#, with: " ",
                                                   options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard unaLinea.count > maximo else { return unaLinea }
        let prefijo = String(unaLinea.prefix(maximo + 1))
        if let corte = prefijo.lastIndex(where: { $0.isWhitespace }),
           corte > prefijo.index(prefijo.startIndex, offsetBy: maximo / 2) {
            return String(prefijo[..<corte]).trimmingCharacters(in: .whitespaces)
        }
        return String(unaLinea.prefix(maximo)).trimmingCharacters(in: .whitespaces)
    }

    private static func escaparHTML(_ texto: String) -> String {
        texto.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Mantiene párrafos y listas simples en vez de convertir todo el dictado en
    /// una sola línea. Todo se escapa antes de entrar al HTML de Notes.
    static func htmlSeguro(_ texto: String) -> String {
        let lineas = normalizarSaltos(texto).components(separatedBy: "\n")
        var salida: [String] = []
        var enLista = false
        func cerrarLista() {
            if enLista { salida.append("</ul>"); enLista = false }
        }
        for linea in lineas {
            let t = linea.trimmingCharacters(in: .whitespaces)
            let esVineta = t.hasPrefix("- ") || t.hasPrefix("• ") || t.hasPrefix("* ")
            if esVineta {
                if !enLista { salida.append("<ul>"); enLista = true }
                let contenido = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                salida.append("<li>\(escaparHTML(contenido))</li>")
            } else {
                cerrarLista()
                salida.append(t.isEmpty ? "<div><br></div>" : "<div>\(escaparHTML(t))</div>")
            }
        }
        cerrarLista()
        return salida.isEmpty ? "<div><br></div>" : salida.joined()
    }

    /// La primera línea breve se vuelve el título. Si el texto es una sola frase
    /// corta, esa frase completa es la nota; si es largo, se conserva íntegro en
    /// el cuerpo y solo se usa un resumen truncado como título.
    static func preparar(_ texto: String) -> Plan? {
        let limpio = normalizarSaltos(texto)
        guard !limpio.isEmpty else { return nil }
        let lineas = limpio.components(separatedBy: "\n")
        let indicesNoVacios = lineas.indices.filter {
            !lineas[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let primero = indicesNoVacios.first else { return nil }
        let primera = lineas[primero].trimmingCharacters(in: .whitespacesAndNewlines)
        let titulo = tituloCorto(primera)
        let cuerpo: String
        if indicesNoVacios.count == 1, primera.count <= 72 {
            cuerpo = ""
        } else if titulo == primera {
            cuerpo = lineas.dropFirst(primero + 1).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            cuerpo = limpio
        }
        return Plan(original: limpio, titulo: titulo, cuerpo: cuerpo,
                    cuerpoHTML: htmlSeguro(cuerpo))
    }

    private static func literalAppleScript(_ texto: String) -> String {
        let seguro = texto.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(seguro)\""
    }

    private static func compacto(_ texto: String) -> String {
        texto.replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Visible para QA: la nota devuelta puede incluir el título antes del cuerpo,
    /// pero debe conservar todo el texto original, en orden y sin truncarlo.
    /// Notes omite los caracteres `-`/`•` de una lista en `plaintext`, aunque la
    /// lista siga visible; por eso comprobamos cada línea semántica en secuencia.
    static func contenidoVerificado(plan: Plan, plaintext: String) -> Bool {
        let recibido = compacto(plaintext)
        let esperadas = normalizarSaltos(plan.original).components(separatedBy: "\n")
            .map { linea -> String in
                var t = linea.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("- ") || t.hasPrefix("• ") || t.hasPrefix("* ") {
                    t = String(t.dropFirst(2))
                }
                return compacto(t)
            }
            .filter { !$0.isEmpty }
        guard !recibido.isEmpty, !esperadas.isEmpty else { return false }
        var inicio = recibido.startIndex
        for esperado in esperadas {
            guard let rango = recibido.range(of: esperado,
                                              options: [.literal],
                                              range: inicio..<recibido.endIndex) else {
                return false
            }
            inicio = rango.upperBound
        }
        return true
    }

    private static func fuente(_ plan: Plan, eliminarDespues: Bool,
                               mostrar: Bool) -> String {
        let mostrarLinea = mostrar ? "show notaBetoDicta" : ""
        let activarLinea = mostrar ? "activate" : ""
        let eliminarLinea = eliminarDespues ? "delete notaBetoDicta" : ""
        return """
        tell application id "com.apple.Notes"
            \(activarLinea)
            set cuentaBetoDicta to default account
            set carpetaBetoDicta to default folder of cuentaBetoDicta
            set notaBetoDicta to make new note at carpetaBetoDicta with properties {name:\(literalAppleScript(plan.titulo)), body:\(literalAppleScript(plan.cuerpoHTML))}
            set idBetoDicta to id of notaBetoDicta
            set textoBetoDicta to plaintext of notaBetoDicta
            \(mostrarLinea)
            \(eliminarLinea)
            return idBetoDicta & linefeed & textoBetoDicta
        end tell
        """
    }

    private static func crearSincrono(_ plan: Plan, eliminarDespues: Bool = false,
                                      mostrar: Bool = true) -> ResultadoHerramientaApple {
        var error: NSDictionary?
        let salida = NSAppleScript(source: fuente(plan, eliminarDespues: eliminarDespues,
                                                  mostrar: mostrar))?
            .executeAndReturnError(&error).stringValue
        guard error == nil, let salida else {
            let numero = error?[NSAppleScript.errorNumber] as? Int ?? 0
            let detalle = (error?[NSAppleScript.errorMessage] as? String)
                ?? "Notas rechazó la automatización."
            Log.write("⚠️ Notas de Apple: error \(numero): \(detalle)")
            AgenteLog.registrar("nota_apple", [
                "ok": false, "verificada": false, "error": numero,
                "titulo": plan.titulo, "caracteres": plan.original.count,
            ])
            let permiso = numero == -1743
                ? " Autoriza BetoDicta en Ajustes del Sistema → Privacidad y seguridad → Automatización → Notas."
                : ""
            return .init(ok: false,
                mensaje: "No pude crear la nota automáticamente.\(permiso) Abrí Notas y dejé el texto completo en el portapapeles.")
        }
        let plaintext = salida.components(separatedBy: .newlines).dropFirst()
            .joined(separator: "\n")
        let verificada = contenidoVerificado(plan: plan, plaintext: plaintext)
        AgenteLog.registrar("nota_apple", [
            "ok": verificada, "verificada": verificada,
            "titulo": plan.titulo, "caracteres": plan.original.count,
        ])
        guard verificada else {
            Log.write("⚠️ Notas de Apple: la verificación del contenido no coincidió")
            return .init(ok: false,
                mensaje: "Notas creó un elemento, pero no pude comprobar que contenga todo el texto. El original sigue completo en el portapapeles.")
        }
        return .init(ok: true,
            mensaje: "Creé y verifiqué la nota «\(plan.titulo)» en Notas de Apple.")
    }

    /// Solicita el consentimiento TCC desde el hilo principal, antes de mandar
    /// el trabajo a la cola. Esto evita congelar el notch mientras Notes arranca
    /// y, a la vez, evita que el diálogo inicial se pierda en un callback de fondo.
    private static func permisoAutomatizacion(preguntar: Bool) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
        guard let destino = descriptor.aeDesc else { return OSStatus(paramErr) }
        return AEDeterminePermissionToAutomateTarget(
            destino, typeWildCard, typeWildCard, preguntar)
    }

    static func crear(_ texto: String,
                      completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { crear(texto, completion: completion) }
            return
        }
        guard let plan = preparar(texto) else {
            completion(.init(ok: false, mensaje: "Dime qué quieres guardar en la nota."))
            return
        }
        // Respaldo antes de cualquier Apple Event. Si falta permiso o Notes falla,
        // el usuario conserva exactamente su dictado y puede pegarlo manualmente.
        copyText(plan.original)
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Notes") != nil else {
            completion(.init(ok: false,
                mensaje: "No encontré Notas de Apple. Dejé el texto en el portapapeles."))
            return
        }
        let permiso = permisoAutomatizacion(preguntar: true)
        guard permiso == noErr else {
            AgenteLog.registrar("nota_apple", [
                "ok": false, "verificada": false, "error": Int(permiso),
                "titulo": plan.titulo, "caracteres": plan.original.count,
            ])
            if let app = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Notes") {
                NSWorkspace.shared.openApplication(at: app, configuration: .init(),
                                                   completionHandler: nil)
            }
            completion(.init(ok: false,
                mensaje: "No tengo permiso para crear la nota. Activa BetoDicta en Ajustes del Sistema → Privacidad y seguridad → Automatización → Notas. Abrí Notas y dejé el texto completo en el portapapeles."))
            return
        }
        cola.async {
            let resultado = crearSincrono(plan)
            DispatchQueue.main.async {
                if !resultado.ok, let app = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.apple.Notes") {
                    NSWorkspace.shared.openApplication(at: app, configuration: .init(),
                                                       completionHandler: nil)
                }
                completion(resultado)
            }
        }
    }

    /// Misma ruta de permiso + cola usada por producción, pero elimina el ítem
    /// temporal después de volver a leerlo. Requiere un run loop de AppKit.
    static func probarFlujoReal(completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let muestra = "Nota temporal BetoDicta\n\n- Ruta asíncrona verificada\n- Sin truncar el contenido"
        guard let plan = preparar(muestra) else {
            completion(.init(ok: false, mensaje: "No se pudo preparar la nota QA.")); return
        }
        let permiso = permisoAutomatizacion(preguntar: true)
        guard permiso == noErr else {
            completion(.init(ok: false,
                mensaje: "Automatización de Notas no autorizada (\(permiso)).")); return
        }
        cola.async {
            let resultado = crearSincrono(plan, eliminarDespues: true, mostrar: false)
            DispatchQueue.main.async { completion(resultado) }
        }
    }

    /// `BETODICTA_NOTASAPPLETEST=1`: QA puro, sin abrir Notas.
    /// `BETODICTA_NOTASAPPLETEST=real`: crea, vuelve a leer y elimina una nota QA.
    static func ejecutarPruebaSiSePidio() {
        guard let modo = ProcessInfo.processInfo.environment["BETODICTA_NOTASAPPLETEST"] else {
            return
        }
        let muestra = """
        Minuta segura de BetoDicta

        - Revisar el informe & anexos
        - Confirmar <fecha> con “Alberto”
        """
        guard let plan = preparar(muestra) else {
            print("NOTASAPPLETEST FALLA no se creó el plan"); exit(3)
        }
        let puro = plan.titulo == "Minuta segura de BetoDicta"
            && plan.cuerpo.contains("Revisar el informe & anexos")
            && plan.cuerpoHTML.contains("&amp;")
            && plan.cuerpoHTML.contains("&lt;fecha&gt;")
            && plan.cuerpoHTML.contains("<ul>")
            && contenidoVerificado(plan: plan, plaintext: muestra)
            && contenidoVerificado(plan: plan, plaintext: """
                Minuta segura de BetoDicta

                Revisar el informe & anexos
                Confirmar <fecha> con “Alberto”
                """)
        guard modo.lowercased() == "real" else {
            print("NOTASAPPLETEST \(puro ? "OK" : "FALLA") puro")
            exit(puro ? 0 : 3)
        }
        guard puro else { print("NOTASAPPLETEST FALLA prevalidación"); exit(3) }
        let resultado = crearSincrono(plan, eliminarDespues: true, mostrar: false)
        print("NOTASAPPLETEST \(resultado.ok ? "OK" : "FALLA") real | \(resultado.mensaje)")
        exit(resultado.ok ? 0 : 3)
    }
}

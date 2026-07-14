import Foundation
import Contacts

// MARK: - Contactos para el modo WhatsApp (Fase 5.5)
//
// Resuelve un NOMBRE a un NÚMERO para mandar directo al chat. Cascada:
//   1) lista IMPORTADA por el usuario (CSV/JSON: nombre,numero)
//   2) Contactos de macOS (permiso)
// 0 coincidencias → avisa · 1 → envía directo · 2+ → modal para elegir.

struct ContactoWA: Identifiable {
    let id = UUID()
    let nombre: String
    let numero: String   // solo dígitos y '+'
}

enum ContactosWA {
    private static var archivo: URL { Config.dir.appendingPathComponent("contactos_wa.json") }
    private static func norm(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespaces)
    }
    private static func soloNumero(_ s: String) -> String {
        String(s.filter { $0.isNumber || $0 == "+" })
    }

    // ---- Lista importada ----
    static func importados() -> [ContactoWA] {
        guard let d = try? Data(contentsOf: archivo),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] else { return [] }
        return arr.compactMap {
            let n = $0["nombre"] ?? ""; let num = soloNumero($0["numero"] ?? "")
            return n.isEmpty ? nil : ContactoWA(nombre: n, numero: num)
        }
    }
    private static func guardar(_ cs: [ContactoWA]) {
        Config.asegurarDirSeguro()
        let arr = cs.map { ["nombre": $0.nombre, "numero": $0.numero] }
        if let d = try? JSONSerialization.data(withJSONObject: arr) { try? d.write(to: archivo, options: .atomic) }
    }
    static func vaciar() { try? FileManager.default.removeItem(at: archivo) }

    /// Importa desde CSV (nombre,numero por línea) o JSON ([{nombre,numero}]). Suma a lo existente. Devuelve el total.
    @discardableResult static func importar(_ url: URL) -> Int {
        guard let txt = try? String(contentsOf: url, encoding: .utf8) else { return importados().count }
        var cs = importados()
        if url.pathExtension.lowercased() == "json",
           let arr = try? JSONSerialization.jsonObject(with: Data(txt.utf8)) as? [[String: Any]] {
            for o in arr {
                let n = (o["nombre"] as? String) ?? (o["name"] as? String) ?? ""
                let raw = o["numero"] ?? o["number"] ?? o["telefono"] ?? o["phone"] ?? ""
                let num = soloNumero(String(describing: raw))
                if !n.isEmpty { cs.append(ContactoWA(nombre: n, numero: num)) }
            }
        } else {
            for (i, line) in txt.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).enumerated() {
                let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 2 else { continue }
                if i == 0, norm(parts[0]).contains("nombre") { continue }   // cabecera
                cs.append(ContactoWA(nombre: parts[0], numero: soloNumero(parts[1])))
            }
        }
        var vistos = Set<String>()
        let dedup = cs.filter { !$0.numero.isEmpty && vistos.insert("\(norm($0.nombre))|\($0.numero)").inserted }
        guardar(dedup)
        return dedup.count
    }
    static func plantillaCSV() -> String {
        "nombre,numero\nAlberto Aldás,593999999999\nMaría López,593988888888\n"
    }

    // ---- Contactos de macOS ----
    static func usarMac() -> Bool { Config.waUsarContactosMac() }
    private static func deMac(_ done: @escaping ([ContactoWA]) -> Void) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { ok, _ in
            guard ok else { done([]); return }
            var out: [ContactoWA] = []
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let req = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: req) { c, _ in
                let nombre = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                for p in c.phoneNumbers {
                    let num = soloNumero(p.value.stringValue)
                    if !nombre.isEmpty, !num.isEmpty { out.append(ContactoWA(nombre: nombre, numero: num)) }
                }
            }
            done(out)
        }
    }

    /// Resuelve un nombre a coincidencias (importados + Mac), dedup por número. Callback en MAIN.
    static func resolver(_ nombre: String, _ done: @escaping ([ContactoWA]) -> Void) {
        let n = norm(nombre)
        let base = importados().filter { !n.isEmpty && norm($0.nombre).contains(n) }
        func terminar(_ extra: [ContactoWA]) {
            var vistos = Set<String>()
            let todo = (base + extra).filter { !$0.numero.isEmpty && vistos.insert($0.numero).inserted }
            DispatchQueue.main.async { done(todo) }
        }
        if usarMac() {
            deMac { mac in terminar(mac.filter { !n.isEmpty && norm($0.nombre).contains(n) }) }
        } else {
            terminar([])
        }
    }

    /// Extrae el DESTINATARIO del texto: "a X", "para X", "enviar a X" al inicio.
    /// Devuelve (nombre?, mensaje). Con coma, el nombre es todo hasta la coma
    /// (nombres de 2 palabras); sin coma, el nombre es la 1ª palabra.
    static func objetivo(_ texto: String) -> (nombre: String?, mensaje: String) {
        let t = texto.trimmingCharacters(in: .whitespaces)
        let low = norm(t)
        let prefs = ["enviar a ", "envia a ", "mandar a ", "manda a ", "mandale a ", "escribe a ", "escribele a ", "para ", "a "]
        for pref in prefs where low.hasPrefix(pref) {
            let resto = String(t.dropFirst(pref.count)).trimmingCharacters(in: .whitespaces)
            if let coma = resto.firstIndex(of: ",") {
                let nombre = String(resto[..<coma]).trimmingCharacters(in: .whitespaces)
                let msg = String(resto[resto.index(after: coma)...]).trimmingCharacters(in: .whitespaces)
                return (nombre.isEmpty ? nil : nombre, msg)
            }
            let parts = resto.split(separator: " ", maxSplits: 1).map(String.init)
            let nombre = parts.first ?? ""
            return (nombre.isEmpty ? nil : nombre, parts.count > 1 ? parts[1] : "")
        }
        return (nil, t)
    }

    /// URL de WhatsApp a un número (o sin número para elegir), con failover app→wa.me.
    static func urlEnvio(numero: String?, texto: String, tieneApp: Bool) -> String {
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let enc = texto.addingPercentEncoding(withAllowedCharacters: cs) ?? texto
        let num = soloNumero(numero ?? "")
        if tieneApp {
            return num.isEmpty ? "whatsapp://send?text=\(enc)" : "whatsapp://send?phone=\(num)&text=\(enc)"
        }
        return num.isEmpty ? "https://wa.me/?text=\(enc)" : "https://wa.me/\(num)?text=\(enc)"
    }
}

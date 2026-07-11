import AppKit
import ApplicationServices

// MARK: - Aprendizaje automático de correcciones
//
// La app pega el texto en el campo con foco. Guarda una referencia a ese
// campo (vía Accesibilidad) y su contenido. En el SIGUIENTE dictado relee
// el mismo campo: si tú corregiste una palabra que el motor escribió mal
// (Kipux → Quipux), lo detecta y aprende la regla sola, sin que hagas nada
// extra ni vayas a ninguna pestaña. Todo local.
//
// Solo aprende sustituciones de UNA palabra por otra PARECIDA (error de
// transcripción), nunca reescrituras de frases — así no mete reglas basura.

enum Aprendizaje {
    private static var campo: AXUIElement?     // el campo donde se pegó
    private static var textoTrasPegar: String? // su contenido justo tras pegar

    /// Tras pegar un dictado: recuerda dónde y qué quedó (para comparar luego).
    /// Se llama con un pequeño retraso para que el Cmd+V ya haya aterrizado.
    static func recordarContexto() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard AXIsProcessTrusted() else { return }
            guard let (elem, valor) = campoEnfocadoYValor() else {
                campo = nil; textoTrasPegar = nil; return
            }
            campo = elem
            textoTrasPegar = valor
        }
    }

    /// Al empezar el siguiente dictado: ¿corregiste algo en ese campo?
    /// Devuelve las reglas aprendidas (para avisarte en el panel).
    @discardableResult
    static func revisarCorreccion() -> [(de: String, a: String)] {
        guard AXIsProcessTrusted(), let elem = campo, let antes = textoTrasPegar else { return [] }
        campo = nil; textoTrasPegar = nil          // un solo intento por dictado
        guard let ahora = valorDe(elem), ahora != antes else { return [] }

        let subs = sustituciones(antes: antes, ahora: ahora)
        var aprendidas: [(de: String, a: String)] = []
        for (x, y) in subs where esCorreccionAprendible(de: x, a: y) {
            let xl = limpiar(x), yl = limpiar(y)     // sin comas/puntos de borde
            if agregarRegla(de: xl, a: yl) {
                aprendidas.append((de: xl, a: yl))
                Log.log(.config, "aprendido: \(xl) → \(yl)")
            }
        }
        return aprendidas
    }

    // MARK: Accesibilidad

    private static func campoEnfocadoYValor() -> (AXUIElement, String)? {
        let sistema = AXUIElementCreateSystemWide()
        var focoRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sistema, kAXFocusedUIElementAttribute as CFString, &focoRef) == .success,
              let foco = focoRef, CFGetTypeID(foco) == AXUIElementGetTypeID() else { return nil }
        let elem = foco as! AXUIElement
        guard let valor = valorDe(elem) else { return nil }
        return (elem, valor)
    }

    private static func valorDe(_ elem: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &v) == .success,
              let s = v as? String else { return nil }
        return s
    }

    // MARK: Diff por palabras

    /// Sustituciones (palabra vieja → palabra nueva) entre dos textos, vía LCS.
    private static func sustituciones(antes: String, ahora: String) -> [(String, String)] {
        let a = antes.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        let b = ahora.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard !a.isEmpty, !b.isEmpty, a.count < 400, b.count < 400 else { return [] }

        // Tabla LCS
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        // Recorrer el diff acumulando bloques borrados/insertados
        var i = 0, j = 0
        var borrados: [String] = [], insertados: [String] = []
        var subs: [(String, String)] = []
        func cerrarBloque() {
            // Un bloque de 1 borrado + 1 insertado = sustitución de palabra.
            if borrados.count == 1, insertados.count == 1 {
                subs.append((borrados[0], insertados[0]))
            }
            borrados.removeAll(); insertados.removeAll()
        }
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                cerrarBloque(); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                borrados.append(a[i]); i += 1
            } else {
                insertados.append(b[j]); j += 1
            }
        }
        while i < a.count { borrados.append(a[i]); i += 1 }
        while j < b.count { insertados.append(b[j]); j += 1 }
        cerrarBloque()
        return subs
    }

    /// ¿Vale la pena aprender X→Y? Solo errores de transcripción: una palabra
    /// limpia por otra PARECIDA, no reescrituras ni palabras comunes distintas.
    private static func esCorreccionAprendible(de x0: String, a y0: String) -> Bool {
        let x = limpiar(x0), y = limpiar(y0)
        guard x.count >= 3, y.count >= 2, x.lowercased() != y.lowercased() else { return false }
        guard !x.contains(" "), !y.contains(" ") else { return false }
        // Deben SONAR parecido: distancia de edición baja respecto al largo.
        let d = levenshtein(x.lowercased(), y.lowercased())
        let umbral = max(2, Int(Double(max(x.count, y.count)) * 0.5))
        return d <= umbral
    }

    /// Quita puntuación de los bordes (comas, puntos, comillas…).
    private static func limpiar(_ w: String) -> String {
        w.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces)
            .union(CharacterSet(charactersIn: "«»“”\"'¿?¡!()")))
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }; if t.isEmpty { return s.count }
        var fila = Array(0...t.count)
        for i in 1...s.count {
            var prev = fila[0]; fila[0] = i
            for j in 1...t.count {
                let tmp = fila[j]
                fila[j] = s[i - 1] == t[j - 1] ? prev : min(prev, fila[j], fila[j - 1]) + 1
                prev = tmp
            }
        }
        return fila[t.count]
    }

    // MARK: Guardar la regla aprendida (consolidando variantes)

    private static let lock = NSLock()
    private static var url: URL { Config.dir.appendingPathComponent("reemplazos.json") }

    /// Agrega X→Y a reemplazos.json. Si ya hay una regla cuyo destino es Y,
    /// suma X como variante; si no, crea una regla nueva. Devuelve false si
    /// ya estaba (nada que aprender).
    private static func agregarRegla(de x0: String, a y: String) -> Bool {
        let x = limpiar(x0).lowercased()
        lock.lock(); defer { lock.unlock() }

        var arr = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []

        // ¿Existe ya una regla que produce Y? → sumar variante.
        for idx in arr.indices {
            guard (arr[idx]["isRegex"] as? Bool) != true,
                  (arr[idx]["replacement"] as? String)?.lowercased() == y.lowercased() else { continue }
            let orig = (arr[idx]["original"] as? String) ?? ""
            let variantes = orig.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if variantes.contains(x) || y.lowercased() == x { return false }
            arr[idx]["original"] = orig.isEmpty ? x : orig + ", " + x
            guardar(arr); return true
        }
        // ¿X ya es variante de OTRA regla? (evitar duplicar el error)
        for r in arr where (r["isRegex"] as? Bool) != true {
            let variantes = ((r["original"] as? String) ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if variantes.contains(x) { return false }
        }
        // Regla nueva.
        arr.append(["original": x, "replacement": y, "aprendida": true])
        guardar(arr); return true
    }

    private static func guardar(_ arr: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

import AppKit
import ApplicationServices

// MARK: - Aprendizaje automático de correcciones
//
// El texto dictado es EFÍMERO: en Claude Code (o cualquier chat) lo pegas,
// lo corriges y pulsas Enter — el campo se vacía. Por eso no esperamos al
// siguiente dictado: tras pegar, VIGILAMOS el campo (lo leemos cada medio
// segundo) y capturamos la versión editada final justo antes de que se
// envíe. Ahí comparamos con lo pegado y aprendemos la corrección.
//
// Solo aprende sustituciones de UNA palabra por otra PARECIDA (error de
// transcripción), nunca reescrituras — así no mete reglas basura. No
// vigila si hay traducción activa (el texto pegado no está en español).
//
// Solo vigila campos donde el texto pegado es el contenido PRINCIPAL
// (prompts, chats, mensajes, búsquedas). En documentos largos no aprende
// —para no confundir tu edición con el resto del texto— pero tampoco daña.

enum Aprendizaje {
    private static var campo: AXUIElement?      // el campo donde se pegó
    private static var pegado: String?          // lo que insertó la app
    private static var ultimoEditado: String?   // última versión con contenido
    private static var vigilante: Timer?
    private static var ticks = 0
    private static var generacion = 0           // descarta vigilancias obsoletas
    private static var pendientes: [(de: String, a: String)] = []  // aprendidas por avisar

    /// Tras pegar un dictado (y si no hay traducción activa): arranca el
    /// vigilante que aprenderá de tu corrección en el sitio.
    static func recordarContexto(pegado texto: String, traducido: Bool) {
        detener()
        generacion += 1
        let gen = generacion
        guard !traducido, AXIsProcessTrusted(),
              !texto.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Esperar a que el Cmd+V aterrice, luego enganchar el campo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // Si otro dictado ya reemplazó esta vigilancia, abortar (sin esto
            // quedaban timers huérfanos con dictados en ráfaga).
            guard gen == generacion else { return }
            guard let (elem, valor) = campoEnfocadoYValor() else { return }
            // Solo campos donde lo pegado es el contenido principal (no un
            // documento largo): el valor no debe ser mucho mayor que el texto.
            guard valor.count <= max(400, texto.count * 3) else { return }
            campo = elem
            pegado = texto
            ultimoEditado = valor
            ticks = 0
            vigilante = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in tick() }
        }
    }

    /// Un tick del vigilante: mientras el campo tenga contenido, guarda esa
    /// versión (posiblemente ya corregida). Cuando se vacía/reduce mucho
    /// (enviaste con Enter o borraste), aprende de la última que vimos.
    private static func tick() {
        ticks += 1
        guard let elem = campo, let t = pegado else { detener(); return }
        let v = valorDe(elem) ?? ""
        // "Vivo" = el campo aún tiene el texto (aunque lo hayas corregido o
        // alargado). Por LONGITUD, no por palabras: así una corrección de UNA
        // palabra ("migrotic" → "mikrotik") sí se captura.
        let vivo = !v.isEmpty && v.count >= max(3, t.count / 3)
        if vivo {
            ultimoEditado = v
        } else {
            aprenderDe(ultimoEditado ?? "", pegado: t)
            detener()
        }
        if ticks > 120 {                 // ~60 s de vida máxima del vigilante
            aprenderDe(ultimoEditado ?? "", pegado: t)
            detener()
        }
    }

    private static func detener() {
        vigilante?.invalidate(); vigilante = nil
        campo = nil; pegado = nil; ultimoEditado = nil
    }

    /// Compara el editado final contra lo pegado y guarda las reglas.
    private static func aprenderDe(_ editado: String, pegado t: String) {
        guard !editado.isEmpty, editado != t else { return }
        for (x, y) in sustituciones(antes: t, ahora: editado) where esCorreccionAprendible(de: x, a: y) {
            let xl = limpiar(x), yl = limpiar(y)
            if agregarRegla(de: xl, a: yl) {
                pendientes.append((de: xl, a: yl))
                Log.log(.config, "aprendido: \(xl) → \(yl)")
            }
        }
    }

    /// Al empezar el siguiente dictado: cierra cualquier vigilancia pendiente
    /// y devuelve lo aprendido (para avisarte en el panel).
    @discardableResult
    static func revisarCorreccion() -> [(de: String, a: String)] {
        // Si aún vigilábamos (no enviaste todavía), aprende de lo que haya.
        if let elem = campo, let t = pegado {
            aprenderDe(valorDe(elem) ?? ultimoEditado ?? "", pegado: t)
        }
        detener()
        let avisos = pendientes
        pendientes.removeAll()
        return avisos
    }

    /// Palabras comunes del español: si la palabra "mal transcrita" es una de
    /// estas, NO se aprende — sería una corrección de contenido, no un error
    /// de vocabulario recurrente. Evita reglas venenosas como todo→toco.
    private static let comunes: Set<String> = [
        "que","los","las","del","por","con","una","para","como","más","pero","sus","son",
        "este","esta","esto","estos","estas","ese","esa","eso","esos","esas","aqui","alli","ahi",
        "todo","toda","todos","todas","otro","otra","otros","otras","mismo","misma","cada","poco",
        "poca","mucho","mucha","muchos","muchas","algo","nada","algun","alguna","cual","quien",
        "donde","cuando","cuanto","como","porque","aunque","entonces","tambien","tampoco","siempre",
        "nunca","ahora","antes","despues","luego","hoy","ayer","año","años","dia","dias","vez","veces",
        "dos","tres","cuatro","cinco","seis","siete","ocho","nueve","diez","cien","mil","bien","mal",
        "hola","casa","cosa","cosas","caso","modo","mano","parte","forma","tipo","lado","hora","tiempo",
        "hombre","mujer","gente","vida","mundo","pais","lugar","punto","hecho","tema","nombre","numero",
        "hacer","tener","poder","decir","estar","haber","hacer","saber","poner","venir","ver","dar","ir",
        "quiero","puedo","tengo","hace","dice","cada","sobre","hasta","desde","entre","segun","contra",
        "hola","adios","gracias","favor","claro","cierto","verdad","acaso","apenas","recien","justo",
        "voy","vamos","fue","era","eran","han","hay","muy","tan","asi","aun","solo","sola","según",
    ]

    private static func esComun(_ w: String) -> Bool {
        comunes.contains(w.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es")).lowercased())
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
        // La palabra "mal transcrita" NO puede ser una palabra común válida:
        // si el motor escribió "todo" y lo cambiaste a "toco", es contenido,
        // no un error de vocabulario — aprenderlo corromperia futuros dictados.
        guard !esComun(x) else { return false }
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

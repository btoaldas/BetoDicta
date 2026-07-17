import AppKit

// MARK: - Modo EN VIVO + colores por modo + detección difusa (sin dependencias)
//
// Tres piezas que trabajan juntas:
//   • ColorModo: cada modo tiene SU color en el notch (el usuario puede fijarlo en hex;
//     si no, los modos base tienen paleta fija y los propios un color determinista por
//     id — siempre el mismo). El fondo del notch se TIÑE suave con ese color.
//   • detectarFuzzy: capa de detección SIN dependencias (viaja en el Git): tolera
//     mal-escuchas por distancia de edición ("molde traductor", "moto agente") aunque
//     no haya Ollama/embeddings. Complementa la capa exacta y la semántica.
//   • ModoVivo: mientras HABLAS, evalúa los parciales (preview/streaming); si dices
//     "modo X" al inicio, el notch cambia YA de nombre+color ("te caché") y tú sigues
//     hablando. Solo visual/anticipo: el modo definitivo lo decide el texto final.

enum ColorModo {
    /// Paleta fija de los modos base (distinguibles entre sí y sobre negro).
    private static let base: [String: NSColor] = [
        "dictado":   NSColor(calibratedWhite: 0.55, alpha: 1),
        "correo":    NSColor(calibratedRed: 0.36, green: 0.62, blue: 1.00, alpha: 1),  // azul
        "oficio":    NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.77, alpha: 1),  // teal
        "tarea":     NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.26, alpha: 1),  // naranja
        "nota":      NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.30, alpha: 1),  // amarillo
        "traducir":  NSColor(calibratedRed: 0.42, green: 0.78, blue: 1.00, alpha: 1),  // celeste
        "asistente": NSColor(calibratedRed: 0.62, green: 0.55, blue: 0.95, alpha: 1),  // violeta
        "buscar":    NSColor(calibratedRed: 0.42, green: 0.85, blue: 0.45, alpha: 1),  // verde
        "agente":    NSColor(calibratedRed: 0.93, green: 0.45, blue: 0.85, alpha: 1),  // magenta
    ]
    /// Paleta para modos PROPIOS: color determinista por id (siempre el mismo).
    private static let propios: [NSColor] = [
        NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.80, green: 0.72, blue: 0.45, alpha: 1),
        NSColor(calibratedRed: 0.70, green: 0.90, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.45, alpha: 1),
        NSColor(calibratedRed: 0.60, green: 0.70, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.75, alpha: 1),
        NSColor(calibratedRed: 0.50, green: 0.90, blue: 0.75, alpha: 1),
        NSColor(calibratedRed: 0.85, green: 0.60, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.55, alpha: 1),
    ]

    /// El color del modo: hex del usuario > paleta base > determinista por id.
    static func de(_ modo: Modo) -> NSColor {
        if let c = hex(modo.color) { return c }
        if let c = base[modo.id] { return c }
        // Hash determinista (djb2) del id → mismo color siempre, incluso tras reiniciar.
        var h: UInt64 = 5381
        for b in modo.id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return propios[Int(h % UInt64(propios.count))]
    }

    /// Tinte de FONDO del notch para el modo: el color al `alpha` sobre negro.
    /// Dictado = negro puro (sin tinte). "Distintas intensidades" según el modo.
    static func fondo(_ modo: Modo) -> NSColor {
        guard modo.id != "dictado" else { return .black }
        let c = de(modo).usingColorSpace(.deviceRGB) ?? de(modo)
        let t: CGFloat = 0.16
        return NSColor(calibratedRed: c.redComponent * t, green: c.greenComponent * t,
                       blue: c.blueComponent * t, alpha: 1)
    }

    static func hex(_ s: String) -> NSColor? {
        var h = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    static func aHex(_ c: NSColor) -> String {
        let d = c.usingColorSpace(.deviceRGB) ?? c
        return String(format: "#%02X%02X%02X", Int(d.redComponent * 255),
                      Int(d.greenComponent * 255), Int(d.blueComponent * 255))
    }
}

// MARK: Detección DIFUSA (sin embeddings, sin red — viaja en el Git)

enum ModoFuzzy {
    /// Tolerancia por distancia de edición: "molde traductor"→traducir, "moto agente"→
    /// agente, "modo tradutor"→traducir. Solo al INICIO del texto. Devuelve el modo y
    /// el texto sin la frase disparadora. Más conservador que la capa exacta (que corre
    /// antes): exige parecido fuerte por palabra.
    static func detectar(_ texto: String) -> (Modo, String)? {
        let norm = normalizar(texto)
        let tokens = norm.split(separator: " ").map(String.init)
        guard tokens.count >= 1 else { return nil }
        var mejor: (modo: Modo, frase: [String], score: Double)? = nil
        for m in ModosStore.todos() where m.id != "dictado" {
            var frases = m.palabraVoz.split(separator: ",").map { normalizar(String($0)) }
            frases.append(normalizar("modo \(m.nombre)"))
            for f in frases {
                let fT = f.split(separator: " ").map(String.init)
                guard !fT.isEmpty, fT.count <= tokens.count else { continue }
                var total = 0.0
                var ok = true
                for (i, fw) in fT.enumerated() {
                    let s = similitud(fw, tokens[i])
                    if s < 0.72 { ok = false; break }   // cada palabra debe parecerse fuerte
                    total += s
                }
                guard ok else { continue }
                let score = total / Double(fT.count)
                if score > (mejor?.score ?? 0.84) {     // umbral global alto (conservador)
                    mejor = (m, fT, score)
                }
            }
        }
        guard let mejor else { return nil }
        let resto = tokens.dropFirst(mejor.frase.count).joined(separator: " ")
        // Recorta sobre el texto ORIGINAL contando palabras (mantiene tildes/caso).
        let origTokens = texto.split(separator: " ")
        let limpio = origTokens.count > mejor.frase.count
            ? origTokens.dropFirst(mejor.frase.count).joined(separator: " ")
            : resto
        return (mejor.modo, limpio.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mal-escuchas conocidas de la palabra "modo" (el STT las confunde seguido).
    private static let variantesModo: Set<String> =
        ["modo", "mudo", "molde", "moto", "modho", "moldo", "mode", "modos", "mod", "moro", "moda"]

    /// Similitud 0-1 por distancia de Levenshtein relativa.
    static func similitud(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        // "modo" y sus mal-escuchas cuentan como iguales entre sí.
        if variantesModo.contains(a), variantesModo.contains(b) { return 1 }
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return 0 }
        let aa = Array(a.utf8), bb = Array(b.utf8)
        var prev = Array(0...bb.count)
        var cur = [Int](repeating: 0, count: bb.count + 1)
        for i in 1...aa.count {
            cur[0] = i
            for j in 1...bb.count {
                let cost = aa[i-1] == bb[j-1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            }
            swap(&prev, &cur)
        }
        let d = Double(prev[bb.count])
        return 1.0 - d / Double(max(n, m))
    }
}

// MARK: Modo EN VIVO (mientras hablas)

enum ModoVivo {
    /// Modo detectado en vivo en ESTE dictado (nil = ninguno aún).
    private(set) static var detectado: Modo?
    private static var aviso: ((Modo) -> Void)?

    /// Al empezar un dictado: resetea y registra el callback de cambio (UI).
    static func empezar(onCambio: @escaping (Modo) -> Void) {
        detectado = nil
        aviso = onCambio
    }
    /// Al terminar la grabación se apaga el aviso pero `detectado` SE CONSERVA: deliver()
    /// lo usa como RESPALDO — si el STT final escribió el comando irreconocible, manda lo
    /// que se detectó en vivo (equivale a haber cambiado el modo a mano en el notch).
    /// Lo limpia empezar() del siguiente dictado.
    static func terminar() { aviso = nil }

    /// Evalúa un PARCIAL (barato; corre en cada actualización). Solo mira el INICIO.
    /// Anti-parpadeo: una vez detectado un modo, no se cambia salvo que aparezca OTRO
    /// distinto con match exacto (el texto crece por delante, no se retracta el inicio).
    static func evaluar(_ parcial: String) {
        guard Config.modoVivo(), aviso != nil else { return }
        let inicio = String(parcial.prefix(60))
        var nuevo: Modo?
        if let (m, _) = ModosStore.detectarPorVoz(inicio) { nuevo = m }
        else if detectado == nil, let (m, _) = ModoFuzzy.detectar(inicio) { nuevo = m }
        guard let m = nuevo, m.id != detectado?.id else { return }
        detectado = m
        DispatchQueue.main.async { aviso?(m) }
    }
}

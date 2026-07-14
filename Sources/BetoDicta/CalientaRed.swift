import Foundation

// MARK: - Despierta el túnel VPN/red (evita el "connection lost" del 1er dictado)
//
// WireGuard (y otras VPN) duermen el túnel cuando está inactivo; la 1ª conexión
// saliente tras estar quieto lo despierta, y a veces esa primera se cae → ~13s de
// latencia + reintento. Disparar un HEAD ligero AL EMPEZAR a grabar despierta el
// túnel MIENTRAS hablas, así el pulido/STT al final ya lo encuentra despierto.
// Fire-and-forget; no bloquea nada; con "Connection: close" (conexión fresca).

enum CalientaRed {
    /// Despierta el túnel de red, sea cual sea la VPN (o ninguna). Es solo tráfico
    /// HTTP normal: agnóstico de OpenVPN/WireGuard/PPTP/… y sin VPN es inofensivo.
    /// SIEMPRE fire-and-forget: nunca bloquea ni detiene el dictado, pase lo que pase.
    static func despertar() {
        guard Config.calentarRed() else { return }
        let base = ChatIA.seleccionada()?.base ?? "https://api.groq.com"
        // Si el pulido es LOCAL (localhost) no hay túnel que despertar → no gastes nada.
        guard let u = URL(string: base), let host = u.host?.lowercased(),
              !["localhost", "127.0.0.1", "::1"].contains(host) else { return }
        var r = URLRequest(url: u); r.httpMethod = "HEAD"; r.timeoutInterval = 6
        r.setValue("close", forHTTPHeaderField: "Connection")
        URLSession.shared.dataTask(with: r) { _, _, _ in }.resume()   // resultado ignorado
    }
}

import Foundation

// MARK: - Despierta el túnel VPN/red (evita el "connection lost" del 1er dictado)
//
// WireGuard (y otras VPN) duermen el túnel cuando está inactivo; la 1ª conexión
// saliente tras estar quieto lo despierta, y a veces esa primera se cae → ~13s de
// latencia + reintento. Disparar un HEAD ligero AL EMPEZAR a grabar despierta el
// túnel MIENTRAS hablas, así el pulido/STT al final ya lo encuentra despierto.
// Fire-and-forget; no bloquea nada; con "Connection: close" (conexión fresca).

enum CalientaRed {
    static func despertar() {
        let base = ChatIA.seleccionada()?.base ?? "https://api.groq.com"
        guard let u = URL(string: base) else { return }
        var r = URLRequest(url: u); r.httpMethod = "HEAD"; r.timeoutInterval = 6
        r.setValue("close", forHTTPHeaderField: "Connection")
        URLSession.shared.dataTask(with: r) { _, _, _ in }.resume()
    }
}

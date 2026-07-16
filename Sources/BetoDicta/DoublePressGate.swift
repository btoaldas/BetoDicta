import Foundation

/// Estado mínimo para reconocer una doble pulsación sin temporizadores ni
/// bloquear el hilo del teclado. La primera pulsación completa arma la puerta;
/// la segunda debe empezar dentro de la ventana configurada.
struct DoublePressGate {
    private(set) var primera: Date?

    var armada: Bool { primera != nil }

    mutating func armar(en fecha: Date = Date()) {
        primera = fecha
    }

    /// Consume la primera pulsación solo cuando la segunda llegó a tiempo.
    /// Una marca vencida también se limpia para que no pueda activarse después.
    mutating func consumirSiCorresponde(en fecha: Date = Date(), ventana: TimeInterval) -> Bool {
        guard let primera else { return false }
        self.primera = nil
        let lapso = fecha.timeIntervalSince(primera)
        return lapso >= 0 && lapso <= ventana
    }

    mutating func reiniciar() {
        primera = nil
    }
}

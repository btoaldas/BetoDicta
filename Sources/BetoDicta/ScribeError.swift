import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Errores

enum ScribeError: LocalizedError {
    case sinApiKey, http(Int, String), sinTexto, ws(String)

    var errorDescription: String? {
        switch self {
        case .sinApiKey: return "No encontré ELEVENLABS_API_KEY en ~/.hermes/.env"
        case .http(let code, let body): return "ElevenLabs respondió \(code): \(body.prefix(120))"
        case .sinTexto: return "Respuesta sin texto"
        case .ws(let message): return "Streaming: \(message)"
        }
    }
}


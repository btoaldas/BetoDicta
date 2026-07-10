import Foundation

// MARK: - Catálogo de modelos Whisper locales descargables (whisper.cpp GGML)

struct WhisperModelo: Identifiable {
    var id: String { archivo }
    let nombre: String
    let archivo: String
    let tamañoMB: Int
    let nota: String
    var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(archivo)")! }
    var localURL: URL { WhisperLocal.modelsDir.appendingPathComponent(archivo) }
    var descargado: Bool { FileManager.default.fileExists(atPath: localURL.path) }
}

enum ModelCatalog {
    /// Modelos Whisper que corren en nuestro whisper-cli (GGML). Verificados.
    static let whisper: [WhisperModelo] = [
        WhisperModelo(nombre: "Tiny", archivo: "ggml-tiny.bin", tamañoMB: 74,
                      nota: "El más liviano y rápido · calidad básica"),
        WhisperModelo(nombre: "Base", archivo: "ggml-base.bin", tamañoMB: 141,
                      nota: "Liviano · buen equilibrio para máquinas modestas"),
        WhisperModelo(nombre: "Small", archivo: "ggml-small.bin", tamañoMB: 465,
                      nota: "Calidad media · rápido"),
        WhisperModelo(nombre: "Medium", archivo: "ggml-medium.bin", tamañoMB: 1462,
                      nota: "Buena calidad · más lento"),
        WhisperModelo(nombre: "Large v3 Turbo", archivo: "ggml-large-v3-turbo.bin", tamañoMB: 1549,
                      nota: "La mejor relación calidad/velocidad · recomendado"),
        WhisperModelo(nombre: "Large v3", archivo: "ggml-large-v3.bin", tamañoMB: 3095,
                      nota: "Máxima calidad · pesado y lento"),
    ]
}

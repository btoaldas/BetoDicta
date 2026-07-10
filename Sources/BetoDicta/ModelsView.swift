import AppKit
import SwiftUI

private let acentoM = Color(red: 0.36, green: 0.28, blue: 0.62)

// MARK: - Pestaña Modelos: proveedores, orden, activación, descarga local

final class ProvidersModel: ObservableObject {
    @Published var lista: [Provider] = Providers.load()
    @Published var descargando = false
    @Published var progreso = 0.0
    @Published var estadoLocal = ""

    func guardar() { Providers.save(lista) }

    func toggle(_ id: String) {
        if let i = lista.firstIndex(where: { $0.id == id }) { lista[i].activo.toggle(); guardar() }
    }
    func subir(_ i: Int) {
        guard i > 0 else { return }
        lista.swapAt(i, i - 1); guardar()
    }
    func bajar(_ i: Int) {
        guard i < lista.count - 1 else { return }
        lista.swapAt(i, i + 1); guardar()
    }

    func revisarLocal() {
        estadoLocal = WhisperLocal.disponible
            ? "Listo (modelo + motor presentes)"
            : (WhisperLocal.cliURL == nil ? "Falta el motor whisper-cli"
               : "Falta el modelo — pulsa Descargar")
    }

    /// Descarga el modelo ggml a ~/.betodicta/models/ (autónomo, no se sube al repo).
    func descargarModelo() {
        let src = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!
        try? FileManager.default.createDirectory(at: WhisperLocal.modelsDir, withIntermediateDirectories: true)
        descargando = true; progreso = 0; estadoLocal = "Descargando modelo (~1.5 GB)…"
        Log.log(.ia, "descargando modelo Whisper local")

        let task = URLSession.shared.downloadTask(with: src) { tmp, _, err in
            DispatchQueue.main.async {
                self.descargando = false
                if let tmp, err == nil {
                    try? FileManager.default.removeItem(at: WhisperLocal.modelURL)
                    try? FileManager.default.moveItem(at: tmp, to: WhisperLocal.modelURL)
                    self.estadoLocal = "Modelo descargado ✓"
                    Log.log(.ia, "modelo Whisper descargado")
                } else {
                    self.estadoLocal = "⚠️ Falló la descarga"
                }
                self.revisarLocal()
            }
        }
        obs = task.progress.observe(\.fractionCompleted) { p, _ in
            DispatchQueue.main.async { self.progreso = p.fractionCompleted }
        }
        task.resume()
    }
    private var obs: NSKeyValueObservation?
}

struct ModelsView: View {
    @StateObject private var m = ProvidersModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Modelos y failover", systemImage: "square.stack.3d.up")
                .font(.headline).foregroundStyle(acentoM)
            Text("Se usa el activo #1; si falla, salta al #2, luego al #3. Ordénalos con las flechas.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(Array(m.lista.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(.system(.body, design: .rounded)).bold()
                        .frame(width: 22).foregroundStyle(p.activo ? acentoM : .secondary)
                    Toggle("", isOn: Binding(get: { p.activo }, set: { _ in m.toggle(p.id) }))
                        .toggleStyle(.switch).labelsHidden()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.nombre).font(.subheadline).bold()
                        Text(p.tipo == "nube" ? "☁︎ nube" : "􀙊 local · sin internet")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Button { m.subir(i) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain).disabled(i == 0)
                        Button { m.bajar(i) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.plain).disabled(i == m.lista.count - 1)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Modelo local
            VStack(alignment: .leading, spacing: 8) {
                Label("Whisper local", systemImage: "internaldrive").font(.subheadline).bold()
                Text(m.estadoLocal).font(.caption).foregroundStyle(.secondary)
                if m.descargando {
                    ProgressView(value: m.progreso).tint(acentoM)
                    Text("\(Int(m.progreso * 100)) %").font(.caption2)
                } else if !WhisperLocal.disponible {
                    Button { m.descargarModelo() } label: {
                        Label("Descargar modelo (~1.5 GB)", systemImage: "arrow.down.circle")
                    }
                }
                Text("El modelo se guarda en ~/.betodicta/models/ · nunca se sube al repositorio.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onAppear { m.revisarLocal() }
    }
}

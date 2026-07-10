import AppKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

private let acentoTr = Color(red: 0.36, green: 0.28, blue: 0.62)

/// Reproductor simple para escuchar las grabaciones del historial.
final class AudioPreview: ObservableObject {
    static let shared = AudioPreview()
    @Published var sonando: URL?
    private var player: AVAudioPlayer?
    private var fin: Any?

    func toggle(_ url: URL) {
        if sonando == url { stop(); return }
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        player = p; p.play(); sonando = url
        // Avisar cuando termine para volver el ícono a play
        fin = Timer.scheduledTimer(withTimeInterval: p.duration + 0.1, repeats: false) { [weak self] _ in
            self?.sonando = nil
        }
    }
    func stop() {
        player?.stop(); player = nil; sonando = nil
        if let fin { (fin as? Timer)?.invalidate(); self.fin = nil }
    }
}

// MARK: - Vista Transcribir: subir archivo + re-transcribir del historial

struct TranscribeView: View {
    @State private var estado = ""
    @State private var resultado = ""
    @State private var trabajando = false
    @State private var grabaciones: [Grabacion] = []
    @ObservedObject private var preview = AudioPreview.shared

    struct Grabacion: Identifiable {
        let id = UUID()
        let wav: URL
        let fecha: Date
        var textoPrevio: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Transcribir audio", systemImage: "waveform.badge.magnifyingglass")
                .font(.headline).foregroundStyle(acentoTr)

            // Subir archivo nuevo
            tarjeta("Subir un archivo", "square.and.arrow.up") {
                Text("Elige un audio o video (wav, mp3, m4a, ogg, mp4, mov…) y lo convierte a texto con tu glosario.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    elegirArchivo()
                } label: {
                    Label("Elegir archivo…", systemImage: "folder")
                }.disabled(trabajando)
            }

            // Re-transcribir del historial
            tarjeta("Re-transcribir un dictado", "clock.arrow.circlepath") {
                Text("Vuelve a pasar un audio guardado por la nube (útil si falló antes o si tu glosario mejoró).")
                    .font(.caption).foregroundStyle(.secondary)
                if grabaciones.isEmpty {
                    Text("No hay grabaciones en el historial.").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(grabaciones.prefix(8)) { g in
                        HStack(spacing: 8) {
                            Button {
                                preview.toggle(g.wav)
                            } label: {
                                Image(systemName: preview.sonando == g.wav ? "stop.circle.fill" : "play.circle")
                                    .foregroundStyle(acentoTr)
                            }.buttonStyle(.plain)
                            Text(fecha(g.fecha)).font(.system(.caption, design: .monospaced))
                            Text(g.textoPrevio.isEmpty ? "(sin texto)" : g.textoPrevio)
                                .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                reTranscribir(g.wav)
                            } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.plain).disabled(trabajando)
                        }
                    }
                }
            }

            if trabajando {
                HStack { ProgressView().controlSize(.small); Text(estado).font(.caption) }
            } else if !estado.isEmpty {
                Text(estado).font(.caption).foregroundStyle(.secondary)
            }

            // Resultado
            if !resultado.isEmpty {
                tarjeta("Resultado", "text.quote") {
                    ScrollView { Text(resultado).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 140)
                    HStack {
                        Button { copiar(resultado) } label: { Label("Copiar", systemImage: "doc.on.clipboard") }
                        Button { guardar(resultado) } label: { Label("Guardar…", systemImage: "square.and.arrow.down") }
                    }
                }
            }
        }
        .onAppear { cargarHistorial() }
    }

    // ---- acciones ----
    private func elegirArchivo() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .wav, .mp3]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url else { return }
        Log.log(.ia, "transcribir archivo: \(url.lastPathComponent)")
        procesar(url, etiqueta: "Transcribiendo \(url.lastPathComponent)…")
    }

    private func reTranscribir(_ wav: URL) {
        Log.log(.ia, "re-transcribir: \(wav.lastPathComponent)")
        procesar(wav, etiqueta: "Re-transcribiendo…")
    }

    private func procesar(_ url: URL, etiqueta: String) {
        trabajando = true; estado = etiqueta; resultado = ""
        transcribeFile(url: url, model: Config.model() == "scribe_v2_realtime" ? "scribe_v2" : Config.model()) { r in
            trabajando = false
            switch r {
            case .success(let texto):
                let limpio = applyReplacements(texto)
                resultado = limpio
                estado = "Listo · \(limpio.count) caracteres"
            case .failure(let e):
                estado = "⚠️ \(e.localizedDescription)"
            }
        }
    }

    private func cargarHistorial() {
        let fm = FileManager.default
        var out: [Grabacion] = []
        if let walker = fm.enumerator(at: HistoryWriter.historyDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in walker where url.pathExtension == "wav" {
                let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let txt = url.deletingPathExtension().appendingPathExtension("txt")
                let previo = (try? String(contentsOf: txt, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                out.append(Grabacion(wav: url, fecha: fecha, textoPrevio: previo))
            }
        }
        grabaciones = out.sorted { $0.fecha > $1.fecha }
    }

    private func copiar(_ t: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
        estado = "📋 Copiado"
    }
    private func guardar(_ t: String) {
        let p = NSSavePanel(); p.nameFieldStringValue = "transcripcion.txt"
        if p.runModal() == .OK, let url = p.url { try? t.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func fecha(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"; return f.string(from: d)
    }

    @ViewBuilder
    private func tarjeta<Content: View>(_ titulo: String, _ icono: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo, systemImage: icono).font(.subheadline).bold().foregroundStyle(acentoTr)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

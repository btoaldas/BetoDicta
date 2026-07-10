import AppKit
import SwiftUI

private let acentoH = Color(red: 0.36, green: 0.28, blue: 0.62)

// MARK: - Historial con buscador: todos tus dictados, filtrables al instante

struct EntradaHistorial: Identifiable {
    let id: URL           // el .txt
    let fecha: Date
    let texto: String
    let wav: URL?         // el audio hermano, si existe

    var duracion: String? {
        guard let wav, let attrs = try? FileManager.default.attributesOfItem(atPath: wav.path),
              let bytes = attrs[.size] as? Int, bytes > 44 else { return nil }
        let seg = Double(bytes - 44) / 32000.0
        return seg >= 60 ? String(format: "%.0f min %.0f s", seg / 60, seg.truncatingRemainder(dividingBy: 60))
                         : String(format: "%.0f s", seg)
    }
}

final class HistorialModel: ObservableObject {
    @Published var entradas: [EntradaHistorial] = []
    @Published var cargando = false

    func cargar() {
        cargando = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lista: [EntradaHistorial] = []
            let fm = FileManager.default
            if let en = fm.enumerator(at: HistoryWriter.historyDir,
                                      includingPropertiesForKeys: [.contentModificationDateKey]) {
                for case let url as URL in en where url.pathExtension == "txt" {
                    guard let texto = try? String(contentsOf: url, encoding: .utf8),
                          !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    let wav = url.deletingPathExtension().appendingPathExtension("wav")
                    lista.append(EntradaHistorial(id: url, fecha: fecha, texto: texto,
                                                  wav: fm.fileExists(atPath: wav.path) ? wav : nil))
                }
            }
            lista.sort { $0.fecha > $1.fecha }
            DispatchQueue.main.async {
                self?.entradas = lista
                self?.cargando = false
            }
        }
    }
}

struct HistorialView: View {
    @StateObject private var m = HistorialModel()
    @ObservedObject private var preview = AudioPreview.shared
    @State private var busqueda = ""
    @State private var copiado: URL?

    /// Búsqueda insensible a mayúsculas y tildes ("aldas" encuentra "Aldás").
    private var filtradas: [EntradaHistorial] {
        let q = busqueda.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return m.entradas }
        return m.entradas.filter {
            $0.texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
                .contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Historial de dictados", systemImage: "clock.arrow.circlepath")
                .font(.headline).foregroundStyle(acentoH)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar en todos tus dictados…", text: $busqueda)
                    .textFieldStyle(.plain)
                if !busqueda.isEmpty {
                    Button { busqueda = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if m.cargando {
                ProgressView("Leyendo historial…").frame(maxWidth: .infinity)
            } else if filtradas.isEmpty {
                Text(busqueda.isEmpty ? "Aún no hay dictados guardados."
                                      : "Nada contiene “\(busqueda)”.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 30)
            } else {
                Text("\(filtradas.count) dictado\(filtradas.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filtradas.prefix(300)) { e in
                        fila(e)
                    }
                    if filtradas.count > 300 {
                        Text("Mostrando los 300 más recientes — afina la búsqueda para ver más antiguos.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { m.cargar() }
    }

    private func fila(_ e: EntradaHistorial) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(Self.formatoFecha.string(from: e.fecha))
                    .font(.caption).bold().foregroundStyle(acentoH)
                if let d = e.duracion {
                    Text(d).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let wav = e.wav {
                    Button { preview.toggle(wav) } label: {
                        Image(systemName: preview.sonando == wav ? "stop.circle.fill" : "play.circle")
                            .foregroundStyle(acentoH)
                    }.buttonStyle(.plain).help("Escuchar el audio")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(e.texto, forType: .string)
                    copiado = e.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiado == e.id { copiado = nil }
                    }
                } label: {
                    Image(systemName: copiado == e.id ? "checkmark.circle.fill" : "doc.on.clipboard")
                        .foregroundStyle(copiado == e.id ? .green : acentoH)
                }.buttonStyle(.plain).help("Copiar el texto")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([e.id])
                } label: {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Mostrar en Finder")
            }
            Text(e.texto)
                .font(.callout)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private static let formatoFecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEE d MMM · HH:mm"
        return f
    }()
}

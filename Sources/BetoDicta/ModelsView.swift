import AppKit
import SwiftUI

private let acentoM = Color(red: 0.36, green: 0.28, blue: 0.62)

// MARK: - Pestaña Modelos: activos+orden, catálogo local, config cloud

final class ProvidersModel: ObservableObject {
    @Published var lista: [Provider] = Providers.load()
    @Published var descargas: [String: Double] = [:]     // archivo → progreso 0..1
    @Published var estadoLocal = ""
    private var obs: [String: NSKeyValueObservation] = [:]

    func recargar() { lista = Providers.load() }
    func guardar() { Providers.save(lista) }

    func toggle(_ id: String) {
        if let i = lista.firstIndex(where: { $0.id == id }) { lista[i].activo.toggle(); guardar() }
    }
    func subir(_ i: Int) { guard i > 0 else { return }; lista.swapAt(i, i - 1); guardar() }
    func bajar(_ i: Int) { guard i < lista.count - 1 else { return }; lista.swapAt(i, i + 1); guardar() }

    /// Cambia el modelo/archivo del proveedor local Whisper.
    func usarModeloLocal(_ archivo: String) {
        if let i = lista.firstIndex(where: { $0.id == "whisper_local" }) {
            lista[i].modelo = archivo; lista[i].activo = true; guardar()
        }
        WhisperLocal.modeloArchivo = archivo
        WhisperServer.apagar(motivo: "cambio de modelo local")
        recargar()
    }
    func modeloLocalActual() -> String {
        Providers.modelo(de: "whisper_local") ?? "ggml-large-v3-turbo.bin"
    }

    func descargar(_ m: WhisperModelo) {
        try? FileManager.default.createDirectory(at: WhisperLocal.modelsDir, withIntermediateDirectories: true)
        descargas[m.archivo] = 0.0001
        Log.log(.ia, "descargando modelo \(m.nombre)")
        let task = URLSession.shared.downloadTask(with: m.url) { [weak self] tmp, _, err in
            DispatchQueue.main.async {
                self?.descargas[m.archivo] = nil
                if let tmp, err == nil {
                    try? FileManager.default.removeItem(at: m.localURL)
                    try? FileManager.default.moveItem(at: tmp, to: m.localURL)
                    Log.log(.ia, "modelo \(m.nombre) descargado")
                } else {
                    Log.log(.ia, "descarga \(m.nombre) falló")
                }
                self?.objectWillChange.send()
            }
        }
        obs[m.archivo] = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async { self?.descargas[m.archivo] = p.fractionCompleted }
        }
        task.resume()
    }
    func borrar(_ m: WhisperModelo) {
        try? FileManager.default.removeItem(at: m.localURL)
        Log.log(.ia, "modelo \(m.nombre) borrado")
        objectWillChange.send()
    }
}

struct ModelsView: View {
    @StateObject private var m = ProvidersModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ── Cascada de failover ──
            seccion("Cascada de failover", "arrow.triangle.branch") {
                Text("Se usa el activo #1; si falla, salta al #2, luego al #3. Ordénalos con las flechas.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(m.lista.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.system(.body, design: .rounded)).bold()
                            .frame(width: 20).foregroundStyle(p.activo ? acentoM : .secondary)
                        Toggle("", isOn: Binding(get: { p.activo }, set: { _ in m.toggle(p.id) }))
                            .toggleStyle(.switch).labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.nombre).font(.subheadline).bold()
                            Text("\(p.tipo == "nube" ? "☁︎ nube" : "􀙊 local") · \(p.modelo ?? "")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(spacing: 1) {
                            Button { m.subir(i) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.plain).disabled(i == 0)
                            Button { m.bajar(i) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.plain).disabled(i == m.lista.count - 1)
                        }
                    }
                    .padding(10).background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            // ── Modelos locales (catálogo descargable) ──
            seccion("Modelos locales (Whisper)", "internaldrive") {
                Text("100% offline y gratis. Descarga el que quieras y actívalo como proveedor local.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ModelCatalog.whisper) { modelo in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(modelo.nombre).font(.subheadline).bold()
                                if m.modeloLocalActual() == modelo.archivo {
                                    Text("EN USO").font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(acentoM).foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                            Text("\(modelo.tamañoMB) MB · \(modelo.nota)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let prog = m.descargas[modelo.archivo] {
                            VStack(spacing: 2) {
                                ProgressView(value: prog).frame(width: 60).tint(acentoM)
                                Text("\(Int(prog * 100))%").font(.system(size: 9))
                            }
                        } else if modelo.descargado {
                            Button("Usar") { m.usarModeloLocal(modelo.archivo) }
                                .disabled(m.modeloLocalActual() == modelo.archivo)
                            Button { m.borrar(modelo) } label: { Image(systemName: "trash").foregroundStyle(.red) }
                                .buttonStyle(.plain)
                        } else {
                            Button { m.descargar(modelo) } label: {
                                Image(systemName: "arrow.down.circle").foregroundStyle(acentoM)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(10).background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            // ── Conexión de proveedores cloud (API keys + modelo) ──
            seccion("Proveedores en la nube", "key") {
                Text("Pon tu API key de cada servicio y elige el modelo. Las claves viven solo en tu Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Providers.cloudDisponibles, id: \.id) { c in
                    CloudRow(id: c.id, nombre: c.nombre, modelos: c.modelos, keyEnv: c.keyEnv, onChange: { m.recargar() })
                }
            }
        }
    }

    @ViewBuilder
    private func seccion<C: View>(_ titulo: String, _ icono: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo, systemImage: icono).font(.headline).foregroundStyle(acentoM)
            content()
        }
    }
}

// MARK: - Fila de proveedor cloud (key + modelo)

struct CloudRow: View {
    let id: String
    let nombre: String
    let modelos: [String]
    let keyEnv: String
    let onChange: () -> Void

    @State private var key = ""
    @State private var modelo = ""
    @State private var mostrarKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(nombre).font(.subheadline).bold()
                Spacer()
                Text(key.isEmpty ? "sin clave" : "conectado")
                    .font(.caption2)
                    .foregroundStyle(key.isEmpty ? Color.secondary : Color.green)
            }
            HStack {
                Group {
                    if mostrarKey {
                        TextField("API key…", text: $key)
                    } else {
                        SecureField("API key…", text: $key)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit { ApiKeys.set(keyEnv, key); onChange() }
                Button { mostrarKey.toggle() } label: {
                    Image(systemName: mostrarKey ? "eye.slash" : "eye")
                }.buttonStyle(.plain)
                Button("Guardar") { ApiKeys.set(keyEnv, key); onChange() }
            }
            Picker("Modelo:", selection: $modelo) {
                ForEach(modelos, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: modelo) { _, nuevo in
                var lista = Providers.load()
                if let i = lista.firstIndex(where: { $0.id == id }) {
                    lista[i].modelo = nuevo; Providers.save(lista); onChange()
                }
            }
        }
        .padding(10).background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            key = ApiKeys.get(keyEnv)
            modelo = Providers.modelo(de: id) ?? modelos.first ?? ""
        }
    }
}

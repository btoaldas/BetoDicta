import AppKit
import SwiftUI

// MARK: - Ventana de configuración (SwiftUI vertical, escribe a config.json)

/// Modelo observable que lee y escribe ~/.betodicta/config.json.
/// Cada cambio persiste al instante con Config.set(...).
final class SettingsModel: ObservableObject {
    @Published var tecla: String { didSet { Config.set("tecla", to: tecla) } }
    @Published var modelo: String { didSet { Config.set("modelo", to: modelo) } }
    @Published var silencioMax: Double { didSet { Config.set("silencio_max_seg", to: silencioMax) } }
    @Published var sonidos: Bool { didSet { Config.set("sonidos", to: sonidos) } }
    @Published var escCancela: Bool { didSet { Config.set("esc_cancela", to: escCancela) } }
    @Published var pausarMultimedia: Bool { didSet { Config.set("atenuar_multimedia", to: pausarMultimedia) } }
    @Published var bajarVolumen: Bool { didSet { Config.set("silenciar_ademas", to: bajarVolumen) } }
    @Published var postProceso: Bool { didSet { Config.set("post_proceso", to: postProceso) } }
    @Published var promptPulido: String { didSet { Config.set("prompt_pulido", to: promptPulido) } }
    @Published var panelVisible: Bool { didSet { Config.set("panel_visible", to: panelVisible) } }
    @Published var mostrarEnDock: Bool {
        didSet {
            Config.set("mostrar_en_dock", to: mostrarEnDock)
            NSApp.setActivationPolicy(mostrarEnDock ? .regular : .accessory)
        }
    }
    @Published var modoDesarrollo: Bool { didSet { Config.set("modo_desarrollo", to: modoDesarrollo) } }

    init() {
        tecla = Config.hotkey()
        modelo = Config.model()
        silencioMax = Config.maxSilence()
        sonidos = Config.sounds()
        escCancela = Config.escCancels()
        pausarMultimedia = Config.duckMedia()
        bajarVolumen = Config.muteToo()
        postProceso = Config.postProcess()
        promptPulido = Config.customPrompt() ?? ""
        panelVisible = Config.panelVisible()
        mostrarEnDock = Config.showInDock()
        modoDesarrollo = Config.devMode()
    }
}

private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)  // púrpura sobrio del logo

struct SettingsView: View {
    @StateObject private var m = SettingsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                encabezado

                seccion("General", "gearshape") {
                    fila("Tecla de dictado") {
                        Picker("", selection: $m.tecla) {
                            Text("fn").tag("fn")
                            ForEach(1...12, id: \.self) { Text("F\($0)").tag("F\($0)") }
                        }.labelsHidden().frame(width: 90)
                    }
                    Toggle("Sonidos de inicio y fin", isOn: $m.sonidos)
                    Toggle("Cancelar con Esc", isOn: $m.escCancela)
                    Toggle("Mostrar el panel al dictar", isOn: $m.panelVisible)
                    Toggle("Mostrar en el Dock", isOn: $m.mostrarEnDock)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-cerrar tras \(Int(m.silencioMax)) s de silencio")
                            .font(.subheadline)
                        Slider(value: $m.silencioMax, in: 15...300, step: 15).tint(acento)
                    }
                }

                seccion("Modelo e IA", "waveform") {
                    fila("Modelo") {
                        Picker("", selection: $m.modelo) {
                            Text("Scribe v2 · en vivo").tag("scribe_v2_realtime")
                            Text("Scribe v2 · lotes").tag("scribe_v2")
                            Text("Scribe v1 · barato").tag("scribe_v1")
                        }.labelsHidden().frame(width: 150)
                    }
                    Toggle("Pulir el texto con IA (Groq)", isOn: $m.postProceso)
                    if m.postProceso {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Estilo del pulido (opcional)").font(.subheadline)
                            TextField("ej: trato formal de usted", text: $m.promptPulido, axis: .vertical)
                                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                        }
                    }
                }

                seccion("Multimedia", "speaker.wave.2") {
                    Toggle("Pausar música y videos al dictar", isOn: $m.pausarMultimedia)
                    Toggle("Bajar el volumen al dictar", isOn: $m.bajarVolumen)
                    Text("Al terminar, todo se reanuda y el volumen vuelve exacto.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                seccion("Avanzado", "wrench.and.screwdriver") {
                    Toggle("Modo desarrollo (notas de depuración)", isOn: $m.modoDesarrollo)
                    Text("Glosario e historial se editan desde el menú del ícono.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text("BetoDicta · hecho en Ecuador 🇪🇨")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(width: 380, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var encabezado: some View {
        HStack(spacing: 12) {
            if let logo = NSImage(contentsOfFile:
                Bundle.main.path(forResource: "logo-original", ofType: "png") ?? "") {
                Image(nsImage: logo).resizable().frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("BetoDicta").font(.title2).bold()
                Text("Configuración").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func seccion<Content: View>(_ titulo: String, _ icono: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo, systemImage: icono)
                .font(.headline).foregroundStyle(acento)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func fila<Trailing: View>(_ label: String,
                                      @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
            Spacer()
            trailing()
        }
    }
}

// MARK: - Contenedor de ventana (una sola instancia)

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "BetoDicta"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

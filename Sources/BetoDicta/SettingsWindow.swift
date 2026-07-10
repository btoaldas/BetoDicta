import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

extension Notification.Name {
    static let betoHotkeyChanged = Notification.Name("BetoDictaHotkeyChanged")
}

private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)  // púrpura sobrio del logo

// MARK: - Modelo observable (lee/escribe ~/.betodicta/config.json)

final class SettingsModel: ObservableObject {
    @Published var tecla: String {
        didSet {
            Config.set("tecla", to: tecla)
            NotificationCenter.default.post(name: .betoHotkeyChanged, object: nil)
        }
    }
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
    @Published var arrancarInicio: Bool {
        didSet {
            let s = SMAppService.mainApp
            if arrancarInicio { try? s.register() } else { try? s.unregister() }
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
        arrancarInicio = SMAppService.mainApp.status == .enabled
        modoDesarrollo = Config.devMode()
    }
}

// MARK: - Grabador de atajo (captura tecla + modificadores)

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var value: String

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.onCapture = { value = $0 }
        return b
    }
    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.display(value)
    }

    final class RecorderButton: NSButton {
        var onCapture: ((String) -> Void)?
        private var recording = false
        private var monitor: Any?
        private var timeout: Timer?
        private var previo = Config.hotkey()

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(startRecording)
            display(Config.hotkey())
        }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        deinit { stop() }

        func display(_ v: String) {
            if !recording { title = pretty(v) + "  ✎" }
        }
        private func pretty(_ v: String) -> String {
            v.split(separator: "+").map { p -> String in
                switch p.lowercased() {
                case "cmd", "command": return "⌘"
                case "ctrl", "control": return "⌃"
                case "opt", "alt", "option": return "⌥"
                case "shift": return "⇧"
                case "fn": return "fn"
                case "space": return "␣"
                default: return p.uppercased()
                }
            }.joined(separator: "")
        }

        @objc private func startRecording() {
            guard !recording else { return }
            recording = true
            previo = Config.hotkey()
            title = "Pulsa… (Esc cancela)"
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                self?.handle(event)
                return nil  // consume solo mientras grabamos
            }
            // Auto-cancelar tras 5s para no dejar el teclado atrapado
            timeout = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                self?.cancel()
            }
        }

        private func stop() {
            timeout?.invalidate(); timeout = nil
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            recording = false
        }

        private func cancel() {
            stop()
            display(previo)  // restaura lo que había, no cambia nada
        }

        private func finish(_ combo: String) {
            stop()
            onCapture?(combo)
            display(combo)
        }

        private func mods(_ f: NSEvent.ModifierFlags) -> [String] {
            var p: [String] = []
            if f.contains(.control) { p.append("ctrl") }
            if f.contains(.option) { p.append("opt") }
            if f.contains(.command) { p.append("cmd") }
            if f.contains(.shift) { p.append("shift") }
            return p
        }

        /// Atajos prohibidos: colisionan con el sistema o con la app.
        private static let prohibidos: Set<String> = [
            "cmd+v", "cmd+c", "cmd+x", "cmd+a", "cmd+z", "cmd+q", "cmd+w",
            "cmd+s", "cmd+tab", "cmd+space", "space",
        ]

        private var maxModsVistos: [String] = []
        private var vioFn = false

        private func handle(_ event: NSEvent) {
            guard recording else { return }

            if event.type == .keyDown {
                if event.keyCode == 53 { cancel(); return }  // Esc cancela
                guard let key = AppDelegate.keyName(for: Int(event.keyCode)) else { return }
                let m = mods(event.modifierFlags)
                let esFuncion = key.hasPrefix("f") && key.count <= 3
                // Letra/espacio sin modificador no es atajo global; F1..F12 sí.
                guard esFuncion || !m.isEmpty else {
                    title = "Añade ⌘/⌃/⌥ a esa tecla"
                    return
                }
                let combo = (m + [key]).joined(separator: "+")
                guard !Self.prohibidos.contains(combo) else {
                    title = "Ese atajo está reservado"; return
                }
                finish(combo)   // tecla+modificadores (ej. cmd+shift+d)

            } else if event.type == .flagsChanged {
                let f = event.modifierFlags
                let m = mods(f)
                if f.contains(.function) { vioFn = true }
                if m.count > maxModsVistos.count { maxModsVistos = m }
                // Al SOLTAR todo sin haber pulsado una tecla → capturar el combo
                // de puros modificadores (o fn) que se mantuvo.
                if m.isEmpty && !f.contains(.function) {
                    if maxModsVistos.count >= 2 {
                        finish(maxModsVistos.prefix(2).joined(separator: "+"))
                    } else if vioFn {
                        finish("fn")
                    }
                    maxModsVistos = []; vioFn = false
                }
            }
        }
    }
}

// MARK: - Vista principal

struct SettingsView: View {
    @StateObject private var m = SettingsModel()
    @State private var seccion = "Ajustes"

    var body: some View {
        VStack(spacing: 0) {
            encabezado
            Picker("", selection: $seccion) {
                Text("Ajustes").tag("Ajustes")
                Text("Acciones").tag("Acciones")
                Text("Estadísticas").tag("Estadísticas")
                Text("Créditos").tag("Créditos")
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch seccion {
                    case "Acciones": acciones
                    case "Estadísticas": StatsView()
                    case "Créditos": creditos
                    default: ajustes
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 400, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var encabezado: some View {
        HStack(spacing: 12) {
            if let logo = NSImage(contentsOfFile:
                Bundle.main.path(forResource: "logo-original", ofType: "png") ?? "") {
                Image(nsImage: logo).resizable().frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("BetoDicta").font(.title2).bold()
                Text("Dictado por voz").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    // ---- Ajustes ----
    private var ajustes: some View {
        Group {
            tarjeta("General", "gearshape") {
                fila("Tecla de dictado") {
                    HotkeyRecorder(value: $m.tecla).frame(width: 120, height: 24)
                }
                Toggle("Sonidos de inicio y fin", isOn: $m.sonidos)
                Toggle("Cancelar con Esc", isOn: $m.escCancela)
                Toggle("Mostrar el panel al dictar", isOn: $m.panelVisible)
                Toggle("Mostrar en el Dock", isOn: $m.mostrarEnDock)
                Toggle("Arrancar al iniciar sesión", isOn: $m.arrancarInicio)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-cerrar tras \(Int(m.silencioMax)) s de silencio").font(.subheadline)
                    Slider(value: $m.silencioMax, in: 15...300, step: 15).tint(acento)
                }
            }
            tarjeta("Modelo e IA", "waveform") {
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
            tarjeta("Multimedia", "speaker.wave.2") {
                Toggle("Pausar música y videos al dictar", isOn: $m.pausarMultimedia)
                Toggle("Bajar el volumen al dictar", isOn: $m.bajarVolumen)
                Text("Al terminar, todo se reanuda y el volumen vuelve exacto.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Avanzado", "wrench.and.screwdriver") {
                Toggle("Modo desarrollo (notas de depuración)", isOn: $m.modoDesarrollo)
            }
        }
    }

    // ---- Acciones ----
    private var acciones: some View {
        Group {
            tarjeta("Glosario", "text.book.closed") {
                boton("Editar palabras del glosario", "pencil") { EditorWindows.showKeyterms() }
                boton("Editar reemplazos", "arrow.left.arrow.right") { EditorWindows.showRules() }
            }
            tarjeta("Dictados", "doc.text") {
                boton("Copiar último dictado", "doc.on.clipboard") { AppActions.copyLast() }
                boton("Exportar dictados de hoy", "square.and.arrow.up") { AppActions.exportToday() }
                boton("Abrir historial", "folder") { AppActions.openHistory() }
            }
            tarjeta("Diagnóstico", "stethoscope") {
                boton("Ver registro (log)", "doc.plaintext") { AppActions.openLog() }
            }
        }
    }

    // ---- Créditos ----
    private var creditos: some View {
        VStack(alignment: .leading, spacing: 16) {
            tarjeta("BetoDicta", "mic") {
                Text("Dictado por voz para macOS, hecho en Ecuador 🇪🇨 para el español latino.")
                    .font(.subheadline)
                link("Repositorio en GitHub", "https://github.com/btoaldas/BetoDicta")
                Text("Licencia GPL-3.0 · libre para siempre").font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Créditos", "heart") {
                Text("Creado por Alberto Aldás en compañía de Claude (Anthropic), programado a pura voz.")
                    .font(.subheadline)
                link("Handy — inspiración open source", "https://github.com/cjpais/Handy")
                link("mediaremote-adapter — pausa de multimedia", "https://github.com/ungive/mediaremote-adapter")
                link("ElevenLabs Scribe — transcripción", "https://elevenlabs.io")
            }
        }
    }

    // ---- helpers de UI ----
    @ViewBuilder
    private func tarjeta<Content: View>(_ titulo: String, _ icono: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo, systemImage: icono).font(.headline).foregroundStyle(acento)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    private func fila<T: View>(_ label: String, @ViewBuilder _ trailing: () -> T) -> some View {
        HStack { Text(label); Spacer(); trailing() }
    }
    private func boton(_ titulo: String, _ icono: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: icono).frame(width: 20); Text(titulo); Spacer() }
        }.buttonStyle(.plain)
    }
    private func link(_ titulo: String, _ url: String) -> some View {
        Button(action: { NSWorkspace.shared.open(URL(string: url)!) }) {
            HStack(spacing: 6) { Image(systemName: "arrow.up.right.square"); Text(titulo) }
                .foregroundStyle(acento)
        }.buttonStyle(.plain)
    }
    private func open(_ file: String) {
        NSWorkspace.shared.open(Config.dir.appendingPathComponent(file))
    }
}

// MARK: - Estadísticas (odómetro con barras)

struct StatsView: View {
    private let t = UsageLog.totales()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Uso de dictado", systemImage: "chart.bar.xaxis").font(.headline).foregroundStyle(acento)

            // KPIs
            HStack(spacing: 10) {
                kpi("Hoy", fmt(t.hoyMin), "mic.fill")
                kpi("Semana", fmt(t.semanaMin), "calendar")
                kpi("Mes", fmt(t.mesMin), "calendar.badge.clock")
            }
            HStack(spacing: 10) {
                kpi("Dictados hoy", "\(t.dictadosHoy)", "waveform")
                kpi("Costo del mes", String(format: "$%.2f", t.mesCosto), "dollarsign.circle")
                kpi("Total año", fmt(t.añoMin), "star.fill")
            }

            // Gráfica de barras: últimos 7 días
            VStack(alignment: .leading, spacing: 8) {
                Text("Últimos 7 días").font(.subheadline).bold()
                barras
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Costo estimado según la tarifa por hora de audio de ElevenLabs.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var barras: some View {
        let maxV = max(t.porDiaSemana.max() ?? 1, 0.1)
        let dias = diasEtiquetas()
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(t.porDiaSemana[i] >= 0.05 ? String(format: "%.0f", t.porDiaSemana[i]) : "")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(acento.opacity(i == 6 ? 1 : 0.55))
                        .frame(height: max(4, CGFloat(t.porDiaSemana[i] / maxV) * 90))
                    Text(dias[i]).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 130)
    }

    private func kpi(_ titulo: String, _ valor: String, _ icono: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icono).foregroundStyle(acento)
            Text(valor).font(.system(.title3, design: .rounded)).bold()
            Text(titulo).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func fmt(_ min: Double) -> String {
        if min >= 60 { return String(format: "%.1f h", min / 60) }
        return String(format: "%.0f min", min)
    }
    private func diasEtiquetas() -> [String] {
        let f = DateFormatter(); f.locale = Locale(identifier: "es"); f.dateFormat = "EEEEE"
        let cal = Calendar.current
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: -(6 - i), to: Date())!
            return f.string(from: d).uppercased()
        }
    }
}

// MARK: - Puente a las acciones del AppDelegate

enum AppActions {
    static var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }
    static func copyLast() { delegate?.copyLastDictationPublic() }
    static func exportToday() { delegate?.exportTodayPublic() }
    static func openHistory() { delegate?.openHistoryPublic() }
    static func openLog() { delegate?.openLogPublic() }
}

// MARK: - Ventana

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

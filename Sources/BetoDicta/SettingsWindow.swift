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
    @Published var microfono: String { didSet { Config.set("microfono", to: microfono) } }
    @Published var aprender: Bool { didSet { Config.set("aprender_correcciones", to: aprender) } }
    @Published var porSonido: Bool { didSet { Config.set("correccion_por_sonido", to: porSonido) } }
    @Published var atajoAprender: String {
        didSet {
            Config.set("atajo_aprender", to: atajoAprender)
            NotificationCenter.default.post(name: .betoHotkeyChanged, object: nil)
        }
    }
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
        microfono = Config.microfono()
        aprender = Config.aprender()
        atajoAprender = Config.atajoAprender()
        porSonido = Config.correccionPorSonido()
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
        private var previo = "fn"   // último valor mostrado (para cancelar)

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(startRecording)
        }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        deinit { stop() }

        func display(_ v: String) {
            if !recording { title = pretty(v) + "  ✎"; previo = v }
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
            title = "Pulsa… (Esc cancela)"   // previo ya tiene el valor actual
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

// MARK: - Vista principal (sidebar + detalle, escala a más secciones)

/// Secciones de la ventana. Para sumar una nueva: agregar el caso aquí y su
/// vista en `detalle` — el sidebar crece solo, sin apretar nada.
private enum Seccion: String, CaseIterable, Identifiable {
    case ajustes = "Ajustes"
    case modelos = "Modelos"
    case historial = "Historial"
    case acciones = "Acciones"
    case transcribir = "Transcribir"
    case estadisticas = "Estadísticas"
    case creditos = "Créditos"

    var id: String { rawValue }
    var icono: String {
        switch self {
        case .ajustes: return "gearshape.fill"
        case .modelos: return "cpu.fill"
        case .historial: return "clock.arrow.circlepath"
        case .acciones: return "bolt.fill"
        case .transcribir: return "waveform.badge.mic"
        case .estadisticas: return "chart.bar.fill"
        case .creditos: return "heart.fill"
        }
    }
}

struct SettingsView: View {
    @StateObject private var m = SettingsModel()
    @State private var seccion: Seccion

    init() {
        // Pruebas de UI: BETODICTA_SECCION=Modelos abre esa sección directo.
        let pedida = ProcessInfo.processInfo.environment["BETODICTA_SECCION"] ?? ""
        _seccion = State(initialValue: Seccion(rawValue: pedida) ?? .ajustes)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detalle
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, idealWidth: 760, maxWidth: .infinity,
               minHeight: 560, idealHeight: 640, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detalle: some View {
        switch seccion {
        case .modelos: ModelsView()
        case .historial: HistorialView()
        case .acciones: acciones
        case .transcribir: TranscribeView()
        case .estadisticas: StatsView()
        case .creditos: creditos
        case .ajustes: ajustes
        }
    }

    // ---- Sidebar ----
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            encabezado
            ForEach(Seccion.allCases) { s in
                Button { seccion = s } label: {
                    HStack(spacing: 9) {
                        Image(systemName: s.icono)
                            .font(.system(size: 13))
                            .frame(width: 22)
                            .foregroundStyle(seccion == s ? .white : acento)
                        Text(s.rawValue)
                            .font(.system(size: 13, weight: seccion == s ? .semibold : .regular))
                            .foregroundStyle(seccion == s ? .white : .primary)
                        Spacer()
                    }
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .background(seccion == s ? acento : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            }
            Spacer()
            pieActualizacion
        }
        .frame(width: 190)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // ---- Pie del sidebar: versión + actualización con un clic ----
    @State private var estadoUpdate: Updater.Estado = .reposo

    private var pieActualizacion: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("v\(Version.numero)")
                .font(.caption2).foregroundStyle(.tertiary)
            switch estadoUpdate {
            case .reposo:
                Button("Verificar actualización") {
                    estadoUpdate = .buscando
                    Updater.verificar { estadoUpdate = $0 }
                }
                .buttonStyle(.plain).font(.caption2).foregroundStyle(acento)
            case .buscando:
                Label("Buscando…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2).foregroundStyle(.secondary)
            case .alDia:
                Label("Ya estás en la última versión", systemImage: "checkmark.circle.fill")
                    .font(.caption2).foregroundStyle(.green)
            case .disponible(let v, let dmg):
                Button {
                    estadoUpdate = .descargando
                    Updater.actualizar(dmg: dmg) { estadoUpdate = $0 }
                } label: {
                    Label("Actualizar a v\(v)", systemImage: "arrow.down.circle.fill")
                        .font(.caption2).bold()
                }
                .buttonStyle(.borderedProminent).tint(acento).controlSize(.small)
            case .descargando:
                Label("Descargando… se reiniciará sola", systemImage: "arrow.down.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            case .error(let msg):
                Button {
                    estadoUpdate = .buscando
                    Updater.verificar { estadoUpdate = $0 }
                } label: {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private var encabezado: some View {
        HStack(spacing: 10) {
            if let logo = NSImage(contentsOfFile:
                Bundle.main.path(forResource: "logo-original", ofType: "png") ?? "") {
                Image(nsImage: logo).resizable().frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("BetoDicta").font(.headline).bold()
                Text("Dictado por voz").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
    }

    // ---- Ajustes ----
    private var ajustes: some View {
        Group {
            tarjeta("General", "gearshape") {
                fila("Tecla de dictado") {
                    HotkeyRecorder(value: $m.tecla).frame(width: 120, height: 24)
                }
                fila("Micrófono") {
                    Picker("", selection: $m.microfono) {
                        Text("Integrado del Mac (recomendado)").tag("")
                        Text("Automático (el del sistema)").tag("auto")
                        ForEach(Microfono.disponibles().filter { !$0.integrado }) { d in
                            Text(d.nombre).tag(d.uid)
                        }
                    }.labelsHidden().frame(width: 230)
                }
                Text("Fijo al integrado, el iPhone cercano ya no roba el micrófono a media grabación.")
                    .font(.caption).foregroundStyle(.secondary)
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
            tarjeta("Pulido con IA", "waveform") {
                Toggle("Pulir el texto con IA (Groq)", isOn: $m.postProceso)
                if m.postProceso {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estilo del pulido (opcional)").font(.subheadline)
                        TextField("ej: trato formal de usted", text: $m.promptPulido, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    }
                }
                Text("Los modelos y proveedores se configuran en la pestaña Modelos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Aprendizaje", "brain.head.profile") {
                Toggle("Aprender de mis correcciones", isOn: $m.aprender)
                Text("Cuando corriges el texto dictado ahí donde lo pegaste (antes de enviarlo), la app aprende la regla sola (ej: Kipux → Quipux). 100% local.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("• Automático en apps nativas (Notas, Mail, Word, Pages…).")
                    .font(.caption).foregroundStyle(.secondary)
                fila("Atajo: aprender de la selección") {
                    HotkeyRecorder(value: $m.atajoAprender).frame(width: 120, height: 24)
                }
                Text("• En Claude Code CLI, terminales o cualquier app: corrige, SELECCIONA el texto corregido y pulsa este atajo — aprende de tu selección.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("Corrección por sonido (fonética)", isOn: $m.porSonido)
                Text("Corrige palabras que SUENAN como un término, aunque no sea una variante ya conocida (ej: cualquier cosa que suene a Quipux). Actívala por término en Editar reemplazos (casilla 🔊). Más potente pero puede sobre-corregir: revisa lo que hizo en Estadísticas (con Modo desarrollo) y revierte apagando el término.")
                    .font(.caption).foregroundStyle(.secondary)
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
                HStack(spacing: 8) {
                    Text("Versión \(Version.numero)").font(.subheadline).bold()
                    Text(Version.fecha).font(.caption).foregroundStyle(.secondary)
                }
                Text("Dictado por voz para macOS, hecho en Ecuador 🇪🇨 para el español latino.")
                    .font(.subheadline)
                link("Página oficial — betodicta.eztic.ec", "https://betodicta.eztic.ec/")
                link("Repositorio en GitHub", "https://github.com/btoaldas/BetoDicta")
                Text("Licencia GPL-3.0 · libre para siempre").font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Apoya el proyecto ☕", "cup.and.saucer.fill") {
                Text("BetoDicta es gratis y libre. Si te sirve, invítame un cafecito para seguir programando (y pagar la IA que ayuda a construirlo). Cualquier aporte suma.")
                    .font(.subheadline)
                link("☕ Invítame un café (tarjeta · Apple Pay · Google Pay)", "https://betodicta.eztic.ec/apoyar")
                link("💜 GitHub Sponsors", "https://github.com/sponsors/btoaldas")
                link("💳 PayPal", "https://betodicta.eztic.ec/apoyar")
                Text("Más formas (transferencia, cripto, etc.) en la página de apoyo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Ayuda", "questionmark.circle") {
                link("Manual de usuario completo", "https://github.com/btoaldas/BetoDicta/blob/main/docs/MANUAL.md")
                Text("Instalación, cada pestaña, cada motor, cada ajuste — todo explicado con capturas.")
                    .font(.caption).foregroundStyle(.secondary)
                link("Reportar un problema", "https://github.com/btoaldas/BetoDicta/issues/new")
                Text("Se abre el formulario en GitHub: cuenta qué hiciste, qué esperabas y qué pasó.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Historial de versiones", "clock.arrow.circlepath") {
                ForEach(Version.historial, id: \.version) { v in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("v\(v.version)").font(.caption).bold().foregroundStyle(acento)
                            Text(v.fecha).font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(v.cambios, id: \.self) { c in
                            Text("· \(c)").font(.caption).foregroundStyle(.primary.opacity(0.85))
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            tarjeta("Créditos", "heart") {
                Text("Creado por Alberto Aldás en compañía de Claude (Anthropic), programado a pura voz.")
                    .font(.subheadline)
                link("Handy — inspiración open source", "https://github.com/cjpais/Handy")
                link("transcribe.cpp — motor de modelos streaming", "https://github.com/handy-computer/transcribe.cpp")
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

            Text(UsageLog.referenciaPrecios)
                .font(.caption).foregroundStyle(.secondary)

            // Bitácora de aprendizajes — solo con Modo desarrollo activo.
            if Config.devMode() {
                AprendizajesDebugView()
            }
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

// MARK: - Bitácora de aprendizajes con reversión (debug)

private let acentoStats = Color(red: 0.36, green: 0.28, blue: 0.62)

struct AprendizajesDebugView: View {
    @State private var entradas: [(fecha: Date, de: String, a: String, sonido: Bool)] = []
    private let f: DateFormatter = { let d = DateFormatter(); d.locale = Locale(identifier: "es"); d.dateFormat = "HH:mm:ss"; return d }()

    var body: some View {
        let unDia = Date().addingTimeInterval(-86400)
        let recientes = entradas.filter { $0.fecha >= unDia }
        VStack(alignment: .leading, spacing: 8) {
            Label("Aprendizaje (debug)", systemImage: "brain.head.profile")
                .font(.subheadline).bold().foregroundStyle(acentoStats)
            if !Config.aprender() {
                Text("El aprendizaje está APAGADO (Ajustes → Aprendizaje). No aprenderá nada hasta activarlo.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if recientes.isEmpty {
                Text("Nada aprendido en las últimas 24 h. Corrige una palabra rara donde la pegaste (antes de enviar) y vuelve a dictar.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(recientes.count) corrección(es) hoy (🔊 = por sonido). Quita la que no quieras:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(recientes.enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 8) {
                        Text(f.string(from: e.fecha)).font(.caption2).foregroundStyle(.tertiary)
                        Text("\(e.sonido ? "🔊 " : "")\(e.de) → \(e.a)").font(.caption).bold()
                        Spacer()
                        Button {
                            Aprendizaje.revertir(de: e.de, a: e.a)
                            entradas = Aprendizaje.historial()
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.red)
                        }.buttonStyle(.plain).help("Deshacer este aprendizaje")
                    }
                }
            }
            Text("Total histórico: \(entradas.count) reglas aprendidas.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { entradas = Aprendizaje.historial() }
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
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 760, height: 640))
            w.minSize = NSSize(width: 720, height: 560)
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

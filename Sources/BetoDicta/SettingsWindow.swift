import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

extension Notification.Name {
    static let betoHotkeyChanged = Notification.Name("BetoDictaHotkeyChanged")
}

private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)  // púrpura sobrio del logo

// MARK: - Sección plegable cuyo TÍTULO completo (no solo la flechita) abre/cierra

struct SeccionPlegable<Content: View>: View {
    let titulo: String
    var icono: String?
    @State private var abierto: Bool
    let content: () -> Content

    init(_ titulo: String, icono: String? = nil, abierto: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.titulo = titulo; self.icono = icono; self.content = content
        _abierto = State(initialValue: abierto)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { abierto.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: abierto ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 12)
                    if let icono { Image(systemName: icono).foregroundStyle(acento) }
                    Text(titulo).font(.headline).foregroundStyle(acento)
                    Spacer()
                }.contentShape(Rectangle())   // toda la fila es clicable
            }.buttonStyle(.plain)
            if abierto { content() }
        }
    }
}

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
    @Published var pulidoProveedor: String { didSet { Config.set("pulido_proveedor", to: pulidoProveedor) } }
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
    @Published var pulidoTimeout: Double { didSet { Config.set("pulido_timeout_seg", to: pulidoTimeout) } }
    @Published var buscarUpdateAlAbrir: Bool { didSet { Config.set("buscar_update_al_abrir", to: buscarUpdateAlAbrir) } }
    @Published var autoactualizar: Bool { didSet { Config.set("autoactualizar", to: autoactualizar) } }
    @Published var avisoNube: Bool { didSet { Config.set("aviso_privacidad_nube", to: avisoNube) } }
    @Published var salvaguardaInyeccion: Bool { didSet { Config.set("salvaguarda_inyeccion", to: salvaguardaInyeccion) } }
    @Published var sttStreaming: Bool { didSet { Config.set("stt_streaming", to: sttStreaming) } }
    @Published var pushToTalk: Bool { didSet { Config.set("hold_para_hablar", to: pushToTalk) } }
    @Published var espacioAlTerminar: Bool { didSet { Config.set("espacio_al_terminar", to: espacioAlTerminar) } }
    @Published var enterAlTerminar: Bool {
        didSet { Config.set("enter_al_terminar", to: enterAlTerminar); if enterAlTerminar { shiftEnterAlTerminar = false } }
    }
    @Published var shiftEnterAlTerminar: Bool {
        didSet { Config.set("shift_enter_al_terminar", to: shiftEnterAlTerminar); if shiftEnterAlTerminar { enterAlTerminar = false } }
    }

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
        pulidoProveedor = Config.pulidoProveedor()
        promptPulido = Config.customPrompt() ?? ""
        panelVisible = Config.panelVisible()
        mostrarEnDock = Config.showInDock()
        arrancarInicio = SMAppService.mainApp.status == .enabled
        modoDesarrollo = Config.devMode()
        pulidoTimeout = Config.pulidoTimeout()
        buscarUpdateAlAbrir = Config.buscarUpdateAlAbrir()
        autoactualizar = Config.autoactualizar()
        avisoNube = Config.avisoNube()
        salvaguardaInyeccion = Config.salvaguardaInyeccion()
        sttStreaming = Config.sttStreaming()
        pushToTalk = Config.pushToTalk()
        espacioAlTerminar = Config.espacioAlTerminar()
        enterAlTerminar = Config.enterAlTerminar()
        shiftEnterAlTerminar = Config.shiftEnterAlTerminar()
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

/// Navegación programática a una sección (p. ej. desde el modal de novedades).
final class NavAjustes: ObservableObject {
    static let shared = NavAjustes()
    @Published var ir: String?
}

struct SettingsView: View {
    @StateObject private var m = SettingsModel()
    @ObservedObject private var nav = NavAjustes.shared
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
        .onChange(of: nav.ir) { _, v in
            if let v, let s = Seccion(rawValue: v) { seccion = s; nav.ir = nil }
        }
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
    @State private var estadoUpdate: Updater.Estado = Updater.disponibleAlArrancar ?? .reposo
    @State private var mostrarNotas = false
    @State private var keyInputs: [String: String] = [:]
    @State private var detectTrigger = 0
    @State private var descubriendoMod = false
    @State private var msgMod: String?
    @State private var msgModId: String?
    @State private var msgModOK = false
    @State private var buscandoLocales = false
    @State private var buscoLocales = false
    @State private var precioIn = ""
    @State private var precioOut = ""

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
                // Clicable: permite volver a verificar aunque el auto-check haya
                // dado "al día" (si no, .onAppear solo re-verifica desde .reposo).
                Button {
                    estadoUpdate = .buscando
                    Updater.verificar { estadoUpdate = $0 }
                } label: {
                    Label("Ya estás en la última versión", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                }
                .buttonStyle(.plain).help("Volver a verificar")
            case .disponible(let v, let dmg, let notas):
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        estadoUpdate = .descargando(0)
                        Updater.actualizar(dmg: dmg) { estadoUpdate = $0 }
                    } label: {
                        Label("Actualizar a v\(v)", systemImage: "arrow.down.circle.fill")
                            .font(.caption2).bold()
                    }
                    .buttonStyle(.borderedProminent).tint(acento).controlSize(.small)
                    if !notas.isEmpty {
                        Button("Ver novedades") { mostrarNotas = true }
                            .buttonStyle(.plain).font(.caption2).foregroundStyle(acento)
                            .popover(isPresented: $mostrarNotas, arrowEdge: .trailing) {
                                ScrollView {
                                    MarkdownSimple(texto: notas).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                }.frame(width: 360, height: 300)
                            }
                    }
                }
            case .descargando(let p):
                VStack(alignment: .leading, spacing: 3) {
                    Label(p >= 0.99 ? "Instalando… se reiniciará sola" : "Descargando… \(Int(p * 100))%",
                          systemImage: "arrow.down.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value: p).frame(width: 140).tint(acento)
                }
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
        .onAppear {
            // "Apenas se abre": si está activado y aún no buscamos, revisa solo.
            if case .reposo = estadoUpdate, Config.buscarUpdateAlAbrir() {
                estadoUpdate = .buscando
                Updater.verificar { estadoUpdate = $0 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Updater.notificacion)) { _ in
            // La búsqueda de arranque terminó con el panel ya abierto.
            if let e = Updater.disponibleAlArrancar { estadoUpdate = e }
        }
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
                Toggle("Mantener presionado para hablar (push-to-talk)", isOn: $m.pushToTalk)
                Text(m.pushToTalk
                     ? "Grabas mientras tengas la tecla presionada; al soltarla, termina y transcribe. Funciona con fn o combinaciones de modificadores (ctrl+opt…), no con F1–F12."
                     : "Modo toque: un toque empieza, otro toque termina. Actívalo para grabar solo mientras mantienes la tecla (fn o modificadores).")
                    .font(.caption).foregroundStyle(.secondary)
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
            tarjeta("Al terminar el dictado", "return") {
                Toggle("Añadir un espacio al final", isOn: $m.espacioAlTerminar)
                Text("Separa dictados seguidos (si no, quedan pegados).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pulsar Enter al terminar", isOn: $m.enterAlTerminar)
                Text("Envía en chats (WhatsApp, Slack…) o salta de línea en editores.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pulsar Shift+Enter al terminar", isOn: $m.shiftEnterAlTerminar)
                Text("Salto de línea suave (sin enviar). Excluyente con Enter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Pulido con IA", "waveform") {
                Toggle("Pulir el texto con IA", isOn: $m.postProceso)
                if m.postProceso {
                    let _ = detectTrigger        // re-render tras detectar/conectar
                    let conectadas = ChatIA.conectadasPulido
                    if conectadas.isEmpty {
                        Text("Conecta una IA de chat (abajo) para usar el pulido.")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        fila("IA para pulido y traducción") {
                            Picker("", selection: $m.pulidoProveedor) {
                                ForEach(conectadas, id: \.id) { Text($0.etiqueta).tag($0.id) }
                            }.labelsHidden().frame(width: 300)
                        }
                        Text("Muestra el proveedor y el modelo activo. Se usa para pulir y traducir.")
                            .font(.caption).foregroundStyle(.secondary)
                        // Selector de MODELO del proveedor elegido (cualquiera:
                        // gateway, nube o local). Elige al vuelo + Descubrir.
                        if let sel = conectadas.first(where: { $0.id == m.pulidoProveedor }) {
                            selectorModelo(sel)
                        }
                    }
                    // Conectar IAs de nube por key (OpenRouter, DeepSeek, xAI…)
                    SeccionPlegable("Conectar más IAs de chat") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach([("OPENROUTER_API_KEY", "OpenRouter"), ("GEMINI_API_KEY", "Gemini (Google)"),
                                     ("ANTHROPIC_API_KEY", "Anthropic (Claude)"), ("DEEPSEEK_API_KEY", "DeepSeek"),
                                     ("XAI_API_KEY", "xAI (Grok)"), ("OPENAI_API_KEY", "OpenAI"),
                                     ("MISTRAL_API_KEY", "Mistral"),
                                     ("CEREBRAS_API_KEY", "Cerebras (gratis)"), ("GITHUB_MODELS_KEY", "GitHub Models (gratis)"),
                                     ("NVIDIA_API_KEY", "NVIDIA NIM (gratis)"), ("TOGETHER_API_KEY", "Together AI"),
                                     ("NOVITA_API_KEY", "Novita AI"), ("ZAI_CHAT_API_KEY", "Z.ai (GLM, gratis)"),
                                     ("SILICONFLOW_API_KEY", "SiliconFlow")], id: \.0) { env, nombre in
                                if ApiKeys.get(env).isEmpty {
                                    HStack(spacing: 8) {
                                        SecureField("API key de \(nombre)", text: Binding(
                                            get: { keyInputs[env] ?? "" }, set: { keyInputs[env] = $0 }))
                                            .textFieldStyle(.roundedBorder)
                                        Button("Conectar") {
                                            ApiKeys.set(env, keyInputs[env] ?? ""); keyInputs[env] = ""; detectTrigger += 1
                                        }.disabled((keyInputs[env] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                    }
                                } else {
                                    HStack {
                                        Label("\(nombre) conectado", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                                        Spacer()
                                        Button("Quitar") { ApiKeys.set(env, ""); detectTrigger += 1 }.controlSize(.small)
                                    }
                                }
                            }
                            Divider()
                            Button("IA personalizada (gateway propio)…") { IAPersonalizadaWindow.show() }
                            HStack(spacing: 8) {
                                Text("Locales: LM Studio / Ollama se detectan solos si están corriendo.")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Button(buscandoLocales ? "Buscando…" : "Buscar") {
                                    buscandoLocales = true
                                    ChatIA.detectarLocales { buscandoLocales = false; buscoLocales = true; detectTrigger += 1 }
                                }.controlSize(.small).disabled(buscandoLocales)
                            }
                            let locales = ["lmstudio", "ollama"].filter { ChatIA.modelosLocales[$0] != nil }
                            ForEach(locales, id: \.self) { lid in
                                Text("• \(lid == "lmstudio" ? "LM Studio" : "Ollama") ✓ (\(ChatIA.modelosLocales[lid] ?? ""))")
                                    .font(.caption2).foregroundStyle(.green)
                            }
                            if buscoLocales && locales.isEmpty && !buscandoLocales {
                                Text("Ninguno corriendo. Abre LM Studio / Ollama con un modelo de CHAT cargado y pulsa Buscar (no necesitan API key).")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        .padding(.top, 6)
                        // Auto-detecta al abrir esta sección (sin tener que pulsar
                        // Buscar): sondeo EN VIVO con sesión fresca.
                        .onAppear { ChatIA.detectarLocales { buscoLocales = true; detectTrigger += 1 } }
                    }
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
            // Avanzado: plegado por defecto; el TÍTULO completo abre/cierra.
            VStack(alignment: .leading, spacing: 10) {
                SeccionPlegable("Avanzado", icono: "wrench.and.screwdriver") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Modo desarrollo (notas de depuración)", isOn: $m.modoDesarrollo)
                        Divider()
                        Toggle("Buscar actualización al abrir", isOn: $m.buscarUpdateAlAbrir)
                        Text("Al arrancar, revisa en silencio si hay versión nueva y te lo muestra aquí abajo. Nunca instala nada sin permiso.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Autoactualizar (instalar sola la versión nueva)", isOn: $m.autoactualizar)
                            .disabled(!m.buscarUpdateAlAbrir)
                        Text("Si encuentra una actualización al abrir, la baja e instala sola (la app se reinicia). Si está apagado, solo te avisa y tú decides.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("Avisos de privacidad al pulir con IA de nube/terceros", isOn: $m.avisoNube)
                        Text("Muestra un recordatorio cuando el pulido usa una IA de nube o un gateway de terceros (tu texto sale de tu Mac). Apágalo si ya lo tienes claro.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("Salvaguarda anti-inyección (extra, para IAs de terceros)", isOn: $m.salvaguardaInyeccion)
                        Text("Si el texto pulido por la IA se dispara de tamaño o mete comandos de shell que tú no dictaste, pega tu dictado ORIGINAL en vez del pulido. Nunca bloquea ni borra: en el peor caso pierdes el pulido, no tus palabras. Útil si usas gateways de terceros y dictas en terminales. Default apagado.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("STT en vivo para la nube (Deepgram)", isOn: $m.sttStreaming)
                        Text("Si tu motor #1 es Deepgram, transcribe EN VIVO por WebSocket (ves el texto mientras hablas) en vez de esperar al soltar la tecla. Necesita tu key de Deepgram. Si está apagado, Deepgram transcribe por lotes como el resto. Default apagado.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Espera del pulido con IA: \(Int(m.pulidoTimeout)) s").font(.subheadline)
                            Slider(value: $m.pulidoTimeout, in: 10...60, step: 5).tint(acento)
                            Text("Cuánto esperar la respuesta de la IA antes de rendirse (y pegar el texto original). Súbelo si tu red es lenta.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                boton("Volver a ver el asistente de configuración", "wand.and.stars") {
                    WizardWindowController.shared.show()
                }
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

    // MARK: - Selector de modelo (para CUALQUIER proveedor de pulido)

    /// Lista de modelos elegibles del proveedor: gateway → los guardados en su
    /// JSON; fijo/local → los descubiertos en caché (modelosPorProveedor).
    private func modelosDe(_ sel: ChatIA) -> [String] {
        if sel.id.hasPrefix("custom:") {
            let gid = String(sel.id.dropFirst(7))
            return PersonalizadaStore.cargar().first(where: { $0.id == gid })?.modelos ?? []
        }
        return ChatIA.modelosPorProveedor[sel.id] ?? []
    }
    /// "modelo · precio" — precio manual del usuario, o el publicado por el
    /// proveedor, o el curado (aprox.).
    private func conPrecio(_ sel: ChatIA, _ modelo: String) -> String {
        if let p = ChatIA.precioDe(sel.id, modelo) { return "\(modelo) · \(p)" }
        return modelo
    }
    @ViewBuilder private func selectorModelo(_ sel: ChatIA) -> some View {
        let _ = detectTrigger
        let lista = modelosDe(sel)
        let activo = sel.modeloEfectivo
        // Incluye el activo aunque no esté en la lista (evita Picker sin tag).
        let opciones = (lista.contains(activo) || activo.isEmpty) ? lista : [activo] + lista
        VStack(alignment: .leading, spacing: 4) {
            fila("Modelo") {
                HStack(spacing: 8) {
                    if opciones.count > 1 {
                        Picker("", selection: Binding(
                            get: { activo },
                            set: { elegirModelo(sel, $0); detectTrigger += 1 })) {
                            ForEach(opciones, id: \.self) { m in
                                Text(conPrecio(sel, m)).tag(m)
                            }
                        }.labelsHidden().frame(width: 300)
                    } else {
                        Text(activo.isEmpty ? "—" : conPrecio(sel, activo)).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(descubriendoMod && msgModId == sel.id ? "Buscando…" : "Descubrir") {
                        descubriendoMod = true; msgMod = nil; msgModId = sel.id
                        descubrirModelosDe(sel)
                    }.controlSize(.small).disabled(descubriendoMod)
                }
            }
            if msgModId == sel.id, let mm = msgMod {
                Text(mm).font(.caption2).foregroundStyle(msgModOK ? .green : .orange)
            }
            Text(sel.id.hasPrefix("custom:")
                 ? "Modelos del gateway. Cambia el activo cuando quieras, aquí mismo."
                 : "Elige el modelo de este proveedor. 'Descubrir' trae la lista completa (con precio si el proveedor lo publica).")
                .font(.caption).foregroundStyle(.secondary)
            // Precio del modelo activo + editor manual (por si el proveedor no lo
            // publica, o para poner el tuyo). Prioridad: manual > publicado > curado.
            if !activo.isEmpty { precioManual(sel, activo) }
            // Aviso de privacidad: al usar nube/gateway, el texto SALE de tu Mac.
            avisoPrivacidad(sel)
        }
    }
    @ViewBuilder private func precioManual(_ sel: ChatIA, _ modelo: String) -> some View {
        let _ = detectTrigger
        let key = "\(sel.id)::\(modelo)"
        let actual = ChatIA.precioDe(sel.id, modelo)
        let esManual = Config.precioManual(key) != nil
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Precio \(esManual ? "(tuyo)" : "($/1M):")").font(.caption2).foregroundStyle(.secondary)
                Text(actual ?? "sin dato").font(.caption2)
                    .foregroundStyle(actual == nil ? .orange : .secondary)
                Spacer()
            }
            HStack(spacing: 6) {
                Text("Poner a mano:").font(.caption2).foregroundStyle(.secondary)
                TextField("entrada", text: $precioIn).frame(width: 60).textFieldStyle(.roundedBorder)
                Text("/").font(.caption2)
                TextField("salida", text: $precioOut).frame(width: 60).textFieldStyle(.roundedBorder)
                Button("Guardar") {
                    if let i = Double(precioIn.replacingOccurrences(of: ",", with: ".")),
                       let o = Double(precioOut.replacingOccurrences(of: ",", with: ".")) {
                        Config.setPrecioManual(key, (i, o)); precioIn = ""; precioOut = ""; detectTrigger += 1
                    }
                }.controlSize(.small)
                if esManual {
                    Button("Quitar") { Config.setPrecioManual(key, nil); detectTrigger += 1 }.controlSize(.small)
                }
            }
        }
    }
    /// Aviso de privacidad/seguridad al pulir con una IA que NO es local.
    @ViewBuilder private func avisoPrivacidad(_ sel: ChatIA) -> some View {
        if !sel.local && Config.avisoNube() {
            let esGateway = sel.id.hasPrefix("custom:")
            let inseguro = esGateway && !sel.baseSegura   // gateway por http://
            VStack(alignment: .leading, spacing: 2) {
                if inseguro {
                    Label("Este gateway usa http SIN cifrar: por seguridad NO se envían tus credenciales (ni la API key ni los encabezados). El pulido no funcionará hasta que uses https.",
                          systemImage: "lock.open.trianglebadge.exclamationmark")
                        .font(.caption2).foregroundStyle(.red)
                } else {
                    Label("Tu texto dictado se ENVÍA a \(sel.proveedorCorto)\(esGateway ? " (gateway de terceros)" : " (nube)") para pulir/traducir. No dictes datos sensibles (claves, tarjetas) con un proveedor de terceros.",
                          systemImage: "exclamationmark.shield")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Text("Para que NADA salga de tu Mac, usa una IA local (LM Studio / Ollama). Puedes ocultar este aviso en Avanzado.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        }
    }
    private func elegirModelo(_ sel: ChatIA, _ nuevo: String) {
        if sel.id.hasPrefix("custom:") {
            let gid = String(sel.id.dropFirst(7))
            var a = PersonalizadaStore.cargar()
            if let k = a.firstIndex(where: { $0.id == gid }) { a[k].modelo = nuevo; PersonalizadaStore.guardar(a) }
        } else {
            Config.setPulidoModelo(sel.id, nuevo)
        }
    }
    private func descubrirModelosDe(_ sel: ChatIA) {
        if sel.id.hasPrefix("custom:") {
            let gid = String(sel.id.dropFirst(7))
            guard let snap = PersonalizadaStore.cargar().first(where: { $0.id == gid }) else { descubriendoMod = false; return }
            PersonalizadaStore.descubrirModelos(snap) { ids, msg in
                // Recarga FRESCO dentro del callback y aplica solo la mutación
                // puntual: no pisa ediciones a otros gateways hechas mientras se
                // descubría (el editor es otra ventana no modal).
                if !ids.isEmpty {
                    var fresh = PersonalizadaStore.cargar()
                    if let k = fresh.firstIndex(where: { $0.id == gid }) {
                        fresh[k].modelos = ids
                        if fresh[k].modelo.isEmpty { fresh[k].modelo = ids[0] }
                        PersonalizadaStore.guardar(fresh)
                    }
                }
                descubriendoMod = false; msgMod = msg; msgModOK = !ids.isEmpty; detectTrigger += 1
            }
        } else {
            ChatIA.descubrirProveedor(sel) { ids, msg in
                descubriendoMod = false; msgMod = msg; msgModOK = !ids.isEmpty; detectTrigger += 1
            }
        }
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
    private let tp = PulidoLog.totales()

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

            // Gasto de PULIDO/traducción con IA (tokens → costo estimado).
            if tp.mesCosto > 0 || tp.pulidosMes > 0 {
                Label("Gasto de pulido con IA", systemImage: "sparkles").font(.headline).foregroundStyle(acento)
                HStack(spacing: 10) {
                    kpi("Hoy", String(format: "$%.3f", tp.hoyCosto), "dollarsign.circle")
                    kpi("Semana", String(format: "$%.3f", tp.semanaCosto), "calendar")
                    kpi("Mes", String(format: "$%.3f", tp.mesCosto), "calendar.badge.clock")
                }
                HStack(spacing: 10) {
                    kpi("Pulidos hoy", "\(tp.pulidosHoy)", "sparkles")
                    kpi("Tokens hoy", "\(tp.tokensHoy)", "number")
                    kpi("Pulidos mes", "\(tp.pulidosMes)", "sum")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gasto de pulido — últimos 7 días").font(.subheadline).bold()
                    barrasCosto
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Estimado con el precio (manual/publicado/curado ~) del modelo que se usó. Con IA LOCAL el costo es $0.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Bitácora de aprendizajes — solo con Modo desarrollo activo.
            if Config.devMode() {
                AprendizajesDebugView()
            }
        }
    }

    private var barrasCosto: some View {
        let maxV = max(tp.costoPorDia.max() ?? 0.001, 0.0001)
        let dias = diasEtiquetas()
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(tp.costoPorDia[i] >= 0.0005 ? String(format: "$%.3f", tp.costoPorDia[i]) : "")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(i == 6 ? 1 : 0.55))
                        .frame(height: max(4, CGFloat(tp.costoPorDia[i] / maxV) * 90))
                    Text(dias[i]).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 130)
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
    /// Abre la Configuración en una sección concreta (ej. "Créditos").
    func show(irA seccion: String) {
        show()
        NavAjustes.shared.ir = seccion
    }
}

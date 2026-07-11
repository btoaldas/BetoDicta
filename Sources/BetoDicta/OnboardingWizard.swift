import AppKit
import SwiftUI
import AVFoundation
import Carbon.HIToolbox

// MARK: - Asistente de primer arranque (wizard)
//
// La primera vez que la app corre en una máquina (o hasta que el usuario lo
// termine), muestra un asistente paso a paso: permisos (micrófono +
// accesibilidad, con check EN VIVO y reinicio), IA de nube, aprendizaje y
// preferencias generales — cada opción con su explicación de qué es y para qué.
//
// Robusto al reinicio de accesibilidad: el flag "wizard_completado" SOLO se
// pone al pulsar "Finalizar". Si el usuario activa accesibilidad y la app se
// reinicia a mitad del asistente, este vuelve a abrirse en el mismo paso y los
// permisos aparecen ya en verde ("check activado, check activado").

private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)

final class WizardWindowController {
    static let shared = WizardWindowController()
    private var window: NSWindow?

    /// ¿Debe mostrarse al arrancar? Solo si no se ha completado.
    static var debeMostrarse: Bool { !Config.wizardCompletado() }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "Bienvenido a BetoDicta"
            w.styleMask = [.titled, .closable]      // sin resize/minimize: es un flujo guiado
            w.setContentSize(NSSize(width: 640, height: 660))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.level = .floating
    }

    func close() { window?.close() }

    /// Reinicia BetoDicta (necesario tras conceder Accesibilidad para que los
    /// taps de teclado/pegado se re-registren con el permiso ya activo).
    static func reiniciarApp() {
        let ruta = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "sleep 0.6; open \"\(ruta)\""]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }
}

// MARK: - Vista del asistente

struct OnboardingView: View {
    @StateObject private var m = SettingsModel()
    @State private var paso: Int = Config.wizardPaso()

    // Estado de permisos (se refresca cada segundo).
    @State private var mic: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var ax: Bool = AXIsProcessTrusted()
    // Si la app arrancó SIN accesibilidad y luego se concede, hay que reiniciar
    // para que los taps se registren. Capturamos el estado al abrir el wizard.
    @State private var axAlArrancar: Bool = AXIsProcessTrusted()

    private let totalPasos = 6
    private let reloj = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            contenido
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            Divider()
            barraInferior.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 640, height: 660)
        .onReceive(reloj) { _ in
            mic = AVCaptureDevice.authorizationStatus(for: .audio)
            ax = AXIsProcessTrusted()
        }
    }

    // ---- Contenido por paso ----
    @ViewBuilder private var contenido: some View {
        switch paso {
        case 0: bienvenida
        case 1: permisos
        case 2: nube
        case 3: aprendizaje
        case 4: preferencias
        default: listo
        }
    }

    // Paso 0 — Bienvenida
    private var bienvenida: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let img = NSImage(named: "AppIcon") {
                    Image(nsImage: img).resizable().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("BetoDicta").font(.largeTitle).bold()
                    Text("Dictado por voz para macOS · español latino 🇪🇨").foregroundStyle(.secondary)
                }
            }
            Text("Pulsas una tecla, hablas, vuelves a pulsar — y el texto aparece donde está tu cursor, en cualquier app.")
                .font(.title3)
            Text("Este asistente te toma ~1 minuto. Vamos a:")
                .font(.headline).padding(.top, 4)
            vinieta("1", "Dar permisos", "Micrófono para escucharte y Accesibilidad para escribir donde tú quieras.")
            vinieta("2", "Conectar IA (opcional)", "Motores de nube para máxima calidad, o quédate 100% gratis y local.")
            vinieta("3", "Que aprenda de ti", "Corrige una palabra una vez y la app la recuerda sola.")
            vinieta("4", "Tus preferencias", "Sonidos, panel, Dock, arranque… todo a tu gusto.")
            Spacer()
            Text("Todo se puede cambiar luego en Configuración. Nada es definitivo.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    // Paso 1 — Permisos (check en vivo)
    private var permisos: some View {
        VStack(alignment: .leading, spacing: 18) {
            encabezado("Permisos", "sin estos dos, la app no puede escucharte ni escribir por ti.")

            permisoFila(
                icono: "mic.fill", titulo: "Micrófono",
                para: "Para convertir tu voz en texto.",
                listo: mic == .authorized,
                estado: micEstadoTexto,
                accion: micAccion, etiquetaBoton: micBotonTexto
            )

            permisoFila(
                icono: "accessibility", titulo: "Accesibilidad",
                para: "Para escribir el texto donde está tu cursor y detectar la tecla de dictado.",
                listo: ax && axAlArrancar,   // verde solo si ya estaba al arrancar (si no, falta reiniciar)
                estado: axEstadoTexto,
                accion: axAccion, etiquetaBoton: "Abrir Ajustes de Accesibilidad"
            )

            // Aviso de reinicio: se concedió accesibilidad DESPUÉS de arrancar.
            if ax && !axAlArrancar {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Accesibilidad activada — reinicia BetoDicta para que tome efecto.",
                          systemImage: "arrow.clockwise.circle.fill")
                        .font(.subheadline).foregroundStyle(acento)
                    Text("Tranquilo: el asistente vuelve exactamente a este paso y verás los dos permisos en verde.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Config.set("wizard_paso", to: 1)   // reabrir aquí
                        WizardWindowController.reiniciarApp()
                    } label: {
                        Label("Reiniciar BetoDicta ahora", systemImage: "arrow.clockwise")
                    }.buttonStyle(.borderedProminent).tint(acento)
                }
                .padding(12)
                .background(acento.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
            if permisosOK {
                Label("Todo listo — pulsa Siguiente.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.subheadline)
            }
        }
    }

    // Paso 2 — IA en la nube (opcional)
    private var nube: some View {
        VStack(alignment: .leading, spacing: 16) {
            encabezado("Inteligencia en la nube (opcional)",
                       "BetoDicta funciona GRATIS y sin internet con motores locales. Si quieres la máxima calidad en vivo, conecta un servicio. Pega la clave o deja en blanco para saltar.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    claveNube(id: "elevenlabs", env: "ELEVENLABS_API_KEY",
                              titulo: "ElevenLabs Scribe", nota: "La mejor calidad, texto EN VIVO. De pago (~$0.22–0.39/h).",
                              enlace: "https://elevenlabs.io/app/settings/api-keys", activarPrimero: true)
                    claveNube(id: "groq", env: "GROQ_API_KEY",
                              titulo: "Groq Whisper", nota: "Muy rápido, capa gratis generosa. También potencia el pulido y la traducción.",
                              enlace: "https://console.groq.com/keys", activarPrimero: false)
                    DisclosureGroup("Más servicios (OpenAI, Mistral)") {
                        VStack(alignment: .leading, spacing: 14) {
                            claveNube(id: "openai", env: "OPENAI_API_KEY",
                                      titulo: "OpenAI", nota: "whisper-1 y gpt-4o-transcribe (~$0.18–0.36/h).",
                                      enlace: "https://platform.openai.com/api-keys", activarPrimero: false)
                            claveNube(id: "mistral", env: "MISTRAL_API_KEY",
                                      titulo: "Mistral (Voxtral)", nota: "Voxtral en la nube, sin descargar nada.",
                                      enlace: "https://console.mistral.ai/api-keys", activarPrimero: false)
                        }.padding(.top, 6)
                    }.font(.subheadline)
                }
            }
        }
    }

    // Paso 3 — Aprendizaje e inteligencia local
    private var aprendizaje: some View {
        VStack(alignment: .leading, spacing: 16) {
            encabezado("Que aprenda de ti", "la app puede recordar tus correcciones y mejorar sola. Todo 100% local.")
            wizToggle("Aprender de mis correcciones", isOn: $m.aprender,
                      nota: "Corriges una palabra donde la pegaste (ej. Kipux → Quipux) y la app guarda la regla sola. En la terminal/Claude Code: seleccionas el texto corregido y pulsas ⌘⇧L. Recomendado.")
            wizToggle("Corrección por sonido (fonética)", isOn: $m.porSonido,
                      nota: "Corrige palabras que SUENAN como un término tuyo, aunque nunca las hayas visto. Más potente pero puede pasarse: la activas término por término (casilla 🔊 en Reemplazos) y siempre es reversible.")
            wizToggle("Pulido con IA (Groq)", isOn: $m.postProceso,
                      nota: "Una IA corrige la puntuación y quita muletillas (\"eh\", \"este…\"). Necesita clave de Groq (paso anterior).")
            Spacer()
        }
    }

    // Paso 4 — Preferencias generales
    private var preferencias: some View {
        VStack(alignment: .leading, spacing: 14) {
            encabezado("Tus preferencias", "afina cómo se comporta. Los valores de fábrica ya están bien para la mayoría.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    wizToggle("Sonidos de inicio y fin", isOn: $m.sonidos,
                              nota: "Un \"tink\" al empezar y un \"glass\" al entregar el texto.")
                    wizToggle("Mostrar el panel al dictar", isOn: $m.panelVisible,
                              nota: "El panel negro junto al notch con el latido de tu voz y el texto en vivo. Apágalo para modo ninja.")
                    wizToggle("Cancelar con Esc", isOn: $m.escCancela,
                              nota: "Pulsar Esc a mitad del dictado descarta todo sin escribir nada.")
                    wizToggle("Pausar música y videos al dictar", isOn: $m.pausarMultimedia,
                              nota: "Pausa Spotify/YouTube/Music mientras hablas y los reanuda al terminar.")
                    wizToggle("Bajar el volumen al dictar", isOn: $m.bajarVolumen,
                              nota: "Además baja el volumen del sistema y lo restaura exacto.")
                    wizToggle("Mostrar en el Dock", isOn: $m.mostrarEnDock,
                              nota: "La app vive en la barra de menú (arriba). Enciéndelo si además la quieres en el Dock.")
                    wizToggle("Arrancar al iniciar sesión", isOn: $m.arrancarInicio,
                              nota: "BetoDicta se abre sola al prender el Mac. Cómodo si dictas a diario.")
                    Divider()
                    wizToggle("Modo desarrollo (debug)", isOn: $m.modoDesarrollo,
                              nota: "Notas técnicas extra en el registro y desbloquea la bitácora de aprendizaje en Estadísticas. Solo si te gusta ver el detalle.")
                }
            }
        }
    }

    // Paso 5 — Listo
    private var listo: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
                Spacer()
            }
            Text("¡Todo listo!").font(.largeTitle).bold().frame(maxWidth: .infinity, alignment: .center)
            Text("Pon el cursor donde quieras escribir y **pulsa \(Config.hotkey()) para tu primer dictado**. Vuelve a pulsar para soltar el texto.")
                .font(.title3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Label("Busca el ícono de micrófono en la barra de menú (arriba a la derecha) para volver a Configuración.", systemImage: "menubar.arrow.up.rectangle")
                Label("Todo lo que elegiste aquí se puede cambiar cuando quieras.", systemImage: "slider.horizontal.3")
                Label("¿Dudas? El manual completo está en Créditos.", systemImage: "book")
            }.font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // ---- Barra inferior (navegación) ----
    private var barraInferior: some View {
        HStack {
            if paso > 0 {
                Button("Atrás") { retroceder() }.controlSize(.large)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<totalPasos, id: \.self) { i in
                    Circle().fill(i == paso ? acento : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if paso < totalPasos - 1 {
                Button(paso == 0 ? "Empezar" : "Siguiente") { avanzar() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(paso == 1 && !permisosOK)
            } else {
                Button("Finalizar") { finalizar() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large).buttonStyle(.borderedProminent).tint(acento)
            }
        }
    }

    // ---- Navegación ----
    private var permisosOK: Bool {
        // Micrófono concedido, y accesibilidad concedida DESDE el arranque
        // (si se concedió a mitad, axAlArrancar es false → falta reiniciar).
        mic == .authorized && ax && axAlArrancar
    }
    private func avanzar() { paso = min(paso + 1, totalPasos - 1); Config.set("wizard_paso", to: paso) }
    private func retroceder() { paso = max(paso - 1, 0); Config.set("wizard_paso", to: paso) }
    private func finalizar() {
        Config.set("wizard_completado", to: true)
        Config.set("wizard_paso", to: 0)
        WizardWindowController.shared.close()
    }

    // ---- Permiso: micrófono ----
    private var micEstadoTexto: String {
        switch mic {
        case .authorized: return "Activado"
        case .denied, .restricted: return "Bloqueado en Ajustes del Sistema"
        default: return "Sin conceder todavía"
        }
    }
    private var micBotonTexto: String { mic == .denied || mic == .restricted ? "Abrir Ajustes del Sistema" : "Activar micrófono" }
    private func micAccion() {
        switch mic {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { mic = AVCaptureDevice.authorizationStatus(for: .audio); _ = ok }
            }
        default:
            abrir("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
    }

    // ---- Permiso: accesibilidad ----
    private var axEstadoTexto: String {
        if ax && !axAlArrancar { return "Activado — falta reiniciar" }
        return ax ? "Activado" : "Sin conceder todavía"
    }
    private func axAccion() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)      // dispara el diálogo del sistema
        abrir("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func abrir(_ url: String) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }

    // ---- Componentes reutilizables ----
    private func encabezado(_ titulo: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.title).bold()
            Text(sub).font(.callout).foregroundStyle(.secondary)
        }
    }
    private func vinieta(_ n: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.subheadline).bold().foregroundStyle(.white)
                .frame(width: 22, height: 22).background(acento).clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(.subheadline).bold()
                Text(d).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func permisoFila(icono: String, titulo: String, para: String,
                             listo: Bool, estado: String,
                             accion: @escaping () -> Void, etiquetaBoton: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: listo ? "checkmark.circle.fill" : icono)
                .font(.system(size: 30))
                .foregroundStyle(listo ? .green : acento)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(titulo).font(.headline)
                    Text(estado).font(.caption).foregroundStyle(listo ? .green : .secondary)
                }
                Text(para).font(.caption).foregroundStyle(.secondary)
                if !listo {
                    Button(etiquetaBoton, action: accion).controlSize(.regular).padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func wizToggle(_ titulo: String, isOn: Binding<Bool>, nota: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(titulo, isOn: isOn).font(.headline)
            Text(nota).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // Fila de clave de nube (guarda en .env y activa el proveedor).
    @ViewBuilder
    private func claveNube(id: String, env: String, titulo: String, nota: String, enlace: String, activarPrimero: Bool) -> some View {
        ClaveNubeRow(id: id, env: env, titulo: titulo, nota: nota, enlace: enlace, activarPrimero: activarPrimero)
    }
}

// MARK: - Fila de clave de nube (estado propio)

private struct ClaveNubeRow: View {
    let id: String, env: String, titulo: String, nota: String, enlace: String
    let activarPrimero: Bool

    @State private var clave: String = ""
    @State private var guardado = false
    @State private var yaTenia = false     // había clave al abrir (no la mostramos en claro)

    private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)
    private var conectado: Bool { yaTenia || guardado }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titulo).font(.headline)
                if conectado {
                    Label("conectado", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button("Conseguir clave") { if let u = URL(string: enlace) { NSWorkspace.shared.open(u) } }
                    .controlSize(.small).buttonStyle(.link)
            }
            Text(nota).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                // Nunca mostramos la clave existente en claro: solo pedimos una
                // nueva si la quiere cambiar. Vacío = se conserva la actual.
                SecureField(conectado ? "Clave guardada — pega otra para reemplazarla"
                                      : "Pega tu API key aquí (o déjalo en blanco)", text: $clave)
                    .textFieldStyle(.roundedBorder)
                Button("Guardar") { guardar() }.controlSize(.regular)
                    .disabled(clave.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { yaTenia = !ApiKeys.get(env).isEmpty }
    }

    private func guardar() {
        let v = clave.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        ApiKeys.set(env, v)
        activarProveedor(id, primero: activarPrimero)
        clave = ""                          // no dejar el secreto en pantalla
        withAnimation { guardado = true }
    }

    /// Enciende el proveedor en la cascada (y opcionalmente lo pone #1).
    private func activarProveedor(_ id: String, primero: Bool) {
        var lista = Providers.load()
        guard let i = lista.firstIndex(where: { $0.id == id }) else { return }
        lista[i].activo = true
        if primero {
            let menor = (lista.map { $0.orden }.min() ?? 0) - 1
            lista[i].orden = menor
        }
        Providers.save(lista)
    }
}

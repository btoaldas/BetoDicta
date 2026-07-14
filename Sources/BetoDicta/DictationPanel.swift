import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Panel flotante en el notch (no roba el foco)

/// Label que acepta clic (izquierdo o derecho) para abrir el selector de motor.
final class MotorLabel: NSTextField {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}

final class DictationPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    let meter: LevelMeterView
    private let keycap = NSTextField(labelWithString: "fn")
    private let motorLabel = MotorLabel(labelWithString: "")
    private let modoLabel = MotorLabel(labelWithString: "")   // arriba-izq: modo activo
    private var fondo: NSView?                                 // forma negra (para el latido "pensando")

    /// Clic sobre el letrero del motor (o el fn): abrir el selector rápido.
    var onMotorClick: (() -> Void)? {
        didSet { motorLabel.onClick = onMotorClick }
    }
    /// Clic sobre el letrero del MODO (arriba-izq): abrir el selector de modo.
    var onModoClick: (() -> Void)? {
        didSet { modoLabel.onClick = onModoClick }
    }

    private let wing: CGFloat = 48      // alas a los lados del notch
    private let strip: CGFloat = 24     // línea de texto bajo el notch
    private var width: CGFloat = 400
    private var height: CGFloat = 60
    private var notchHeight: CGFloat = 36

    init() {
        // Geometría real del notch (áreas útiles a sus lados)
        var notchRect = NSRect(x: 0, y: 0, width: 210, height: 36)
        if let screen = NSScreen.main {
            notchHeight = max(screen.safeAreaInsets.top, 28)
            let left = screen.auxiliaryTopLeftArea
            let right = screen.auxiliaryTopRightArea
            if let left, let right {
                notchRect = NSRect(x: left.maxX, y: screen.frame.maxY - notchHeight,
                                   width: right.minX - left.maxX, height: notchHeight)
            } else {
                notchRect = NSRect(x: screen.frame.midX - 105, y: screen.frame.maxY - notchHeight,
                                   width: 210, height: notchHeight)
            }
        }
        width = notchRect.width + wing * 2
        height = notchHeight + strip
        meter = LevelMeterView(frame: NSRect(x: 8, y: strip + 7, width: wing - 16, height: notchHeight - 14))

        panel = NSPanel(contentRect: NSRect(x: notchRect.minX - wing,
                                            y: notchRect.maxY - height,
                                            width: width, height: height),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true

        // Forma negra que abraza el notch: alas arriba + tira de texto abajo
        let background = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.cgColor
        background.layer?.cornerRadius = 12
        background.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.contentView = background
        fondo = background

        // Ala izquierda: el latido (a la altura del notch)
        background.addSubview(meter)

        // Ala derecha: tecla fn estilo keycap
        keycap.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        keycap.textColor = .white
        keycap.alignment = .center
        keycap.wantsLayer = true
        keycap.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        keycap.layer?.cornerRadius = 5
        keycap.layer?.borderWidth = 1
        keycap.layer?.borderColor = NSColor(calibratedWhite: 0.4, alpha: 1).cgColor
        // Keycap abajo + letrero del motor arriba, adaptado al alto del ala
        // (36 pt con notch real, ~28 pt en pantallas externas).
        let capW: CGFloat = 30
        let capH: CGFloat = notchHeight >= 34 ? 18 : 14
        keycap.font = NSFont.systemFont(ofSize: capH >= 18 ? 12 : 10, weight: .semibold)
        keycap.frame = NSRect(x: width - wing + (wing - capW) / 2,
                              y: strip + 2,
                              width: capW, height: capH)
        background.addSubview(keycap)

        // Encima del fn: con qué MOTOR se está dictando ahora mismo
        // (rota en vivo cuando el failover conmuta de proveedor).
        motorLabel.font = NSFont.systemFont(ofSize: 7, weight: .bold)
        motorLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        motorLabel.alignment = .center
        motorLabel.maximumNumberOfLines = 1
        let motorH = max(8, notchHeight - capH - 7)
        motorLabel.frame = NSRect(x: width - wing + 1,
                                  y: strip + capH + 4,
                                  width: wing - 2, height: min(motorH, 10))
        background.addSubview(motorLabel)

        // Tira inferior: UNA línea de texto delgadita, alineada a la DERECHA
        // (lo último dicho queda pegado al borde, a la altura del fn) y el
        // texto viejo se recorta por la IZQUIERDA con "…". Así nunca se oculta
        // lo último que se habla.
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .right
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingHead
        label.frame = NSRect(x: 8, y: 4, width: width - 16, height: 15)
        background.addSubview(label)

        // Ala IZQUIERDA, arriba (sobre el audio): el MODO activo. Clic para
        // cambiarlo — igual que el letrero del motor a la derecha.
        modoLabel.font = NSFont.systemFont(ofSize: 7, weight: .bold)
        modoLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        modoLabel.alignment = .center
        modoLabel.maximumNumberOfLines = 1
        modoLabel.frame = NSRect(x: 1, y: strip + notchHeight - 11, width: wing - 2, height: 10)
        modoLabel.onClick = onModoClick
        background.addSubview(modoLabel)   // encima del meter (z-order)
        setModo(ModosStore.activo())
    }

    /// Fija el letrero del modo activo (arriba-izq del notch).
    func setModo(_ modo: Modo) {
        let txt = modo.id == "dictado" ? "dictado" : modo.nombre.lowercased()
        modoLabel.stringValue = txt
        // El modo por defecto va tenue; los otros resaltan (están transformando).
        modoLabel.textColor = modo.id == "dictado"
            ? NSColor(calibratedWhite: 0.5, alpha: 1)
            : NSColor(calibratedRed: 0.62, green: 0.55, blue: 0.95, alpha: 1)
    }

    // Un "flash" (aviso breve, ej. "📚 Aprendí…") tiene prioridad sobre el
    // texto del dictado hasta que caduca — así se alcanza a ver sin tapar.
    private var flashHasta = Date.distantPast

    func show(_ text: String) {
        guard Config.panelVisible() else { return }
        reposicionar()
        update(text)
        panel.orderFrontRegardless()
    }

    /// Muestra un aviso breve por N segundos, por encima del texto del dictado.
    func flash(_ text: String, segundos: TimeInterval = 2.5) {
        guard Config.panelVisible(), !enRespuestaIA else { return }
        reposicionar()
        flashHasta = Date().addingTimeInterval(segundos)
        label.stringValue = text
        panel.orderFrontRegardless()
    }

    /// La pantalla con notch, o la que tenga el ratón, o la principal.
    /// Al cerrar/abrir el portátil o mover de monitor, la pantalla activa
    /// cambia — sin esto el panel se queda pegado a coordenadas viejas
    /// (aparecía abajo a la izquierda tras dormir/despertar el Mac).
    private func pantallaActiva() -> NSScreen? {
        if let conNotch = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) {
            return conNotch
        }
        let raton = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(raton, $0.frame, false) } ?? NSScreen.main
    }

    /// Recalcula geometría del notch y recoloca el panel en la pantalla
    /// activa AHORA (se llama en cada aparición, no solo al arrancar).
    private func reposicionar() {
        guard let screen = pantallaActiva() else { return }
        var notchRect = NSRect(x: screen.frame.midX - 105,
                               y: screen.frame.maxY - 36, width: 210, height: 36)
        notchHeight = max(screen.safeAreaInsets.top, 28)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchRect = NSRect(x: left.maxX, y: screen.frame.maxY - notchHeight,
                               width: right.minX - left.maxX, height: notchHeight)
        } else {
            notchRect = NSRect(x: screen.frame.midX - 105, y: screen.frame.maxY - notchHeight,
                               width: 210, height: notchHeight)
        }
        let nuevoAncho = notchRect.width + wing * 2
        let nuevoAlto = notchHeight + strip
        // Si cambió el tamaño (notch ↔ pantalla externa), relayout completo.
        if abs(nuevoAncho - width) > 0.5 || abs(nuevoAlto - height) > 0.5 {
            width = nuevoAncho; height = nuevoAlto
            relayout()
        }
        panel.setFrame(NSRect(x: notchRect.minX - wing, y: notchRect.maxY - height,
                              width: width, height: height), display: true)
    }

    /// Reajusta los subviews cuando cambia el tamaño (cambio de pantalla).
    private func relayout() {
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: width, height: height)
        meter.frame = NSRect(x: 8, y: strip + 7, width: wing - 16, height: notchHeight - 14)
        let capW: CGFloat = 30
        let capH: CGFloat = notchHeight >= 34 ? 18 : 14
        keycap.font = NSFont.systemFont(ofSize: capH >= 18 ? 12 : 10, weight: .semibold)
        keycap.frame = NSRect(x: width - wing + (wing - capW) / 2, y: strip + 2, width: capW, height: capH)
        let motorH = max(8, notchHeight - capH - 7)
        motorLabel.frame = NSRect(x: width - wing + 1, y: strip + capH + 4,
                                  width: wing - 2, height: min(motorH, 10))
        modoLabel.frame = NSRect(x: 1, y: strip + notchHeight - 11, width: wing - 2, height: 10)
        label.frame = NSRect(x: 8, y: 4, width: width - 16, height: 15)
    }

    /// Teleprompter de una línea: siempre muestra el FINAL (lo último dicho).
    /// El truncado por la cabeza (.byTruncatingHead) + alineación derecha se
    /// encargan de recortar lo viejo; no hace falta cortar a mano.
    func update(_ text: String) {
        // No pisar un aviso breve todavía vigente ni la respuesta de la IA.
        guard !enRespuestaIA, Date() >= flashHasta else { return }
        label.stringValue = text.replacingOccurrences(of: "\n", with: " ")
    }

    /// Update que SÍ pisa el flash (para la entrega final del dictado).
    func updateForzado(_ text: String) {
        guard !enRespuestaIA else { return }   // el dictado NO pisa la respuesta de la IA
        flashHasta = .distantPast
        label.stringValue = text.replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Notch de RESPUESTA DE IA (distinto al de dictado)
    //
    // Al revés del dictado: aquí aparece lo que la IA RESPONDE (mientras habla), no lo
    // que tú dictas. Look propio (🤖, color azul, sin medidor de mic) para reconocerlo,
    // y NO se comporta como el dictado (no lo pisan update/flash, no muestra nivel).

    private(set) var enRespuestaIA = false
    private let colorIA = NSColor(calibratedRed: 0.45, green: 0.72, blue: 1.0, alpha: 1)

    /// El agente está PENSANDO: notch late (pulso) + con qué IA trabaja (local/Hermes/
    /// OpenClaw). Súper básico — solo se ve que está pensando. `ia` = nombre a mostrar.
    func pensando(ia: String) {
        guard Config.panelVisible() else { return }
        enRespuestaIA = true
        reposicionar()
        meter.isHidden = true
        modoLabel.stringValue = "🤖 IA"
        motorLabel.stringValue = ia.uppercased()
        motorLabel.textColor = colorIA
        label.textColor = colorIA
        label.stringValue = "pensando…"
        panel.orderFrontRegardless()
        pulsar(true)
    }

    /// Muestra la RESPUESTA de la IA (mientras habla). Sigue latiendo suave.
    func respuestaIA(_ texto: String) {
        guard Config.panelVisible() else { return }
        if !enRespuestaIA { pensando(ia: "local") }   // por si no pasó por "pensando"
        label.textColor = colorIA
        label.stringValue = texto.replacingOccurrences(of: "\n", with: " ")
        panel.orderFrontRegardless()
    }

    /// Latido del notch entero (pulso de opacidad). "Está pensando/hablando".
    private func pulsar(_ on: Bool) {
        guard let l = fondo?.layer else { return }
        if on {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1.0; a.toValue = 0.55; a.duration = 0.75
            a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(a, forKey: "pulso")
        } else { l.removeAnimation(forKey: "pulso"); l.opacity = 1 }
    }

    /// Actualiza el texto de la respuesta (si la IA lo entrega en trozos).
    func actualizarRespuestaIA(_ texto: String) {
        guard enRespuestaIA else { return }
        label.stringValue = texto.replacingOccurrences(of: "\n", with: " ")
    }

    /// Cierra el modo respuesta de IA y vuelve el notch a lo normal.
    func finRespuestaIA() {
        guard enRespuestaIA else { return }
        enRespuestaIA = false
        pulsar(false)
        label.textColor = .white
        motorLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        meter.isHidden = false
        setModo(ModosStore.activo())   // restaura el letrero de modo
        hide(after: 1.5)
    }

    /// Letrero del motor activo, encima del fn. Verde = texto en vivo;
    /// gris = se transcribe al soltar la tecla. Clic = selector rápido.
    func setMotor(_ nombre: String, enVivo: Bool) {
        motorLabel.stringValue = nombre.uppercased()
        motorLabel.textColor = enVivo
            ? NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
    }

    /// Menú emergente anclado al letrero del motor (para el selector rápido).
    func popUpMotorMenu(_ menu: NSMenu) {
        menu.popUp(positioning: nil,
                   at: NSPoint(x: motorLabel.frame.minX, y: motorLabel.frame.minY - 4),
                   in: panel.contentView)
    }
    func popUpModoMenu(_ menu: NSMenu) {
        menu.popUp(positioning: nil,
                   at: NSPoint(x: modoLabel.frame.minX, y: modoLabel.frame.minY - 4),
                   in: panel.contentView)
    }

    var esVisible: Bool { panel.isVisible }

    func hide(after seconds: TimeInterval = 0) {
        meter.reset()
        if seconds == 0 {
            panel.orderOut(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [panel] in
                panel.orderOut(nil)
            }
        }
    }
}


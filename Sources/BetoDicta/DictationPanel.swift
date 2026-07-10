import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Panel flotante en el notch (no roba el foco)

final class DictationPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    let meter: LevelMeterView
    private let keycap = NSTextField(labelWithString: "fn")
    private let motorLabel = NSTextField(labelWithString: "")

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
    }

    func show(_ text: String) {
        guard Config.panelVisible() else { return }
        update(text)
        panel.orderFrontRegardless()
    }

    /// Teleprompter de una línea: siempre muestra el FINAL (lo último dicho).
    /// El truncado por la cabeza (.byTruncatingHead) + alineación derecha se
    /// encargan de recortar lo viejo; no hace falta cortar a mano.
    func update(_ text: String) {
        label.stringValue = text.replacingOccurrences(of: "\n", with: " ")
    }

    /// Letrero del motor activo, encima del fn. Verde = texto en vivo;
    /// gris = se transcribe al soltar la tecla.
    func setMotor(_ nombre: String, enVivo: Bool) {
        motorLabel.stringValue = nombre.uppercased()
        motorLabel.textColor = enVivo
            ? NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
    }

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


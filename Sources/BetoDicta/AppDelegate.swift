import AppKit
import AVFoundation
import Carbon.HIToolbox
import ServiceManagement

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var appMenu: NSMenu?

    /// Clic derecho en el ícono del Dock muestra el mismo menú.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        appMenu?.copy() as? NSMenu
    }

    /// Clic izquierdo en el ícono del Dock (sin ventanas abiertas) → abre la
    /// configuración, para que el ícono haga algo útil y no se quede mudo.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { SettingsWindowController.shared.show() }
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first(where: { $0.tag == 77 })?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
        menu.items.first(where: { $0.tag == 78 })?.state = Config.postProcess() ? .on : .off
        menu.items.first(where: { $0.tag == 79 })?.state = Config.devMode() ? .on : .off
        menu.items.first(where: { $0.tag == 81 })?.state = Config.showInDock() ? .on : .off
        if let tradMenu = menu.items.first(where: { $0.tag == 82 })?.submenu {
            let activo = Config.translate()
            let idioma = Config.translateTo()
            for it in tradMenu.items {
                guard let obj = it.representedObject as? String else { continue }
                it.state = (obj.isEmpty && !activo) || (activo && obj == idioma) ? .on : .off
            }
            menu.items.first(where: { $0.tag == 82 })?.title =
                activo ? "Traducir al dictar: \(idioma)" : "Traducir al dictar"
        }
        if let recientes = menu.items.first(where: { $0.tag == 80 })?.submenu {
            recientes.removeAllItems()
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            for entrada in latestTexts(5) {
                guard let texto = try? String(contentsOf: entrada.url, encoding: .utf8), !texto.isEmpty else { continue }
                let resumen = texto.count > 44 ? String(texto.prefix(44)) + "…" : texto
                let item = NSMenuItem(title: "\(fmt.string(from: entrada.date))  \(resumen)",
                                      action: #selector(copyRecent(_:)), keyEquivalent: "")
                item.representedObject = texto
                item.target = self
                recientes.addItem(item)
            }
            if recientes.items.isEmpty {
                recientes.addItem(NSMenuItem(title: "(vacío)", action: nil, keyEquivalent: ""))
            }
        }
        while let viejo = menu.items.first(where: { $0.tag == 99 }) {
            menu.removeItem(viejo)
        }
        var idx = 1
        let titulo = NSMenuItem(title: "— Uso de dictado —", action: nil, keyEquivalent: "")
        titulo.tag = 99
        menu.insertItem(titulo, at: idx)
        idx += 1
        for line in UsageLog.resumen() {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.tag = 99
            menu.insertItem(item, at: idx)
            idx += 1
        }
    }

    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let panel = DictationPanel()
    private var stream: StreamClient?
    private var history: HistoryWriter?
    private let media = MediaControl()
    private var hotKeyRef: EventHotKeyRef?
    private var lastVoice = Date()
    private var silenceTimer: Timer?
    private var lastPartial = ""

    private func playSound(_ name: String) {
        guard Config.sounds() else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Esc durante un dictado: cancela todo — no transcribe, no pega.
    private func cancelDictation() {
        guard recorder.isRecording else { return }
        disarmEsc()
        media.dictationEnded()
        silenceTimer?.invalidate()
        silenceTimer = nil
        liveTimer?.invalidate()
        liveTimer = nil
        _ = recorder.stop()
        stream?.disconnect()
        stream = nil
        tcppStream?.cancel()
        tcppStream = nil
        history?.discard()
        history = nil
        playSound("Basso")
        panel.update("✕ Cancelado")
        panel.hide(after: 1)
    }

    private var tecla: String { Config.hotkey() }
    /// Solo hay texto en vivo (streaming) si el proveedor #1 de la cadena es
    /// ElevenLabs Y el modelo es realtime. Si el #1 es Whisper local o Groq,
    /// se graba plano y se transcribe con la cadena de failover al terminar —
    /// así el ORDEN de la pestaña Modelos manda de verdad.
    private var isStreamingModel: Bool {
        guard let primero = Providers.cadena().first, primero.id == "elevenlabs" else { return false }
        return (primero.modelo ?? "scribe_v2") == "scribe_v2_realtime"
    }

    func applicationWillTerminate(_ notification: Notification) {
        WhisperServer.apagar(motivo: "salida de la app")
        VoxtralServer.apagar(motivo: "salida de la app")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = Self.menuBarIcon() {
            statusItem.button?.image = icon      // monocromo, se adapta a claro/oscuro
        } else {
            statusItem.button?.title = "🎙"      // respaldo
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "BetoDicta v\(Version.numero) — \(tecla) para dictar", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Configuración…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Editar keyterms", action: #selector(openKeyterms), keyEquivalent: "")
        menu.addItem(withTitle: "Editar reemplazos", action: #selector(openReplacements), keyEquivalent: "")
        menu.addItem(withTitle: "Copiar último dictado", action: #selector(copyLastDictation), keyEquivalent: "c")
        let recientes = NSMenuItem(title: "Últimos dictados", action: nil, keyEquivalent: "")
        recientes.tag = 80
        recientes.submenu = NSMenu()
        menu.addItem(recientes)
        menu.addItem(withTitle: "Exportar dictados de hoy", action: #selector(exportToday), keyEquivalent: "e")
        menu.addItem(withTitle: "Abrir historial", action: #selector(openHistory), keyEquivalent: "")
        menu.addItem(withTitle: "Ver registro (log)", action: #selector(openLog), keyEquivalent: "l")
        let dev = NSMenuItem(title: "Modo desarrollo", action: #selector(toggleDevMode(_:)), keyEquivalent: "")
        dev.tag = 79
        menu.addItem(dev)
        let dock = NSMenuItem(title: "Mostrar en el Dock", action: #selector(toggleDock(_:)), keyEquivalent: "")
        dock.tag = 81
        menu.addItem(dock)
        let auto = NSMenuItem(title: "Arrancar al iniciar sesión", action: #selector(toggleAutostart(_:)), keyEquivalent: "")
        auto.tag = 77
        menu.addItem(auto)
        let post = NSMenuItem(title: "Post-proceso con IA (Groq)", action: #selector(togglePostProcess(_:)), keyEquivalent: "")
        post.tag = 78
        menu.addItem(post)
        // Traducir al dictar (submenú con idiomas)
        let trad = NSMenuItem(title: "Traducir al dictar", action: nil, keyEquivalent: "")
        trad.tag = 82
        let tradMenu = NSMenu()
        let apagar = NSMenuItem(title: "Desactivado", action: #selector(setTranslate(_:)), keyEquivalent: "")
        apagar.representedObject = ""; tradMenu.addItem(apagar)
        tradMenu.addItem(NSMenuItem.separator())
        for idioma in ["inglés", "portugués", "francés", "italiano", "alemán", "chino"] {
            let it = NSMenuItem(title: idioma.capitalized, action: #selector(setTranslate(_:)), keyEquivalent: "")
            it.representedObject = idioma
            tradMenu.addItem(it)
        }
        trad.submenu = tradMenu
        menu.addItem(trad)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
        self.appMenu = menu   // el mismo menú se ofrece en el Dock

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        registerHotKey()

        // Caja negra: rescatar dictados de sesiones que murieron a medias,
        // y matar whisper-servers huérfanos de crashes anteriores.
        DispatchQueue.global(qos: .utility).async {
            HistoryWriter.rescatarHuerfanos()
            WhisperServer.limpiarHuerfanos()
            VoxtralServer.limpiarHuerfanos()
        }


        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.panel.meter.push(level)
                if level > 0.15 { self?.lastVoice = Date() }
            }
        }

        // Modo demo para captura de pantalla: BETODICTA_DEMO=1 abre el panel
        // con texto y latido simulado, sin grabar. Solo para el README.
        if ProcessInfo.processInfo.environment["BETODICTA_DEMO"] == "1" {
            startDemo()
        }
        // Abrir Configuración directo (pruebas de UI sin tocar el menú)
        if ProcessInfo.processInfo.environment["BETODICTA_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SettingsWindowController.shared.show()
            }
        }
    }

    private func startDemo() {
        panel.show("revisé el Quipux del GAD y configuré el MikroTik")
        var phase: Double = 0
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            phase += 0.35
            let level = Float(0.4 + 0.5 * abs(sin(phase)) * abs(sin(phase * 0.6)))
            self?.panel.meter.push(level)
        }
    }

    /// Ícono de barra de menú dibujado en código: micrófono + latido.
    /// Es una "template image" → macOS lo tiñe solo según el tema (claro/oscuro).
    private static func menuBarIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let ink = NSColor.black  // template: el color real lo pone el sistema
            ink.setFill()
            ink.setStroke()

            // Cuerpo del micrófono (cápsula)
            NSBezierPath(roundedRect: NSRect(x: 6, y: 6.5, width: 6, height: 9),
                         xRadius: 3, yRadius: 3).fill()

            // Arco/soporte bajo el micrófono
            let stand = NSBezierPath()
            stand.lineWidth = 1.4
            stand.appendArc(withCenter: NSPoint(x: 9, y: 9),
                            radius: 5, startAngle: 200, endAngle: 340)
            stand.stroke()
            // Pie del micrófono
            NSBezierPath(rect: NSRect(x: 8.35, y: 2.2, width: 1.3, height: 2.4)).fill()
            NSBezierPath(rect: NSRect(x: 6.5, y: 2, width: 5, height: 1.1)).fill()

            // 3 barras del latido a la derecha (alturas distintas)
            let heights: [CGFloat] = [4, 7, 5]
            for (i, h) in heights.enumerated() {
                let x = 13.2 + CGFloat(i) * 1.7
                NSBezierPath(roundedRect: NSRect(x: x, y: 9 - h / 2, width: 1.1, height: h),
                             xRadius: 0.5, yRadius: 0.5).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // Puentes públicos para la GUI
    func copyLastDictationPublic() { copyLastDictation() }
    func exportTodayPublic() { exportToday() }
    func openHistoryPublic() { openHistory() }
    func openLogPublic() { openLog() }

    @objc private func openSettings() { Log.log(.ui, "abrir configuración"); SettingsWindowController.shared.show() }
    @objc private func openConfig() { NSWorkspace.shared.open(Config.dir.appendingPathComponent("config.json")) }
    @objc private func openKeyterms() { NSWorkspace.shared.open(Config.dir.appendingPathComponent("keyterms.txt")) }
    @objc private func openReplacements() { NSWorkspace.shared.open(Config.dir.appendingPathComponent("reemplazos.json")) }
    @objc private func copyLastDictation() {
        let fm = FileManager.default
        var newest: (url: URL, date: Date)?
        if let walker = fm.enumerator(at: HistoryWriter.historyDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in walker where url.pathExtension == "txt" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if newest == nil || date > newest!.date { newest = (url, date) }
            }
        }
        guard let newest, let text = try? String(contentsOf: newest.url, encoding: .utf8), !text.isEmpty else {
            panel.show("Historial vacío — nada que copiar")
            panel.hide(after: 1.5)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        panel.show("📋 Copiado: " + text)
        panel.hide(after: 2)
    }

    @objc private func togglePostProcess(_ sender: NSMenuItem) {
        Log.log(.ui, "toggle post-proceso")
        Config.set("post_proceso", to: !Config.postProcess())
    }

    @objc private func setTranslate(_ sender: NSMenuItem) {
        let idioma = sender.representedObject as? String ?? ""
        Config.set("traducir", to: !idioma.isEmpty)
        if !idioma.isEmpty { Config.set("traducir_idioma", to: idioma) }
        Log.log(.ui, "traducir → \(idioma.isEmpty ? "desactivado" : idioma)")
    }

    @objc private func toggleAutostart(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
        } else {
            try? service.register()
        }
    }

    /// Los .txt más recientes del historial, ordenados del más nuevo al más viejo.
    private func latestTexts(_ count: Int) -> [(date: Date, url: URL)] {
        let fm = FileManager.default
        var found: [(Date, URL)] = []
        if let walker = fm.enumerator(at: HistoryWriter.historyDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in walker where url.pathExtension == "txt" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                found.append((date, url))
            }
        }
        return found.sorted { $0.0 > $1.0 }.prefix(count).map { (date: $0.0, url: $0.1) }
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        playSound("Glass")
    }

    @objc private func exportToday() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd"
        let hoy = HistoryWriter.historyDir.appendingPathComponent(fmt.string(from: Date()))
        fmt.dateFormat = "yyyy-MM-dd"
        let día = fmt.string(from: Date())
        var nota = "# Dictados del \(día)\n\n"
        let archivos = ((try? FileManager.default.contentsOfDirectory(at: hoy, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !archivos.isEmpty else {
            panel.show("Hoy no hay dictados que exportar")
            panel.hide(after: 1.5)
            return
        }
        for archivo in archivos {
            let hora = archivo.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: ":")
            let texto = (try? String(contentsOf: archivo, encoding: .utf8)) ?? ""
            nota += "## \(hora)\n\n\(texto)\n\n"
        }
        let destino = Config.exportFolder().appendingPathComponent("Dictados-\(día).md")
        try? nota.write(to: destino, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(destino)
    }

    @objc private func openLog() {
        Log.log(.ui, "abrir registro")
        let log = Config.dir.appendingPathComponent("betodicta.log")
        if !FileManager.default.fileExists(atPath: log.path) {
            try? "".write(to: log, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(log)
    }

    @objc private func toggleDock(_ sender: NSMenuItem) {
        Log.log(.ui, "toggle Dock")
        let show = !Config.showInDock()
        Config.set("mostrar_en_dock", to: show)
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    @objc private func toggleDevMode(_ sender: NSMenuItem) {
        Config.set("modo_desarrollo", to: !Config.devMode())
    }

    @objc private func openHistory() {
        Log.log(.ui, "abrir historial")
        try? FileManager.default.createDirectory(at: HistoryWriter.historyDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(HistoryWriter.historyDir)
    }

    // MARK: Tecla

    private var fnMonitorsInstalled = false

    private func registerHotKey() {
        installCarbonHandler()
        applyBinding()
        // Re-registrar en vivo cuando la GUI cambie la tecla
        NotificationCenter.default.addObserver(
            forName: .betoHotkeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyBinding()
        }
    }

    /// El binding actual, separado en (modificadores, tecla-opcional).
    /// "fn" → (["fn"], nil) · "ctrl+opt" → (["ctrl","opt"], nil) ·
    /// "cmd+shift+d" → (["cmd","shift"], "d")
    private var comboMods: Set<String> = []

    /// Aplica (o re-aplica) la tecla de dictado leyendo la config actual.
    private func applyBinding() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        let parts = tecla.lowercased().split(separator: "+").map(String.init)
        let modNames = ["fn", "cmd", "command", "ctrl", "control", "opt", "alt", "option", "shift"]
        let keyPart = parts.last.flatMap { modNames.contains($0) ? nil : $0 }

        if let key = keyPart, let code = Self.keyCode(for: key) {
            // Tecla real + modificadores → hotkey de Carbon
            var mods = 0
            for p in parts.dropLast() {
                switch p {
                case "cmd", "command": mods |= cmdKey
                case "ctrl", "control": mods |= controlKey
                case "opt", "alt", "option": mods |= optionKey
                case "shift": mods |= shiftKey
                default: break
                }
            }
            let id = EventHotKeyID(signature: OSType(0x42544443), id: 1)
            let status = RegisterEventHotKey(UInt32(code), UInt32(mods), id, GetApplicationEventTarget(), 0, &hotKeyRef)
            comboMods = []
            if status != noErr {                    // atajo inválido/ocupado → fn
                Log.write("hotkey: '\(tecla)' falló (status \(status)), vuelvo a fn")
                fallbackAFn()
            }
        } else {
            // Solo modificadores (fn, ctrl+opt, cmd+shift…) → monitor de flags
            let m = Set(parts.map { p -> String in
                switch p {
                case "command": return "cmd"
                case "control": return "ctrl"
                case "alt", "option": return "opt"
                default: return p
                }
            })
            let validos: Set<String> = ["fn", "cmd", "ctrl", "opt", "shift"]
            if m.isEmpty || !m.isSubset(of: validos) {
                Log.write("hotkey: '\(tecla)' inválido, vuelvo a fn")
                fallbackAFn()
            } else {
                comboMods = m
                installFlagsMonitor()
            }
        }
    }

    private func fallbackAFn() {
        comboMods = ["fn"]
        Config.set("tecla", to: "fn")
        installFlagsMonitor()
    }

    /// Convierte "cmd+shift+d" o "f6" en (keyCode, modificadores Carbon).
    static func parseBinding(_ s: String) -> (Int, Int)? {
        let parts = s.lowercased().split(separator: "+").map { String($0) }
        guard let keyName = parts.last else { return nil }
        var mods = 0
        for p in parts.dropLast() {
            switch p {
            case "cmd", "command": mods |= cmdKey
            case "ctrl", "control": mods |= controlKey
            case "opt", "alt", "option": mods |= optionKey
            case "shift": mods |= shiftKey
            default: break
            }
        }
        guard let code = keyCode(for: keyName) else { return nil }
        return (code, mods)
    }

    /// Nombre de tecla desde un keyCode (para el grabador de atajos).
    static func keyName(for code: Int) -> String? {
        let map: [Int: String] = [
            kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5",
            kVK_F6: "f6", kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9",
            kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12", kVK_Space: "space",
            kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d",
            kVK_ANSI_E: "e", kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h",
            kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
            kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p",
            kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
            kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
            kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
        ]
        return map[code]
    }

    static func keyCode(for name: String) -> Int? {
        let fKeys: [String: Int] = [
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
            "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9,
            "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        ]
        if let f = fKeys[name] { return f }
        let letters: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "space": kVK_Space,
        ]
        return letters[name]
    }

    /// Handler Carbon único: id 1 = tecla de dictado, id 2 = Esc (cancelar).
    private func installCarbonHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async {
                if hotKeyID.id == 1 { delegate.toggle() }
                if hotKeyID.id == 2 { delegate.cancelDictation() }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private var escHotKeyRef: EventHotKeyRef?

    /// Esc se apropia SOLO durante el dictado — sin permisos extra.
    private func armEsc() {
        guard Config.escCancels(), escHotKeyRef == nil else { return }
        let id = EventHotKeyID(signature: OSType(0x42544443), id: 2)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &escHotKeyRef)
    }

    private func disarmEsc() {
        if let ref = escHotKeyRef {
            UnregisterEventHotKey(ref)
            escHotKeyRef = nil
        }
    }

    private var comboArmed = false
    private var comboUsedWithKey = false

    /// Convierte los flags actuales al conjunto de nombres ("fn","ctrl"…).
    private func activeMods(_ f: NSEvent.ModifierFlags) -> Set<String> {
        var s = Set<String>()
        if f.contains(.function) { s.insert("fn") }
        if f.contains(.command) { s.insert("cmd") }
        if f.contains(.control) { s.insert("ctrl") }
        if f.contains(.option) { s.insert("opt") }
        if f.contains(.shift) { s.insert("shift") }
        return s
    }

    /// Monitor de flags para atajos de puros modificadores (fn, ctrl+opt…).
    /// Se dispara al SOLTAR el combo exacto, si no se usó junto a otra tecla.
    private func installFlagsMonitor() {
        guard !fnMonitorsInstalled else { return }
        fnMonitorsInstalled = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        let flagsHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self, !self.comboMods.isEmpty else { return }
            let active = self.activeMods(event.modifierFlags)
            if active == self.comboMods {
                self.comboArmed = true          // combo exacto presionado
                self.comboUsedWithKey = false
            } else if self.comboArmed, active.isEmpty || !self.comboMods.isSubset(of: active) {
                self.comboArmed = false
                if !self.comboUsedWithKey {
                    DispatchQueue.main.async { self.toggle() }
                }
            }
        }
        let keyHandler: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            if self.comboArmed { self.comboUsedWithKey = true }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyHandler)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            flagsHandler(event); return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            keyHandler(event); return event
        }
    }

    // MARK: Flujo de dictado

    func toggle() {
        if recorder.isRecording {
            stopAndTranscribe()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        lastPartial = ""
        lastVoice = Date()
        // Motor local bajo demanda: carga en paralelo mientras hablas.
        // Solo el PRIMER local de la cadena — los de más atrás (failover
        // profundo) arrancan en frío solo si de verdad les toca, para no
        // pagar 2 modelos en RAM por cada dictado.
        let primerLocal = Providers.cadena().first(where: { $0.tipo == "local" })?.id
        DispatchQueue.global(qos: .userInitiated).async {
            switch primerLocal {
            case "whisper_local": WhisperServer.precalentar()
            case "voxtral_local": VoxtralServer.precalentar()
            default: break
            }
        }
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.recorder.isRecording else { timer.invalidate(); return }
            // Mientras grabas, los servers locales no deben apagarse (dictados largos).
            if WhisperServer.corriendo { WhisperServer.tocar() }
            if VoxtralServer.corriendo { VoxtralServer.tocar() }
            let quiet = Date().timeIntervalSince(self.lastVoice)
            let limit = Config.maxSilence()
            if quiet >= limit {
                timer.invalidate()
                self.panel.update("🔇 \(Int(limit))s de silencio — cerrando dictado…")
                self.stopAndTranscribe()
            }
        }
        let history = HistoryWriter()
        self.history = history

        // Streaming local NATIVO: proveedor #1 local con modelo streaming
        // (Nemotron 3.5, Voxtral Realtime) → texto en vivo 100% offline.
        if let primero = Providers.cadena().first,
           ["nemotron_local", "voxtral_local", "canary_local"].contains(primero.id),
           TcppStreamClient.disponible(proveedor: primero.id) {
            let client = TcppStreamClient(proveedor: primero.id)
            self.tcppStream = client
            client.onPartial = { [weak self] texto in
                guard let self, self.recorder.isRecording else { return }
                self.lastPartial = texto
                self.panel.update(texto)
                self.history?.savePartial(texto)
            }
            recorder.onChunk = { [weak client] chunk in
                history.append(chunk: chunk)
                client?.send(chunk: chunk)
            }
            do {
                try client.start()
                try recorder.start()
                armEsc()
                media.dictationStarted()
                playSound("Tink")
                panel.show("Escuchando (local en vivo)… (\(tecla) termina)")
            } catch {
                self.tcppStream = nil
                panel.show("⚠️ \(error.localizedDescription)")
                panel.hide(after: 3)
                history.discard(); self.history = nil
            }
            return
        }

        if isStreamingModel {
            panel.show("Conectando con Scribe…")
            let stream = StreamClient()
            self.stream = stream
            stream.onPartial = { [weak self] text in
                guard let self else { return }
                self.lastPartial = text
                let done = stream.fullText()
                let visible = done.isEmpty ? text : done + " " + text
                self.panel.update(visible)
                history.savePartial(visible)
            }
            stream.onCommitted = { [weak self] full in
                self?.panel.update(full)
                history.savePartial(full, force: true)
            }
            stream.onError = { [weak self] message in
                Log.write("stream: ERROR \(message)")
                self?.panel.update("⚠️ \(message)")
            }
            stream.connect { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    // Sin streaming (sin red/saldo): grabar igual y usar el
                    // failover al terminar. El dictado no se pierde.
                    Log.log(.ia, "streaming no conectó (\(error.localizedDescription)) → grabando para failover")
                    self.stream = nil
                    self.recorder.onChunk = { chunk in history.append(chunk: chunk) }
                    do {
                        try self.recorder.start()
                        self.armEsc()
                        self.media.dictationStarted()
                        self.playSound("Tink")
                        self.panel.update("Escuchando (sin conexión)… (\(self.tecla) termina)")
                    } catch {
                        self.panel.update("⚠️ Micrófono: \(error.localizedDescription)")
                        self.panel.hide(after: 3)
                        history.discard(); self.history = nil
                    }
                case .success:
                    self.recorder.onChunk = { [weak stream] chunk in
                        history.append(chunk: chunk)
                        stream?.send(chunk: chunk)
                    }
                    do {
                        try self.recorder.start()
                        self.armEsc()
                        self.media.dictationStarted()
                        self.playSound("Tink")
                        self.panel.update("Escuchando… (\(self.tecla) para terminar)")
                    } catch {
                        self.panel.update("⚠️ Micrófono: \(error.localizedDescription)")
                        self.panel.hide(after: 3)
                    }
                }
            }
        } else {
            recorder.onChunk = { chunk in
                history.append(chunk: chunk)
            }
            do {
                try recorder.start()
                armEsc()
                media.dictationStarted()
                playSound("Tink")
                panel.show("Escuchando… (\(tecla) para terminar)")
                startLiveLocal(history: history)
            } catch {
                panel.show("⚠️ Micrófono: \(error.localizedDescription)")
                panel.hide(after: 3)
            }
        }
    }

    // MARK: Texto en vivo LOCAL (pseudo-streaming con whisper-server caliente)
    //
    // Cada ~1.6 s re-transcribe el audio acumulado contra el server residente
    // y actualiza el panel — el efecto ElevenLabs, 100% offline. Solo corre
    // cuando el primer proveedor local de la cadena es Whisper y el panel
    // está visible; el resultado FINAL sigue saliendo del failover normal.
    private var liveTimer: Timer?
    private var liveEnVuelo = false
    private var tcppStream: TcppStreamClient?

    private func startLiveLocal(history: HistoryWriter) {
        guard Config.panelVisible(),
              Providers.cadena().first(where: { $0.tipo == "local" })?.id == "whisper_local" else { return }
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.recorder.isRecording else { timer.invalidate(); return }
            guard WhisperServer.corriendo, !self.liveEnVuelo else { return }
            let pcm = self.recorder.pcmAcumulado
            guard pcm.count > 16000 else { return }   // >0.5 s de audio
            self.liveEnVuelo = true
            WhisperServer.transcribe(wav: HistoryWriter.wavData(pcm: pcm)) { [weak self] r in
                guard let self else { return }
                self.liveEnVuelo = false
                // Solo pintar si seguimos grabando (evita pisar el resultado final)
                if case .success(let texto) = r, self.recorder.isRecording, !texto.isEmpty {
                    self.lastPartial = texto
                    self.panel.update(texto)
                    self.history?.savePartial(texto)
                }
            }
        }
    }

    private func stopAndTranscribe() {
        disarmEsc()
        media.dictationEnded()
        silenceTimer?.invalidate()
        silenceTimer = nil
        liveTimer?.invalidate()
        liveTimer = nil
        let wav = recorder.stop()
        let seconds = Double(wav.count - 44) / 32000.0

        // Streaming local nativo: cerrar el audio y esperar el texto final.
        if let tcpp = tcppStream {
            self.tcppStream = nil
            guard seconds > 0.4 else {
                tcpp.cancel()
                history?.discard(); history = nil
                panel.update("Muy corto — nada que transcribir")
                panel.hide(after: 1.2)
                return
            }
            panel.update("⏳ Cerrando dictado…")
            var entregado = false
            tcpp.onFinal = { [weak self] final in
                guard let self, !entregado else { return }
                entregado = true
                if final.isEmpty {
                    // Motor cerró sin texto: que la cascada normal lo rescate.
                    Failover.transcribe(wav: wav) { [weak self] r in
                        if case .success(let (raw, proveedor)) = r {
                            self?.deliver(raw: raw, wav: wav, via: proveedor)
                        } else {
                            self?.history?.finish(wav: wav, finalText: "")
                            self?.history = nil
                            self?.panel.update("⚠️ Sin texto — audio guardado")
                            self?.panel.hide(after: 3)
                        }
                    }
                } else {
                    self.deliver(raw: final, wav: wav, via: "Nemotron (en vivo)")
                }
            }
            tcpp.finish()
            // Tope: si el motor no responde en 20 s, cascada normal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard !entregado else { return }
                entregado = true
                tcpp.cancel()
                Log.log(.ia, "beto-stream no entregó el final → failover")
                Failover.transcribe(wav: wav) { [weak self] r in
                    if case .success(let (raw, proveedor)) = r {
                        self?.deliver(raw: raw, wav: wav, via: proveedor)
                    } else {
                        self?.history?.finish(wav: wav, finalText: "")
                        self?.history = nil
                        self?.panel.update("⚠️ Todos fallaron — audio guardado")
                        self?.panel.hide(after: 3)
                    }
                }
            }
            return
        }

        if let stream {
            guard seconds > 0.4 else {
                stream.disconnect()
                self.stream = nil
                history?.discard()
                history = nil
                panel.update("Muy corto — nada que transcribir")
                panel.hide(after: 1.2)
                return
            }
            panel.update("⏳ Cerrando dictado…")
            stream.commit()
            // Esperar el committed final (con tope de 6 s y respaldo al último parcial)
            var finished = false
            let finish: (String) -> Void = { [weak self] raw in
                guard let self, !finished else { return }
                finished = true
                stream.disconnect()
                self.stream = nil
                self.deliver(raw: raw, wav: wav, via: "ElevenLabs (en vivo)")
            }
            stream.onCommitted = { full in finish(full) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, !finished else { return }
                let fallback = stream.fullText().isEmpty ? self.lastPartial : stream.fullText()
                finish(fallback)
            }
        } else {
            guard seconds > 0.4 else {
                history?.discard()
                history = nil
                panel.update("Muy corto — nada que transcribir")
                panel.hide(after: 1.2)
                return
            }
            panel.update("⏳ Transcribiendo…")
            // Failover: recorre los proveedores activos en orden.
            Failover.transcribe(wav: wav) { [weak self] result in
                switch result {
                case .success(let (raw, proveedor)):
                    if proveedor != "ElevenLabs Scribe" { self?.panel.update("vía \(proveedor)") }
                    self?.deliver(raw: raw, wav: wav, via: proveedor)
                case .failure(let error):
                    self?.history?.finish(wav: wav, finalText: "")
                    self?.history = nil
                    self?.panel.update("⚠️ Todos los proveedores fallaron — audio guardado")
                    Log.log(.ia, "failover agotado: \(error.localizedDescription)")
                    self?.panel.hide(after: 4)
                }
            }
        }
    }

    private func deliver(raw: String, wav: Data, via proveedor: String) {
        let segundos = Double(wav.count - 44) / 32000.0
        UsageLog.record(provider: proveedor, seconds: segundos)

        let crudo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trasReglas = applyReplacements(crudo)

        // Pipeline de auditoría — cada paso queda registrado
        Log.write("──── dictado \(String(format: "%.1f", segundos))s · \(proveedor) ────")
        Log.write("  1·crudo:      \(crudo)")
        if trasReglas != crudo {
            Log.write("  2·reglas:     \(trasReglas)")
        }

        guard !trasReglas.isEmpty else {
            history?.finish(wav: wav, finalText: "")
            history = nil
            panel.update("(silencio)")
            panel.hide(after: 1.8)
            return
        }
        // Paso opcional: pulir con IA → luego traducir (si están activos)
        let seguir: (String) -> Void = { [weak self] texto in
            self?.talVezTraducir(texto, rawText: crudo, wav: wav)
        }
        if Config.postProcess(), Config.groqKey() != nil {
            panel.update("🤖 Puliendo…")
            LLMPostProcess.enhance(trasReglas) { pulido in
                if pulido != trasReglas { Log.write("  3·IA:         \(pulido)") }
                seguir(pulido)
            }
        } else {
            seguir(trasReglas)
        }
    }

    /// Si "traducir" está activo, traduce antes de entregar; si no, entrega directo.
    private func talVezTraducir(_ text: String, rawText: String, wav: Data) {
        if Config.translate(), Config.groqKey() != nil {
            let idioma = Config.translateTo()
            panel.update("🌐 Traduciendo a \(idioma)…")
            Translate.to(idioma, text: text) { [weak self] traducido in
                Log.write("  4·traducido:  \(traducido)")
                Log.write("  ✓ entregado:  \(traducido)")
                self?.finishDelivery(traducido, rawText: rawText, wav: wav)
            }
        } else {
            Log.write("  ✓ entregado:  \(text)")
            finishDelivery(text, rawText: rawText, wav: wav)
        }
    }

    private func finishDelivery(_ text: String, rawText: String, wav: Data) {
        // El .txt guarda SOLO lo entregado, limpio. El crudo queda en el log.
        history?.finish(wav: wav, finalText: text)
        history = nil
        pasteText(text)
        playSound("Glass")
        panel.update("✓ " + text)
        panel.hide(after: 1.8)
    }
}


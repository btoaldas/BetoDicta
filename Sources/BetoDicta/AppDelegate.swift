import AppKit
import AVFoundation
import Carbon.HIToolbox
import ServiceManagement

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first(where: { $0.tag == 77 })?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
        menu.items.first(where: { $0.tag == 78 })?.state = Config.postProcess() ? .on : .off
        menu.items.first(where: { $0.tag == 79 })?.state = Config.devMode() ? .on : .off
        menu.items.first(where: { $0.tag == 81 })?.state = Config.showInDock() ? .on : .off
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
        _ = recorder.stop()
        stream?.disconnect()
        stream = nil
        history?.discard()
        history = nil
        playSound("Basso")
        panel.update("✕ Cancelado")
        panel.hide(after: 1)
    }

    private var tecla: String { Config.hotkey() }
    private var isStreamingModel: Bool { Config.model() == "scribe_v2_realtime" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🎙"
        let menu = NSMenu()
        menu.addItem(withTitle: "BetoDicta v0.4 — \(tecla) para dictar (\(Config.model()))", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Editar configuración", action: #selector(openConfig), keyEquivalent: "")
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        registerHotKey()


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
        Config.set("post_proceso", to: !Config.postProcess())
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
        let log = Config.dir.appendingPathComponent("betodicta.log")
        if !FileManager.default.fileExists(atPath: log.path) {
            try? "".write(to: log, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(log)
    }

    @objc private func toggleDock(_ sender: NSMenuItem) {
        let show = !Config.showInDock()
        Config.set("mostrar_en_dock", to: show)
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    @objc private func toggleDevMode(_ sender: NSMenuItem) {
        Config.set("modo_desarrollo", to: !Config.devMode())
    }

    @objc private func openHistory() {
        try? FileManager.default.createDirectory(at: HistoryWriter.historyDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(HistoryWriter.historyDir)
    }

    // MARK: Tecla

    private func registerHotKey() {
        installCarbonHandler()
        if tecla.lowercased() == "fn" {
            registerFnKey()
        } else {
            registerFKey(named: tecla.lowercased())
        }
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

    private var fnDown = false
    private var fnUsedInCombo = false

    private func registerFnKey() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        let flagsHandler: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.keyCode == 63 else { return }
            if event.modifierFlags.contains(.function) {
                self.fnDown = true
                self.fnUsedInCombo = false
            } else if self.fnDown {
                self.fnDown = false
                if !self.fnUsedInCombo {
                    DispatchQueue.main.async { self.toggle() }
                }
            }
        }
        let comboHandler: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            if self.fnDown { self.fnUsedInCombo = true }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: comboHandler)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            flagsHandler(event); return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            comboHandler(event); return event
        }
    }

    private func registerFKey(named name: String) {
        let fKeys: [String: Int] = [
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
            "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
            "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        ]
        let keyCode = fKeys[name] ?? kVK_F6

        let hotKeyID = EventHotKeyID(signature: OSType(0x42544443), id: 1) // "BTDC"
        RegisterEventHotKey(UInt32(keyCode), 0, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
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
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.recorder.isRecording else { timer.invalidate(); return }
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
                    self.panel.update("⚠️ \(error.localizedDescription)")
                    self.panel.hide(after: 3)
                    self.stream = nil
                    history.discard()
                    self.history = nil
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
            } catch {
                panel.show("⚠️ Micrófono: \(error.localizedDescription)")
                panel.hide(after: 3)
            }
        }
    }

    private func stopAndTranscribe() {
        disarmEsc()
        media.dictationEnded()
        silenceTimer?.invalidate()
        silenceTimer = nil
        let wav = recorder.stop()
        let seconds = Double(wav.count - 44) / 32000.0

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
                self.deliver(raw: raw, wav: wav)
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
            panel.update("⏳ Transcribiendo \(String(format: "%.1f", seconds))s…")
            transcribeBatch(wav: wav, model: Config.model()) { [weak self] result in
                switch result {
                case .success(let raw):
                    self?.deliver(raw: raw, wav: wav)
                case .failure(let error):
                    // Falló la nube, pero tu voz queda a salvo en el historial
                    self?.history?.finish(wav: wav, finalText: "")
                    self?.history = nil
                    self?.panel.update("⚠️ \(error.localizedDescription) — audio guardado en historial")
                    self?.panel.hide(after: 4)
                }
            }
        }
    }

    private func deliver(raw: String, wav: Data) {
        let segundos = Double(wav.count - 44) / 32000.0
        UsageLog.record(provider: Config.model(), seconds: segundos)

        let crudo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let trasReglas = applyReplacements(crudo)

        // Pipeline de auditoría — cada paso queda registrado
        Log.write("──── dictado \(String(format: "%.1f", segundos))s · \(Config.model()) ────")
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
        if Config.postProcess(), Config.groqKey() != nil {
            panel.update("🤖 Puliendo…")
            LLMPostProcess.enhance(trasReglas) { [weak self] pulido in
                if pulido != trasReglas { Log.write("  3·IA:         \(pulido)") }
                Log.write("  ✓ entregado:  \(pulido)")
                self?.finishDelivery(pulido, rawText: crudo, wav: wav)
            }
        } else {
            Log.write("  ✓ entregado:  \(trasReglas)")
            finishDelivery(trasReglas, rawText: crudo, wav: wav)
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


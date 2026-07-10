import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let acentoEd = Color(red: 0.36, green: 0.28, blue: 0.62)

// MARK: - Editor visual de keyterms (CRUD completo + activar/desactivar + import/export)

struct Keyterm: Identifiable {
    let id = UUID()
    var texto: String
    var activo: Bool
}

final class KeytermsStore: ObservableObject {
    @Published var items: [Keyterm] = []
    private var url: URL { Config.dir.appendingPathComponent("keyterms.txt") }

    init() { load() }

    func load() {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        items = text.split(separator: "\n").compactMap { raw in
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return nil }
            // "# palabra" = desactivada (se conserva pero no se usa)
            if s.hasPrefix("#") {
                let t = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : Keyterm(texto: t, activo: false)
            }
            return Keyterm(texto: s, activo: true)
        }
    }
    func save() {
        let text = items.map { $0.activo ? $0.texto : "# \($0.texto)" }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
    func add(_ w: String) {
        let t = w.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !items.contains(where: { $0.texto.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        items.insert(Keyterm(texto: t, activo: true), at: 0); save(); Log.log(.config, "glosario: +\(t)")
    }
    func remove(_ offsets: IndexSet) { items.remove(atOffsets: offsets); save(); Log.log(.config, "glosario: eliminada palabra") }
    var activas: Int { items.filter { $0.activo }.count }

    func exportar(to dest: URL) { try? String(contentsOf: url, encoding: .utf8).write(to: dest, atomically: true, encoding: .utf8) }
    func importar(from src: URL) {
        guard let nuevo = try? String(contentsOf: src, encoding: .utf8) else { return }
        for linea in nuevo.split(separator: "\n") {
            let s = linea.trimmingCharacters(in: .whitespaces)
            add(s.hasPrefix("#") ? String(s.dropFirst()).trimmingCharacters(in: .whitespaces) : s)
        }
    }
}

struct KeytermsEditor: View {
    @StateObject private var store = KeytermsStore()
    @State private var nueva = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Palabras del glosario").font(.title3).bold()
                    Text("\(store.activas) activas de \(store.items.count) · viajan al modelo")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Importar…") { importar() }
                    Button("Exportar…") { exportar() }
                } label: { Image(systemName: "square.and.arrow.up.on.square") }
                    .frame(width: 44)
            }

            HStack {
                TextField("Nueva palabra…", text: $nueva)
                    .textFieldStyle(.roundedBorder).onSubmit { agregar() }
                Button("Agregar", action: agregar)
                    .disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach($store.items) { $item in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { item.activo },
                            set: { item.activo = $0; store.save() }))
                            .toggleStyle(.checkbox).labelsHidden()
                        TextField("", text: Binding(
                            get: { item.texto },
                            set: { item.texto = $0 }), onCommit: { store.save() })
                            .textFieldStyle(.plain)
                            .foregroundStyle(item.activo ? .primary : .secondary)
                            .strikethrough(!item.activo)
                        Spacer()
                        Button { borrar(item.id) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }
                .onDelete { store.remove($0) }
            }
            .frame(minHeight: 280)
        }
        .padding(20).frame(width: 440, height: 520)
    }

    private func agregar() { store.add(nueva); nueva = "" }
    private func borrar(_ id: UUID) {
        if let i = store.items.firstIndex(where: { $0.id == id }) { store.remove(IndexSet(integer: i)) }
    }
    private func exportar() {
        let p = NSSavePanel(); p.nameFieldStringValue = "glosario-betodicta.txt"
        if p.runModal() == .OK, let url = p.url { store.exportar(to: url); Log.log(.config, "exportado a \(url.lastPathComponent)") }
    }
    private func importar() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.plainText, .text]
        if p.runModal() == .OK, let url = p.url { store.importar(from: url); Log.log(.config, "importado de \(url.lastPathComponent)") }
    }
}

// MARK: - Editor visual de reemplazos (CRUD + activar/desactivar + import/export)

struct Rule: Identifiable {
    let id = UUID()
    var original: String
    var replacement: String
    var isRegex: Bool
    var activo: Bool
}

final class RulesStore: ObservableObject {
    @Published var rules: [Rule] = []
    private var url: URL { Config.dir.appendingPathComponent("reemplazos.json") }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        rules = arr.map { Rule(original: $0["original"] as? String ?? "",
                               replacement: $0["replacement"] as? String ?? "",
                               isRegex: $0["isRegex"] as? Bool ?? false,
                               activo: $0["activo"] as? Bool ?? true) }
    }
    /// Guarda descartando filas totalmente vacías (así no quedan huérfanas).
    func save() {
        let limpias = rules.filter {
            !($0.original.trimmingCharacters(in: .whitespaces).isEmpty &&
              $0.replacement.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        let arr = limpias.map { r -> [String: Any] in
            var d: [String: Any] = ["original": r.original, "replacement": r.replacement]
            if r.isRegex { d["isRegex"] = true }
            if !r.activo { d["activo"] = false }
            return d
        }
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
    }
    func purgarVacias() {
        rules.removeAll {
            $0.original.trimmingCharacters(in: .whitespaces).isEmpty &&
            $0.replacement.trimmingCharacters(in: .whitespaces).isEmpty
        }
        save()
    }
    func add() { rules.append(Rule(original: "", replacement: "", isRegex: false, activo: true)); Log.log(.config, "reemplazos: +fila") }
    func remove(_ id: UUID) { rules.removeAll { $0.id == id }; save(); Log.log(.config, "reemplazos: eliminada regla") }

    func exportar(to dest: URL) { try? Data(contentsOf: url).write(to: dest) }
    func importar(from src: URL) {
        guard let data = try? Data(contentsOf: src),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for d in arr {
            rules.append(Rule(original: d["original"] as? String ?? "",
                              replacement: d["replacement"] as? String ?? "",
                              isRegex: d["isRegex"] as? Bool ?? false,
                              activo: d["activo"] as? Bool ?? true))
        }
        save()
    }
}

struct RulesEditor: View {
    @StateObject private var store = RulesStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reemplazos").font(.title3).bold()
                    Text("Si el modelo escucha lo de la izquierda, lo cambia por lo de la derecha.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Importar…") { importar() }
                    Button("Exportar…") { exportar() }
                } label: { Image(systemName: "square.and.arrow.up.on.square") }.frame(width: 44)
                Button { store.add() } label: { Image(systemName: "plus") }
            }
            HStack(spacing: 8) {
                Text("").frame(width: 22)
                Text("Escuchado (variantes con coma)").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                Text("Se escribe").font(.caption).frame(width: 120, alignment: .leading)
                Text("").frame(width: 22)
            }
            List {
                ForEach($store.rules) { $rule in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(get: { rule.activo },
                                                 set: { rule.activo = $0; store.save() }))
                            .toggleStyle(.checkbox).labelsHidden().frame(width: 22)
                        TextField("kipux, keybox…", text: $rule.original, onCommit: { store.save() })
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Quipux", text: $rule.replacement, onCommit: { store.save() })
                            .textFieldStyle(.roundedBorder).frame(width: 110)
                        Button { store.remove(rule.id) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }.buttonStyle(.plain).frame(width: 22)
                    }
                    .opacity(rule.activo ? 1 : 0.5)
                }
            }
            .frame(minHeight: 300)
        }
        .padding(20).frame(width: 580, height: 520)
        .onDisappear { store.purgarVacias() }   // al cerrar, limpia filas en blanco
    }

    private func exportar() {
        let p = NSSavePanel(); p.nameFieldStringValue = "reemplazos-betodicta.json"
        if p.runModal() == .OK, let url = p.url { store.exportar(to: url); Log.log(.config, "exportado a \(url.lastPathComponent)") }
    }
    private func importar() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let url = p.url { store.importar(from: url); Log.log(.config, "importado de \(url.lastPathComponent)") }
    }
}

// MARK: - Ventanas contenedoras

enum EditorWindows {
    private static var keytermsWin: NSWindow?
    private static var rulesWin: NSWindow?

    static func showKeyterms() { show(&keytermsWin, "Glosario · BetoDicta", KeytermsEditor()) }
    static func showRules() { show(&rulesWin, "Reemplazos · BetoDicta", RulesEditor()) }

    private static func show<V: View>(_ win: inout NSWindow?, _ title: String, _ view: V) {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = title
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.center()
        win?.makeKeyAndOrderFront(nil)
    }
}

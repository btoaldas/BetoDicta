import Foundation

// MARK: - Mini tareas/notas locales (Fase 4 de Modos)
//
// Almacén simple en ~/.betodicta/pendientes.json. Un dictado con modo Tarea/Nota
// (o cualquier modo con `almacen` puesto) agrega un ítem aquí, además de pegarlo.
// Se ven/gestionan en Ajustes → Tareas y notas. 100% local, sin nube.

struct Pendiente: Codable, Identifiable {
    var id: String
    var tipo: String      // "tarea" | "nota"
    var texto: String
    var fecha: Double     // epoch (segundos)
    var hecho: Bool       // solo tareas

    init(tipo: String, texto: String) {
        id = UUID().uuidString; self.tipo = tipo; self.texto = texto
        fecha = Date().timeIntervalSince1970; hecho = false
    }
    // Decodificación tolerante.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        tipo = (try? c.decode(String.self, forKey: .tipo)) ?? "nota"
        texto = (try? c.decode(String.self, forKey: .texto)) ?? ""
        fecha = (try? c.decode(Double.self, forKey: .fecha)) ?? 0
        hecho = (try? c.decode(Bool.self, forKey: .hecho)) ?? false
    }
}

enum NotasStore {
    private static var url: URL { Config.dir.appendingPathComponent("pendientes.json") }
    private static let lock = NSLock()

    static func todos() -> [Pendiente] {
        lock.lock(); defer { lock.unlock() }
        guard let d = try? Data(contentsOf: url),
              let l = try? JSONDecoder().decode([Pendiente].self, from: d) else { return [] }
        return l
    }
    static func tareas() -> [Pendiente] { todos().filter { $0.tipo == "tarea" } }
    static func notas() -> [Pendiente] { todos().filter { $0.tipo == "nota" } }

    private static func guardar(_ items: [Pendiente]) {
        Config.asegurarDirSeguro()
        if let d = try? JSONEncoder().encode(items) {
            lock.lock(); try? d.write(to: url, options: .atomic); lock.unlock()
        }
    }

    @discardableResult static func agregar(tipo: String, texto: String) -> Pendiente {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = Pendiente(tipo: tipo == "tarea" ? "tarea" : "nota", texto: t)
        var l = todos(); l.insert(p, at: 0); guardar(l)
        Log.log(.config, "\(p.tipo) agregada: \(t.prefix(40))")
        return p
    }
    static func borrar(_ id: String) { guardar(todos().filter { $0.id != id }) }
    static func alternar(_ id: String) {
        var l = todos()
        if let i = l.firstIndex(where: { $0.id == id }) { l[i].hecho.toggle(); guardar(l) }
    }
    static func editar(_ id: String, texto: String) {
        var l = todos()
        if let i = l.firstIndex(where: { $0.id == id }) { l[i].texto = texto; guardar(l) }
    }
    /// Borra las tareas marcadas como hechas.
    static func limpiarHechas() { guardar(todos().filter { !($0.tipo == "tarea" && $0.hecho) }) }
}

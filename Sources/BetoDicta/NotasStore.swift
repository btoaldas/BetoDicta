import Darwin
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
    var fechaObjetivo: Double? // fecha/hora opcional del recordatorio local
    var avisar: Bool           // interruptor por ítem
    var avisadoEn: Double?     // evita repetir el mismo aviso tras reiniciar

    init(tipo: String, texto: String, fechaObjetivo: Date? = nil,
         avisar: Bool? = nil) {
        id = UUID().uuidString; self.tipo = tipo; self.texto = texto
        fecha = Date().timeIntervalSince1970; hecho = false
        self.fechaObjetivo = fechaObjetivo?.timeIntervalSince1970
        self.avisar = avisar ?? (fechaObjetivo != nil)
        avisadoEn = nil
    }
    // Decodificación tolerante.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        tipo = (try? c.decode(String.self, forKey: .tipo)) ?? "nota"
        texto = (try? c.decode(String.self, forKey: .texto)) ?? ""
        fecha = (try? c.decode(Double.self, forKey: .fecha)) ?? 0
        hecho = (try? c.decode(Bool.self, forKey: .hecho)) ?? false
        fechaObjetivo = try? c.decodeIfPresent(Double.self, forKey: .fechaObjetivo)
        avisar = (try? c.decode(Bool.self, forKey: .avisar)) ?? (fechaObjetivo != nil)
        avisadoEn = try? c.decodeIfPresent(Double.self, forKey: .avisadoEn)
    }
}

extension Notification.Name {
    static let betoPendientesChanged = Notification.Name("BetoDictaPendientesChanged")
}

enum NotasStore {
    private static var url: URL { Config.dir.appendingPathComponent("pendientes.json") }
    private static var lockURL: URL { Config.dir.appendingPathComponent("pendientes.lock") }
    private static let lock = NSLock()

    /// `NSLock` cubre los hilos de la app; `flock` cubre además dos hooks/binarios
    /// de QA simultáneos. El candado vive en un archivo separado porque el JSON se
    /// reemplaza atómicamente y, por tanto, cambia de inode al guardar.
    private static func conBloqueo<T>(_ bloque: () -> T) -> T {
        lock.lock()
        Config.asegurarDirSeguro()
        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        var bloqueoArchivo = Darwin.flock()
        bloqueoArchivo.l_type = Int16(F_WRLCK)
        bloqueoArchivo.l_whence = Int16(SEEK_SET)
        if fd >= 0 {
            _ = Darwin.fchmod(fd, S_IRUSR | S_IWUSR)
            _ = Darwin.fcntl(fd, F_SETLKW, &bloqueoArchivo)
        }
        defer {
            if fd >= 0 {
                bloqueoArchivo.l_type = Int16(F_UNLCK)
                _ = Darwin.fcntl(fd, F_SETLK, &bloqueoArchivo)
                _ = Darwin.close(fd)
            }
            lock.unlock()
        }
        return bloque()
    }

    private static func cargarSinLock() -> [Pendiente] {
        guard let d = try? Data(contentsOf: url),
              let l = try? JSONDecoder().decode([Pendiente].self, from: d) else { return [] }
        return l
    }

    static func todos() -> [Pendiente] {
        conBloqueo { cargarSinLock() }
    }
    static func tareas() -> [Pendiente] { todos().filter { $0.tipo == "tarea" } }
    static func notas() -> [Pendiente] { todos().filter { $0.tipo == "nota" } }

    private static func guardarSinLock(_ items: [Pendiente]) {
        Config.asegurarDirSeguro()
        if let d = try? JSONEncoder().encode(items) {
            try? d.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                    ofItemAtPath: url.path)
        }
    }

    private static func mutar(_ bloque: (inout [Pendiente]) -> Bool) {
        let cambio = conBloqueo {
            var items = cargarSinLock()
            let cambio = bloque(&items)
            if cambio { guardarSinLock(items) }
            return cambio
        }
        guard cambio else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .betoPendientesChanged, object: nil)
        }
    }

    @discardableResult static func agregar(tipo: String, texto: String) -> Pendiente {
        agregar(tipo: tipo, texto: texto, fechaObjetivo: nil, avisar: nil)
    }

    @discardableResult static func agregar(tipo: String, texto: String,
                                           fechaObjetivo: Date?,
                                           avisar: Bool? = nil) -> Pendiente {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectada = fechaObjetivo ?? AppleAgenda.previsualizar(t).fecha
        let p = Pendiente(tipo: tipo == "tarea" ? "tarea" : "nota", texto: t,
                          fechaObjetivo: detectada, avisar: avisar)
        mutar { $0.insert(p, at: 0); return true }
        Log.log(.config, "\(p.tipo) agregada: \(t.prefix(40))")
        return p
    }
    static func borrar(_ id: String) {
        mutar { items in
            let antes = items.count; items.removeAll { $0.id == id }
            return items.count != antes
        }
    }
    static func alternar(_ id: String) {
        mutar { items in
            guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
            items[i].hecho.toggle(); return true
        }
    }
    static func editar(_ id: String, texto: String) {
        mutar { items in
            guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
            items[i].texto = texto
            if items[i].fechaObjetivo == nil,
               let fecha = AppleAgenda.previsualizar(texto).fecha {
                items[i].fechaObjetivo = fecha.timeIntervalSince1970
                items[i].avisar = true; items[i].avisadoEn = nil
            }
            return true
        }
    }

    static func programar(_ id: String, fecha: Date?, avisar: Bool) {
        mutar { items in
            guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
            items[i].fechaObjetivo = fecha?.timeIntervalSince1970
            items[i].avisar = avisar && fecha != nil
            items[i].avisadoEn = nil
            return true
        }
    }

    /// Marca exactamente una vez y devuelve el ítem que ganó la carrera. El timer,
    /// el despertar de la Mac y un cambio de configuración pueden coincidir.
    @discardableResult static func marcarAvisado(_ id: String, ahora: Date = Date()) -> Pendiente? {
        var resultado: Pendiente?
        mutar { items in
            guard let i = items.firstIndex(where: {
                $0.id == id && !$0.hecho && $0.avisar && $0.avisadoEn == nil
            }) else { return false }
            items[i].avisadoEn = ahora.timeIntervalSince1970
            resultado = items[i]
            return true
        }
        return resultado
    }
    /// Borra las tareas marcadas como hechas.
    static func limpiarHechas() {
        mutar { items in
            let antes = items.count
            items.removeAll { $0.tipo == "tarea" && $0.hecho }
            return items.count != antes
        }
    }
}

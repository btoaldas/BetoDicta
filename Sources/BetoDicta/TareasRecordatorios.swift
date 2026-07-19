import Foundation
import UserNotifications

/// Reloj local de Tareas y notas. No usa IA ni nube: detecta vencimientos,
/// recupera avisos al despertar/reabrir la Mac y ofrece dos resúmenes diarios.
final class TareasRecordatorios: NSObject, UNUserNotificationCenterDelegate {
    struct Aviso {
        let titulo: String
        let cuerpo: String
        let hablar: Bool
        let id: String
    }

    static let shared = TareasRecordatorios()
    private let centro: UNUserNotificationCenter?
    private var timer: Timer?
    private var observador: NSObjectProtocol?
    private var presentar: ((Aviso) -> Void)?
    private var iniciada = false

    private override init() {
        // UserNotifications lanza una excepción Objective-C (no capturable en
        // Swift) si el ejecutable se abre suelto desde build/release. El reloj y
        // el notch sí funcionan allí; el centro del sistema solo existe en .app.
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app",
           Bundle.main.bundleIdentifier != nil {
            centro = UNUserNotificationCenter.current()
        } else { centro = nil }
        super.init()
    }

    func iniciar(presentar: @escaping (Aviso) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.iniciar(presentar: presentar) }
            return
        }
        self.presentar = presentar
        guard !iniciada else { revisarAhora(); return }
        iniciada = true
        centro?.delegate = self
        observador = NotificationCenter.default.addObserver(
            forName: .betoPendientesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.solicitarPermisoSiHaceFalta()
            self?.revisarAhora()
        }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.revisarAhora()
        }
        RunLoop.main.add(t, forMode: .common); timer = t
        solicitarPermisoSiHaceFalta()
        // Deja terminar el arranque visual antes de mostrar un aviso recuperado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.revisarAhora() }
    }

    func detener() {
        timer?.invalidate(); timer = nil
        if let observador { NotificationCenter.default.removeObserver(observador) }
        observador = nil; iniciada = false; presentar = nil
    }

    func solicitarPermisoSiHaceFalta() {
        let necesitaAvisos = Config.tareasAvisos() && NotasStore.todos().contains {
            $0.fechaObjetivo != nil && !$0.hecho && $0.avisar
                && ($0.tipo == "tarea" || Config.tareasAvisarNotas())
        }
        let necesita = necesitaAvisos
            || Config.tareasResumenManana() || Config.tareasResumenTarde()
        guard necesita, let centro else { return }
        centro.getNotificationSettings { [weak self] ajustes in
            guard ajustes.authorizationStatus == .notDetermined else { return }
            self?.centro?.requestAuthorization(options: [.alert, .sound]) { permitido, error in
                if let error { Log.write("⚠️ avisos de tareas: \(error.localizedDescription)") }
                else { Log.write("avisos de tareas: permiso \(permitido ? "concedido" : "denegado")") }
            }
        }
    }

    static func estadoPermiso(completion: @escaping (String) -> Void) {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app",
              Bundle.main.bundleIdentifier != nil else {
            completion("Disponibles en la app instalada"); return
        }
        UNUserNotificationCenter.current().getNotificationSettings { ajustes in
            let texto: String
            switch ajustes.authorizationStatus {
            case .authorized: texto = "Permitidas"
            case .provisional: texto = "Provisionales"
            case .denied: texto = "Denegadas en macOS"
            case .notDetermined: texto = "Se pedirán al primer aviso"
            @unknown default: texto = "Estado desconocido"
            }
            DispatchQueue.main.async { completion(texto) }
        }
    }

    /// Visible para QA. Resume sin IA y sin enviar datos fuera de la Mac.
    static func resumenTexto(items: [Pendiente], ahora: Date,
                             incluirSinFecha: Bool = true) -> String {
        let cal = Calendar.current
        let inicioHoy = cal.startOfDay(for: ahora)
        let inicioManana = cal.date(byAdding: .day, value: 1, to: inicioHoy)!
        let finManana = cal.date(byAdding: .day, value: 1, to: inicioManana)!
        let tareas = items.filter { $0.tipo == "tarea" && !$0.hecho }
        guard !tareas.isEmpty else { return "No tienes tareas pendientes." }

        var vencidas = 0, hoy = 0, manana = 0, despues = 0, sinFecha = 0
        for t in tareas {
            guard let e = t.fechaObjetivo else { sinFecha += 1; continue }
            let f = Date(timeIntervalSince1970: e)
            if f < inicioHoy { vencidas += 1 }
            else if f < inicioManana { hoy += 1 }
            else if f < finManana { manana += 1 }
            else { despues += 1 }
        }
        var bloques: [String] = []
        if vencidas > 0 { bloques.append("vencidas: \(vencidas)") }
        if hoy > 0 { bloques.append("hoy: \(hoy)") }
        if manana > 0 { bloques.append("mañana: \(manana)") }
        if despues > 0 { bloques.append("próximas: \(despues)") }
        if incluirSinFecha, sinFecha > 0 { bloques.append("sin fecha: \(sinFecha)") }

        let relevantes = tareas.filter { incluirSinFecha || $0.fechaObjetivo != nil }
            .sorted {
                ($0.fechaObjetivo ?? Double.greatestFiniteMagnitude)
                    < ($1.fechaObjetivo ?? Double.greatestFiniteMagnitude)
            }
        let ejemplos = relevantes.prefix(3).map { $0.texto }.joined(separator: "; ")
        let conteo = bloques.isEmpty ? "pendientes: \(tareas.count)" : bloques.joined(separator: " · ")
        return ejemplos.isEmpty ? "Tienes \(conteo)." : "Tienes \(conteo). \(ejemplos)"
    }

    func revisarAhora(ahora: Date = Date()) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.revisarAhora(ahora: ahora) }
            return
        }
        let vencidos = Config.tareasAvisos() ? NotasStore.todos().filter { item in
            guard !item.hecho, item.avisar, item.avisadoEn == nil,
                  let e = item.fechaObjetivo, e <= ahora.timeIntervalSince1970 else { return false }
            return item.tipo == "tarea" || Config.tareasAvisarNotas()
        }.sorted { ($0.fechaObjetivo ?? 0) < ($1.fechaObjetivo ?? 0) } : []

        let marcados = vencidos.compactMap { NotasStore.marcarAvisado($0.id, ahora: ahora) }
        if marcados.count == 1, let p = marcados.first {
            publicar(.init(titulo: p.tipo == "nota" ? "Nota programada" : "Tarea pendiente",
                           cuerpo: p.texto, hablar: Config.tareasAvisosVoz(),
                           id: "pendiente.\(p.id)"))
        } else if !marcados.isEmpty {
            let muestra = marcados.prefix(3).map(\.texto).joined(separator: "; ")
            publicar(.init(titulo: "\(marcados.count) pendientes vencidos",
                           cuerpo: muestra, hablar: Config.tareasAvisosVoz(),
                           id: "pendientes.\(Int(ahora.timeIntervalSince1970))"))
        }
        revisarResumen(ahora: ahora)
    }

    private func revisarResumen(ahora: Date) {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: ahora)
        let minutos = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let clave = Self.claveDia(ahora)
        // Si la Mac se abre de noche, entrega solo el resumen más reciente y marca
        // el de la mañana como cubierto: nunca dispara dos discursos seguidos.
        if Config.tareasResumenTarde(), minutos >= Config.tareasResumenTardeMinutos(),
           Config.tareasResumenUltimo("tarde") != clave {
            Config.set("tareas_resumen_ultimo_tarde", to: clave)
            if Config.tareasResumenManana() { Config.set("tareas_resumen_ultimo_manana", to: clave) }
            publicarResumen(titulo: "Resumen de la tarde", ahora: ahora, periodo: "tarde")
            return
        }
        if Config.tareasResumenManana(), minutos >= Config.tareasResumenMananaMinutos(),
           Config.tareasResumenUltimo("manana") != clave {
            Config.set("tareas_resumen_ultimo_manana", to: clave)
            publicarResumen(titulo: "Resumen del día", ahora: ahora, periodo: "manana")
        }
    }

    private func publicarResumen(titulo: String, ahora: Date, periodo: String) {
        let cuerpo = Self.resumenTexto(items: NotasStore.todos(), ahora: ahora,
                                       incluirSinFecha: Config.tareasResumenIncluirSinFecha())
        publicar(.init(titulo: titulo, cuerpo: cuerpo,
                       hablar: Config.tareasAvisosVoz(),
                       id: "resumen.\(periodo).\(Self.claveDia(ahora))"))
    }

    private static func claveDia(_ fecha: Date) -> String {
        let f = DateFormatter(); f.calendar = .current; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: fecha)
    }

    private func publicar(_ aviso: Aviso) {
        Log.log(.config, "aviso local: \(aviso.titulo) — \(aviso.cuerpo.prefix(120))")
        AgenteLog.registrar("aviso_pendiente", ["id": aviso.id, "titulo": aviso.titulo,
                                                 "texto": aviso.cuerpo, "voz": aviso.hablar])
        presentar?(aviso)

        guard let centro else { return }
        centro.getNotificationSettings { [weak self] ajustes in
            guard [.authorized, .provisional].contains(ajustes.authorizationStatus) else { return }
            let c = UNMutableNotificationContent(); c.title = aviso.titulo; c.body = aviso.cuerpo
            if Config.tareasAvisosSonido() { c.sound = .default }
            let req = UNNotificationRequest(identifier: "ec.bto.betodicta.\(aviso.id)",
                                            content: c, trigger: nil)
            self?.centro?.add(req) { error in
                if let error { Log.write("⚠️ notificación de tarea: \(error.localizedDescription)") }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Config.tareasAvisosSonido() ? [.banner, .list, .sound] : [.banner, .list])
    }
}

/// Hooks puros y net-zero. Viven antes de `NSApplication` en main.swift para
/// poder correr en CI, SSH o el sandbox de un agente sin una sesión Aqua.
enum TareasNotasQA {
    static func ejecutarSiSePidio() {
        let env = ProcessInfo.processInfo.environment
        if env["BETODICTA_TASKREMINDERTEST"] == "1" { probarRecordatorios() }
        if env["BETODICTA_NOTATEST"] == "1" { probarAlmacen() }
    }

    private static func probarRecordatorios() -> Never {
        let cal = Calendar(identifier: .gregorian)
        let ahora = cal.date(from: DateComponents(year: 2026, month: 7, day: 19,
                                                   hour: 10, minute: 0))!
        let fecha = cal.date(from: DateComponents(year: 2026, month: 7, day: 19,
                                                   hour: 20, minute: 0))!
        let p = NotasStore.agregar(tipo: "tarea", texto: "QA llamar a Rafael",
                                   fechaObjetivo: fecha, avisar: true)
        let agregado = NotasStore.todos().contains {
            $0.id == p.id && $0.fechaObjetivo == fecha.timeIntervalSince1970 && $0.avisar
        }
        let resumen = TareasRecordatorios.resumenTexto(items: [p], ahora: ahora)
        let resumenOK = resumen.contains("hoy: 1") && resumen.contains("QA llamar a Rafael")
        let primero = NotasStore.marcarAvisado(p.id, ahora: ahora)
        let segundo = NotasStore.marcarAvisado(p.id, ahora: ahora)
        let unaVez = primero?.avisadoEn != nil && segundo == nil
        let parseada = AppleAgenda.previsualizar("Llamar a Rafael mañana a las 8:00 p.m.",
                                                 ahora: ahora).fecha
        let fechaOK = parseada.map {
            let c = cal.dateComponents([.day, .hour, .minute], from: $0)
            return c.day == 20 && c.hour == 20 && c.minute == 0
        } ?? false
        NotasStore.borrar(p.id)
        let netoCero = !NotasStore.todos().contains { $0.id == p.id }
        let permisos = (try? FileManager.default.attributesOfItem(
            atPath: Config.dir.appendingPathComponent("pendientes.json").path)[.posixPermissions]
            as? NSNumber)?.intValue == 0o600
        let ok = agregado && resumenOK && unaVez && fechaOK && netoCero && permisos
        print("TASKREMINDERTEST agregado=\(agregado) fecha=\(fechaOK) resumen=\(resumenOK) unaVez=\(unaVez) neto=\(netoCero) 0600=\(permisos)")
        print("TASKREMINDERTEST \(ok ? "TODO OK" : "FALLA")")
        exit(ok ? 0 : 3)
    }

    private static func probarAlmacen() -> Never {
        let p = NotasStore.agregar(tipo: "tarea", texto: "  prueba xyz  ")
        let addOk = NotasStore.todos().contains { $0.id == p.id && $0.texto == "prueba xyz" }
            && p.hecho == false
        NotasStore.alternar(p.id)
        let togOk = NotasStore.todos().first { $0.id == p.id }?.hecho == true
        NotasStore.borrar(p.id)
        let delOk = !NotasStore.todos().contains { $0.id == p.id }
        let ok = addOk && togOk && delOk
        print("NOTATEST add=\(addOk) toggle=\(togOk) delete=\(delOk) → \(ok ? "TODO OK" : "✗ FALLA")")
        exit(ok ? 0 : 3)
    }
}

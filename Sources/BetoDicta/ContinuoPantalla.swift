import AppKit
import CoreImage
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Bitácora continua: pantalla
//
// Capturas periódicas al intervalo que elija el usuario (5 s … 1 h).
//
// Se usa `SCScreenshotManager` en vez de un `SCStream` permanente: para un
// intervalo de 30 s o de un minuto, mantener un flujo vivo todo el día solo
// gastaría memoria y CPU. Aquí se pide una imagen, se decide si aporta algo y
// se suelta.
//
// Nada se guarda si la pantalla está bloqueada o dormida, ni si la imagen es
// prácticamente idéntica a la anterior. Cada N minutos se fuerza una aunque no
// haya cambios, para que la línea de tiempo no quede en blanco.

@available(macOS 14.0, *)
final class ContinuoPantalla {

    static let shared = ContinuoPantalla()

    private var reloj: Timer?
    private var capturando = false
    private var inicioIntento = Date.distantPast
    private var huellaPrevia: [UInt8]?
    private var ultimaEscritura = Date.distantPast
    private let contexto = CIContext(options: [.useSoftwareRenderer: false])
    private let escribir = DispatchQueue(label: "betodicta.continuo.pantalla", qos: .utility)

    private(set) var activo = false

    private init() {}

    // MARK: Ciclo de vida

    func arrancar() {
        guard Config.continuoActivo(), Config.continuoPantallaActiva() else { return }
        guard !activo else { return }
        let intervalo = Double(Config.continuoPantallaIntervaloSegundos())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloj?.invalidate()
            self.reloj = Timer.scheduledTimer(withTimeInterval: intervalo, repeats: true) { [weak self] _ in
                self?.tic()
            }
            self.activo = true
            Log.log(.sistema, "bitácora: pantalla cada \(Int(intervalo)) s")
        }
    }

    func detener() {
        DispatchQueue.main.async { [weak self] in
            self?.reloj?.invalidate()
            self?.reloj = nil
            self?.activo = false
            self?.huellaPrevia = nil
        }
    }

    /// Aplica un cambio de intervalo sin reiniciar la app.
    func reconfigurar() {
        detener()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.arrancar() }
    }

    // MARK: Captura

    private func tic() {
        // `capturando` no puede quedarse pegado: si `SCShareableContent` se
        // queda esperando (permiso de grabación de pantalla sin conceder tras
        // reinstalar el binario), sin este rescate el módulo enmudece para
        // siempre y sin un solo error en el registro.
        if capturando {
            if Date().timeIntervalSince(inicioIntento) > 30 {
                Log.log(.sistema, "bitácora: la captura anterior se quedó colgada (¿falta permiso de grabación de pantalla?) — reintento")
                capturando = false
            } else {
                return
            }
        }
        guard Config.continuoActivo(), Config.continuoPantallaActiva() else { return }
        if Config.continuoPantallaPausarBloqueada(), Self.pantallaNoDisponible() {
            Log.debug("bitácora: pantalla bloqueada o dormida, no capturo")
            return
        }
        if Config.continuoSoloConCorriente(), !EnergiaMac.conCorriente() {
            Log.debug("bitácora: con batería y el ajuste pide corriente, no capturo")
            return
        }
        capturando = true
        inicioIntento = Date()
        Task { [weak self] in
            await self?.capturar()
            self?.capturando = false
        }
    }

    private func capturar() async {
        do {
            let contenido = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                onScreenWindowsOnly: true)
            let elegidos = Self.monitoresElegidos(de: contenido)
            guard !elegidos.isEmpty else { return }

            let excluidas = Config.continuoPantallaAppsExcluidas()
            let apps = contenido.applications.filter { excluidas.contains($0.bundleIdentifier) }

            for pantalla in elegidos {
                let filtro = SCContentFilter(display: pantalla,
                                             excludingApplications: apps,
                                             exceptingWindows: [])
                let conf = SCStreamConfiguration()
                let escala = Config.continuoPantallaEscala()
                // `pointPixelScale` da los píxeles reales del panel: sin él, en
                // una pantalla Retina se captura a la mitad de resolución y el
                // texto queda ilegible para un OCR posterior.
                let anchoReal = Double(pantalla.width) * Double(filtro.pointPixelScale)
                let altoReal = Double(pantalla.height) * Double(filtro.pointPixelScale)
                conf.width = max(2, Int(anchoReal * escala) & ~1)
                conf.height = max(2, Int(altoReal * escala) & ~1)
                conf.showsCursor = false
                conf.captureResolution = .best

                let imagen = try await SCScreenshotManager.captureImage(contentFilter: filtro,
                                                                       configuration: conf)
                procesar(imagen, monitor: Int(pantalla.displayID))
            }
        } catch {
            Log.log(.sistema, "bitácora: captura de pantalla falló (\(error.localizedDescription))")
        }
    }

    private func procesar(_ imagen: CGImage, monitor: Int) {
        let ahora = Date()
        let forzarMin = Config.continuoPantallaForzarMinutos()
        let forzado = forzarMin > 0 && ahora.timeIntervalSince(ultimaEscritura) >= Double(forzarMin) * 60

        // La deduplicación se salta cuando toca fotograma forzado: primero se
        // decide si es obligatorio guardar, y solo si no lo es se compara.
        if !forzado, Config.continuoPantallaDeduplicar() {
            let huella = Self.huella(de: imagen)
            if let previa = huellaPrevia, Self.diferencia(previa, huella) < Config.continuoPantallaUmbralCambio() {
                return
            }
            huellaPrevia = huella
        } else {
            huellaPrevia = Self.huella(de: imagen)
        }

        ultimaEscritura = ahora
        let frente = NSWorkspace.shared.frontmostApplication
        let app = frente?.localizedName
        let ventana = Self.tituloVentanaAlFrente()
        let visibles = Config.continuoPantallaAppsVisibles()
            ? Self.appsALaVista(excluyendo: app)
            : []

        escribir.async { [weak self] in
            guard let self, let url = self.guardar(imagen, instante: ahora) else { return }
            ContinuoIndice.shared.registrarPantalla(ruta: url, instante: ahora,
                                                    app: app, ventana: ventana,
                                                    monitor: monitor, visibles: visibles)
        }
    }

    private func guardar(_ imagen: CGImage, instante: Date) -> URL? {
        let carpeta = ContinuoAudio.carpetaDelDia(instante, sub: "pantalla")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

        let formato = Config.continuoPantallaFormato()
        let extensiones = ["jpeg": "jpg", "heic": "heic", "png": "png"]
        let tipos: [String: UTType] = ["jpeg": .jpeg, "heic": .heic, "png": .png]
        let ext = extensiones[formato] ?? "jpg"
        let url = carpeta.appendingPathComponent(ContinuoAudio.sello(instante) + "." + ext)

        guard let destino = CGImageDestinationCreateWithURL(url as CFURL,
                                                            (tipos[formato] ?? .jpeg).identifier as CFString,
                                                            1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if formato != "png" {
            props[kCGImageDestinationLossyCompressionQuality] = Config.continuoPantallaCalidad()
        }
        CGImageDestinationAddImage(destino, imagen, props as CFDictionary)
        guard CGImageDestinationFinalize(destino) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    // MARK: Deduplicación

    /// Miniatura de 16×16 en gris. Comparar dos de estas cuesta microsegundos y
    /// basta para saber si la pantalla cambió de verdad.
    private static func huella(de imagen: CGImage) -> [UInt8] {
        let lado = 16
        var pixeles = [UInt8](repeating: 0, count: lado * lado)
        guard let espacio = CGColorSpace(name: CGColorSpace.linearGray),
              let ctx = CGContext(data: &pixeles, width: lado, height: lado,
                                  bitsPerComponent: 8, bytesPerRow: lado,
                                  space: espacio,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return pixeles }
        ctx.draw(imagen, in: CGRect(x: 0, y: 0, width: lado, height: lado))
        return pixeles
    }

    /// Diferencia media normalizada entre dos huellas (0 = idénticas).
    private static func diferencia(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var suma = 0
        for i in 0..<a.count { suma += abs(Int(a[i]) - Int(b[i])) }
        return Double(suma) / Double(a.count) / 255.0
    }

    // MARK: Estado de la pantalla

    /// `true` si está bloqueada, dormida o con el salvapantallas puesto: no hay
    /// nada que valga la pena guardar.
    static func pantallaNoDisponible() -> Bool {
        if let info = CGSessionCopyCurrentDictionary() as? [String: Any],
           let bloqueada = info["CGSSessionScreenIsLocked"] as? Int, bloqueada == 1 {
            return true
        }
        return CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    private static func monitoresElegidos(de contenido: SCShareableContent) -> [SCDisplay] {
        let pedidos = Config.continuoPantallaMonitores()
        if pedidos.isEmpty {
            if let principal = contenido.displays.first(where: { $0.displayID == CGMainDisplayID() }) {
                return [principal]
            }
            return Array(contenido.displays.prefix(1))
        }
        return contenido.displays.filter { pedidos.contains(Int($0.displayID)) }
    }

    /// Aplicaciones con ventanas a la vista, de delante hacia atrás, sin la
    /// activa (que ya va en su propio campo). Es el «qué más había abierto»
    /// que da contexto a la captura.
    private static func appsALaVista(excluyendo activa: String?) -> [String] {
        guard let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else { return [] }
        var vistas: [String] = []
        for v in lista {
            // Solo la capa normal de ventanas: fuera menús, Dock y adornos.
            guard let capa = v[kCGWindowLayer as String] as? Int, capa == 0,
                  let nombre = v[kCGWindowOwnerName as String] as? String,
                  !nombre.isEmpty, nombre != activa,
                  !vistas.contains(nombre) else { continue }
            vistas.append(nombre)
            if vistas.count >= 6 { break }   // el contexto útil se agota pronto
        }
        return vistas
    }

    /// Título de la ventana al frente, si el permiso de accesibilidad lo permite.
    /// Es contexto útil para buscar después; su ausencia no es un fallo.
    private static func tituloVentanaAlFrente() -> String? {
        guard let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else { return nil }
        let pidFrente = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for v in lista {
            guard let pid = v[kCGWindowOwnerPID as String] as? pid_t, pid == pidFrente,
                  let nombre = v[kCGWindowName as String] as? String, !nombre.isEmpty else { continue }
            return nombre
        }
        return nil
    }
}

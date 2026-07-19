import AppKit
import Foundation

/// QA puro del nuevo núcleo. No abre apps, no reproduce música, no pide permisos,
/// no llama IAs y no escribe configuración.
enum AgenteCoreQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BETODICTA_AGENTCORETEST"] == "1" else { return }
        var resultados: [Bool] = []
        func comprobar(_ nombre: String, _ condicion: @autoclosure () -> Bool, _ detalle: String = "") {
            let ok = condicion(); resultados.append(ok)
            print("AGENTCORE \(ok ? "OK" : "✗") \(nombre)\(detalle.isEmpty ? "" : " | " + detalle)")
        }

        let activadores = ["oye Bto", "oye Jarvis", "oye mamá"]
        let a = PerfilAgente.invocacion(en: "Oye, Bto: ¿qué tareas tengo hoy?", activadores: activadores)
        comprobar("activación Bto", a?.contenido == "¿qué tareas tengo hoy?", a?.contenido ?? "nil")
        let b = PerfilAgente.invocacion(en: "Oye mamá, recuérdame llamar a Rafael", activadores: activadores)
        comprobar("activación personalizada", b?.frase == "oye mamá" && b?.contenido.hasPrefix("recuérdame") == true)
        comprobar("sin falso positivo intermedio",
                  PerfilAgente.invocacion(en: "Ayer dije oye Jarvis en una película", activadores: activadores) == nil)
        let listaActivadores = FrasesConfigurables.parsear("\"Oye, Bto\"\nOye Jarvis\n“Oye, mamá”")
        comprobar("activadores con coma/comillas",
                  listaActivadores == ["Oye, Bto", "Oye Jarvis", "Oye, mamá"],
                  listaActivadores.joined(separator: " | "))
        comprobar("coma del STT no cambia la activación",
                  PerfilAgente.invocacion(en: "Oye, Bto, abre Gmail", activadores: listaActivadores)?.contenido == "abre Gmail")
        comprobar("no degrada a activador de una palabra",
                  PerfilAgente.invocacion(en: "Oye, ¿qué pasó?", activadores: listaActivadores) == nil)
        let activadoresPeligrosos = ["oye", "bto", "beto", "oye bto"]
        comprobar("ignora activadores configurados de una palabra",
                  PerfilAgente.invocacion(en: "Oye, qué tontera, esto era solo un dictado",
                                           activadores: activadoresPeligrosos) == nil
                    && PerfilAgente.invocacion(en: "Beto está trabajando hoy",
                                               activadores: activadoresPeligrosos) == nil)
        comprobar("conserva activador deliberado de dos palabras",
                  PerfilAgente.invocacion(en: "Oye, Bto, abre Gmail",
                                           activadores: activadoresPeligrosos)?.contenido == "abre Gmail")

        let seguimiento = AgenteNucleo.completarSeguimiento(
            "Mándaselo a Alberto por WhatsApp", referencia: "La reunión será mañana a las ocho.")
        let planSeguimiento = seguimiento.flatMap { ModoPlanificador.detectarNatural($0,
            catalogo: ModoCatalogo(modos: ModosStore.todos())) }
        comprobar("memoria resuelve pronombre con confirmación",
                  planSeguimiento?.cadena.acciones.first?.modo.accion == "whatsapp"
                    && planSeguimiento?.cadena.acciones.first?.destinatario == "Alberto"
                    && planSeguimiento?.cadena.contenido.contains("reunión será mañana") == true)
        let seguimientoReal = AgenteNucleo.planificar(
            "Mándaselo a Alberto por WhatsApp",
            catalogo: ModoCatalogo(modos: ModosStore.todos()),
            referencia: "La reunión será mañana a las ocho.",
            ignorarInterruptor: true)
        comprobar("seguimiento atraviesa el núcleo",
                  seguimientoReal?.cadena.acciones.first?.destinatario == "Alberto"
                    && seguimientoReal?.cadena.contenido.contains("reunión será mañana") == true)
        comprobar("memoria no invade una narración",
                  AgenteNucleo.completarSeguimiento("Ayer lo envié por WhatsApp", referencia: "secreto") == nil)

        comprobar("proveedor Spotify", Musica.reconocerProveedor(en: "en Spotify") == "spotify")
        comprobar("proveedor Apple Music", Musica.reconocerProveedor(en: "Apple Music") == "apple_music")
        comprobar("consulta musical limpia",
                  Musica.extraerConsulta("reproduce en Spotify música de Jessy Uribe", proveedor: "spotify") == "Jessy Uribe",
                  Musica.extraerConsulta("reproduce en Spotify música de Jessy Uribe", proveedor: "spotify"))
        comprobar("música distingue reproducir de buscar",
                  Musica.intencion("modo música, pon una canción de Julio Jaramillo") == .reproducir
                    && Musica.intencion("modo música, busca Julio Jaramillo") == .buscar
                    && Musica.intencion("busca Julio Jaramillo") == .buscar)
        comprobar("consulta quita relleno de canción cualquiera",
                  Musica.extraerConsulta("modo música, pon una canción cualquiera de Julio Jaramillo",
                                         proveedor: "auto") == "Julio Jaramillo",
                  Musica.extraerConsulta("modo música, pon una canción cualquiera de Julio Jaramillo",
                                         proveedor: "auto"))
        comprobar("consulta de búsqueda musical queda limpia",
                  Musica.extraerConsulta("modo música, busca Julio Jaramillo",
                                         proveedor: "auto") == "Julio Jaramillo")
        let ordenMusicaBto = PerfilAgente.invocacion(
            en: "Oye, Bto, pon música", activadores: activadores)?.contenido
        let planMusicaBto = ordenMusicaBto.flatMap {
            AgenteNucleo.planificar($0, catalogo: ModoCatalogo(modos: ModosStore.todos()),
                                    ignorarInterruptor: true)
        }
        comprobar("Oye Bto pon música atraviesa activador y núcleo",
                  ordenMusicaBto == "pon música"
                    && planMusicaBto?.cadena.acciones.first?.modo.base == "musica"
                    && planMusicaBto?.cadena.acciones.first?.modo.musicaAccion == "reproducir"
                    && planMusicaBto?.cadena.contenido.isEmpty == true)
        let catalogoFixture = """
        {"resultCount":1,"results":[{"trackId":154339650,"trackName":"Nuestro Juramento","artistName":"julio jaramillo","trackViewUrl":"https://music.apple.com/ec/album/nuestro-juramento/154339397?i=154339650"}]}
        """.data(using: .utf8)!
        let cancionCatalogo = AppleMusicCatalogo.decodificar(catalogoFixture)
        comprobar("catálogo Apple decodifica primer resultado seguro",
                  cancionCatalogo?.id == "154339650"
                    && cancionCatalogo?.url.scheme == "music"
                    && cancionCatalogo?.url.host == "music.apple.com")
        comprobar("catálogo Apple verifica título y artista",
                  cancionCatalogo.map {
                    AppleMusicCatalogo.coincide($0, titulo: "Nuestro Juramento",
                                                artista: "Julio Jaramillo")
                        && !AppleMusicCatalogo.coincide($0, titulo: "AnaLucia_01", artista: "")
                  } == true)
        comprobar("búsqueda de catálogo es HTTPS y acotada",
                  AppleMusicCatalogo.urlBusqueda("Julio Jaramillo", pais: "EC")?.absoluteString
                    .contains("limit=1") == true)
        comprobar("URL propia segura", Musica.plantillaSegura("https://ejemplo.test/buscar?q={q}"))
        comprobar("rechaza esquema ejecutable", !Musica.plantillaSegura("javascript:alert('{q}')"))
        comprobar("HTTP solo local", Musica.plantillaSegura("http://localhost:8080/?q={q}")
                    && !Musica.plantillaSegura("http://ejemplo.test/?q={q}"))
        comprobar("Atajo musical verifica artista real",
                  AppleAtajos.coincideMusica(consulta: "Jessi Uribe",
                                              titulo: "Dulce pecado", artista: "Jessi Uribe"))
        comprobar("Atajo musical verifica título real",
                  AppleAtajos.coincideMusica(consulta: "La vida es bella",
                                              titulo: "La vida es bella", artista: "Artista"))
        comprobar("Atajo musical rechaza pista anterior",
                  !AppleAtajos.coincideMusica(consulta: "Jessi Uribe",
                                               titulo: "AnaLucia_01", artista: "Voz local"))

        let fraseCapturaExacta = "Haz una captura de una sección, guárdala en Descargas con el nombre \"informe\", cópiala y ábrela."
        let captura = SolicitudCapturaMac.interpretar(fraseCapturaExacta)
        comprobar("captura interpreta área, salida y nombre",
                  captura.tipo == .imagen && captura.area == .seleccion
                    && captura.destino == .descargas && captura.nombre == "informe"
                    && captura.guardar && captura.copiar && captura.abrir,
                  "\(captura.area.rawValue) · \(captura.destino.rawValue) · \(captura.nombre ?? "nil")")
        let capturaSTT = SolicitudCapturaMac.interpretar(
            "Oye, Bto, haz una captura de una sección, guárdala en Descargas con el nombre de informe y, por favor, copia la y luego abre la.")
        comprobar("captura tolera pronombres separados por STT",
                  capturaSTT.area == .seleccion && capturaSTT.destino == .descargas
                    && capturaSTT.nombre == "informe" && capturaSTT.guardar
                    && capturaSTT.copiar && capturaSTT.abrir,
                  "nombre=\(capturaSTT.nombre ?? "nil") copiar=\(capturaSTT.copiar) abrir=\(capturaSTT.abrir)")

        // Prueba la orquestación de la segunda mitad (archivo → copiar → abrir)
        // con destinos inyectados: no cambia el clipboard del usuario ni lanza
        // Preview durante el pipeline de QA. La implementación real usa AppKit.
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("betodicta-captura-qa-\(UUID().uuidString).png")
        let fixtureData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlGDfQAAAAASUVORK5CYII=")
        let fixtureOK = fixtureData.flatMap {
            do { try $0.write(to: fixture, options: .atomic); return true }
            catch { return false }
        } ?? false
        var urlCopiada: URL?
        var tipoCopiado: TipoCapturaMac?
        var urlAbierta: URL?
        let post = CapturaMac.accionesPosteriores(
            captura, archivo: fixture,
            copiador: { url, tipo in
                urlCopiada = url; tipoCopiado = tipo
                return NSImage(contentsOf: url) != nil
            },
            abridor: { url in urlAbierta = url; return true })
        comprobar("captura ejecuta copiar y abrir después de guardar",
                  fixtureOK && post.copiada && post.abierta && post.completo
                    && urlCopiada == fixture && tipoCopiado == .imagen && urlAbierta == fixture,
                  "copiada=\(post.copiada) abierta=\(post.abierta) completa=\(post.completo)")
        let postAperturaFallida = CapturaMac.accionesPosteriores(
            captura, archivo: fixture,
            copiador: { _, _ in true },
            abridor: { _ in false })
        comprobar("captura no declara éxito si una acción final falla",
                  postAperturaFallida.copiada && !postAperturaFallida.abierta
                    && !postAperturaFallida.completo)
        try? FileManager.default.removeItem(at: fixture)
        let grabacion = SolicitudCapturaMac.interpretar(
            "Graba la pantalla durante 15 segundos con micrófono y guarda en Documentos",
            duracionPredeterminada: 0)
        comprobar("grabación interpreta duración y audio",
                  grabacion.tipo == .video && grabacion.duracion == 15
                    && grabacion.microfono && grabacion.destino == .documentos)
        let nombreVideoAutomatico = CapturaMac.nombreSeguro(nil, tipo: .video)
        comprobar("grabación automática conserva segundos y termina en .mov",
                  nombreVideoAutomatico.hasSuffix(".mov")
                    && nombreVideoAutomatico.range(
                        of: #"\d{2}\.\d{2}\.\d{2}\.mov$"#,
                        options: .regularExpression) != nil,
                  nombreVideoAutomatico)
        comprobar("extensión de video incompatible se normaliza a .mov",
                  CapturaMac.nombreSeguro("demostración.mp4", tipo: .video)
                    == "demostración.mov")
        comprobar("puntos del nombre no se confunden con una extensión",
                  CapturaMac.nombreSeguro("informe.final", tipo: .video)
                    == "informe.final.mov")
        comprobar("captura automática termina en .png",
                  CapturaMac.nombreSeguro(nil, tipo: .imagen).hasSuffix(".png"))
        let fraseGrabacionExacta =
            "Graba la pantalla durante 15 segundos con micrófono y guarda en documentos."
        let planGrabacion = ModoResolver.detectarPedidoNatural(
            fraseGrabacionExacta, catalogo: ModoCatalogo(modos: ModosStore.todos()),
            permitirCapturas: true)
        comprobar("grabación natural funciona sin Oye Bto ni modo",
                  planGrabacion?.cadena.acciones.first?.modo.accion == "grabar_pantalla"
                    && planGrabacion?.cadena.contenido == fraseGrabacionExacta,
                  planGrabacion?.descripcion ?? "nil")
        var resolucionGrabacion: ResultadoModo?
        ModoResolver.resolver(texto: fraseGrabacionExacta,
                              modoBase: ModosStore.modo("dictado"),
                              contexto: nil, vivo: nil) { resolucionGrabacion = $0 }
        let usaConfirmacion: Bool
        if case let .preguntarPlan(p)? = resolucionGrabacion {
            usaConfirmacion = p.cadena.acciones.first?.modo.accion == "grabar_pantalla"
        } else { usaConfirmacion = false }
        comprobar("resolver principal propone grabación en vez de dictarla",
                  usaConfirmacion)
        let modoGrabacion = planGrabacion?.cadena.acciones.first?.modo
            ?? Modo(id: "qa-grabacion", nombre: "Grabación", icono: "record.circle",
                    base: "accion", accion: "grabar_pantalla")
        let cadenaGrabacion = ModoCadena(
            transforms: [],
            acciones: [ModoAccionPlan(modo: modoGrabacion, destinatario: nil)],
            contenido: fraseGrabacionExacta)
        comprobar("grabación exige silencio total del asistente",
                  MensajesAgente.requiereSilencioTotal(cadenaGrabacion))

        let fraseManualWA = "Oye, Bto, haz una grabación en pantalla y luego guarda en mis documentos, "
            + "cópialo en el portapapeles o envíalo por WhatsApp a Alberto"
        let grabacionManualWA = SolicitudCapturaMac.interpretar(
            fraseManualWA, duracionPredeterminada: 0)
        let argsManualWA = CapturaMac.argumentos(grabacionManualWA,
            archivo: URL(fileURLWithPath: "/tmp/betodicta-manual.mov"))
        comprobar("grabación sin duración queda continua y conserva toda la cadena",
                  grabacionManualWA.tipo == .video
                    && grabacionManualWA.duracion == nil
                    && grabacionManualWA.detencion == "continua_betodicta"
                    && grabacionManualWA.destino == .documentos
                    && grabacionManualWA.copiar
                    && grabacionManualWA.compartirWhatsApp
                    && grabacionManualWA.contactoWhatsApp == "Alberto"
                    && argsManualWA.contains("-v") && !argsManualWA.contains("-i")
                    && !argsManualWA.contains("-U") && !argsManualWA.contains("-V"),
                  grabacionManualWA.detallePlan + " | " + argsManualWA.joined(separator: " "))
        let grabacionDocumentosSinPreposicion = SolicitudCapturaMac.interpretar(
            "Oye, Bto, graba la pantalla hasta que yo la detenga y guarda mis documentos",
            duracionPredeterminada: 30)
        comprobar("guarda mis documentos conserva destino y control continuo",
                  grabacionDocumentosSinPreposicion.destino == .documentos
                    && grabacionDocumentosSinPreposicion.controlContinuoBetoDicta
                    && grabacionDocumentosSinPreposicion.duracion == nil)
        let grabacionPredeterminada = SolicitudCapturaMac.interpretar(
            "Haz una grabación de pantalla y guarda en Documentos",
            duracionPredeterminada: 30)
        comprobar("duración predeterminada parametrizable detiene sola",
                  grabacionPredeterminada.duracionAutomatica == 30
                    && CapturaMac.argumentos(grabacionPredeterminada,
                        archivo: URL(fileURLWithPath: "/tmp/betodicta-30.mov"))
                        .suffix(3).contains("30"),
                  grabacionPredeterminada.detallePlan)
        let grabacionManualExplicita = SolicitudCapturaMac.interpretar(
            "Graba la pantalla hasta que yo la detenga", duracionPredeterminada: 30)
        comprobar("orden manual explícita vence al tiempo configurado",
                  grabacionManualExplicita.duracion == nil
                    && grabacionManualExplicita.detencion == "continua_betodicta")
        let modoCompartirVideo = Modo(id: "qa-video-wa", nombre: "Video WhatsApp",
            icono: "record.circle", base: "accion", accion: "captura_compartir")
        let cadenaVideoWA = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: modoCompartirVideo, destinatario: "Alberto")],
            contenido: fraseManualWA)
        comprobar("video para WhatsApp también silencia voz y sonidos",
                  MensajesAgente.requiereSilencioTotal(cadenaVideoWA))
        var modoTraducir = ModosStore.modo("traducir")
        modoTraducir.id = "qa-traducir"
        let cadenaTransformaYGraba = ModoCadena(
            transforms: [modoTraducir],
            acciones: cadenaGrabacion.acciones,
            contenido: "traduce y graba la pantalla")
        comprobar("cadena con grabación también queda silenciosa",
                  MensajesAgente.requiereSilencioTotal(cadenaTransformaYGraba))
        let modoCaptura = Modo(id: "qa-captura", nombre: "Captura", icono: "camera",
                               base: "accion", accion: "captura_pantalla")
        let cadenaCapturaSilencio = ModoCadena(
            transforms: [],
            acciones: [ModoAccionPlan(modo: modoCaptura, destinatario: nil)],
            contenido: "captura la pantalla")
        comprobar("captura estática conserva respuestas configuradas",
                  !MensajesAgente.requiereSilencioTotal(cadenaCapturaSilencio))
        comprobar("captura responde al resultado y no deja acuse previo pegado",
                  MensajesAgente.esperaResultado(cadenaCapturaSilencio))
        comprobar("narración sobre grabación no ejecuta la herramienta",
                  AgenteNucleo.planificarCaptura(
                    "El programa graba la pantalla durante 15 segundos para una demostración.") == nil)
        let compartirCaptura = SolicitudCapturaMac.interpretar(
            "Toma una captura de pantalla y envíala por WhatsApp al grupo TI Noticias")
        comprobar("WhatsApp queda como preparación segura",
                  compartirCaptura.compartirWhatsApp && compartirCaptura.copiar
                    && compartirCaptura.contactoWhatsApp == "grupo TI Noticias",
                  compartirCaptura.contactoWhatsApp ?? "nil")
        let fraseTomoWA = "Tomo una captura y la envío por WhatsApp a Alberto."
        let planTomoWA = AgenteNucleo.planificarCaptura(fraseTomoWA)
        let solicitudTomoWA = SolicitudCapturaMac.interpretar(fraseTomoWA)
        comprobar("STT toma→tomo conserva captura a contacto",
                  planTomoWA?.cadena.acciones.first?.modo.accion == "captura_compartir"
                    && solicitudTomoWA.compartirWhatsApp
                    && solicitudTomoWA.contactoWhatsApp == "Alberto",
                  solicitudTomoWA.contactoWhatsApp ?? "nil")
        comprobar("tomo narrativo no acciona captura",
                  AgenteNucleo.planificarCaptura(
                    "Tomo capturas para mis informes todos los días.") == nil
                    && AgenteNucleo.planificarCaptura(
                        "Ayer tomó una captura y la envió por WhatsApp.") == nil)
        comprobar("pegado WA espera foco y nunca confunde otra app",
                  PegadoWhatsApp.decidir(politica: .preparar, appDisponible: true,
                    bundleFrente: "com.apple.finder", bundleEsperado: "net.whatsapp.WhatsApp",
                    intento: 2, maxIntentos: 25) == .esperar
                    && PegadoWhatsApp.decidir(politica: .preparar, appDisponible: true,
                        bundleFrente: "net.whatsapp.WhatsApp",
                        bundleEsperado: "net.whatsapp.WhatsApp",
                        intento: 3, maxIntentos: 25) == .pegar(autoEnviar: false)
                    && PegadoWhatsApp.decidir(politica: .enviar, appDisponible: true,
                        bundleFrente: "net.whatsapp.WhatsApp",
                        bundleEsperado: "net.whatsapp.WhatsApp",
                        intento: 3, maxIntentos: 25) == .pegar(autoEnviar: true)
                    && PegadoWhatsApp.decidir(politica: .preparar, appDisponible: true,
                        bundleFrente: "com.apple.finder",
                        bundleEsperado: "net.whatsapp.WhatsApp",
                        intento: 25, maxIntentos: 25) == .manual
                    && PegadoWhatsApp.decidir(politica: .portapapeles, appDisponible: true,
                        bundleFrente: "net.whatsapp.WhatsApp",
                        bundleEsperado: "net.whatsapp.WhatsApp",
                        intento: 0, maxIntentos: 25) == .manual)
        SeguridadTeclado.bloquearRetorno(durante: 1)
        comprobar("adjunto WhatsApp bloquea Enter automático pendiente",
                  !SeguridadTeclado.retornoPermitido)
        let waAntes = EstadoAdjuntoWhatsApp(imagenes: 4, dialogos: 0,
            marcadores: 0, botonesEnviar: 1)
        comprobar("autoenvío WA exige evidencia nueva del adjunto",
                  !WhatsAppAccesibilidad.adjuntoConfirmado(antes: waAntes,
                    despues: waAntes)
                    && WhatsAppAccesibilidad.adjuntoConfirmado(antes: waAntes,
                        despues: EstadoAdjuntoWhatsApp(imagenes: 5, dialogos: 0,
                            marcadores: 0, botonesEnviar: 1))
                    && !WhatsAppAccesibilidad.adjuntoConfirmado(antes: waAntes,
                        despues: EstadoAdjuntoWhatsApp(imagenes: 5, dialogos: 0,
                            marcadores: 0, botonesEnviar: 0)))
        let cuarto = SolicitudCapturaMac.interpretar(
            "Captura el cuadrante superior derecho y guarda en el escritorio")
        let argsCuarto = CapturaMac.argumentos(cuarto,
            archivo: URL(fileURLWithPath: "/tmp/betodicta-qa.png"))
        let regionValida = argsCuarto.firstIndex(of: "-R").flatMap { i -> Bool? in
            guard i + 1 < argsCuarto.count else { return false }
            let nums = argsCuarto[i + 1].split(separator: ",").compactMap { Double($0) }
            return nums.count == 4 && nums[2] > 0 && nums[3] > 0
        } ?? false
        comprobar("cuadrante usa región o selector nativo seguro",
                  cuarto.area == .superiorDerecha
                    && (regionValida || (argsCuarto.contains("-i") && argsCuarto.contains("-s"))),
                  argsCuarto.joined(separator: " "))
        comprobar("acciones de pantalla registradas",
                  Acciones.valido("captura_pantalla") && Acciones.valido("grabar_pantalla")
                    && Acciones.valido("captura_compartir"))
        comprobar("núcleo enruta captura natural",
                  AgenteNucleo.planificarCaptura("Por favor, haz una captura de la ventana y guárdala en Descargas")?
                    .cadena.acciones.first?.modo.accion == "captura_pantalla")
        let planCapturaSinActivador = ModoResolver.detectarPedidoNatural(
            fraseCapturaExacta, catalogo: ModoCatalogo(modos: ModosStore.todos()),
            permitirCapturas: true)
        comprobar("captura exacta funciona sin Oye Bto ni modo",
                  planCapturaSinActivador?.cadena.acciones.first?.modo.accion == "captura_pantalla"
                    && planCapturaSinActivador?.cadena.contenido == fraseCapturaExacta)
        comprobar("narración de captura no acciona",
                  AgenteNucleo.planificarCaptura("La captura de pantalla del informe fue enviada ayer") == nil)

        let modoMusicaRespuesta = ModosStore.modo("musica")
        let cadenaSoloMusica = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: modoMusicaRespuesta, destinatario: nil)],
            contenido: "música andina")
        comprobar("Música espera resultado real", MensajesAgente.esperaResultado(cadenaSoloMusica))
        let modoArchivo = Modo(id: "qa-archivo", nombre: "Archivo", icono: "doc",
                               base: "accion", accion: "archivo")
        let cadenaArchivo = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: modoArchivo, destinatario: nil)],
            contenido: "informe final")
        comprobar("acuse operativo breve",
                  MensajesAgente.acuse(cadenaArchivo).hasPrefix("De acuerdo, voy a "))
        let preguntaArchivo = ModoPlanificador.pregunta(para: cadenaArchivo)
        let preguntaHablada = MensajesAgente.confirmacion(preguntaArchivo,
                                                           modoNormal: ModosStore.modo("dictado"))
        comprobar("pregunta hablada explica fn y X",
                  preguntaHablada.contains("función una vez")
                    && preguntaHablada.contains("X") && preguntaHablada.contains("Dictado")
                    && preguntaHablada.contains("buscar un archivo")
                    && !preguntaHablada.contains("abrir buscar"),
                  preguntaHablada)
        if let apple = Musica.proveedor("apple_music") {
            let tocando = Musica.mensaje(estado: .reproduciendo, proveedor: apple,
                                         consulta: "música andina", intencion: .reproducir)
            let buscando = Musica.mensaje(estado: .busqueda, proveedor: apple,
                                          consulta: "música andina", intencion: .reproducir)
            let buscarSolo = Musica.mensaje(estado: .busqueda, proveedor: apple,
                                            consulta: "música andina", intencion: .buscar)
            comprobar("Música distingue play de búsqueda",
                      tocando.contains("reproduciendo")
                        && buscando.contains("No pude reproducir")
                        && buscando.contains("búsqueda")
                        && buscarSolo.contains("te abrí la búsqueda")
                        && !buscarSolo.contains("No pude"),
                      tocando + " | " + buscando + " | " + buscarSolo)
        } else { comprobar("proveedor Apple disponible en catálogo", false) }
        comprobar("formatos de respuesta estables",
                  FormatoRespuestaAgente.texto.rawValue == "texto"
                    && FormatoRespuestaAgente.textoVoz.rawValue == "texto_voz")

        let moonshot = ChatIA.fijos.first { $0.id == "moonshot" }
        let reqMoonshot = moonshot?.requestChat(prompt: "Corrige este texto", temperatura: 0.15, textLen: 18)
        let bodyMoonshot = reqMoonshot?.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        comprobar("Kimi API usa endpoint y parámetros oficiales",
                  reqMoonshot?.url?.absoluteString == "https://api.moonshot.ai/v1/chat/completions"
                    && bodyMoonshot?["model"] as? String == "kimi-k2.6"
                    && (bodyMoonshot?["thinking"] as? [String: String])?["type"] == "disabled"
                    && bodyMoonshot?["temperature"] == nil)
        let kimiCuenta = ChatIA.fijos.first { $0.id == "kimi_code" }
        let reqKimiCuenta = kimiCuenta?.requestChat(prompt: "Corrige este texto", temperatura: 0.15, textLen: 18)
        let bodyKimiCuenta = reqKimiCuenta?.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        comprobar("Kimi por cuenta queda separado e identificado",
                  reqKimiCuenta?.url?.absoluteString == "https://api.kimi.com/coding/v1/chat/completions"
                    && bodyKimiCuenta?["model"] as? String == "kimi-for-coding"
                    && bodyKimiCuenta?["temperature"] == nil
                    && reqKimiCuenta?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("BetoDicta/") == true
                    && ChatIA.precioDe("kimi_code", "kimi-for-coding")?.contains("cuenta") == true)
        let codexCuenta = ChatIA.fijos.first { $0.id == "codex_account" }
        comprobar("ChatGPT por cuenta es texto vía Codex y no una API falsa",
                  codexCuenta?.esCuentaCodex == true
                    && codexCuenta?.base == "codex://account"
                    && codexCuenta?.requestChat(prompt: "Corrige", temperatura: 0,
                                                textLen: 7) == nil
                    && ChatIA.precioDe("codex_account", "automático")?.contains("plan ChatGPT") == true)
        comprobar("cuenta Codex no se anuncia como motor de embeddings",
                  !EmbeddingSearch.motores.contains(where: { $0.id == "codex_account" }))
        let modelosCodex = AgenteCodex.modelosDisponibles()
        comprobar("selector Codex enumera automático y familia 5.6",
                  modelosCodex.first?.id == "automatico"
                    && modelosCodex.contains(where: { $0.id == "gpt-5.6-sol" })
                    && modelosCodex.contains(where: { $0.id == "gpt-5.6-terra" })
                    && modelosCodex.contains(where: { $0.id == "gpt-5.6-luna" }),
                  modelosCodex.map(\.id).joined(separator: ", "))
        comprobar("razonamiento Codex acotado para voz",
                  AgenteCodex.esfuerzosDisponibles.map(\.id)
                    == ["automatico", "low", "medium", "high", "xhigh"])

        let catalogo = ModoCatalogo(modos: ModosStore.todos())
        let gmailLargo = "Oye Bto, abre Gmail y escribe un correo electrónico bien estructurado para albertoalex@gmail.com y que diga lo siguiente y que trate sobre el siguiente asunto: Necesito que se prepare un programa para un evento mañana en la Universidad Estatal Amazónica."
        let invGmail = PerfilAgente.invocacion(en: gmailLargo, activadores: activadores)
        let planGmail = invGmail.flatMap { OrdenEstructurada.detectar($0.contenido,
            catalogo: catalogo, aplicaciones: []) }
        comprobar("orden global Gmail",
                  planGmail?.cadena.transforms.first?.id == "correo"
                    && planGmail?.cadena.acciones.first?.modo.accion == "gmail"
                    && planGmail?.cadena.acciones.first?.destinatario == "albertoalex@gmail.com"
                    && planGmail?.cadena.contenido.hasPrefix("Necesito que se prepare") == true,
                  "\(planGmail?.descripcion ?? "nil") | \(planGmail?.cadena.contenido ?? "nil")")
        let gmailHablado = OrdenEstructurada.detectar(
            "Abre Gmail y escribe un correo para alberto alex arroba gmail punto com: prueba de dirección dictada.",
            catalogo: catalogo, aplicaciones: [])
        comprobar("correo dictado con arroba/punto",
                  gmailHablado?.cadena.acciones.first?.destinatario == "albertoalex@gmail.com",
                  gmailHablado?.cadena.acciones.first?.destinatario ?? "nil")
        let gmailPunto = OrdenEstructurada.detectar(
            "Abre Gmail y escribe un correo para beto@gmail.com. Necesitamos preparar el programa del evento.",
            catalogo: catalogo, aplicaciones: [])
        comprobar("punto del STT separa cabecera y cuerpo",
                  gmailPunto?.cadena.contenido == "Necesitamos preparar el programa del evento.",
                  gmailPunto?.cadena.contenido ?? "nil")

        let outlook = OrdenEstructurada.detectar(
            "Abre Outlook y escribe un correo para equipo@example.com. Asunto: Reunión de mañana. Cuerpo: Nos reunimos a las diez.",
            catalogo: catalogo, aplicaciones: [])
        comprobar("Outlook separa destinatario/asunto/cuerpo",
                  outlook?.cadena.acciones.first?.modo.accion == "outlook"
                    && outlook?.cadena.acciones.first?.destinatario == "equipo@example.com"
                    && outlook?.cadena.acciones.first?.asunto == "Reunión de mañana"
                    && outlook?.cadena.contenido == "Nos reunimos a las diez.",
                  "asunto=\(outlook?.cadena.acciones.first?.asunto ?? "nil") cuerpo=\(outlook?.cadena.contenido ?? "nil")")

        let word = AplicacionMac(nombre: "Microsoft Word", bundleId: "com.microsoft.Word",
                                 ruta: "/Applications/Microsoft Word.app",
                                 alias: ["microsoft word", "word"])
        let planWord = OrdenEstructurada.detectar(
            "Por favor abre Word y crea un oficio totalmente completo con encabezado, fecha, destinatario y cierre solicitando apoyo para los juegos internos de la universidad.",
            catalogo: catalogo, aplicaciones: [word])
        comprobar("orden global Word + oficio",
                  planWord?.cadena.transforms.first?.id == "oficio"
                    && planWord?.cadena.acciones.first?.modo.base == "aplicacion"
                    && planWord?.cadena.acciones.first?.modo.appBundleId == "com.microsoft.Word"
                    && planWord?.cadena.contenido.contains("totalmente completo") == true,
                  "\(planWord?.descripcion ?? "nil") | \(planWord?.cadena.contenido ?? "nil")")
        let oficioEstructurado = """
        OFICIO N° [___________]
        Puyo, 18 de julio de 2026

        Señor [___________]
        [___________]

        Asunto: Solicitud de apoyo

        Estimado señor [___________],

        Solicito su apoyo para los juegos internos de la institución.

        Atentamente,

        [___________]
        """
        let preservado = DocumentosMac.contenidoParaAplicacion(oficioEstructurado,
                                                                consumidas: 0)
        comprobar("Word conserva los saltos generados por el modo Oficio",
                  preservado == oficioEstructurado && preservado.contains("\n\nAsunto:"))
        let trasPuente = DocumentosMac.contenidoParaAplicacion(
            "Word y escribe:\nPrimera línea.\n\nSegunda línea.", consumidas: 1)
        comprobar("Word quita la orden sin aplanar el documento",
                  trasPuente == "Primera línea.\n\nSegunda línea.", trasPuente)
        let formatoOficio = DocumentosMac.planWord(oficioEstructurado)
        comprobar("Oficio recibe formato profesional determinista",
                  formatoOficio.esEstructurado
                    && formatoOficio.estilos.first?.rol == "encabezado"
                    && formatoOficio.estilos.first?.negrita == true
                    && formatoOficio.estilos.first?.alineacion == .derecha
                    && formatoOficio.estilos.contains { $0.rol == "asunto" && $0.negrita }
                    && formatoOficio.estilos.contains { $0.rol == "cuerpo" && $0.alineacion == .justificada }
                    && formatoOficio.estilos.contains { $0.rol == "firma" && $0.alineacion == .centro })
        comprobar("Word usa alineaciones VBA reales, no constantes SDEF desplazadas",
                  DocumentosMac.AlineacionWord.izquierda.appleScript == "0"
                    && DocumentosMac.AlineacionWord.centro.appleScript == "1"
                    && DocumentosMac.AlineacionWord.derecha.appleScript == "2"
                    && DocumentosMac.AlineacionWord.justificada.appleScript == "3")
        comprobar("texto común de Word no se fuerza como oficio",
                  !DocumentosMac.planWord("Hola, ¿qué tal?").esEstructurado)
        let wordMencionaGmail = OrdenEstructurada.detectar(
            "Abre Word y crea un oficio que explique cómo utilizar Gmail en la universidad.",
            catalogo: catalogo, aplicaciones: [word])
        comprobar("una app citada en el contenido no roba el destino",
                  wordMencionaGmail?.cadena.acciones.first?.modo.appBundleId == "com.microsoft.Word"
                    && wordMencionaGmail?.cadena.acciones.first?.modo.base == "aplicacion")

        var modosQuipux = ModosStore.todos()
        modosQuipux.append(Modo(id: "qa-quipux", nombre: "Quipux", icono: "globe",
                                base: "accion", prompt: "https://quipux.example/", esFijo: false,
                                accion: "url"))
        let planQuipux = OrdenEstructurada.detectar(
            "Abre Quipux y crea un oficio: solicito la revisión del trámite.",
            catalogo: ModoCatalogo(modos: modosQuipux), aplicaciones: [])
        comprobar("conector web propio reutilizable",
                  planQuipux?.cadena.acciones.first?.modo.id == "qa-quipux"
                    && planQuipux?.cadena.contenido == "solicito la revisión del trámite.")
        comprobar("web propia exige HTTPS o localhost",
                  Acciones.plantillaURLSegura("https://quipux.example/?q={q}")
                    && Acciones.plantillaURLSegura("http://127.0.0.1:8080/?q={q}")
                    && !Acciones.plantillaURLSegura("http://quipux.example/?q={q}")
                    && !Acciones.plantillaURLSegura("javascript:alert('{q}')"))
        comprobar("redactar sin destino no abre una app",
                  OrdenEstructurada.detectar("Redacta un correo: revisemos el contrato.",
                                             catalogo: catalogo, aplicaciones: []) == nil)
        let crearArchivo = OrdenEstructurada.detectar(
            "Crea un archivo llamado agenda de mañana: comprar materiales y llamar a Rafael.",
            catalogo: catalogo, aplicaciones: [])
        comprobar("crear archivo pide ubicación y conserva texto",
                  crearArchivo?.cadena.transforms.isEmpty == true
                    && crearArchivo?.cadena.acciones.first?.modo.accion == "archivo_nuevo"
                    && crearArchivo?.cadena.acciones.first?.nombreArchivo == "agenda de mañana"
                    && crearArchivo?.cadena.contenido == "comprar materiales y llamar a Rafael.",
                  "nombre=\(crearArchivo?.cadena.acciones.first?.nombreArchivo ?? "nil") contenido=\(crearArchivo?.cadena.contenido ?? "nil")")
        comprobar("narración no se vuelve trabajo autónomo",
                  OrdenEstructurada.detectar("Ayer abrí Word y escribí un oficio para explicar el proceso.",
                                             catalogo: catalogo, aplicaciones: [word]) == nil)

        let borrador = BorradoresCorreo.preparar(
            texto: "ASUNTO: Programa del evento\n\nEstimado Alberto:\nAdjunto el programa.",
            destinatario: "alberto@example.com", asuntoSugerido: nil)
        let gmailURL = BorradoresCorreo.urlGmail(borrador)
        let gmailItems = gmailURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        comprobar("borrador extrae asunto sin enviarlo",
                  borrador.asunto == "Programa del evento"
                    && !borrador.cuerpo.contains("ASUNTO:")
                    && gmailURL?.scheme == "https"
                    && gmailItems?.first(where: { $0.name == "to" })?.value == "alberto@example.com"
                    && gmailItems?.first(where: { $0.name == "su" })?.value == "Programa del evento",
                  gmailURL?.absoluteString ?? "nil")

        let outlookBorrador = BorradorCorreoPreparado(
            destinatario: "equipo@example.com", asunto: "Reunión",
            cuerpo: "Nos vemos mañana")
        let outlookMailto = BorradoresCorreo.urlMail(outlookBorrador)
        let outlookItems = outlookMailto.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
        }
        comprobar("Outlook recibe un mailto con los tres campos",
                  outlookMailto?.scheme == "mailto"
                    && outlookMailto?.path == "equipo@example.com"
                    && outlookItems?.first(where: { $0.name == "subject" })?.value == "Reunión"
                    && outlookItems?.first(where: { $0.name == "body" })?.value == "Nos vemos mañana",
                  outlookMailto?.absoluteString ?? "nil")

        let musicaExacta = ModoResolver.detectarExacto(
            "modo música Spotify, Jessy Uribe", catalogo: catalogo)
        comprobar("modo Música exacto con proveedor",
                  musicaExacta?.modo.base == "musica"
                    && musicaExacta?.modo.musicaProveedor == "spotify"
                    && musicaExacta?.textoLimpio == "Jessy Uribe",
                  "base=\(musicaExacta?.modo.base ?? "nil") proveedor=\(musicaExacta?.modo.musicaProveedor ?? "nil") texto=\(musicaExacta?.textoLimpio ?? "nil")")
        let cadenaMusica = ModosStore.detectarCadena(
            "modo traducir inglés modo música YouTube Music, buenos días")
        comprobar("Música coexiste en cadena",
                  cadenaMusica?.transforms.map(\.id) == ["traducir"]
                    && cadenaMusica?.acciones.first?.modo.base == "musica"
                    && cadenaMusica?.acciones.first?.modo.musicaProveedor == "youtube_music"
                    && cadenaMusica?.contenido == "buenos días")
        let buscarMusicaNatural = ModoPlanificador.detectarNatural(
            "Busca música de Julio Jaramillo", catalogo: catalogo)
        comprobar("búsqueda musical natural no reproduce",
                  buscarMusicaNatural?.cadena.acciones.first?.modo.base == "musica"
                    && buscarMusicaNatural?.cadena.acciones.first?.modo.musicaAccion == "buscar"
                    && buscarMusicaNatural?.cadena.contenido.localizedCaseInsensitiveContains("Julio Jaramillo") == true,
                  "acción=\(buscarMusicaNatural?.cadena.acciones.first?.modo.musicaAccion ?? "nil") · \(buscarMusicaNatural?.cadena.contenido ?? "nil")")
        let reproducirMusicaNatural = ModoPlanificador.detectarNatural(
            "Pon una canción cualquiera de Julio Jaramillo", catalogo: catalogo)
        comprobar("reproducción musical natural conserva intención",
                  reproducirMusicaNatural?.cadena.acciones.first?.modo.base == "musica"
                    && reproducirMusicaNatural?.cadena.acciones.first?.modo.musicaAccion == "reproducir"
                    && Musica.extraerConsulta(reproducirMusicaNatural?.cadena.contenido ?? "",
                                              proveedor: "auto") == "Julio Jaramillo",
                  "acción=\(reproducirMusicaNatural?.cadena.acciones.first?.modo.musicaAccion ?? "nil") · \(reproducirMusicaNatural?.cadena.contenido ?? "nil")")
        var simBuscar: ResultadoMusica?
        Musica.ejecutar("Julio Jaramillo", intencion: .buscar, simular: true) { simBuscar = $0 }
        comprobar("simulación buscar solo abre resultados", simBuscar?.estado == .busqueda)
        var simReproducir: ResultadoMusica?
        Musica.ejecutar("Julio Jaramillo", intencion: .reproducir, simular: true) { simReproducir = $0 }
        comprobar("simulación reproducir exige reproducción", simReproducir?.estado == .reproduciendo)
        struct Plan { let texto: String; let accion: String; let proveedor: String?; let contiene: String }
        let planes = [
            Plan(texto: "Pon música de Jessy Uribe", accion: "musica", proveedor: nil, contiene: "Jessy Uribe"),
            Plan(texto: "Reproduce en Spotify música andina", accion: "musica", proveedor: "spotify", contiene: "andina"),
            Plan(texto: "Recuérdame mañana a las 8 llamar a Rafael", accion: "recordatorios", proveedor: nil, contiene: "mañana"),
            Plan(texto: "Agenda una reunión mañana a las 10", accion: "calendario", proveedor: nil, contiene: "mañana"),
            Plan(texto: "Busca el archivo informe final", accion: "archivo", proveedor: nil, contiene: "informe final"),
        ]
        for c in planes {
            let p = ModoPlanificador.detectarNatural(c.texto, catalogo: catalogo)
            let e = p?.cadena.acciones.first?.modo
            let id = e?.base == "musica" ? "musica" : e?.accion
            let ok = id == c.accion && (c.proveedor == nil || e?.musicaProveedor == c.proveedor)
                && p?.cadena.contenido.localizedCaseInsensitiveContains(c.contiene) == true
            comprobar("plan \(c.accion)", ok, "\(id ?? "nil") · \(p?.cadena.contenido ?? "nil")")
        }

        let finderPlan = ModoPlanificador.detectarNatural(
            "Busca el archivo informe final y muéstralo en Finder", catalogo: catalogo)
        let finderSolicitud = finderPlan.map {
            ArchivosMac.interpretarSolicitud(
                $0.cadena.contenido,
                forzarFinder: $0.cadena.acciones.first?.modo.prompt == "finder")
        }
        comprobar("buscar archivo puede mostrar todos los resultados en Finder",
                  finderPlan?.cadena.acciones.first?.modo.accion == "archivo"
                    && finderPlan?.cadena.acciones.first?.modo.prompt == "finder"
                    && finderSolicitud?.mostrarEnFinder == true
                    && finderSolicitud?.consulta == "informe final",
                  "\(finderSolicitud?.consulta ?? "nil") · finder=\(finderSolicitud?.mostrarEnFinder ?? false)")
        let finderDirecto = ModoPlanificador.detectarNatural(
            "Mostrar en Finder el archivo informe final", catalogo: catalogo)
        comprobar("mostrar en Finder es una orden de archivo",
                  finderDirecto?.cadena.acciones.first?.modo.accion == "archivo"
                    && finderDirecto?.cadena.acciones.first?.modo.prompt == "finder"
                    && finderDirecto.map {
                        ArchivosMac.interpretarSolicitud(
                            $0.cadena.contenido, forzarFinder: true).consulta
                    } == "informe final")
        let finderAlFinal = ArchivosMac.interpretarSolicitud("informe final en Finder")
        comprobar("en Finder al final se separa de la consulta",
                  finderAlFinal.mostrarEnFinder && finderAlFinal.consulta == "informe final")
        comprobar("mencionar Finder como nombre no fuerza visualización",
                  !ArchivosMac.interpretarSolicitud("informe sobre Finder").mostrarEnFinder)
        let candidatosArchivo = [
            URL(fileURLWithPath: "/Users/prueba/pdot2023.txt"),
            URL(fileURLWithPath: "/Users/prueba/MANUAL.md"),
            URL(fileURLWithPath: "/Users/prueba/Informe_Final_2026.docx"),
            URL(fileURLWithPath: "/Users/prueba/final-informe-firmado.pdf"),
            URL(fileURLWithPath: "/Users/prueba/rclone-drive.log"),
        ]
        let rankingArchivo = ArchivosMac.ordenarCoincidenciasPorNombre(
            candidatosArchivo, consulta: "informe final")
        comprobar("preview de archivos filtra resultados que coinciden solo por contenido",
                  rankingArchivo.map(\.lastPathComponent) == [
                    "Informe_Final_2026.docx", "final-informe-firmado.pdf"
                  ], rankingArchivo.map(\.lastPathComponent).joined(separator: " | "))
        comprobar("preview no inventa sugerencias sin coincidencia por nombre",
                  ArchivosMac.ordenarCoincidenciasPorNombre(
                    Array(candidatosArchivo.prefix(2)), consulta: "informe final").isEmpty)

        let negativos = [
            "La música del informe fue agradable",
            "Ayer recordé la reunión del calendario",
            "El archivo explica cómo buscar música",
            "Spotify anunció una nueva tarifa",
            "Mi mamá puso música mientras trabajaba",
        ]
        for t in negativos {
            comprobar("narración no acciona", ModoPlanificador.detectarNatural(t, catalogo: catalogo) == nil, t)
        }

        let musica = ModosStore.modo("musica")
        let reversible = ModoCadena(transforms: [], acciones: [ModoAccionPlan(modo: musica, destinatario: nil)], contenido: "algo")
        let recordatorio = Modo(id: "qa-rem", nombre: "Recordatorio", icono: "bell", base: "accion", accion: "recordatorios")
        let cambio = ModoCadena(transforms: [], acciones: [ModoAccionPlan(modo: recordatorio, destinatario: nil)], contenido: "algo")
        let whatsapp = Modo(id: "qa-wa", nombre: "WhatsApp", icono: "message", base: "accion", accion: "whatsapp")
        let externo = ModoCadena(transforms: [], acciones: [ModoAccionPlan(modo: whatsapp, destinatario: "Alberto")], contenido: "hola")
        let capturaLocal = Modo(id: "qa-captura", nombre: "Captura", icono: "camera",
                                base: "accion", accion: "captura_pantalla")
        let cadenaCaptura = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: capturaLocal, destinatario: nil)], contenido: "pantalla")
        let capturaWA = Modo(id: "qa-captura-wa", nombre: "Captura WhatsApp", icono: "camera",
                             base: "accion", accion: "captura_compartir")
        let cadenaCapturaWA = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: capturaWA, destinatario: nil)], contenido: "pantalla")
        comprobar("consultivo siempre pregunta", !PoliticaAgente.autoEjecutar(reversible, nivel: .consultivo))
        comprobar("asistido abre música", PoliticaAgente.autoEjecutar(reversible, nivel: .asistido))
        comprobar("asistido confirma cambio", !PoliticaAgente.autoEjecutar(cambio, nivel: .asistido))
        comprobar("autónomo crea local", PoliticaAgente.autoEjecutar(cambio, nivel: .autonomo))
        comprobar("externo siempre confirma", !PoliticaAgente.autoEjecutar(externo, nivel: .autonomo))
        comprobar("captura local confirma en asistido",
                  !PoliticaAgente.autoEjecutar(cadenaCaptura, nivel: .asistido)
                    && PoliticaAgente.autoEjecutar(cadenaCaptura, nivel: .autonomo))
        comprobar("captura para WhatsApp siempre confirma",
                  !PoliticaAgente.autoEjecutar(cadenaCapturaWA, nivel: .autonomo))

        var rutina = RutinaAgente(nombre: "Empezar oficina")
        rutina.frases = ["empezar oficina", "iniciar trabajo"]
        rutina.pasos = [PasoRutinaAgente(tipo: "musica", valor: "{texto}"),
                         PasoRutinaAgente(tipo: "recordatorio", valor: "revisar correo")]
        let dr = RutinasAgenteStore.detectar("Empezar oficina música andina", en: [rutina])
        comprobar("rutina parametrizable", dr?.rutina.id == rutina.id && dr?.contenido == "música andina")
        comprobar("riesgo de rutina consolidado", RutinasAgenteStore.riesgo(rutina) == .cambioLocal)

        let atajo = AppleAtajos.url(nombre: "Casa Bto", texto: "enciende la luz & música")?.absoluteString ?? ""
        comprobar("Atajo codifica el texto", atajo.hasPrefix("shortcuts://run-shortcut?")
                    && atajo.contains("Casa%20Bto") && !atajo.contains(" & "), atajo)

        let planRecordatorioHora = ModoPlanificador.detectarNatural(
            "recuérdame mañana a las 8:00 p.m. llamar a Rafael", catalogo: catalogo)
        comprobar("dos puntos de una hora no cortan el contenido",
                  planRecordatorioHora?.cadena.acciones.first?.modo.accion == "recordatorios"
                    && planRecordatorioHora?.cadena.contenido == "mañana a las 8:00 p.m. llamar a Rafael",
                  planRecordatorioHora?.cadena.contenido ?? "nil")
        let planCalendarioHora = ModoPlanificador.detectarNatural(
            "Agenda una reunión mañana a las 10:00 a.m.", catalogo: catalogo)
        comprobar("calendario tampoco corta la hora",
                  planCalendarioHora?.cadena.acciones.first?.modo.accion == "calendario"
                    && planCalendarioHora?.cadena.contenido == "una reunión mañana a las 10:00 a.m.",
                  planCalendarioHora?.cadena.contenido ?? "nil")
        let planHorario = ModoPlanificador.detectarNatural(
            "Agenda un horario mañana a las 10:00", catalogo: catalogo)
        comprobar("agenda un horario enruta a Calendario y conserva título",
                  planHorario?.cadena.acciones.first?.modo.accion == "calendario"
                    && planHorario?.cadena.contenido == "un horario mañana a las 10:00",
                  planHorario?.cadena.contenido ?? "nil")
        comprobar("narración sobre un horario no crea evento",
                  ModoPlanificador.detectarNatural(
                    "La agenda de la oficina tiene un horario mañana a las 10:00",
                    catalogo: catalogo) == nil)

        let referencia = Calendar.current.date(from: DateComponents(
            year: 2026, month: 7, day: 18, hour: 14, minute: 30))!
        let manana = Calendar.current.date(byAdding: .day, value: 1, to: referencia)!
        func agendaCoincide(_ texto: String, hora: Int, minuto: Int = 0,
                            titulo: String = "llamar a Rafael") -> Bool {
            let p = AppleAgenda.previsualizar(texto, ahora: referencia)
            guard let f = p.fecha, p.error == nil else { return false }
            return Calendar.current.isDate(f, inSameDayAs: manana)
                && Calendar.current.component(.hour, from: f) == hora
                && Calendar.current.component(.minute, from: f) == minuto
                && p.titulo == titulo
        }
        comprobar("recordatorio exacto 8 p.m.",
                  agendaCoincide("mañana a las 8:00 p.m. llamar a Rafael", hora: 20))
        comprobar("recordatorio p. m. separado",
                  agendaCoincide("mañana a las 8:00 p. m. llamar a Rafael", hora: 20))
        comprobar("recordatorio 8 a.m.",
                  agendaCoincide("mañana a las 8:00 a.m. llamar a Rafael", hora: 8))
        comprobar("recordatorio 24 horas",
                  agendaCoincide("mañana a las 20:15 llamar a Rafael", hora: 20, minuto: 15))
        comprobar("horario natural llega completo a EventKit",
                  agendaCoincide("un horario mañana a las 10:00", hora: 10,
                                 titulo: "un horario"))
        comprobar("medianoche y mediodía no se confunden",
                  agendaCoincide("mañana a las 12:00 a.m. llamar a Rafael", hora: 0)
                    && agendaCoincide("mañana a las 12:00 p.m. llamar a Rafael", hora: 12))
        comprobar("franja de la noche",
                  agendaCoincide("mañana a las 8 de la noche llamar a Rafael", hora: 20))
        let agendaLimpia = AppleAgenda.previsualizar(
            "para mañana a las 3:00 p.m. de la tarde, una reunión con Israel", ahora: referencia)
        comprobar("fecha se retira del título",
                  agendaLimpia.error == nil && agendaLimpia.titulo == "una reunión con Israel"
                    && agendaLimpia.fecha.map { Calendar.current.component(.hour, from: $0) } == 15,
                  agendaLimpia.titulo)
        let invalida = AppleAgenda.previsualizar(
            "mañana a las 00:00 p.m. llamar a Rafael", ahora: referencia)
        comprobar("hora inválida no inventa medianoche",
                  invalida.fecha == nil && invalida.error != nil,
                  invalida.error ?? "sin error")

        let fallos = resultados.filter { !$0 }.count
        if fallos == 0 { print("AGENTCORE TODO OK") }
        else { print("AGENTCORE ✗ \(fallos) FALLOS") }
        fflush(stdout); exit(fallos == 0 ? 0 : 4)
    }
}

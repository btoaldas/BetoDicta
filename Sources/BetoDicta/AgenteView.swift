import AppKit
import EventKit
import SwiftUI

@MainActor
final class AgenteSettingsModel: ObservableObject {
    @Published var activo: Bool { didSet { Config.set("agente_nucleo_activo", to: activo) } }
    @Published var nombre: String { didSet { Config.set("agente_nombre", to: nombre) } }
    @Published var personalidad: String { didSet { Config.set("agente_personalidad", to: personalidad) } }
    @Published var activadores: String {
        didSet {
            let a = FrasesConfigurables.parsear(activadores)
            Config.set("agente_activadores", to: a)
        }
    }
    @Published var autonomia: String { didSet { Config.set("agente_autonomia", to: autonomia) } }
    @Published var motor: String { didSet { Config.set("agente_motor", to: motor) } }
    @Published var fallback: Bool { didSet { Config.set("agente_fallback_local", to: fallback) } }
    @Published var proveedorIA: String { didSet { Config.set("agente_ia_proveedor", to: proveedorIA) } }
    @Published var modeloIA: String { didSet { Config.set("agente_ia_modelo", to: modeloIA) } }
    @Published var memoria: Bool { didSet { Config.set("agente_memoria_activa", to: memoria) } }
    @Published var memoriaContexto: Bool { didSet { Config.set("agente_memoria_contexto_ia", to: memoriaContexto) } }
    @Published var turnos: Double { didSet { Config.set("agente_memoria_turnos", to: Int(turnos)) } }
    @Published var pegar: Bool { didSet { Config.set("agente_pega", to: pegar) } }
    @Published var respuestaActiva: Bool { didSet { Config.set("agente_respuesta_activa", to: respuestaActiva) } }
    @Published var respuestaFormato: String { didSet { Config.set("agente_respuesta_formato", to: respuestaFormato) } }
    @Published var codexEstado = "Sin comprobar"
    @Published var codexConectado = false
    @Published var codexTrabajando = false
    @Published var codexBin: String { didSet { Config.set("agente_codex_bin", to: codexBin) } }
    @Published var codexTimeout: Double { didSet { Config.set("agente_codex_timeout", to: codexTimeout) } }
    @Published var codexModelo: String { didSet { Config.set("codex_cuenta_modelo", to: codexModelo) } }
    @Published var codexEsfuerzo: String { didSet { Config.set("codex_cuenta_esfuerzo", to: codexEsfuerzo) } }

    @Published var toolMusica: Bool { didSet { Config.set("agente_tool_musica", to: toolMusica) } }
    @Published var toolCalendario: Bool { didSet { Config.set("agente_tool_calendario", to: toolCalendario) } }
    @Published var toolRecordatorios: Bool { didSet { Config.set("agente_tool_recordatorios", to: toolRecordatorios) } }
    @Published var toolArchivos: Bool { didSet { Config.set("agente_tool_archivos", to: toolArchivos) } }
    @Published var toolAplicaciones: Bool { didSet { Config.set("agente_tool_aplicaciones", to: toolAplicaciones) } }
    @Published var toolComunicaciones: Bool { didSet { Config.set("agente_tool_comunicaciones", to: toolComunicaciones) } }
    @Published var toolAtajos: Bool { didSet { Config.set("agente_tool_atajos", to: toolAtajos) } }
    @Published var toolCapturas: Bool { didSet { Config.set("agente_tool_capturas", to: toolCapturas) } }
    @Published var atajoApple: String { didSet { Config.set("agente_atajo_apple", to: atajoApple) } }
    @Published var atajos: [String] = []

    @Published var capturaDestino: String { didSet { Config.set("captura_destino", to: capturaDestino) } }
    @Published var capturaGuardar: Bool { didSet { Config.set("captura_guardar", to: capturaGuardar) } }
    @Published var capturaCopiar: Bool { didSet { Config.set("captura_copiar", to: capturaCopiar) } }
    @Published var capturaAbrir: Bool { didSet { Config.set("captura_abrir", to: capturaAbrir) } }
    @Published var capturaMicrofono: Bool { didSet { Config.set("captura_microfono", to: capturaMicrofono) } }
    @Published var capturaClics: Bool { didSet { Config.set("captura_mostrar_clics", to: capturaClics) } }
    @Published var capturaWhatsAppAccion: String { didSet { Config.set("captura_whatsapp_accion", to: capturaWhatsAppAccion) } }
    @Published var capturaDuracion: Int { didSet { Config.set("captura_duracion_predeterminada", to: capturaDuracion) } }
    @Published var capturaSegmento: Int { didSet { Config.set("captura_segmento_segundos", to: capturaSegmento) } }

    @Published var cascadaMusica: [String] { didSet { Config.set("musica_cascada", to: cascadaMusica) } }
    @Published var reproducir: Bool { didSet { Config.set("musica_intentar_reproducir", to: reproducir) } }
    @Published var musicaSinConsulta: String { didSet { Config.set("musica_sin_consulta", to: musicaSinConsulta) } }
    @Published var musicaCatalogo: Bool { didSet { Config.set("musica_catalogo_automatico", to: musicaCatalogo) } }
    @Published var musicaAtajo: String { didSet { Config.set("musica_atajo_apple", to: musicaAtajo) } }
    @Published var musicaAtajoPrimero: Bool { didSet { Config.set("musica_atajo_primero", to: musicaAtajoPrimero) } }
    @Published var rutinas: [RutinaAgente]
    @Published var aviso = ""
    @Published var permisosTick = 0

    init() {
        activo = Config.agenteNucleoActivo(); nombre = Config.agenteNombre()
        personalidad = Config.agentePersonalidad()
        activadores = FrasesConfigurables.formatear(Config.agenteActivadores())
        autonomia = Config.agenteAutonomia(); motor = Config.agenteMotor()
        fallback = Config.agenteFallbackCerebro(); proveedorIA = Config.agenteIAProveedor()
        modeloIA = Config.agenteIAModelo(); memoria = Config.agenteMemoriaActiva()
        memoriaContexto = Config.agenteMemoriaContextoIA()
        turnos = Double(Config.agenteMemoriaTurnos()); pegar = Config.agentePega()
        respuestaActiva = Config.agenteRespuestaActiva()
        respuestaFormato = Config.agenteRespuestaFormato()
        codexBin = Config.agenteCodexBin(); codexTimeout = Config.agenteCodexTimeout()
        codexModelo = Config.codexCuentaModelo(); codexEsfuerzo = Config.codexCuentaEsfuerzo()
        toolMusica = Config.agenteHerramientaMusica()
        toolCalendario = Config.agenteHerramientaCalendario()
        toolRecordatorios = Config.agenteHerramientaRecordatorios()
        toolArchivos = Config.agenteHerramientaArchivos()
        toolAplicaciones = Config.agenteHerramientaAplicaciones()
        toolComunicaciones = Config.agenteHerramientaComunicaciones()
        toolAtajos = Config.agenteHerramientaAtajos(); toolCapturas = Config.agenteHerramientaCapturas()
        atajoApple = Config.agenteAtajoApple()
        capturaDestino = Config.capturaDestino(); capturaGuardar = Config.capturaGuardarArchivo()
        capturaCopiar = Config.capturaCopiarPortapapeles()
        capturaAbrir = Config.capturaAbrirAlTerminar(); capturaMicrofono = Config.capturaGrabarMicrofono()
        capturaClics = Config.capturaMostrarClics()
        capturaWhatsAppAccion = Config.capturaWhatsAppPolitica().rawValue
        capturaDuracion = Config.capturaDuracionPredeterminada()
        capturaSegmento = Config.capturaSegmentoSegundos()
        cascadaMusica = Config.musicaCascada(); reproducir = Config.musicaIntentarReproducir()
        musicaSinConsulta = Config.musicaSinConsulta()
        musicaCatalogo = Config.musicaCatalogoAutomatico()
        musicaAtajo = Config.musicaAtajoApple(); musicaAtajoPrimero = Config.musicaAtajoPrimero()
        rutinas = RutinasAgenteStore.todas()
    }

    func moverMusica(_ i: Int, _ delta: Int) {
        let j = i + delta; guard i >= 0, i < cascadaMusica.count, j >= 0, j < cascadaMusica.count else { return }
        cascadaMusica.swapAt(i, j)
    }

    func quitarMusica(_ id: String) { cascadaMusica.removeAll { $0 == id } }
    func agregarMusica(_ id: String) {
        guard !cascadaMusica.contains(id) else { return }; cascadaMusica.append(id)
    }

    func agregarProveedor(nombre: String, url: String) -> Bool {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, Musica.plantillaSegura(u) else {
            aviso = "Usa una URL HTTPS con {q} (HTTP solo en localhost)."; return false
        }
        var p = Config.musicaProveedoresPersonales()
        p.removeAll { PerfilAgente.normalizar($0["nombre"] ?? "") == PerfilAgente.normalizar(n) }
        p.append(["nombre": n, "url": u]); Config.set("musica_proveedores_personales", to: p)
        if let id = Musica.personales().first(where: { $0.nombre == n })?.id { agregarMusica(id) }
        aviso = "Proveedor «\(n)» agregado."; return true
    }

    func borrarProveedor(_ id: String) {
        guard let p = Musica.proveedor(id) else { return }
        let restantes = Config.musicaProveedoresPersonales().filter {
            PerfilAgente.normalizar($0["nombre"] ?? "") != PerfilAgente.normalizar(p.nombre)
        }
        Config.set("musica_proveedores_personales", to: restantes); quitarMusica(id)
    }

    func cargarAtajos() { AppleAtajos.listar { [weak self] in self?.atajos = $0 } }
    func instalarAtajoMusica() {
        let r = AppleAtajos.instalarMusicaIncluido()
        aviso = r.mensaje
        if r.ok {
            musicaAtajo = AppleAtajos.nombreMusicaIncluido
            musicaAtajoPrimero = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.cargarAtajos() }
        }
    }
    func actualizarCodex() {
        codexTrabajando = true
        AgenteCodex.estado { [weak self] estado in
            self?.codexEstado = estado.texto; self?.codexConectado = estado == .chatgpt
            self?.codexTrabajando = false
        }
    }
    func conectarCodex() {
        codexTrabajando = true; codexEstado = "Esperando autorización en el navegador…"
        AgenteCodex.autorizar { [weak self] ok, mensaje in
            self?.codexConectado = ok; self?.codexEstado = mensaje
            self?.codexTrabajando = false
        }
    }
    func guardarRutinas() { RutinasAgenteStore.guardar(rutinas); aviso = "Rutinas guardadas." }
    func nuevaRutina() { var r = RutinaAgente(nombre: "Nueva rutina"); r.pasos = [PasoRutinaAgente()]; rutinas.append(r) }
    func borrarRutina(_ i: Int) { guard rutinas.indices.contains(i) else { return }; rutinas.remove(at: i) }
}

struct AgenteView: View {
    @StateObject private var m = AgenteSettingsModel()
    @State private var proveedorNombre = ""
    @State private var proveedorURL = ""

    private let violeta = Color(red: 0.36, green: 0.28, blue: 0.62)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Asistente por voz").font(.title2).bold()
                Text("El cerebro orquesta tus Modos y herramientas. Dictado sigue siendo Dictado: puedes apagar este núcleo sin perder nada de lo anterior.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            card("Presencia y personalidad", "person.wave.2.fill") {
                Toggle("Activar el núcleo del asistente", isOn: $m.activo)
                field("Nombre", text: $m.nombre, placeholder: "Bto, Jarvis, Mamá…")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frases de activación al iniciar un dictado").font(.subheadline)
                    TextEditor(text: $m.activadores)
                        .font(.body).frame(minHeight: 58, maxHeight: 82)
                        .padding(5).background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Una frase por línea y mínimo dos palabras. La puntuación no importa: “Oye, Bto” coincide con “Oye Bto”. Activadores de una palabra como “oye” o “Bto” se ignoran para que un dictado normal no llame al agente. Funciona dentro del dictado iniciado con fn; el micrófono no queda escuchando en reposo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personalidad").font(.subheadline)
                    TextEditor(text: $m.personalidad).font(.body).frame(minHeight: 90)
                        .padding(5).background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Define tono, trato, longitud y manera de expresarse. La voz TTS se elige aparte.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            card("Autonomía", "shield.lefthalf.filled") {
                Picker("Nivel", selection: $m.autonomia) {
                    ForEach(NivelAutonomiaAgente.allCases) { Text($0.nombre).tag($0.rawValue) }
                }.pickerStyle(.segmented)
                Text(NivelAutonomiaAgente(rawValue: m.autonomia)?.detalle ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Enviar mensajes/correos, publicar, comprar o borrar siempre exige confirmación, incluso en Autónomo.")
                    .font(.caption).foregroundStyle(.orange)
            }

            card("Respuestas", "waveform.and.speech.bubble.fill") {
                Toggle("Responder al actuar, preguntar o no entender", isOn: $m.respuestaActiva)
                if m.respuestaActiva {
                    Picker("Formato", selection: $m.respuestaFormato) {
                        Text("Solo texto").tag("texto")
                        Text("Texto y voz").tag("texto_voz")
                    }.pickerStyle(.segmented)
                    Text("Usa la personalidad y la voz preconfiguradas. Las confirmaciones se leen en voz, y cada acción responde brevemente sin inventar que tuvo éxito.")
                        .font(.caption).foregroundStyle(.secondary)
                    if m.respuestaFormato == "texto_voz", !Config.ttsActivo() {
                        Text("Activa “Que BetoDicta pueda hablarte (TTS)” en Avanzado para oírla; mientras tanto seguirá respondiendo por texto.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            card("Cerebro y memoria", "brain.head.profile") {
                Picker("Cerebro principal", selection: $m.motor) {
                    Text("IA configurada en BetoDicta").tag("local")
                    Text("Hermes").tag("hermes")
                    Text("ChatGPT por cuenta (Codex)").tag("codex")
                }
                if m.motor == "hermes" || m.fallback {
                    Text(AgenteHermes.disponible
                         ? "Hermes detectado. Solo razona y responde: las acciones pasan por la política de autonomía de BetoDicta."
                         : "Hermes no está disponible; se omite sin detener al asistente.")
                        .font(.caption).foregroundStyle(AgenteHermes.disponible ? Color.secondary : Color.orange)
                    Button("Nueva conversación con Hermes") { AgenteHermes.reiniciar(); m.aviso = "Conversación de Hermes reiniciada." }
                        .controlSize(.small)
                }
                if m.motor == "codex" || m.fallback {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Circle().fill(m.codexConectado ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(m.codexEstado).font(.caption)
                            Spacer()
                            Button("Comprobar") { m.actualizarCodex() }
                                .controlSize(.small).disabled(m.codexTrabajando)
                            Button("Conectar en navegador") { m.conectarCodex() }
                                .controlSize(.small).disabled(m.codexTrabajando || !AgenteCodex.disponible)
                        }
                        Text("La autorización y renovación pertenecen al cliente oficial Codex; BetoDicta no recibe tu contraseña, cookies ni token. Consume el cupo de Codex incluido en tu plan ChatGPT, no créditos del API.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Modelo Codex", selection: $m.codexModelo) {
                            ForEach(AgenteCodex.modelosDisponibles()) { modelo in
                                Text(modelo.nombre + (modelo.oculto ? " · compatibilidad" : ""))
                                    .tag(modelo.id)
                            }
                        }
                        Picker("Razonamiento", selection: $m.codexEsfuerzo) {
                            ForEach(AgenteCodex.esfuerzosDisponibles) { esfuerzo in
                                Text(esfuerzo.nombre).tag(esfuerzo.id)
                            }
                        }
                        Text(AgenteCodex.descripcionModelo(m.codexModelo))
                            .font(.caption2).foregroundStyle(.secondary)
                        field("Ruta Codex (opcional)", text: $m.codexBin,
                              placeholder: "Vacío = autodetectar ~/.local/bin/codex")
                        HStack {
                            Text("Esperar hasta \(Int(m.codexTimeout)) s").font(.caption)
                            Slider(value: $m.codexTimeout, in: 15...180, step: 5).frame(maxWidth: 260)
                        }
                    }
                }
                Toggle("Si el cerebro principal falla, probar cerebros de respaldo", isOn: $m.fallback)
                let conectadas = ChatIA.conectadasPulido
                Picker("IA del asistente", selection: $m.proveedorIA) {
                    Text("Cascada global de pulido").tag("")
                    ForEach(conectadas, id: \.id) { Text($0.etiqueta).tag($0.id) }
                }
                field("Modelo (opcional)", text: $m.modeloIA, placeholder: "Vacío = modelo activo del proveedor")
                VStack(alignment: .leading, spacing: 3) {
                    Text("El plan mensual de ChatGPT y el API de OpenAI siguen separados. La opción Codex sirve como cerebro conversacional oficial; STT y TTS continúan usando Apple, motores locales o sus propias APIs.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Abrir plataforma API de OpenAI", destination: URL(string: "https://platform.openai.com/")!)
                        .font(.caption)
                }
                Toggle("Memoria conversacional corta (local)", isOn: $m.memoria)
                if m.memoria {
                    HStack {
                        Text("Recordar \(Int(m.turnos)) turnos").font(.subheadline)
                        Slider(value: $m.turnos, in: 1...30, step: 1).frame(maxWidth: 260)
                        Button("Borrar memoria") { MemoriaAgente.limpiar(); m.aviso = "Memoria corta borrada." }
                            .controlSize(.small)
                    }
                    Toggle("Usar esa memoria como contexto del cerebro", isOn: $m.memoriaContexto)
                    Text("Si eliges una IA de nube, el contexto necesario se envía a ese proveedor. Apágalo para conservar solo los seguimientos locales.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Pegar también la respuesta en la aplicación activa", isOn: $m.pegar)
            }

            card("Herramientas nativas", "wrench.and.screwdriver.fill") {
                Toggle("Música", isOn: $m.toolMusica)
                Toggle("Aplicaciones instaladas", isOn: $m.toolAplicaciones)
                Toggle("Borradores en Gmail, Mail, Outlook, WhatsApp y Mensajes", isOn: $m.toolComunicaciones)
                Text("Prepara y abre el borrador con destinatario/asunto/cuerpo. Nunca pulsa Enviar por ti.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Buscar y abrir archivos (Spotlight)", isOn: $m.toolArchivos)
                Divider()
                Toggle("Capturas y grabaciones de pantalla", isOn: $m.toolCapturas)
                if m.toolCapturas {
                    Picker("Guardar por defecto", selection: $m.capturaDestino) {
                        ForEach(DestinoCapturaMac.allCases) { Text($0.nombre).tag($0.rawValue) }
                    }
                    Toggle("Guardar un archivo por defecto", isOn: $m.capturaGuardar)
                    Toggle("Copiar también las capturas al portapapeles", isOn: $m.capturaCopiar)
                    Toggle("Abrir el resultado al terminar", isOn: $m.capturaAbrir)
                    Picker("Al compartir por WhatsApp", selection: $m.capturaWhatsAppAccion) {
                        ForEach(PoliticaWhatsAppCaptura.allCases) { p in
                            Text(p.nombre).tag(p.rawValue)
                        }
                    }
                    Toggle("Incluir micrófono en grabaciones", isOn: $m.capturaMicrofono)
                    Toggle("Mostrar clics en grabaciones", isOn: $m.capturaClics)
                    Picker("Si no dices duración", selection: $m.capturaDuracion) {
                        Text("Hasta que la detenga en BetoDicta").tag(0)
                        Text("15 segundos").tag(15)
                        Text("30 segundos").tag(30)
                        Text("1 minuto").tag(60)
                        Text("2 minutos").tag(120)
                        Text("5 minutos").tag(300)
                    }
                    if m.capturaDuracion == 0 {
                        Picker("Proteger grabación cada", selection: $m.capturaSegmento) {
                            Text("1 minuto").tag(60)
                            Text("5 minutos · recomendado").tag(300)
                            Text("10 minutos").tag(600)
                            Text("15 minutos").tag(900)
                            Text("30 minutos").tag(1800)
                        }
                    }
                    HStack {
                        Text("Permiso de pantalla: \(CapturaMac.permisoConcedido() ? "Permitido" : "Pendiente")")
                        Spacer()
                        Button("Solicitar permiso") {
                            let ok = CapturaMac.solicitarPermiso()
                            m.permisosTick += 1
                            m.aviso = ok ? "Permiso de pantalla concedido."
                                : "Autoriza BetoDicta en Privacidad y seguridad → Grabación de pantalla."
                        }.controlSize(.small)
                    }.font(.caption)
                    Text("Con duración, BetoDicta se detiene solo. Sin duración, empieza de inmediato: una sola pulsación de tu tecla de dictado —o ‘Detener y guardar’ en el menú— cierra el .mov. Los fragmentos periódicos protegen las grabaciones largas. El notch permanece oculto. En WhatsApp puedes dejar el archivo en el portapapeles, pegarlo para revisar o activar expresamente el autoenvío.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle("Recordatorios de Mac (EventKit)", isOn: $m.toolRecordatorios)
                Toggle("Calendario de Mac (EventKit)", isOn: $m.toolCalendario)
                HStack {
                    Text("Recordatorios: \(AppleAgenda.nombreEstado(AppleAgenda.estadoRecordatorios()))")
                    Spacer()
                    Button("Solicitar permiso") { AppleAgenda.solicitarRecordatorios { _ in m.permisosTick += 1 } }
                        .controlSize(.small)
                }.font(.caption)
                HStack {
                    Text("Calendario: \(AppleAgenda.nombreEstado(AppleAgenda.estadoEventos()))")
                    Spacer()
                    Button("Solicitar permiso") { AppleAgenda.solicitarEventos { _ in m.permisosTick += 1 } }
                        .controlSize(.small)
                }.font(.caption)
                let _ = m.permisosTick
                Divider()
                Toggle("Pasarela Apple mediante Atajos", isOn: $m.toolAtajos)
                if m.toolAtajos {
                    field("Atajo que recibe el texto", text: $m.atajoApple, placeholder: "Mi atajo de BetoDicta")
                    if !m.atajos.isEmpty {
                        Picker("Atajos encontrados", selection: $m.atajoApple) {
                            Text("Elegir…").tag("")
                            ForEach(m.atajos, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button("Actualizar lista de Atajos") { m.cargarAtajos() }.controlSize(.small)
                    Text("Siri no permite recibir texto arbitrario mediante una API pública. BetoDicta usa el puente oficial de Atajos: tú creas el atajo y decides qué puede hacer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            musica
            rutinas

            if !m.aviso.isEmpty { Text(m.aviso).font(.caption).foregroundStyle(violeta) }
        }
        .onAppear { m.cargarAtajos(); m.actualizarCodex() }
    }

    private var musica: some View {
        card("Modo Música y failover", "music.note.list") {
            Toggle("Intentar reproducir una coincidencia de la biblioteca de Apple Music", isOn: $m.reproducir)
            Picker("Al decir “pon música” sin artista", selection: $m.musicaSinConsulta) {
                Text("Poner una canción aleatoria").tag("aleatorio")
                Text("Reanudar lo último").tag("reanudar")
            }
            Toggle("Reproducir el primer resultado del catálogo de Apple Music",
                   isOn: $m.musicaCatalogo)
            Text("Usa el buscador público de Apple y Accesibilidad; verifica título y artista. Si falla, continúa por la cascada.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Si no puede reproducir o la app no está, continúa por la cascada y termina en búsqueda web.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Probar primero un Atajo de Apple Music", isOn: $m.musicaAtajoPrimero)
            if m.musicaAtajoPrimero {
                field("Atajo de música", text: $m.musicaAtajo, placeholder: "Reproducir con BetoDicta")
                let instalado = m.atajos.contains(m.musicaAtajo)
                HStack(spacing: 8) {
                    Image(systemName: instalado ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(instalado ? .green : .orange)
                    Text(instalado ? "Atajo incluido instalado" : "Falta autorizar el Atajo incluido una vez")
                        .font(.caption)
                    if !instalado, m.musicaAtajo == AppleAtajos.nombreMusicaIncluido {
                        Button("Instalar…") { m.instalarAtajoMusica() }.controlSize(.small)
                    }
                }
                if !m.atajos.isEmpty {
                    Picker("Atajo encontrado", selection: $m.musicaAtajo) {
                        Text("Elegir…").tag("")
                        ForEach(m.atajos, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text("BetoDicta trae «\(AppleAtajos.nombreMusicaIncluido)» ya construido y lo prueba primero. macOS exige confirmar su importación una vez. Busca una coincidencia en tu biblioteca; BetoDicta verifica título/artista y, si no coincide, continúa por la cascada. Puedes editarlo o sustituirlo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(m.cascadaMusica.enumerated()), id: \.element) { i, id in
                HStack {
                    Text("\(i + 1). \(Musica.nombre(id))").font(.subheadline)
                    Spacer()
                    Button { m.moverMusica(i, -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.plain).disabled(i == 0)
                    Button { m.moverMusica(i, 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain).disabled(i == m.cascadaMusica.count - 1)
                    Button { m.quitarMusica(id) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain)
                }
            }
            let faltan = Musica.catalogo().filter { !m.cascadaMusica.contains($0.id) }
            if !faltan.isEmpty {
                Menu("Agregar a la cascada") {
                    ForEach(faltan) { p in Button(p.nombre) { m.agregarMusica(p.id) } }
                }.controlSize(.small)
            }
            Divider()
            Text("Proveedor propio").font(.subheadline).bold()
            TextField("Nombre", text: $proveedorNombre).textFieldStyle(.roundedBorder)
            TextField("https://servicio.example/buscar?q={q}", text: $proveedorURL).textFieldStyle(.roundedBorder)
            HStack {
                Button("Agregar") {
                    if m.agregarProveedor(nombre: proveedorNombre, url: proveedorURL) {
                        proveedorNombre = ""; proveedorURL = ""
                    }
                }.controlSize(.small)
            }
            ForEach(Musica.personales()) { p in
                HStack {
                    Text(p.nombre).font(.caption)
                    Spacer()
                    Button("Quitar") { m.borrarProveedor(p.id) }.controlSize(.small)
                }
            }
        }
    }

    private var rutinas: some View {
        card("Rutinas creadas por ti", "list.bullet.rectangle.portrait") {
            Text("Cada rutina tiene frases de activación y pasos ordenados. {texto} representa lo que dices después del nombre.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach($m.rutinas) { $rutina in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("", isOn: $rutina.activa).labelsHidden()
                        TextField("Nombre", text: $rutina.nombre)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            m.rutinas.removeAll { $0.id == rutina.id }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                    }
                    TextField("Frases separadas por coma", text: Binding(
                        get: { rutina.frases.joined(separator: ", ") },
                        set: { valor in rutina.frases = valor.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    )).textFieldStyle(.roundedBorder)
                    ForEach($rutina.pasos) { $paso in
                        HStack {
                            Picker("", selection: $paso.tipo) {
                                Text("Música").tag("musica"); Text("Aplicación").tag("app")
                                Text("URL").tag("url"); Text("Atajo Apple").tag("atajo")
                                Text("Tarea local").tag("tarea"); Text("Nota local").tag("nota")
                                Text("Recordatorio").tag("recordatorio"); Text("Calendario").tag("calendario")
                                Text("Archivo").tag("archivo")
                                Text("Captura de pantalla").tag("captura")
                                Text("Grabación de pantalla").tag("grabacion")
                            }.labelsHidden().frame(width: 150)
                            TextField("Valor o {texto}", text: $paso.valor)
                                .textFieldStyle(.roundedBorder)
                            Button { rutina.pasos.removeAll { $0.id == paso.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                        }
                    }
                    Button("Agregar paso") { rutina.pasos.append(PasoRutinaAgente()) }.controlSize(.small)
                }
                .padding(10).background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button("Nueva rutina") { m.nuevaRutina() }
                Button("Guardar rutinas") { m.guardarRutinas() }.buttonStyle(.borderedProminent).tint(violeta)
            }.controlSize(.small)
        }
    }

    private func field(_ titulo: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(titulo).font(.subheadline).frame(width: 170, alignment: .leading)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func card<Content: View>(_ titulo: String, _ icono: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo, systemImage: icono).font(.headline).foregroundStyle(violeta)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

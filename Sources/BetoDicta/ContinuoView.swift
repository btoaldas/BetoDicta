import SwiftUI

/// Mismo púrpura del logo que usa la ventana de ajustes. Se repite aquí porque
/// allí es `private` y no merece la pena tocar ese archivo solo por un color.
private let acentoBitacora = Color(red: 0.36, green: 0.28, blue: 0.62)

// MARK: - Pestaña "Bitácora" (grabación continua)
//
// Todo lo que hace el módulo se decide aquí. Una sola excepción deliberada:
// que la bitácora ceda el micrófono al dictado NO es un ajuste, es invariante
// del código. Se explica en pantalla, no se ofrece como interruptor.

final class ContinuoModel: ObservableObject {

    @Published var activo: Bool { didSet { Config.set("continuo_activo", to: activo); aplicar() } }
    @Published var carpeta: String { didSet { Config.set("continuo_carpeta", to: carpeta) } }

    @Published var audioModo: String { didSet { Config.set("continuo_audio_modo", to: audioModo); aplicar() } }
    @Published var audioEco: Bool { didSet { Config.set("continuo_audio_cancelacion_eco", to: audioEco); aplicar() } }
    @Published var audioSegmento: Double { didSet { Config.set("continuo_audio_segmento_segundos", to: Int(audioSegmento)) } }
    @Published var audioAdoptar: Bool { didSet { Config.set("continuo_audio_adoptar_dictado", to: audioAdoptar) } }
    @Published var audioUmbral: Double { didSet { Config.set("continuo_audio_umbral_voz", to: audioUmbral) } }

    @Published var pantallaActiva: Bool { didSet { Config.set("continuo_pantalla_activa", to: pantallaActiva); aplicar() } }
    @Published var pantallaIntervalo: Double { didSet { Config.set("continuo_pantalla_intervalo_segundos", to: Int(pantallaIntervalo)); aplicar() } }
    @Published var pantallaFormato: String { didSet { Config.set("continuo_pantalla_formato", to: pantallaFormato) } }
    @Published var pantallaCalidad: Double { didSet { Config.set("continuo_pantalla_calidad", to: pantallaCalidad) } }
    @Published var pantallaEscala: Double { didSet { Config.set("continuo_pantalla_escala", to: pantallaEscala) } }
    @Published var pantallaDedup: Bool { didSet { Config.set("continuo_pantalla_deduplicar", to: pantallaDedup) } }
    @Published var pantallaUmbral: Double { didSet { Config.set("continuo_pantalla_umbral_cambio", to: pantallaUmbral) } }
    @Published var pantallaForzar: Double { didSet { Config.set("continuo_pantalla_forzar_minutos", to: Int(pantallaForzar)) } }
    @Published var pantallaPausar: Bool { didSet { Config.set("continuo_pantalla_pausar_bloqueada", to: pantallaPausar) } }
    @Published var appsExcluidas: String { didSet { Config.set("continuo_pantalla_apps_excluidas", to: listaDe(appsExcluidas)) } }

    @Published var soloCorriente: Bool { didSet { Config.set("continuo_solo_con_corriente", to: soloCorriente) } }

    @Published var retencionDias: Double { didSet { Config.set("continuo_retencion_dias", to: Int(retencionDias)) } }
    @Published var retencionAuto: Bool { didSet { Config.set("continuo_retencion_automatica", to: retencionAuto) } }
    @Published var retencionAvisar: Bool { didSet { Config.set("continuo_retencion_avisar_sin_procesar", to: retencionAvisar) } }

    // ---- Tanda diferida ----
    @Published var dispIntervalo: Bool { didSet { guardarDisparadores() } }
    @Published var dispHora: Bool { didSet { guardarDisparadores() } }
    @Published var dispArranque: Bool { didSet { guardarDisparadores() } }
    @Published var dispApagado: Bool { didSet { guardarDisparadores() } }
    @Published var loteIntervalo: Double { didSet { Config.set("continuo_lote_intervalo_minutos", to: Int(loteIntervalo)); ContinuoPlanificador.reconfigurar() } }
    @Published var loteMinutoDia: Double { didSet { Config.set("continuo_lote_minuto_del_dia", to: Int(loteMinutoDia)); ContinuoPlanificador.reconfigurar() } }
    @Published var loteMotor: String { didSet { Config.set("continuo_lote_motor", to: loteMotor) } }
    @Published var loteComprimir: Bool { didSet { Config.set("continuo_lote_comprimir", to: loteComprimir) } }
    @Published var loteCorriente: Bool { didSet { Config.set("continuo_lote_solo_con_corriente", to: loteCorriente) } }
    @Published var ocrActivo: Bool { didSet { Config.set("continuo_ocr_activo", to: ocrActivo) } }
    @Published var ocrPreciso: Bool { didSet { Config.set("continuo_ocr_preciso", to: ocrPreciso) } }
    @Published var resumenActivo: Bool { didSet { Config.set("continuo_resumen_activo", to: resumenActivo) } }
    @Published var resumenPantalla: Bool { didSet { Config.set("continuo_resumen_incluir_pantalla", to: resumenPantalla) } }
    @Published var resumenMax: Double { didSet { Config.set("continuo_resumen_max_caracteres", to: Int(resumenMax)) } }
    @Published var resumenInstruccion: String { didSet { Config.set("continuo_resumen_instruccion", to: resumenInstruccion) } }
    @Published var resumenEstado: String = "—"
    @Published var loteEstado: String = "—"
    @Published var loteCorriendo = false

    @Published var resumen: String = "—"
    @Published var aviso: String?

    init() {
        activo = Config.continuoActivo()
        let raiz = Config.continuoCarpeta().path
        let casa = FileManager.default.homeDirectoryForCurrentUser.path
        carpeta = raiz.hasPrefix(casa) ? "~" + raiz.dropFirst(casa.count) : raiz
        audioModo = Config.continuoAudioModo()
        audioEco = Config.continuoAudioCancelacionEco()
        audioSegmento = Double(Config.continuoAudioSegmentoSegundos())
        audioAdoptar = Config.continuoAudioAdoptarDictado()
        audioUmbral = Config.continuoAudioUmbralVoz()
        pantallaActiva = Config.continuoPantallaActiva()
        pantallaIntervalo = Double(Config.continuoPantallaIntervaloSegundos())
        pantallaFormato = Config.continuoPantallaFormato()
        pantallaCalidad = Config.continuoPantallaCalidad()
        pantallaEscala = Config.continuoPantallaEscala()
        pantallaDedup = Config.continuoPantallaDeduplicar()
        pantallaUmbral = Config.continuoPantallaUmbralCambio()
        pantallaForzar = Double(Config.continuoPantallaForzarMinutos())
        pantallaPausar = Config.continuoPantallaPausarBloqueada()
        appsExcluidas = Config.continuoPantallaAppsExcluidas().joined(separator: ", ")
        soloCorriente = Config.continuoSoloConCorriente()
        retencionDias = Double(Config.continuoRetencionDias())
        retencionAuto = Config.continuoRetencionAutomatica()
        retencionAvisar = Config.continuoRetencionAvisarSinProcesar()
        let disp = Config.continuoLoteDisparadores()
        dispIntervalo = disp.contains("intervalo")
        dispHora = disp.contains("hora")
        dispArranque = disp.contains("arranque")
        dispApagado = disp.contains("apagado")
        loteIntervalo = Double(Config.continuoLoteIntervaloMinutos())
        loteMinutoDia = Double(Config.continuoLoteMinutoDelDia())
        loteMotor = Config.continuoLoteMotor()
        loteComprimir = Config.continuoLoteComprimir()
        loteCorriente = Config.continuoLoteSoloConCorriente()
        ocrActivo = Config.continuoOcrActivo()
        ocrPreciso = Config.continuoOcrPreciso()
        resumenActivo = Config.continuoResumenActivo()
        resumenPantalla = Config.continuoResumenIncluirPantalla()
        resumenMax = Double(Config.continuoResumenMaxCaracteres())
        resumenInstruccion = Config.continuoResumenInstruccion()
        refrescar()
        loteEstado = ContinuoPlanificador.descripcion()
    }

    private func guardarDisparadores() {
        var d: [String] = []
        if dispIntervalo { d.append("intervalo") }
        if dispHora { d.append("hora") }
        if dispArranque { d.append("arranque") }
        if dispApagado { d.append("apagado") }
        Config.set("continuo_lote_disparadores", to: d)
        ContinuoPlanificador.reconfigurar()
        loteEstado = ContinuoPlanificador.descripcion()
    }

    /// Lanza una tanda a mano. Salta la condición de energía: lo pidió alguien
    /// que está mirando la pantalla.
    func transcribirAhora() {
        guard !loteCorriendo else { return }
        loteCorriendo = true
        loteEstado = "Transcribiendo…"
        ContinuoLote.ejecutar(manual: true) { [weak self] resultado in
            self?.loteCorriendo = false
            self?.loteEstado = resultado
            self?.refrescar()
        }
    }

    /// Pide el resumen del día a la IA configurada.
    func resumirAhora() {
        resumenEstado = "Redactando…"
        ContinuoLote.resumirDia { [weak self] r in
            self?.resumenEstado = r
        }
    }

    private func listaDe(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func aplicar() {
        ContinuoBitacora.reconfigurar()
    }

    func refrescar() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            ContinuoIndice.shared.abrir()
            let r = ContinuoIndice.shared.resumen()
            let texto = "\(r.audio) fragmentos de audio · \(r.pantalla) capturas · "
                + ContinuoBitacora.tamanoLegible(r.bytes)
                + (r.pendientes > 0 ? " · \(r.pendientes) sin procesar" : " · todo procesado")
            DispatchQueue.main.async { self?.resumen = texto }
        }
    }

    /// Consulta la purga y avisa si se llevaría material sin procesar.
    func revisarPurga() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let balance = ContinuoBitacora.revisarPurga() else {
                DispatchQueue.main.async { self?.aviso = "Retención en «para siempre»: no hay nada que purgar." }
                return
            }
            let t = ContinuoBitacora.tamanoLegible(balance.bytes)
            let msg: String
            if balance.filas == 0 {
                msg = "Nada que purgar todavía."
            } else if balance.hayMaterialSinProcesar {
                msg = "⚠️ Se borrarían \(balance.filas) elementos (\(t)), y \(balance.sinProcesar) de ellos NO tienen transcripción ni texto reconocido. Esa información se perdería."
            } else {
                msg = "Se borrarían \(balance.filas) elementos (\(t)). Todos están ya procesados."
            }
            DispatchQueue.main.async { self?.aviso = msg }
        }
    }

    func purgar(forzar: Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let r = ContinuoBitacora.purgar(forzar: forzar)
            let msg = r.bloqueada
                ? "Purga detenida: hay material sin procesar. Usa «Purgar de todos modos» si aceptas perderlo."
                : "Purgados \(r.borradas) elementos."
            DispatchQueue.main.async { self?.aviso = msg; self?.refrescar() }
        }
    }
}

struct ContinuoView: View {
    @StateObject private var m = ContinuoModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Bitácora continua")
                .font(.title2).bold().foregroundStyle(acentoBitacora)
            Text("Graba audio y toma capturas en segundo plano para poder reconstruir el día. Todo se queda en este equipo.")
                .font(.callout).foregroundStyle(.secondary)

            Toggle("Activar la bitácora", isOn: $m.activo)
                .help("Apagada de fábrica. Nada se graba hasta que la enciendas.")

            Text(m.resumen).font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Abrir carpeta") { ContinuoBitacora.abrirCarpeta() }
                Button("Actualizar") { m.refrescar() }
                Text(m.carpeta).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Divider()

            SeccionPlegable("Audio", icono: "waveform", abierto: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Qué se graba", selection: $m.audioModo) {
                        Text("Siempre").tag("siempre")
                        Text("Solo cuando hay voz").tag("voz")
                        Text("Solo al dictar").tag("manual")
                    }.pickerStyle(.radioGroup)

                    Toggle("Cancelación de eco de macOS", isOn: $m.audioEco)
                        .help("Sin esto el micrófono integrado entrega una señal tan baja que se descarta como silencio. Déjalo activado salvo que sepas lo que haces.")

                    HStack {
                        Text("Cerrar un trozo cada")
                        Slider(value: $m.audioSegmento, in: 30...900, step: 30).frame(width: 200)
                        Text("\(Int(m.audioSegmento)) s").monospacedDigit()
                    }

                    if m.audioModo == "voz" {
                        HStack {
                            Text("Sensibilidad")
                            Slider(value: $m.audioUmbral, in: 0.001...0.05).frame(width: 180)
                            Text(String(format: "%.4f", m.audioUmbral)).monospacedDigit().font(.caption)
                        }
                        Text("Más bajo capta voces lejanas; más alto evita que se transcriba ruido como si fuera habla.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle("Incorporar también el audio de los dictados", isOn: $m.audioAdoptar)
                        .help("Mientras dictas, la bitácora cede el micrófono. Con esto, el audio que graba el dictado se suma a la línea de tiempo y no queda hueco.")

                    Label("Al dictar con la tecla de siempre, la bitácora suelta el micrófono y vuelve sola al terminar. El dictado manda: eso no se puede desactivar.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SeccionPlegable("Pantalla", icono: "camera.viewfinder", abierto: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Tomar capturas", isOn: $m.pantallaActiva)

                    HStack {
                        Text("Cada")
                        Slider(value: $m.pantallaIntervalo, in: 5...3600, step: 5).frame(width: 200)
                        Text(intervaloLegible(Int(m.pantallaIntervalo))).monospacedDigit()
                    }

                    Picker("Formato", selection: $m.pantallaFormato) {
                        Text("JPEG").tag("jpeg")
                        Text("HEIC").tag("heic")
                        Text("PNG (sin pérdida)").tag("png")
                    }.pickerStyle(.segmented).frame(width: 320)

                    HStack {
                        Text("Calidad")
                        Slider(value: $m.pantallaCalidad, in: 0.1...1.0).frame(width: 160)
                        Text(String(format: "%.0f %%", m.pantallaCalidad * 100)).monospacedDigit()
                    }
                    HStack {
                        Text("Escala")
                        Slider(value: $m.pantallaEscala, in: 0.25...1.0).frame(width: 160)
                        Text(String(format: "%.0f %%", m.pantallaEscala * 100)).monospacedDigit()
                    }

                    Toggle("No guardar si la pantalla no cambió", isOn: $m.pantallaDedup)
                    if m.pantallaDedup {
                        HStack {
                            Text("Cuánto debe cambiar")
                            Slider(value: $m.pantallaUmbral, in: 0.0...0.2).frame(width: 160)
                            Text(String(format: "%.1f %%", m.pantallaUmbral * 100)).monospacedDigit()
                        }
                    }
                    HStack {
                        Text("Forzar una captura cada")
                        Slider(value: $m.pantallaForzar, in: 0...120, step: 5).frame(width: 160)
                        Text(m.pantallaForzar == 0 ? "nunca" : "\(Int(m.pantallaForzar)) min").monospacedDigit()
                    }

                    Toggle("Pausar con la pantalla bloqueada o dormida", isOn: $m.pantallaPausar)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apps excluidas (identificadores separados por comas)").font(.caption)
                        TextField("com.ejemplo.banca, com.ejemplo.claves", text: $m.appsExcluidas)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            SeccionPlegable("Procesamiento diferido", icono: "text.badge.checkmark", abierto: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Transcribir mientras grabas mantendría un modelo de voz ocupando el procesador todo el día. Se hace en una sola pasada, cuando tú digas.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Cuándo").font(.caption).foregroundStyle(.secondary)
                    Toggle("Cada cierto tiempo", isOn: $m.dispIntervalo)
                    if m.dispIntervalo {
                        HStack {
                            Slider(value: $m.loteIntervalo, in: 15...1440, step: 15).frame(width: 200)
                            Text(m.loteIntervalo < 60
                                 ? "\(Int(m.loteIntervalo)) min"
                                 : String(format: "%.1f h", m.loteIntervalo / 60)).monospacedDigit()
                        }
                    }
                    Toggle("A una hora fija", isOn: $m.dispHora)
                    if m.dispHora {
                        HStack {
                            Slider(value: $m.loteMinutoDia, in: 0...1439, step: 15).frame(width: 200)
                            Text(String(format: "%02d:%02d", Int(m.loteMinutoDia) / 60, Int(m.loteMinutoDia) % 60))
                                .monospacedDigit()
                        }
                    }
                    Toggle("Al abrir la aplicación", isOn: $m.dispArranque)
                    Toggle("Al apagar el equipo", isOn: $m.dispApagado)
                        .help("macOS da un margen corto al apagar. Se transcribe lo que alcance; el resto queda pendiente para la próxima.")

                    Divider()

                    Picker("Motor", selection: $m.loteMotor) {
                        Text("Apple, en el dispositivo").tag("apple_speech")
                        Text("Whisper local").tag("whisper_local")
                    }.pickerStyle(.radioGroup)
                    Text("Apple transcribe sin que el audio salga del equipo. Recomendado para grabaciones de jornada completa.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Comprimir el audio al transcribirlo", isOn: $m.loteComprimir)
                        .help("El crudo se guarda sin comprimir para sobrevivir a un corte. Ya transcrito, se comprime y se libera espacio.")
                    Toggle("Solo con el equipo enchufado", isOn: $m.loteCorriente)

                    HStack {
                        Button(m.loteCorriendo ? "Transcribiendo…" : "Transcribir ahora") { m.transcribirAhora() }
                            .disabled(m.loteCorriendo)
                        Text(m.loteEstado).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SeccionPlegable("Texto de las capturas", icono: "text.viewfinder") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Leer el texto de las capturas", isOn: $m.ocrActivo)
                        .help("Reconocimiento en el dispositivo, con Vision. No sale nada del equipo y no consume cuota.")
                    Toggle("Modo preciso", isOn: $m.ocrPreciso)
                        .help("Preciso reconoce mejor y tarda más. Rápido basta para buscar por palabras sueltas.")
                    Text("Se ejecuta en la misma pasada que la transcripción.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SeccionPlegable("Resumen del día con IA", icono: "sparkles") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Esto es lo ÚNICO del módulo que puede salir del equipo: si el cerebro elegido es de nube, se le manda el texto del día. Apagado de fábrica a propósito.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Redactar un resumen del día", isOn: $m.resumenActivo)
                    Toggle("Incluir también el texto de las capturas", isOn: $m.resumenPantalla)

                    HStack {
                        Text("Enviar como máximo")
                        Slider(value: $m.resumenMax, in: 2000...60000, step: 2000).frame(width: 180)
                        Text("\(Int(m.resumenMax)) caracteres").monospacedDigit().font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instrucción para la IA (vacío = la de fábrica)").font(.caption)
                        TextEditor(text: $m.resumenInstruccion)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 70)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
                    }

                    HStack {
                        Button("Resumir hoy") { m.resumirAhora() }
                        Text(m.resumenEstado).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("El resumen se guarda como resumen-AAAA-MM-DD.md dentro de la carpeta del día.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SeccionPlegable("Energía", icono: "bolt") {
                Toggle("Trabajar solo con el equipo enchufado", isOn: $m.soloCorriente)
                    .help("Con batería, transcribir y capturar consume bastante. Con esto la bitácora espera a la corriente.")
            }

            SeccionPlegable("Retención y borrado", icono: "clock.arrow.circlepath") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Conservar")
                        Slider(value: $m.retencionDias, in: 0...365, step: 30).frame(width: 200)
                        Text(m.retencionDias == 0 ? "para siempre" : "\(Int(m.retencionDias)) días").monospacedDigit()
                    }
                    Toggle("Purgar automáticamente al cumplirse el plazo", isOn: $m.retencionAuto)
                    Toggle("Avisar si va a borrar material sin transcribir ni reconocer", isOn: $m.retencionAvisar)
                        .help("Recomendado. Borrar audio sin transcribir es perder información que nunca se llegó a extraer.")

                    HStack {
                        Button("Ver qué se borraría") { m.revisarPurga() }
                        Button("Purgar") { m.purgar(forzar: false) }
                        Button("Purgar de todos modos") { m.purgar(forzar: true) }
                            .help("Borra también lo que todavía no se ha procesado. No hay vuelta atrás.")
                    }
                    if let aviso = m.aviso {
                        Text(aviso).font(.caption)
                            .foregroundStyle(aviso.hasPrefix("⚠️") ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Label("Grabar conversaciones de terceros puede requerir su consentimiento. Revisa qué te obliga la normativa de tu país antes de usarla en reuniones.",
                  systemImage: "exclamationmark.shield")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { m.refrescar() }
    }

    private func intervaloLegible(_ s: Int) -> String {
        s < 60 ? "\(s) s" : (s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s")
    }
}

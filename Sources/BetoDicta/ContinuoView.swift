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
        refrescar()
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

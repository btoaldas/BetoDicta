import AppKit
import SwiftUI
import WebKit

struct ResultadoReproductorYouTube {
    let encontro: Bool
    let reproduciendo: Bool
    let mensaje: String
}

@MainActor
final class ReproductorYouTubeModel: ObservableObject {
    @Published var consulta = ""
    @Published var resultados: [VideoYouTubeInterno] = []
    @Published var indiceActual: Int?
    @Published var videoID = ""
    @Published var tituloActual = ""
    @Published var estado = "Busca una canción, artista o álbum."
    @Published var cargando = false
    @Published var reproduciendo = false
    @Published var listo = false
    @Published var secuenciaCarga = 0
    @Published var reproducirAlCargar = false

    var ejecutarJavaScript: ((String) -> Void)?
    private var pendienteID: UUID?
    private var pendiente: ((ResultadoReproductorYouTube) -> Void)?
    private var detencionSolicitada = false

    func ejecutar(_ texto: String, reproducir: Bool,
                  completion: @escaping (ResultadoReproductorYouTube) -> Void) {
        consulta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if consulta.isEmpty, reproducir {
            consulta = Config.musicaInternaConsultaPredeterminada()
        }
        buscar(reproducir: reproducir && Config.musicaInternaAutoReproducir(),
               completion: completion)
    }

    func buscar(reproducir: Bool = false,
                completion: ((ResultadoReproductorYouTube) -> Void)? = nil) {
        let q = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            estado = "Escribe una canción, artista, álbum o enlace de YouTube."
            completion?(.init(encontro: false, reproduciendo: false, mensaje: estado)); return
        }
        cancelarPendiente(mensaje: "La búsqueda anterior fue reemplazada.")
        cargando = true; estado = "Buscando «\(q)» en YouTube…"
        YouTubeDataAPI.buscar(q) { [weak self] resultado in
            guard let self else { return }
            self.cargando = false
            switch resultado {
            case .failure(let error):
                self.resultados = []
                self.estado = error.localizedDescription
                completion?(.init(encontro: false, reproduciendo: false, mensaje: self.estado))
            case .success(let videos):
                self.resultados = videos
                guard !videos.isEmpty else {
                    self.estado = "YouTube no encontró resultados musicales para «\(q)»."
                    completion?(.init(encontro: false, reproduciendo: false, mensaje: self.estado)); return
                }
                if reproducir {
                    self.iniciarPendiente(completion)
                    self.seleccionar(0, reproducir: true)
                } else {
                    // Una búsqueda no interrumpe lo que ya suena. En una ventana
                    // nueva sí prepara el primero, sin pulsar Play.
                    if self.videoID.isEmpty { self.seleccionar(0, reproducir: false) }
                    self.estado = "Encontré \(videos.count) resultado(s) para «\(q)»."
                    completion?(.init(encontro: true, reproduciendo: false,
                                      mensaje: "Abrí \(videos.count) resultados de «\(q)» en el reproductor interno de BetoDicta."))
                }
            }
        }
    }

    func seleccionar(_ indice: Int, reproducir: Bool = true) {
        guard resultados.indices.contains(indice) else { return }
        indiceActual = indice; detencionSolicitada = false
        let video = resultados[indice]
        videoID = video.id; tituloActual = video.titulo
        reproduciendo = false; reproducirAlCargar = reproducir
        estado = reproducir ? "Cargando «\(video.titulo)»…" : "Preparé «\(video.titulo)»."
        secuenciaCarga += 1
    }

    func alternar() { ejecutarJavaScript?("bdCommand('toggle')") }
    func detener() {
        detencionSolicitada = true
        ejecutarJavaScript?("bdCommand('stop')")
        reproduciendo = false; estado = "Reproducción detenida."
    }
    func anterior() {
        guard !resultados.isEmpty else { return }
        let actual = indiceActual ?? 0
        seleccionar(actual > 0 ? actual - 1 : resultados.count - 1)
    }
    func siguiente() {
        guard !resultados.isEmpty else { return }
        let actual = indiceActual ?? -1
        seleccionar((actual + 1) % resultados.count)
    }

    func mensajeWeb(_ cuerpo: Any) {
        guard let d = cuerpo as? [String: Any], let tipo = d["type"] as? String else { return }
        let id = d["id"] as? String ?? ""
        if ProcessInfo.processInfo.environment["BETODICTA_YTPLAYERTEST"] != nil {
            print("YTPLAYERWEB tipo=\(tipo) valor=\(d["value"] ?? "-") id=\(id)")
            fflush(stdout)
        }
        switch tipo {
        case "ready":
            listo = true
            if videoID.isEmpty {
                estado = "Reproductor listo."
            } else if videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#,
                                    options: .regularExpression) != nil {
                // `updateNSView` puede ocurrir antes de que el documento haya
                // definido bdLoad. Ready es la barrera fiable: repetimos aquí
                // la carga vigente y no dependemos de una carrera WebKit/SwiftUI.
                ejecutarJavaScript?("bdLoad('\(videoID)', \(reproducirAlCargar ? "true" : "false"))")
            }
        case "state":
            guard let valor = (d["value"] as? NSNumber)?.intValue else { return }
            if let titulo = d["title"] as? String, !titulo.isEmpty { tituloActual = titulo }
            if valor == 1 {
                reproduciendo = true; estado = "Reproduciendo «\(tituloActual)»."
                if id.isEmpty || id == videoID {
                    resolverPendiente(.init(encontro: true, reproduciendo: true,
                        mensaje: "Listo, estoy reproduciendo «\(tituloActual)» en BetoDicta."))
                }
            } else if valor == 2 {
                reproduciendo = false; estado = "En pausa: «\(tituloActual)»."
            } else if valor == 0 {
                reproduciendo = false; estado = "Terminó «\(tituloActual)»."
                if detencionSolicitada {
                    detencionSolicitada = false; estado = "Reproducción detenida."
                } else if Config.musicaInternaAvanzarSolo() { siguiente() }
            }
        case "error":
            reproduciendo = false
            let codigo = (d["value"] as? NSNumber)?.intValue ?? 0
            estado = "YouTube no permitió reproducir este resultado (error \(codigo)). Elige otro."
            resolverPendiente(.init(encontro: true, reproduciendo: false, mensaje: estado))
        case "autoplayBlocked":
            reproduciendo = false
            estado = "macOS bloqueó el inicio automático. Pulsa Play una vez en el reproductor."
            resolverPendiente(.init(encontro: true, reproduciendo: false, mensaje: estado))
        default: break
        }
    }

    private func iniciarPendiente(_ completion: ((ResultadoReproductorYouTube) -> Void)?) {
        guard let completion else { return }
        let id = UUID(); pendienteID = id; pendiente = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.pendienteID == id else { return }
            self.estado = "YouTube mostró el resultado, pero no confirmó reproducción a tiempo."
            self.resolverPendiente(.init(encontro: true, reproduciendo: false, mensaje: self.estado))
        }
    }

    private func resolverPendiente(_ resultado: ResultadoReproductorYouTube) {
        guard let p = pendiente else { return }
        pendiente = nil; pendienteID = nil; p(resultado)
    }

    private func cancelarPendiente(mensaje: String) {
        guard pendiente != nil else { return }
        resolverPendiente(.init(encontro: false, reproduciendo: false, mensaje: mensaje))
    }
}

private struct ReproductorWebYouTube: NSViewRepresentable {
    @ObservedObject var model: ReproductorYouTubeModel

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        weak var model: ReproductorYouTubeModel?
        var ultimaCarga = -1

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "beto" else { return }
            DispatchQueue.main.async { [weak self] in self?.model?.mensajeWeb(message.body) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "beto")
        let web = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = web; context.coordinator.model = model
        model.ejecutarJavaScript = { [weak web] js in
            DispatchQueue.main.async { web?.evaluateJavaScript(js, completionHandler: nil) }
        }
        web.loadHTMLString(Self.html, baseURL: URL(string: "https://betodicta.app/"))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.model = model
        guard context.coordinator.ultimaCarga != model.secuenciaCarga, !model.videoID.isEmpty else { return }
        context.coordinator.ultimaCarga = model.secuenciaCarga
        let id = Self.literalJS(model.videoID)
        web.evaluateJavaScript("bdLoad(\(id), \(model.reproducirAlCargar ? "true" : "false"))",
                               completionHandler: nil)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "beto")
        if coordinator.model?.ejecutarJavaScript != nil { coordinator.model?.ejecutarJavaScript = nil }
    }

    private static func literalJS(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8), json.count >= 2 else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    private static let html = """
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>html,body,#player{width:100%;height:100%;margin:0;background:#0d0b12;overflow:hidden}</style>
    </head><body><div id="player"></div><script>
    var player=null, pending=null;
    function info(type,value){
      var d={type:type,value:value||0,id:'',title:''};
      try{var v=player&&player.getVideoData?player.getVideoData():{};d.id=v.video_id||'';d.title=v.title||'';}catch(e){}
      window.webkit.messageHandlers.beto.postMessage(d);
    }
    function onYouTubeIframeAPIReady(){
      player=new YT.Player('player',{width:'100%',height:'100%',playerVars:{playsinline:1,rel:0,origin:'https://betodicta.app'},events:{
        onReady:function(){pending=null;info('ready',1);},
        onStateChange:function(e){info('state',e.data);},
        onError:function(e){info('error',e.data);},
        onAutoplayBlocked:function(){info('autoplayBlocked',1);}
      }});
    }
    function bdLoad(id,play){
      if(!player||!player.loadVideoById){pending={id:id,play:play};return;}
      if(play){player.loadVideoById(id);}else{player.cueVideoById(id);}
    }
    function bdCommand(cmd){
      if(!player)return;
      if(cmd==='toggle'){if(player.getPlayerState()===1)player.pauseVideo();else player.playVideo();}
      else if(cmd==='play')player.playVideo();else if(cmd==='pause')player.pauseVideo();
      else if(cmd==='stop')player.stopVideo();
    }
    var tag=document.createElement('script');tag.src='https://www.youtube.com/iframe_api';
    document.head.appendChild(tag);
    </script></body></html>
    """
}

private struct ReproductorYouTubeView: View {
    @ObservedObject var model: ReproductorYouTubeModel
    private let violeta = Color(red: 0.36, green: 0.28, blue: 0.62)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.house.fill").foregroundStyle(violeta)
                TextField("Canción, artista, álbum o enlace de YouTube", text: $model.consulta)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.buscar() }
                Button("Buscar") { model.buscar() }
                    .keyboardShortcut(.return, modifiers: [])
                    .help("Buscar música sin iniciar la reproducción")
                Button {
                    model.buscar(reproducir: true)
                } label: { Label("Buscar y reproducir", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(violeta)
                    .help("Buscar y reproducir el primer resultado")
            }

            ReproductorWebYouTube(model: model)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 18) {
                Button(action: model.anterior) { Image(systemName: "backward.end.fill") }
                    .help("Resultado anterior")
                Button(action: model.alternar) {
                    Image(systemName: model.reproduciendo ? "pause.fill" : "play.fill")
                        .font(.title2)
                }.help(model.reproduciendo ? "Pausar" : "Reproducir")
                Button(action: model.detener) { Image(systemName: "stop.fill") }
                    .help("Detener la reproducción")
                Button(action: model.siguiente) { Image(systemName: "forward.end.fill") }
                    .help("Resultado siguiente")
                Spacer()
                if !model.videoID.isEmpty {
                    Button {
                        if let u = URL(string: "https://music.youtube.com/watch?v=\(model.videoID)") {
                            NSWorkspace.shared.open(u)
                        }
                    } label: { Label("Abrir en YouTube Music", systemImage: "arrow.up.right.square") }
                        .controlSize(.small).help("Abrir esta pista en el navegador")
                }
            }.buttonStyle(.bordered)

            HStack(spacing: 7) {
                if model.cargando { ProgressView().controlSize(.small) }
                Circle().fill(model.reproduciendo ? Color.green : (model.listo ? Color.secondary : Color.orange))
                    .frame(width: 7, height: 7)
                Text(model.estado).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Configurar cuenta o clave…") {
                    SettingsWindowController.shared.show(irA: "Asistente")
                }.controlSize(.small).help("Abrir la configuración del reproductor interno")
            }

            if !model.resultados.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(model.resultados.enumerated()), id: \.element.id) { indice, video in
                            Button { model.seleccionar(indice) } label: {
                                HStack(spacing: 9) {
                                    AsyncImage(url: video.miniatura) { fase in
                                        if let imagen = fase.image { imagen.resizable().scaledToFill() }
                                        else { Color.gray.opacity(0.18).overlay(Image(systemName: "music.note")) }
                                    }.frame(width: 84, height: 47).clipped().cornerRadius(5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(video.titulo).font(.subheadline).lineLimit(2)
                                        Text(video.canal).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if model.indiceActual == indice {
                                        Image(systemName: model.reproduciendo ? "speaker.wave.2.fill" : "play.circle")
                                            .foregroundStyle(violeta)
                                    }
                                }.padding(6).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .background(model.indiceActual == indice ? violeta.opacity(0.10) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .help("Reproducir \(video.titulo), de \(video.canal)")
                        }
                    }
                }.frame(maxHeight: 205)
            }
        }
        .padding(16)
        .frame(minWidth: 660, idealWidth: 720, minHeight: 600, idealHeight: 690)
    }
}

@MainActor
final class ReproductorYouTubeInterno {
    static let shared = ReproductorYouTubeInterno()
    let model = ReproductorYouTubeModel()
    private var window: NSWindow?

    func mostrar() {
        crearSiHaceFalta()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func ejecutar(_ consulta: String, reproducir: Bool,
                  completion: @escaping (ResultadoReproductorYouTube) -> Void) {
        mostrar()
        model.ejecutar(consulta, reproducir: reproducir, completion: completion)
    }

    private func crearSiHaceFalta() {
        guard window == nil else { return }
        let hosting = NSHostingController(rootView: ReproductorYouTubeView(model: model))
        let w = NSWindow(contentViewController: hosting)
        w.title = "Música · BetoDicta"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(.init(width: 720, height: 690))
        w.minSize = .init(width: 660, height: 600)
        w.isReleasedWhenClosed = false
        w.center(); window = w
    }
}

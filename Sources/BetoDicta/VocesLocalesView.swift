import SwiftUI

// MARK: - Editor de la biblioteca de voces locales (Fase 7)
//
// El usuario agrega/detecta/elige sus voces clonadas (XTTS local). Nada viene de
// fábrica: cada quien sube las suyas. Se elige UNA como activa para el Modo Agente.

struct VocesLocalesEditor: View {
    @State private var voces: [VozLocal] = VocesLocales.todas()
    @State private var activa: String = Config.ttsVozLocal()
    @State private var mostrarAgregar = false
    @State private var nuevoNombre = ""
    @State private var nuevoCmd = ""
    @State private var nuevaPersona = ""
    @State private var detectadas: [(nombre: String, cmd: String)] = []
    @State private var estado = ""

    private func refrescar() { voces = VocesLocales.todas(); activa = VocesLocales.activa()?.id ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tus voces clonadas (100% local, XTTS). Elige con cuál habla el Modo Agente. Ninguna viene incluida — agregas las tuyas.")
                .font(.caption).foregroundStyle(.secondary)

            if voces.isEmpty {
                Text("Todavía no agregaste ninguna voz.").font(.caption).italic().foregroundStyle(.secondary)
            } else {
                ForEach(voces) { v in
                    HStack(spacing: 8) {
                        Button {
                            VocesLocales.fijarActiva(v.id); activa = v.id
                        } label: {
                            Image(systemName: activa == v.id ? "largecircle.fill.circle" : "circle")
                        }.buttonStyle(.plain)
                        Text(v.nombre).font(.callout)
                        if !v.persona.isEmpty { Text("· persona ✓").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        Button("🔊") {
                            estado = "Generando “\(v.nombre)”…"
                            Voz.probarVozLocal(v) { estado = "" }
                        }.controlSize(.small).help("Probar esta voz (genera en local, tarda)")
                        Button("Quitar") { VocesLocales.borrar(v.id); refrescar() }.controlSize(.small)
                    }
                }
            }

            HStack {
                Button("➕ Agregar voz") { mostrarAgregar.toggle() }.controlSize(.small)
                Button("🔍 Detectar mis voces (VozClonPOC)") {
                    detectadas = VocesLocales.detectarDeVozClon()
                    estado = detectadas.isEmpty ? "No encontré proyectos entrenados en \(Config.vozClonBase())." : ""
                }.controlSize(.small)
            }

            if !detectadas.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Encontradas — pulsa para agregar:").font(.caption).bold()
                    ForEach(Array(detectadas.enumerated()), id: \.offset) { _, d in
                        HStack {
                            Text(d.nombre).font(.caption)
                            Spacer()
                            Button("Agregar") {
                                VocesLocales.agregar(nombre: d.nombre, cmd: d.cmd)
                                detectadas.removeAll { $0.nombre == d.nombre }; refrescar()
                            }.controlSize(.small)
                        }
                    }
                }.padding(6).background(Color.secondary.opacity(0.08)).cornerRadius(6)
            }

            if mostrarAgregar {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Nombre (ej. Mamá Rafaela)", text: $nuevoNombre)
                        .textFieldStyle(.roundedBorder).frame(width: 300)
                    TextField("Comando con {texto} y {salida}", text: $nuevoCmd)
                        .textFieldStyle(.roundedBorder).frame(width: 460)
                    Text("Persona (opcional): cómo habla esa persona. El Agente redacta en ese estilo antes de que la voz lo lea.").font(.caption2).foregroundStyle(.secondary)
                    TextField("ej. Habla como mamá: cariñosa, diminutivos (mijo), termina con 'chao chao'…", text: $nuevaPersona, axis: .vertical)
                        .textFieldStyle(.roundedBorder).frame(width: 460).lineLimit(2...5)
                    HStack {
                        Button("Guardar") {
                            let n = nuevoNombre.trimmingCharacters(in: .whitespaces)
                            let c = nuevoCmd.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty, c.contains("{texto}") else { estado = "Falta nombre o {texto} en el comando."; return }
                            VocesLocales.agregar(nombre: n, cmd: c, persona: nuevaPersona.trimmingCharacters(in: .whitespaces))
                            nuevoNombre = ""; nuevoCmd = ""; nuevaPersona = ""; mostrarAgregar = false; estado = ""; refrescar()
                        }.controlSize(.small)
                        Button("Cancelar") { mostrarAgregar = false }.controlSize(.small)
                    }
                }.padding(6).background(Color.secondary.opacity(0.08)).cornerRadius(6)
            }

            if !estado.isEmpty { Text(estado).font(.caption).foregroundStyle(.secondary) }
            Text("Cada voz es un comando de tu VozClonPOC. \"Detectar\" arma el comando solo escaneando tus proyectos entrenados. Es batch (genera y luego suena); en CPU tarda unos segundos.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { refrescar() }
    }
}

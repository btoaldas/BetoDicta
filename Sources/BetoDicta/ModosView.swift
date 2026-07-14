import AppKit
import SwiftUI

// MARK: - Pestaña Modos: qué hacer con lo dictado + su IA/prompt por modo

private let acentoMo = Color(red: 0.36, green: 0.28, blue: 0.62)

final class ModosModel: ObservableObject {
    @Published var modos: [Modo] = ModosStore.todos()
    @Published var activo: String = Config.modoActivo()

    func guardar() { ModosStore.guardar(modos) }
    func activar(_ id: String) {
        ModosStore.fijarActivo(id); activo = id
        // Refleja el cambio en el notch al instante.
        (NSApp.delegate as? AppDelegate)?.refrescarModoNotch()
    }
    func binding(_ id: String) -> Binding<Modo>? {
        guard let i = modos.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { self.modos[i] }, set: { self.modos[i] = $0; self.guardar() })
    }
    func crear() -> String {
        let m = ModosStore.crear(nombre: "Mi modo")
        modos = ModosStore.todos()
        return m.id
    }
    func borrar(_ id: String) {
        ModosStore.borrar(id)
        modos = ModosStore.todos(); activo = Config.modoActivo()
        (NSApp.delegate as? AppDelegate)?.refrescarModoNotch()
    }
}

struct ModosView: View {
    @StateObject private var m = ModosModel()
    @State private var expandido: String?

    /// IAs de pulido conectadas (para el selector por modo).
    private var iasPulido: [ChatIA] { ChatIA.conectadasPulido }

    @State private var porVoz = Config.modoPorVoz()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Modos — qué hacer con lo dictado", systemImage: "wand.and.stars")
                    .font(.headline).foregroundStyle(acentoMo)
                Spacer()
                Button { expandido = m.crear() } label: { Image(systemName: "plus") }
                    .help("Crear un modo propio")
            }
            Text("El MODO decide cómo se procesa tu dictado: solo pulir (Dictado), o formatearlo como correo, oficio, tarea, nota, traducirlo o responder. Elígelo al vuelo desde el notch (arriba-izquierda) o el menú de la barra. Cada modo usa su propia IA y su propio prompt.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Activar un modo POR VOZ", isOn: $porVoz)
                .toggleStyle(.switch).controlSize(.mini)
                .onChange(of: porVoz) { _, v in Config.set("modo_por_voz", to: v) }
            Text("Si lo enciendes y empiezas el dictado con la frase de un modo (ej. \"modo tarea comprar la comida\"), ese modo se aplica solo a ese dictado y la frase se quita. Edita o vacía cada frase abajo.")
                .font(.caption2).foregroundStyle(.secondary)

            ForEach(m.modos) { modo in
                tarjetaModo(modo)
            }
        }
    }

    @ViewBuilder private func tarjetaModo(_ modo: Modo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: modo.icono).foregroundStyle(acentoMo).frame(width: 20)
                Text(modo.nombre).font(.subheadline).bold()
                if modo.id == "dictado" {
                    Text("por defecto").font(.system(size: 9)).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.gray.opacity(0.3)).clipShape(Capsule())
                }
                Spacer()
                if m.activo == modo.id {
                    Label("Activo", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                } else {
                    Button("Activar") { m.activar(modo.id) }.controlSize(.small)
                }
                Button {
                    expandido = expandido == modo.id ? nil : modo.id
                } label: {
                    Image(systemName: expandido == modo.id ? "chevron.up" : "chevron.down")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if expandido == modo.id, let b = m.binding(modo.id) {
                editor(b)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func editor(_ b: Binding<Modo>) -> some View {
        Divider()
        // Modo PROPIO: nombre + comportamiento base editables.
        if !b.wrappedValue.esFijo {
            HStack {
                Text("Nombre:").font(.caption).frame(width: 90, alignment: .leading)
                TextField("Mi modo", text: b.nombre).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            HStack {
                Text("Comportamiento:").font(.caption).frame(width: 110, alignment: .leading)
                Picker("", selection: b.base) {
                    Text("Pulir / reescribir").tag("pulir")
                    Text("Traducir").tag("traducir")
                    Text("Responder (asistente)").tag("responder")
                }.labelsHidden().frame(width: 200)
            }
        }
        // Palabra de voz (para activar por voz)
        HStack {
            Text("Frase de voz:").font(.caption).frame(width: 90, alignment: .leading)
            TextField("ej. modo tarea (vacío = sin voz)", text: b.palabraVoz).textFieldStyle(.roundedBorder).frame(width: 240)
        }
        // Traducir: idioma destino
        if b.wrappedValue.base == "traducir" {
            HStack {
                Text("Traducir a:").font(.caption).frame(width: 90, alignment: .leading)
                TextField("inglés", text: b.idiomaDestino).textFieldStyle(.roundedBorder).frame(width: 160)
            }
        }
        // Prompt (salvo Dictado, que usa la limpieza estándar)
        if b.wrappedValue.id != "dictado" {
            Text("Instrucción para la IA (prompt):").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: b.prompt)
                .font(.callout).frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3)))
        } else {
            Text("El modo Dictado usa la limpieza estándar (puntuación, muletillas, glosario). Su 'estilo' se ajusta en Ajustes → Pulido.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // IA propia del modo (o global de pulido)
        HStack {
            Text("IA de este modo:").font(.caption).frame(width: 110, alignment: .leading)
            Picker("", selection: b.proveedorId) {
                Text("Global (la de Pulido)").tag("")
                ForEach(iasPulido, id: \.id) { ia in
                    Text(ia.proveedorCorto).tag(ia.id)
                }
            }.labelsHidden().frame(width: 220)
        }
        // Modelo (opcional): solo si eligió una IA específica
        if !b.wrappedValue.proveedorId.isEmpty {
            HStack {
                Text("Modelo:").font(.caption).frame(width: 110, alignment: .leading)
                TextField("(default del proveedor)", text: b.modelo).textFieldStyle(.roundedBorder).frame(width: 220)
            }
        }
        Text("Consejo: deja la IA en 'Global' para usar la misma que pules; o elige una específica (ej. una potente para 'Asistente', una gratis para 'Tarea').")
            .font(.caption2).foregroundStyle(.secondary)
        // Borrar (solo modos propios; los base no se borran)
        if !b.wrappedValue.esFijo {
            Button(role: .destructive) {
                expandido = nil; m.borrar(b.wrappedValue.id)
            } label: { Label("Borrar este modo", systemImage: "trash") }
            .controlSize(.small)
        }
    }
}

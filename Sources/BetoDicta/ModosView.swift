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
}

struct ModosView: View {
    @StateObject private var m = ModosModel()
    @State private var expandido: String?

    /// IAs de pulido conectadas (para el selector por modo).
    private var iasPulido: [ChatIA] { ChatIA.conectadasPulido }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Modos — qué hacer con lo dictado", systemImage: "wand.and.stars")
                .font(.headline).foregroundStyle(acentoMo)
            Text("El MODO decide cómo se procesa tu dictado: solo pulir (Dictado), o formatearlo como correo, oficio, tarea, nota, traducirlo o responder. Elígelo al vuelo desde el notch (arriba-izquierda) o el menú de la barra. Cada modo puede usar su propia IA y su propio prompt.")
                .font(.caption).foregroundStyle(.secondary)

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
    }
}

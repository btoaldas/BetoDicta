import SwiftUI

// MARK: - Pestaña Tareas y notas (Fase 4 de Modos)

private let acentoNo = Color(red: 0.36, green: 0.28, blue: 0.62)

struct NotasView: View {
    @State private var items: [Pendiente] = NotasStore.todos()
    @State private var nuevo = ""
    @State private var tipoNuevo = "tarea"

    private func recargar() { items = NotasStore.todos() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Tareas y notas", systemImage: "checklist").font(.headline).foregroundStyle(acentoNo)
            Text("Se llenan solas cuando dictas con el modo Tarea o Nota (o por voz: \"modo tarea comprar la comida\"). También puedes agregar aquí a mano. 100% local en tu Mac.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Picker("", selection: $tipoNuevo) { Text("Tarea").tag("tarea"); Text("Nota").tag("nota") }
                    .labelsHidden().frame(width: 100)
                TextField("Agregar a mano…", text: $nuevo).textFieldStyle(.roundedBorder)
                Button("Agregar") {
                    let t = nuevo.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { NotasStore.agregar(tipo: tipoNuevo, texto: t); nuevo = ""; recargar() }
                }.disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            let tareas = items.filter { $0.tipo == "tarea" }
            let notas = items.filter { $0.tipo == "nota" }

            HStack {
                Text("Tareas (\(tareas.count))").font(.subheadline).bold()
                Spacer()
                if tareas.contains(where: { $0.hecho }) {
                    Button("Limpiar hechas") { NotasStore.limpiarHechas(); recargar() }.controlSize(.small)
                }
                Button { recargar() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Refrescar")
            }
            if tareas.isEmpty { Text("Sin tareas.").font(.caption).foregroundStyle(.tertiary) }
            ForEach(tareas) { t in
                HStack(spacing: 8) {
                    Button { NotasStore.alternar(t.id); recargar() } label: {
                        Image(systemName: t.hecho ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(t.hecho ? .green : .secondary)
                    }.buttonStyle(.plain)
                    Text(t.texto).font(.callout).strikethrough(t.hecho)
                        .foregroundStyle(t.hecho ? .secondary : .primary)
                    Spacer()
                    Button { NotasStore.borrar(t.id); recargar() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }

            Divider()
            Text("Notas (\(notas.count))").font(.subheadline).bold()
            if notas.isEmpty { Text("Sin notas.").font(.caption).foregroundStyle(.tertiary) }
            ForEach(notas) { n in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text").foregroundStyle(acentoNo)
                    Text(n.texto).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { NotasStore.borrar(n.id); recargar() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: recargar)
    }
}

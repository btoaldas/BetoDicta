import AppKit
import SwiftUI

// MARK: - Pestaña Modos: qué hacer con lo dictado + su IA/prompt por modo

private let acentoMo = Color(red: 0.36, green: 0.28, blue: 0.62)

final class ModosModel: ObservableObject {
    @Published var modos: [Modo] = ModosStore.todos()
    @Published var defecto: String = Config.modoDefecto()

    func guardar() { ModosStore.guardar(modos) }
    /// Fija el modo POR DEFECTO (sticky). El cambio al vuelo va por el notch/menú.
    func ponerDefecto(_ id: String) {
        ModosStore.fijarDefecto(id); defecto = id
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
        modos = ModosStore.todos(); defecto = Config.modoDefecto()
        (NSApp.delegate as? AppDelegate)?.refrescarModoNotch()
    }
}

struct ModosView: View {
    @StateObject private var m = ModosModel()
    @State private var expandido: String?

    /// IAs de pulido conectadas (para el selector por modo).
    private var iasPulido: [ChatIA] { ChatIA.conectadasPulido }

    @State private var porVoz = Config.modoPorVoz()
    @State private var porContexto = Config.modoPorContexto()
    @State private var revertir = Config.modoRevertir()
    @State private var nuevoIdioma = ""
    @State private var idiomasVer = 0   // fuerza refrescar el picker tras añadir uno
    @State private var usarMacWA = ContactosWA.usarMac()
    @State private var contactosVer = 0
    @State private var resultadoImport = ""

    private func importarContactos() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.commaSeparatedText, .json, .plainText, .text, .vCard]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url {
            let r = ContactosWA.importar(u)
            resultadoImport = "✅ \(r.validos) importados (\(r.detalle)) · \(r.invalidos) inválidos · \(r.total) en total"
            contactosVer += 1
        }
    }
    private func exportarContactos(_ formato: String) {
        let p = NSSavePanel(); p.nameFieldStringValue = "contactos_whatsapp.\(formato)"
        if p.runModal() == .OK, let u = p.url {
            let txt = formato == "json" ? ContactosWA.exportarJSON() : ContactosWA.exportarCSV()
            try? txt.write(to: u, atomically: true, encoding: .utf8)
        }
    }

    /// Lista de idiomas para el picker; garantiza que el valor actual sea seleccionable.
    /// Compara EXACTO (no case-insensitive): si el valor guardado difiere en
    /// mayúsculas/acentos de un base, se inserta tal cual para que el tag empareje
    /// y el Picker nunca quede en blanco.
    private func listaIdiomas(_ actual: String) -> [(nombre: String, bandera: String)] {
        var lista = Idiomas.todos()
        if !actual.isEmpty, !lista.contains(where: { $0.nombre == actual }) {
            lista.insert((actual, Idiomas.bandera(actual)), at: 0)
        }
        return lista
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Modos — qué hacer con lo dictado", systemImage: "wand.and.stars")
                    .font(.headline).foregroundStyle(acentoMo)
                Spacer()
                Button { AnalizadorWindow.show() } label: { Image(systemName: "wand.and.stars.inverse") }
                    .help("Mejorar modos: analiza el registro y sugiere mejoras (autónomo o con IA)")
                Button { ModosLog.abrir() } label: { Image(systemName: "doc.text.magnifyingglass") }
                    .help("Ver el registro detallado de modos (para analizar y mejorar)")
                Button { expandido = m.crear() } label: { Image(systemName: "plus") }
                    .help("Crear un modo propio")
            }
            Text("El MODO decide cómo se procesa tu dictado: solo pulir (Dictado), o formatearlo como correo, oficio, tarea, nota, traducirlo o responder. Cada modo usa su propia IA y su propio prompt. Marca uno como POR DEFECTO aquí; cámbialo al vuelo desde el notch (arriba-izquierda) o el menú de la barra.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("El modo elegido al vuelo es de UN SOLO USO (vuelve al de por defecto tras dictar)", isOn: $revertir)
                .toggleStyle(.switch).controlSize(.mini)
                .onChange(of: revertir) { _, v in Config.set("modo_revertir", to: v) }
            Text("Encendido: cambiar a Correo/Traducir/… desde el notch aplica solo a ese dictado y luego vuelve al modo por defecto. Apagado: el modo elegido se queda fijo hasta que lo cambies.")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle("Activar un modo POR VOZ", isOn: $porVoz)
                .toggleStyle(.switch).controlSize(.mini)
                .onChange(of: porVoz) { _, v in Config.set("modo_por_voz", to: v) }
            Text("Si lo enciendes y empiezas el dictado con la frase de un modo (ej. \"modo tarea comprar la comida\"), ese modo se aplica solo a ese dictado y la frase se quita. Edita o vacía cada frase abajo.")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle("Activar un modo POR APP / SITIO WEB", isOn: $porContexto)
                .toggleStyle(.switch).controlSize(.mini)
                .onChange(of: porContexto) { _, v in Config.set("modo_por_contexto", to: v) }
            Text("Aplica un modo solo por estar en cierta app o página. Ej.: en Outlook usa Correo; en Quipux (por URL) usa Oficio. Configura las apps y sitios de cada modo abajo. La voz manda sobre el contexto.")
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
                Spacer()
                if m.defecto == modo.id {
                    Label("Por defecto", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                } else {
                    Button("Poner por defecto") { m.ponerDefecto(modo.id) }.controlSize(.small)
                }
                Button {
                    expandido = expandido == modo.id ? nil : modo.id
                    nuevoIdioma = ""   // no arrastrar borrador entre tarjetas
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

    /// Puente [String] ⇄ texto "a, b, c" para editar listas en un TextField.
    private func listaTexto(_ b: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { b.wrappedValue.joined(separator: ", ") },
            set: { b.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        )
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
                    Text("Buscar (web / Spotlight)").tag("buscar")
                    Text("Acción (abrir app/correo/web)").tag("accion")
                }.labelsHidden().frame(width: 200)
            }
        }
        // Palabra de voz (para activar por voz)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Frases de voz:").font(.caption).frame(width: 90, alignment: .leading)
                TextField("ej. modo tarea, mudo tarea (vacío = sin voz)", text: b.palabraVoz)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
            }
            Text("Separa VARIAS con coma (failover ante mal-escuchas del STT). La más larga que calce gana.")
                .font(.caption2).foregroundStyle(.secondary).padding(.leading, 98)
        }
        // Frases de ejemplo para el reconocimiento INTELIGENTE (embeddings)
        if b.wrappedValue.id != "dictado" {
            HStack(alignment: .top) {
                Text("Ejemplos:").font(.caption).frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("ej. mándale un whatsapp, escribir por whatsapp", text: listaTexto(b.ejemplosVoz))
                        .textFieldStyle(.roundedBorder).frame(width: 300)
                    Text("Formas NATURALES de pedir este modo (para el reconocimiento inteligente por significado). Tus frases se embeben con TU motor. Sepáralas con coma.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        // Triggers por contexto (app / sitio). Dictado no dispara por contexto.
        if b.wrappedValue.id != "dictado" {
            HStack(alignment: .top) {
                Text("En apps:").font(.caption).frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("ej. Outlook, Mail, com.microsoft.Outlook", text: listaTexto(b.apps))
                        .textFieldStyle(.roundedBorder).frame(width: 300)
                    Text("Nombres o bundle IDs, separados por coma. Coincide por parte del nombre.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Text("En sitios:").font(.caption).frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("ej. quipux.gob.ec, mail.google.com", text: listaTexto(b.sitios))
                        .textFieldStyle(.roundedBorder).frame(width: 300)
                    Text("Dominios o trozos de URL (navegador). Requiere permiso de Automatización la 1ª vez.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        // Traducir: idioma destino como LISTA con banderita + agregar propios
        if b.wrappedValue.base == "traducir" {
            HStack(alignment: .top) {
                Text("Traducir a:").font(.caption).frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: b.idiomaDestino) {
                        ForEach(listaIdiomas(b.wrappedValue.idiomaDestino), id: \.nombre) { item in
                            Text("\(item.bandera)  \(item.nombre.capitalized)").tag(item.nombre)
                        }
                    }.labelsHidden().frame(width: 220)
                    HStack {
                        TextField("Agregar otro idioma…", text: $nuevoIdioma)
                            .textFieldStyle(.roundedBorder).frame(width: 150)
                        Button("Añadir") {
                            let n = Idiomas.agregar(nuevoIdioma)
                            if !n.isEmpty { b.idiomaDestino.wrappedValue = n; nuevoIdioma = ""; idiomasVer += 1 }
                        }.controlSize(.small)
                        .disabled(nuevoIdioma.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .id(idiomasVer)
        }
        // Buscar: buscador destino (web o Spotlight) + URL personalizada. Sin IA ni prompt.
        if b.wrappedValue.base == "buscar" {
            HStack {
                Text("Buscar en:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: b.buscador) {
                    ForEach(Buscadores.base, id: \.id) { item in Text(item.nombre).tag(item.id) }
                }.labelsHidden().frame(width: 240)
            }
            if b.wrappedValue.buscador == "personalizado" {
                HStack {
                    Text("URL:").font(.caption).frame(width: 90, alignment: .leading)
                    TextField("https://ejemplo.com/buscar?q={q}", text: b.prompt)
                        .textFieldStyle(.roundedBorder).frame(width: 280)
                }
            }
            Text("Dictas y se abre el buscador con tu consulta (usa {q} donde va el texto). Spotlight abre ⌘Espacio en tu Mac. Sin IA.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // Acción: qué abrir con el texto (app/correo/web) — Fase 5. Sin IA ni prompt.
        if b.wrappedValue.base == "accion" {
            HStack {
                Text("Acción:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: b.accion) {
                    ForEach(Acciones.base, id: \.id) { item in Text(item.nombre).tag(item.id) }
                }.labelsHidden().frame(width: 260)
            }
            if b.wrappedValue.accion == "url" {
                HStack {
                    Text("URL:").font(.caption).frame(width: 90, alignment: .leading)
                    TextField("https://quipux.gob.ec/…?q={q}", text: b.prompt)
                        .textFieldStyle(.roundedBorder).frame(width: 280)
                }
            }
            // WhatsApp: contactos para "enviar a <nombre>"
            if b.wrappedValue.accion == "whatsapp" {
                let _ = contactosVer
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contactos (\(ContactosWA.importados().count) importados) — para \"enviar a <nombre>\"")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Importar CSV/JSON…") { importarContactos() }.controlSize(.small)
                        Button("Exportar CSV") { exportarContactos("csv") }.controlSize(.small)
                        Button("Exportar JSON") { exportarContactos("json") }.controlSize(.small)
                        Toggle("Contactos de Mac", isOn: $usarMacWA).toggleStyle(.switch).controlSize(.mini)
                            .onChange(of: usarMacWA) { _, v in Config.set("wa_usar_contactos_mac", to: v) }
                    }
                    if !resultadoImport.isEmpty {
                        Text(resultadoImport).font(.caption).foregroundStyle(.green)
                    }
                    Text("Di \"modo whatsapp, a Alberto, hola qué tal\" → busca a Alberto y abre su chat. Si hay varios, eliges. Importa CSV/JSON (o export de Google/Gmail: detecta columnas Nombre/Teléfono). Exportar vacío = te da un ejemplo del formato. Si no encuentra el nombre, cae a Contactos de Mac.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("Dictas y se abre eso con tu texto (usa {q} en tu URL). Apps como Notas/Finder: copia el texto y abre la app para que pegues (⌘V). Quipux/tu web: pon la URL. Sin IA.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // Guardar en la lista local (Tareas/Notas) — Fase 4. No aplica a Buscar/Acción/Dictado.
        if b.wrappedValue.id != "dictado" && b.wrappedValue.base != "buscar" && b.wrappedValue.base != "accion" {
            HStack {
                Text("Guardar en:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: b.almacen) {
                    Text("No guardar").tag("")
                    Text("Tareas").tag("tarea")
                    Text("Notas").tag("nota")
                }.labelsHidden().frame(width: 160)
            }
        }
        // Prompt (salvo Dictado/Traducir/Buscar/Acción, que no usan prompt libre)
        if b.wrappedValue.id != "dictado" && b.wrappedValue.base != "buscar" && b.wrappedValue.base != "traducir" && b.wrappedValue.base != "accion" {
            Text("Instrucción para la IA (prompt):").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: b.prompt)
                .font(.callout).frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3)))
        } else if b.wrappedValue.id == "dictado" {
            Text("El modo Dictado usa la limpieza estándar (puntuación, muletillas, glosario). Su 'estilo' se ajusta en Ajustes → Pulido.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // IA propia del modo (no aplica a Buscar/Acción, que no usan IA)
        if b.wrappedValue.base != "buscar" && b.wrappedValue.base != "accion" {
            HStack {
                Text("IA de este modo:").font(.caption).frame(width: 110, alignment: .leading)
                Picker("", selection: b.proveedorId) {
                    Text("Global (la de Pulido)").tag("")
                    ForEach(iasPulido, id: \.id) { ia in
                        Text(ia.proveedorCorto).tag(ia.id)
                    }
                }.labelsHidden().frame(width: 220)
            }
            if !b.wrappedValue.proveedorId.isEmpty {
                HStack {
                    Text("Modelo:").font(.caption).frame(width: 110, alignment: .leading)
                    TextField("(default del proveedor)", text: b.modelo).textFieldStyle(.roundedBorder).frame(width: 220)
                }
            }
            Text("Consejo: deja la IA en 'Global' para usar la misma que pules; o elige una específica (ej. una potente para 'Asistente', una gratis para 'Tarea').")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // Borrar (solo modos propios; los base no se borran)
        if !b.wrappedValue.esFijo {
            Button(role: .destructive) {
                expandido = nil; m.borrar(b.wrappedValue.id)
            } label: { Label("Borrar este modo", systemImage: "trash") }
            .controlSize(.small)
        }
    }
}

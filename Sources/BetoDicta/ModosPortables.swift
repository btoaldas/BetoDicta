import Foundation

// MARK: - Exportar / Importar modos (paquetes JSON SIN secretos)
//
// Un usuario puede regalar sus modos —incluidas conexiones API completas— a
// otro BetoDicta: el paquete lleva la declaración (URL, endpoints, prompts,
// frases), JAMÁS los secretos (viven en el Llavero y no forman parte del
// struct) ni datos personales del exportador (su usuario de login y su IA
// local se vacían). Quien importa elige QUÉ modos quedarse, y solo pone su
// propia clave. Mismo espíritu que RecetasPortables.

struct PaqueteModos: Codable {
    var formato: String = "betodicta-modos"
    var version: Int = 1
    var modos: [Modo] = []
}

enum ModosPortables {
    static let tamanoMaximo = 2 * 1024 * 1024   // un paquete de modos jamás pesa MB

    /// Copia LIMPIA para regalar: sin usuario de login (dato personal del
    /// exportador), sin IA local (ids que no existen en otra máquina), nunca
    /// fija, y con id nuevo para no chocar con los del receptor.
    static func sanearParaExportar(_ m: Modo) -> Modo {
        var out = m
        out.esFijo = false
        out.proveedorId = ""
        out.modelo = ""
        out.appNombre = ""; out.appBundleId = ""; out.appRuta = ""
        if out.conexion != nil {
            out.conexion?.auth.usuario = ""
        }
        return out
    }

    /// ¿El importador tendrá que poner un secreto propio para que funcione?
    /// (auth con clave/API key). Sirve para el letrero "falta la clave".
    static func necesitaSecreto(_ modo: Modo) -> Bool {
        guard let t = modo.conexion?.auth.tipo else { return false }
        return t == "apikey" || t == "login"
    }

    static func exportar(_ modos: [Modo]) -> Data? {
        // Solo modos PROPIOS: los base ya existen en cualquier instalación,
        // regalarlos duplicaría catálogo en el receptor.
        let propios = modos.filter { !$0.esFijo }
        guard !propios.isEmpty else { return nil }
        let paquete = PaqueteModos(modos: propios.map(sanearParaExportar))
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(paquete)
    }

    /// Valida y prepara lo importable. Devuelve los modos LISTOS (ids nuevos si
    /// chocan con los existentes) y los motivos de rechazo de los demás.
    static func importar(_ data: Data,
                         existentes: [Modo] = ModosStore.todos()) -> (validos: [Modo], errores: [String]) {
        guard data.count <= tamanoMaximo else { return ([], ["el archivo pesa demasiado para ser un paquete de modos"]) }
        guard let paquete = try? JSONDecoder().decode(PaqueteModos.self, from: data),
              paquete.formato == "betodicta-modos" else {
            return ([], ["el archivo no es un paquete de modos de BetoDicta"])
        }
        var validos: [Modo] = []
        var errores: [String] = []
        let idsExistentes = Set(existentes.map(\.id))
        for var m in paquete.modos {
            let nombre = m.nombre.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nombre.isEmpty else { errores.append("un modo sin nombre fue descartado"); continue }
            m.esFijo = false
            m.proveedorId = ""; m.modelo = ""
            if let cx = m.conexion {
                guard ConexionesMotor.urlSegura(cx.baseURL) else {
                    errores.append("«\(nombre)»: la URL base no es segura (https, o http solo localhost)"); continue
                }
                let metodosValidos = Set(["GET", "POST", "PUT", "DELETE"])
                guard cx.endpoints.allSatisfy({ metodosValidos.contains($0.metodo.uppercased()) }) else {
                    errores.append("«\(nombre)»: un endpoint trae un método HTTP inválido"); continue
                }
                m.conexion?.auth.usuario = ""   // por si el paquete vino de una versión sucia
            }
            if m.accion == "url" || m.buscador == "personalizado" {
                // Las plantillas de URL propias también deben ser seguras.
                if !m.prompt.isEmpty, !Acciones.plantillaURLSegura(m.prompt) {
                    errores.append("«\(nombre)»: su URL no es segura"); continue
                }
            }
            if idsExistentes.contains(m.id) || validos.contains(where: { $0.id == m.id }) {
                m.id = "propio-\(UUID().uuidString.prefix(8))"
            }
            validos.append(m)
        }
        return (validos, errores)
    }

    /// Suma los elegidos a la biblioteca del receptor.
    static func fusionar(_ nuevos: [Modo]) {
        guard !nuevos.isEmpty else { return }
        var lista = ModosStore.todos()
        lista.append(contentsOf: nuevos)
        ModosStore.guardar(lista)
    }
}

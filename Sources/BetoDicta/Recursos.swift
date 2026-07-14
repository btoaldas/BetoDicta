import Foundation

// MARK: - Recursos de la Mac + recomendación de parámetros (wizard/test de rendimiento)
//
// Idea de Alberto: en vez de defaults ciegos, mirar los recursos ACTUALES de la máquina
// (RAM, núcleos, GPU) y RECOMENDAR qué activar (precargar el clon, cada cuánto dormir…).
// Así en una Mac potente se aprovecha; en una modesta no se satura. El usuario decide.

enum Recursos {
    struct Info {
        var ramGB: Double          // RAM total
        var ramLibreGB: Double     // RAM libre aprox (ahora)
        var nucleos: Int           // núcleos de CPU
        var appleSilicon: Bool     // GPU/NPU integrada (acelera algunas cosas)
    }

    struct Recomendacion {
        var preactivarClon: Bool   // mantener el modelo XTTS en RAM
        var dormirMin: Double      // minutos de inactividad para dormirlo
        var motivo: String         // por qué (para mostrar)
    }

    static func info() -> Info {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        var silicon = false
        #if arch(arm64)
        silicon = true
        #endif
        return Info(ramGB: total, ramLibreGB: ramLibreGB(), nucleos: ProcessInfo.processInfo.activeProcessorCount,
                    appleSilicon: silicon)
    }

    /// Recomienda parámetros según la RAM (el clon XTTS residente ocupa ~2 GB).
    static func recomendar(_ i: Info = info()) -> Recomendacion {
        // Con poca RAM: no mantener 2 GB colgados; dormir rápido. Con harta: aprovechar.
        if i.ramGB >= 24 {
            return Recomendacion(preactivarClon: true, dormirMin: 15,
                                  motivo: "Tienes \(fmt(i.ramGB)) GB de RAM — de sobra. Clon precargado (respuesta rápida) y duerme a los 15 min.")
        } else if i.ramGB >= 12 {
            return Recomendacion(preactivarClon: true, dormirMin: 5,
                                  motivo: "Tienes \(fmt(i.ramGB)) GB de RAM — bien. Clon precargado y duerme a los 5 min para liberar cuando no lo uses.")
        } else {
            return Recomendacion(preactivarClon: false, dormirMin: 3,
                                  motivo: "Tienes \(fmt(i.ramGB)) GB de RAM — justo. Mejor NO precargar el clon (la 1ª respuesta tarda más pero no cuelga 2 GB); duerme a los 3 min.")
        }
    }

    /// RAM libre aproximada (páginas libres+inactivas × tamaño de página), en GB.
    private static func ramLibreGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = Double(vm_kernel_page_size)
        let libres = (Double(stats.free_count) + Double(stats.inactive_count)) * page
        return libres / 1_073_741_824.0
    }

    private static func fmt(_ g: Double) -> String { String(format: "%.0f", g) }
}

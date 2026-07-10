import CoreAudio
import Foundation

// MARK: - Selección de micrófono (CoreAudio)
//
// macOS conmuta el micrófono por defecto al iPhone (Continuity) o a
// auriculares BT cuando le da la gana — y un iPhone en el bolsillo graba
// silencio. BetoDicta usa por DEFECTO el micrófono integrado del Mac;
// en Ajustes se puede elegir otro o volver al automático del sistema.

struct EntradaAudio: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let nombre: String
    let integrado: Bool
}

enum Microfono {

    /// Todos los dispositivos con canales de ENTRADA.
    static func disponibles() -> [EntradaAudio] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard tieneEntrada(id) else { return nil }
            return EntradaAudio(id: id,
                                uid: cadena(id, kAudioDevicePropertyDeviceUID) ?? "",
                                nombre: cadena(id, kAudioObjectPropertyName) ?? "¿?",
                                integrado: transporte(id) == kAudioDeviceTransportTypeBuiltIn)
        }
    }

    /// El micrófono que la app debe usar según config:
    /// "auto" → nil (no tocar, default del sistema) · UID → ese dispositivo
    /// · sin config → el integrado del Mac (el fix anti-iPhone).
    static func elegido() -> AudioDeviceID? {
        let pref = Config.microfono()
        if pref == "auto" { return nil }
        let lista = disponibles()
        if !pref.isEmpty, let d = lista.first(where: { $0.uid == pref }) { return d.id }
        return lista.first(where: { $0.integrado })?.id
    }

    // ---- helpers CoreAudio ----

    private static func tieneEntrada(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return false }
        let abl = buf.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(abl).reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func transporte(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
        return t
    }

    private static func cadena(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var ref: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let st = withUnsafeMutablePointer(to: &ref) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        return st == noErr ? ref as String? : nil
    }
}

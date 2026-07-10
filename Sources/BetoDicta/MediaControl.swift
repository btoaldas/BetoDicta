import AppKit
import CoreAudio

// MARK: - Control multimedia (pausa lo que suena y atenúa el volumen al dictar)

final class MediaControl {
    private var previousVolume: Int?
    private var pausedMedia = false

    /// Al empezar a dictar: recuerda el volumen, lo baja, y pausa lo que suene.
    func dictationStarted() {
        guard Config.duckMedia() else { return }
        // Detectar ANTES de tocar nada (nuestros propios sonidos también cuentan)
        let algoSuena = Self.isAudioPlaying()
        previousVolume = readVolume()
        setVolume(Config.duckVolume())
        // Ojo: un video EN PAUSA puede mantener el audio "abierto" y disparar
        // un play fantasma (se auto-corrige al terminar). Interruptor propio:
        if Config.pausePlayback(), algoSuena {
            Self.sendPlayPauseKey()
            pausedMedia = true
        }
    }

    /// Al terminar o cancelar: volumen EXACTO de antes y play solo si estaba sonando.
    func dictationEnded() {
        if let volume = previousVolume {
            setVolume(volume)
            previousVolume = nil
        }
        if pausedMedia {
            Self.sendPlayPauseKey()
            pausedMedia = false
        }
    }

    /// ¿La salida de audio está en uso? (CoreAudio: cubre Edge, YouTube,
    /// Spotify, Música — cualquier app que esté reproduciendo sonido)
    private static func isAudioPlaying() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceID) == noErr else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Simula la tecla física ⏯ del teclado — la misma que pausa YouTube,
    /// Spotify o lo que el sistema tenga "sonando ahora".
    private static func sendPlayPauseKey() {
        let NX_KEYTYPE_PLAY: Int32 = 16
        func post(down: Bool) {
            let data1 = Int((Int(NX_KEYTYPE_PLAY) << 16) | ((down ? 0x0A : 0x0B) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    private func readVolume() -> Int {
        let script = NSAppleScript(source: "output volume of (get volume settings)")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return Int(result?.int32Value ?? 50)
    }

    private func setVolume(_ value: Int) {
        let script = NSAppleScript(source: "set volume output volume \(max(0, min(100, value)))")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }
}

import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox

// MARK: - Pegado (clipboard + Cmd+V, restaurando lo que había)

func pasteText(_ text: String) {
    if !AXIsProcessTrusted() {
        Log.write("⚠️ PEGADO BLOQUEADO: falta permiso de Accesibilidad para BetoDicta")
    }
    let pb = NSPasteboard.general
    let previous = pb.string(forType: .string)
    pb.clearContents()
    pb.setString(text, forType: .string)

    let src = CGEventSource(stateID: .combinedSessionState)
    let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
    let vUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    vDown?.flags = .maskCommand
    vUp?.flags = .maskCommand
    vDown?.post(tap: .cghidEventTap)
    vUp?.post(tap: .cghidEventTap)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
    }
}

/// Pulsa ⌘N (nuevo ítem) — para las acciones que crean nota/recordatorio/documento.
func presionarNuevo() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: false)
    down?.flags = .maskCommand; up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

/// Abre Spotlight (⌘Espacio) — para el modo Buscar en la Mac.
func abrirSpotlight() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Space), keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Space), keyDown: false)
    down?.flags = .maskCommand; up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

/// Pulsa Return (o Shift+Return) — para los flags "Enter / Shift+Enter al
/// terminar el dictado". Se llama con un pequeño retraso tras pegar.
func presionarRetorno(shift: Bool) {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
    if shift { down?.flags = .maskShift; up?.flags = .maskShift }
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}


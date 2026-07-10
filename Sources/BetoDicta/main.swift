// BetoDicta v0.2 — dictado por voz de Alberto Aldás
// <tecla>: abre panel y graba · <tecla> otra vez: transcribe y pega
// Streaming en vivo (scribe_v2_realtime) o batch (scribe_v1 / scribe_v2)
//
// Config ~/.betodicta/config.json: {"tecla": "fn", "modelo": "scribe_v2_realtime"}
//   tecla: fn | F1..F12
//   modelo: scribe_v2_realtime (texto en vivo) | scribe_v2 | scribe_v1 (batch)
// ~/.betodicta/keyterms.txt — una palabra por línea (streaming usa las primeras 50)
// ~/.betodicta/reemplazos.json — [{"original":"a, b","replacement":"X"}]
// API key: ELEVENLABS_API_KEY en ~/.hermes/.env

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

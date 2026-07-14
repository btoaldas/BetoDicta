import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Configuración

struct Config {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".betodicta")

    private static let lock = NSLock()
    private static var cache: [String: Any]?

    private static func json() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        if let c = cache { return c }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return cache ?? [:] }
        cache = obj
        return obj
    }

    static func hotkey() -> String { (json()["tecla"] as? String) ?? "fn" }
    static func maxSilence() -> TimeInterval { (json()["silencio_max_seg"] as? Double) ?? 120 }
    static func sounds() -> Bool { (json()["sonidos"] as? Bool) ?? true }
    static func escCancels() -> Bool { (json()["esc_cancela"] as? Bool) ?? true }
    static func duckMedia() -> Bool { (json()["atenuar_multimedia"] as? Bool) ?? true }
    static func duckVolume() -> Int { (json()["volumen_dictado"] as? Int) ?? 1 }
    static func postProcess() -> Bool { (json()["post_proceso"] as? Bool) ?? false }
    /// Qué IA hace el pulido (y la traducción). Cualquier proveedor de chat
    /// conectado, no solo Groq. Default "groq".
    static func pulidoProveedor() -> String { (json()["pulido_proveedor"] as? String) ?? "groq" }
    /// Cascada de FAILOVER de pulido: ids de proveedores en el ORDEN elegido por el
    /// usuario (1º intenta, si cae salta al siguiente). Vacío = automática (el
    /// proveedor de pulido primero, luego el resto de conectados).
    static func pulidoCascada() -> [String] { (json()["pulido_cascada"] as? [String]) ?? [] }
    /// Modelo ACTIVO elegido por el usuario para un proveedor de pulido (por id).
    /// Si no eligió, se usa el modelo por defecto del proveedor. Aplica a todos
    /// (Groq, OpenAI, OpenRouter, Gemini, locales…), no solo a los gateways.
    static func pulidoModelo(_ id: String) -> String? {
        guard let m = (json()["pulido_modelos"] as? [String: Any])?[id] as? String, !m.isEmpty else { return nil }
        return m
    }
    static func setPulidoModelo(_ id: String, _ modelo: String?) {
        var d = (json()["pulido_modelos"] as? [String: Any]) ?? [:]
        if let modelo, !modelo.isEmpty { d[id] = modelo } else { d[id] = nil }
        set("pulido_modelos", to: d)
    }
    /// Precio MANUAL puesto por el usuario para un (proveedor::modelo): USD por
    /// 1M tokens (entrada, salida). Tiene prioridad sobre el publicado/curado.
    static func precioManual(_ key: String) -> (Double, Double)? {
        guard let arr = (json()["precios_manuales"] as? [String: Any])?[key] as? [Double], arr.count == 2 else { return nil }
        return (arr[0], arr[1])
    }
    static func setPrecioManual(_ key: String, _ inOut: (Double, Double)?) {
        var d = (json()["precios_manuales"] as? [String: Any]) ?? [:]
        if let io = inOut { d[key] = [io.0, io.1] } else { d[key] = nil }
        set("precios_manuales", to: d)
    }
    static func customPrompt() -> String? {
        guard let s = json()["prompt_pulido"] as? String, !s.isEmpty else { return nil }
        return s
    }
    static func pausePlayback() -> Bool { (json()["pausar_multimedia"] as? Bool) ?? true }
    static func devMode() -> Bool { (json()["modo_desarrollo"] as? Bool) ?? false }
    /// Segundos a esperar la respuesta del pulido con IA (Groq) antes de
    /// rendirse. Parametrizable (Avanzado). Default 20, hasta 60.
    static func pulidoTimeout() -> Double { min(60, max(5, (json()["pulido_timeout_seg"] as? Double) ?? 20)) }
    static func showInDock() -> Bool { (json()["mostrar_en_dock"] as? Bool) ?? false }
    /// Al abrir la app, busca en silencio si hay versión nueva (GitHub) y la
    /// muestra abajo-izquierda ("Actualización disponible"). Parametrizable.
    static func buscarUpdateAlAbrir() -> Bool { (json()["buscar_update_al_abrir"] as? Bool) ?? true }
    /// Si encuentra actualización al abrir, la instala sola (sin pedir). OFF
    /// por defecto: reinstalar+reiniciar es una acción grande, es opt-in.
    static func autoactualizar() -> Bool { (json()["autoactualizar"] as? Bool) ?? false }
    /// Muestra el aviso de privacidad cuando el pulido usa una IA de NUBE o un
    /// gateway de terceros (tu texto sale de tu Mac). Default ON. Parametrizable.
    static func avisoNube() -> Bool { (json()["aviso_privacidad_nube"] as? Bool) ?? true }
    /// Push-to-talk: mantener la tecla presionada graba, soltarla termina
    /// (en vez del modo toque-para-empezar / toque-para-terminar). Default OFF.
    static func pushToTalk() -> Bool { (json()["hold_para_hablar"] as? Bool) ?? false }
    /// Salvaguarda anti-inyección: si el texto PULIDO por la IA diverge
    /// groseramente del dictado (crece desmedido o mete comandos que el
    /// original no tenía), entrega el ORIGINAL. NUNCA bloquea, solo cae a tus
    /// palabras. Opt-in (default OFF) para no estorbar el uso normal.
    static func salvaguardaInyeccion() -> Bool { (json()["salvaguarda_inyeccion"] as? Bool) ?? false }
    /// Account ID de Cloudflare (va en la URL de Workers AI, como el chat).
    /// Sin él, el motor STT de Cloudflare no puede llamar (avisa en la UI).
    static func cloudflareAccountId() -> String { (json()["cloudflare_account_id"] as? String) ?? "" }
    /// Región de Azure AI Speech (ej. eastus) — va en la URL del endpoint.
    static func azureSpeechRegion() -> String { (json()["azure_speech_region"] as? String) ?? "" }
    /// Búsqueda SEMÁNTICA del historial (por significado, con embeddings). Opt-in
    /// (default OFF: necesita Ollama u otro motor de embeddings). Parametrizable:
    /// base + modelo + key. Default = Ollama local bge-m3 (gratis, privado).
    static func busquedaSemantica() -> Bool { (json()["busqueda_semantica"] as? Bool) ?? false }
    /// STT en vivo/streaming para motores de NUBE que lo soportan (hoy Deepgram
    /// por WebSocket). Opt-in (default OFF): si está apagado, esos motores
    /// transcriben por LOTES al soltar la tecla (como siempre). Additivo: no
    /// cambia el comportamiento del resto de la cascada.
    static func sttStreaming() -> Bool { (json()["stt_streaming"] as? Bool) ?? false }
    /// Motor de embeddings elegido ("ollama"|"openai"|"gemini"|"mistral"|"custom").
    /// Default Ollama (local), pero el usuario elige en Avanzado según lo que tenga.
    static func embeddingProveedor() -> String { (json()["embedding_proveedor"] as? String) ?? "ollama" }
    /// Modo POR DEFECTO (sticky): al que se vuelve tras cada dictado si modoRevertir.
    /// Se fija en Ajustes → Modos ("Poner por defecto"). Default "dictado".
    static func modoDefecto() -> String { (json()["modo_defecto"] as? String) ?? "dictado" }
    /// Modo activo AHORA (qué hacer con lo dictado). Transitorio: el notch/menú lo
    /// cambia al vuelo; si modoRevertir está ON, vuelve al defecto tras cada dictado.
    static func modoActivo() -> String { (json()["modo_activo"] as? String) ?? modoDefecto() }
    /// El modo elegido en caliente (notch/menú) es de UN SOLO USO: tras dictar,
    /// vuelve al modo por defecto. Default ON (pedido de Alberto). Apágalo = sticky.
    static func modoRevertir() -> Bool { (json()["modo_revertir"] as? Bool) ?? true }
    /// Idiomas que el usuario agregó al selector de "Traducir" (además de los base).
    static func idiomasPersonales() -> [String] { (json()["idiomas_personales"] as? [String]) ?? [] }
    /// Activar un modo por VOZ: si el dictado empieza con la frase de un modo
    /// (ej. "modo tarea comprar la comida"), se usa ese modo y se quita la frase.
    /// Default ON (los modos base traen su frase; edítalas o vacíalas en Modos).
    static func modoPorVoz() -> Bool { (json()["modo_por_voz"] as? Bool) ?? true }
    /// Activar un modo por CONTEXTO: si estás en una app (ej. Outlook) o un sitio
    /// web (ej. Quipux) que un modo declara, ese modo se aplica solo a ese dictado.
    /// Default ON (inofensivo: los modos base no traen apps/sitios hasta que los pongas).
    static func modoPorContexto() -> Bool { (json()["modo_por_contexto"] as? Bool) ?? true }
    /// WhatsApp: usar los Contactos de macOS además de la lista importada. Default ON.
    static func waUsarContactosMac() -> Bool { (json()["wa_usar_contactos_mac"] as? Bool) ?? true }
    /// Glosario INTELIGENTE: en el pulido, manda solo los términos afines al dictado
    /// (con embeddings) en vez de los 80 → prompt corto = más rápido. Default OFF (opt-in).
    static func glosarioInteligente() -> Bool { (json()["glosario_inteligente"] as? Bool) ?? false }
    /// Reconocimiento SEMÁNTICO de modos por voz (capa 3, embeddings): entiende el
    /// llamado del modo aunque lo digas de mil formas. Default OFF (opt-in).
    static func modoSemantico() -> Bool { (json()["modo_semantico"] as? Bool) ?? false }
    /// Cuántas palabras del inicio se analizan como "zona-comando" (parametrizable).
    static func modoSemanticoPalabras() -> Int { (json()["modo_sem_palabras"] as? Int) ?? 5 }
    /// Umbral de cercanía (coseno) para aceptar un modo: más alto = más estricto.
    static func modoSemanticoUmbral() -> Double { (json()["modo_sem_umbral"] as? Double) ?? 0.5 }
    /// Registro detallado del subsistema de modos (~/.betodicta/logs/modos.jsonl). Default ON.
    static func logModos() -> Bool { (json()["log_modos"] as? Bool) ?? true }
    /// Apple Speech nativo (STT on-device, macOS 26+): idioma BCP-47. es-EC se
    /// mapea al español más cercano. Parametrizable.
    static func appleSpeechIdioma() -> String { (json()["apple_speech_idioma"] as? String) ?? "es-EC" }

    // Fase 7 — TTS (texto→voz). Default OFF (opt-in).
    static func ttsActivo() -> Bool { (json()["tts_activo"] as? Bool) ?? false }
    static func ttsVoz() -> String { (json()["tts_voz"] as? String) ?? "" }
    static func ttsVelocidad() -> Double { (json()["tts_velocidad"] as? Double) ?? 0.5 }
    /// Cerebro del Modo Agente: "local" (IA local de BetoDicta) | "hermes" (pasarela a
    /// Hermes: su LLM + sus herramientas). A futuro: "openclaw". Parametrizable.
    static func agenteMotor() -> String { (json()["agente_motor"] as? String) ?? "local" }
    /// Ruta del binario hermes (vacío = autodetectar ~/.local/bin/hermes).
    static func hermesBin() -> String { (json()["hermes_bin"] as? String) ?? "" }

    /// El Modo Agente PEGA su respuesta donde estés (como el dictado). Default OFF:
    /// el agente es conversacional (notch + voz); actívalo si quieres el texto pegado.
    /// A futuro será inteligente según la intención (pedir texto → pega; preguntar → no).
    static func agentePega() -> Bool { (json()["agente_pega"] as? Bool) ?? false }

    /// Motor de TTS: "apple" (voz de macOS) | "elevenlabs" (voz clonada Bto) |
    /// "xtts_local" (tu clon local). Cascada de failover parametrizable.
    static func ttsProveedor() -> String { (json()["tts_proveedor"] as? String) ?? "apple" }
    /// voice_id de ElevenLabs para TTS (tu voz clonada "Bto"). Vacío = usar el default.
    static func ttsElevenVoz() -> String { (json()["tts_eleven_voz"] as? String) ?? "qoHnXuIkkICzacInt72I" }
    static func ttsElevenModelo() -> String { (json()["tts_eleven_modelo"] as? String) ?? "eleven_flash_v2_5" }
    /// Streaming por WebSocket para ElevenLabs (suena mientras se genera). Default ON.
    static func ttsElevenStreaming() -> Bool { (json()["tts_eleven_streaming"] as? Bool) ?? true }
    /// Parámetros POR proveedor TTS de nube (voz/modelo/streaming). Todo parametrizable.
    static func ttsCloudVoz(_ id: String) -> String { ((json()["tts_cloud_voz"] as? [String: String]) ?? [:])[id] ?? "" }
    static func ttsCloudModelo(_ id: String) -> String { ((json()["tts_cloud_modelo"] as? [String: String]) ?? [:])[id] ?? "" }
    /// Streaming por proveedor (solo aplica si el proveedor soporta WS). Default ON.
    static func ttsCloudStreaming(_ id: String) -> Bool { ((json()["tts_cloud_streaming"] as? [String: Bool]) ?? [:])[id] ?? true }
    static func fijarTtsCloud(_ campo: String, _ id: String, _ valor: Any) {
        var d = (json()[campo] as? [String: Any]) ?? [:]; d[id] = valor; set(campo, to: d)
    }
    /// Comando de shell para tu clon LOCAL XTTS (VozClonPOC). {texto} y {salida}
    /// se sustituyen. Vacío = motor no configurado (failover). Parametrizable.
    /// (Compat: se usa si no hay voces en la biblioteca [[VocesLocales]].)
    static func ttsXttsCmd() -> String { (json()["tts_xtts_cmd"] as? String) ?? "" }
    /// Voz LOCAL clonada seleccionada de la biblioteca (id). Vacío = la primera.
    static func ttsVozLocal() -> String { (json()["tts_voz_local"] as? String) ?? "" }
    /// Entrenador Piper: URL del checkpoint base (fine-tune). Vacío = default conocido.
    static func piperBaseURL() -> String { (json()["piper_base_url"] as? String) ?? "" }
    /// Entrenador Piper: tamaño de lote (batch). Default 8 (CPU 64GB). Parametrizable.
    static func piperBatch() -> Int { (json()["piper_batch"] as? Int) ?? 8 }
    /// Preactivar el servidor XTTS residente (modelo cargado en RAM) cuando el clon
    /// local es el motor activo → respuesta rápida. Default ON. Parametrizable.
    static func ttsXttsPreactivar() -> Bool { (json()["tts_xtts_preactivar"] as? Bool) ?? true }
    /// Modo RÁPIDO del clon: streaming (suena en ~1-2s mientras genera) en vez de por
    /// lotes (~4s pero garantizado fluido). El server corre a baja prioridad + hilos
    /// limitados para que el audio no se trabe. Default OFF (el usuario lo activa).
    static func ttsXttsRapido() -> Bool { (json()["tts_xtts_rapido"] as? Bool) ?? false }
    /// Hilos de CPU para el clon (0 = auto: núcleos-4, deja CPU al audio). Parametrizable.
    static func ttsXttsHilos() -> Int { (json()["tts_xtts_hilos"] as? Int) ?? 0 }
    /// Colchón (caché) del modo rápido en SEGUNDOS: cuánto audio junta antes de sonar.
    /// Más = más fluido (cubre las pausas del XTTS) pero arranca un poco más tarde.
    /// Default 2.5s → suena en ~2.5s (vs 4s por lotes) y cubre las pausas. Parametrizable.
    static func ttsXttsColchonSeg() -> Double { (json()["tts_xtts_colchon_seg"] as? Double) ?? 2.5 }
    /// DORMIR el clon (descargar el modelo, liberar RAM/CPU) tras N minutos sin usarse;
    /// se despierta al grabar (fn). Default ON, 5 min. No satura la Mac cuando no lo usas.
    static func ttsXttsDormir() -> Bool { (json()["tts_xtts_dormir"] as? Bool) ?? true }
    static func ttsXttsDormirMin() -> Double { (json()["tts_xtts_dormir_min"] as? Double) ?? 5 }
    /// Modo AHORRO global: al inactivar (mismos minutos), libera lo pesado (clon + latido
    /// de red); fn despierta todo. Default ON. Parametrizable.
    static func ahorroGlobal() -> Bool { (json()["ahorro_global"] as? Bool) ?? true }
    /// Carpeta base de VozClonPOC (para el botón "Detectar mis voces"). Parametrizable.
    static func vozClonBase() -> String { (json()["voz_clon_base"] as? String) ?? "~/Downloads/VozClonPOC" }
    /// Buscadores propios del usuario: [{nombre, url}] (url con {q}). Para el modo Buscar.
    static func buscadoresPersonales() -> [[String: String]] { (json()["buscadores_personales"] as? [[String: String]]) ?? [] }
    /// Despertar el túnel de red al grabar (mitiga latencia del 1er dictado con VPN). Default ON.
    static func calentarRed() -> Bool { (json()["calentar_red"] as? Bool) ?? true }
    /// Cada cuántos segundos late la red para mantener la conexión caliente (pulido
    /// rápido aunque dictes cada varios minutos). Default 15s. Parametrizable.
    static func latidoRedSegundos() -> Double { (json()["latido_red_segundos"] as? Double) ?? 15 }
    static func embeddingBase() -> String { (json()["embedding_base"] as? String) ?? "http://localhost:11434" }
    static func embeddingModelo() -> String { (json()["embedding_modelo"] as? String) ?? "bge-m3" }
    static func embeddingKeyEnv() -> String { (json()["embedding_key_env"] as? String) ?? "OPENAI_API_KEY" }
    static func muteToo() -> Bool { (json()["silenciar_ademas"] as? Bool) ?? false }
    static func translate() -> Bool { (json()["traducir"] as? Bool) ?? false }
    static func translateTo() -> String { (json()["traducir_idioma"] as? String) ?? "inglés" }
    static func panelVisible() -> Bool { (json()["panel_visible"] as? Bool) ?? true }
    static func exportFolder() -> URL {
        if let s = json()["carpeta_exportar"] as? String, !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static func groqKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !env.isEmpty { return env }
        let envFile = dir.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("GROQ_API_KEY=") {
            let key = String(line.dropFirst("GROQ_API_KEY=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        return nil
    }

    /// Escribe un valor en config.json de forma ATÓMICA y serializada, para
    /// que la GUI y el dictado no corrompan el archivo al leer/escribir a la vez.
    static func set(_ key: String, to value: Any) {
        lock.lock()
        var obj = cache ?? {
            (try? Data(contentsOf: dir.appendingPathComponent("config.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        }()
        obj[key] = value
        cache = obj
        // Escribir DENTRO del lock: dos set() concurrentes escribían snapshots
        // viejos tras soltar el lock → se perdía una actualización EN DISCO
        // (la memoria quedaba bien, pero el próximo arranque la perdía).
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            let cfg = dir.appendingPathComponent("config.json")
            try? data.write(to: cfg, options: .atomic)
            protegerSecreto(cfg)
        }
        lock.unlock()
        Log.log(.config, "cambio: \(key) = \(value)")
    }

    /// Fija permisos 0600 a un archivo que puede contener secretos (claves,
    /// gateways). Defensa en profundidad además del ~/.betodicta a 0700.
    static func protegerSecreto(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// Asegura que ~/.betodicta exista y quede en 0700 (solo el dueño).
    static func asegurarDirSeguro() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }
    /// Al arrancar: baja a 0600 los archivos con secretos que ya existan
    /// (para quien actualiza desde una versión que los dejaba en 0644).
    static func endurecerSecretosExistentes() {
        asegurarDirSeguro()
        for f in [".env", "config.json", "ia_personalizadas.json"] {
            let u = dir.appendingPathComponent(f)
            if FileManager.default.fileExists(atPath: u.path) { protegerSecreto(u) }
        }
    }
    static func model() -> String { (json()["modelo"] as? String) ?? "scribe_v2_realtime" }
    /// Segundos que el whisper-server local vive tras el último uso (mín. 10).
    static func whisperKeepAlive() -> TimeInterval { max(10, (json()["whisper_keepalive"] as? Double) ?? 120) }
    /// Micrófono: "" = integrado del Mac (default anti-iPhone) · "auto" =
    /// el del sistema · UID = dispositivo específico.
    static func microfono() -> String { (json()["microfono"] as? String) ?? "" }
    /// Aprender de tus correcciones en el sitio (lee el campo vía
    /// Accesibilidad). Opt-in: apagado por defecto.
    static func aprender() -> Bool { (json()["aprender_correcciones"] as? Bool) ?? false }
    /// Atajo global para "aprender de la selección" (funciona en cualquier
    /// app, incl. Claude Code CLI). Default ⌘⇧L.
    static func atajoAprender() -> String { (json()["atajo_aprender"] as? String) ?? "cmd+shift+l" }
    /// Corrección por SONIDO (fonética): corrige palabras que suenan como un
    /// término marcado, aunque no sea una variante exacta ya conocida.
    /// Opt-in: apagada por defecto (más agresiva, puede sobre-corregir).
    static func correccionPorSonido() -> Bool { (json()["correccion_por_sonido"] as? Bool) ?? false }
    /// Asistente de primer arranque: ¿ya lo terminó el usuario? Solo se marca
    /// true al pulsar "Finalizar" — así un reinicio por Accesibilidad a mitad
    /// del wizard lo reabre en el mismo paso en vez de saltárselo.
    // Qué hacer al TERMINAR un dictado (tras pegar). Todos opt-in, default off.
    /// Añade un espacio al final (separa dictados seguidos).
    static func espacioAlTerminar() -> Bool { (json()["espacio_al_terminar"] as? Bool) ?? false }
    /// Pulsa Enter al terminar (envía en chats / salta línea en editores).
    static func enterAlTerminar() -> Bool { (json()["enter_al_terminar"] as? Bool) ?? false }
    /// Pulsa Shift+Enter al terminar (salto de línea suave).
    static func shiftEnterAlTerminar() -> Bool { (json()["shift_enter_al_terminar"] as? Bool) ?? false }

    /// Coincidencia por AUDIO (experimental): reconocer un término por tu voz
    /// grabada, además del texto. Opt-in, apagado por defecto.
    static func matchPorAudio() -> Bool { (json()["match_por_audio"] as? Bool) ?? false }
    /// Umbral de distancia para el match por audio (nil = usar el default).
    static func umbralAudio() -> Double? { json()["umbral_audio"] as? Double }
    /// Umbral SEPARADO para el dictado real (spotting corre en otra escala que
    /// "probar por voz"). nil = cae al de probar hasta calibrarlo.
    static func umbralAudioDictado() -> Double? { json()["umbral_audio_dictado"] as? Double }

    static func wizardCompletado() -> Bool { (json()["wizard_completado"] as? Bool) ?? false }
    /// ¿Existe ya la decisión del wizard? (ausente = nunca se ha decidido;
    /// sirve para migrar a usuarios que actualizan desde una versión sin wizard).
    static func tieneWizardFlag() -> Bool { json()["wizard_completado"] != nil }
    /// Paso guardado del asistente (para reabrir donde iba tras un reinicio).
    static func wizardPaso() -> Int { (json()["wizard_paso"] as? Int) ?? 0 }
    /// Última versión que el usuario YA vio (para el modal de novedades).
    static func ultimaVersionVista() -> String { (json()["ultima_version_vista"] as? String) ?? "" }
    /// ¿Hay señales de que la app ya se usó antes en esta máquina? (config,
    /// historial, uso, claves…). Distingue "actualización" de "instalación nueva".
    static func instalacionPrevia() -> Bool {
        let fm = FileManager.default
        for f in ["config.json", "uso.jsonl", "providers.json", ".env", "keyterms.txt"] {
            if fm.fileExists(atPath: dir.appendingPathComponent(f).path) { return true }
        }
        return fm.fileExists(atPath: dir.appendingPathComponent("historial").path)
    }

    /// Tarifa por hora que TÚ pusiste para un motor (override del default).
    static func tarifa(_ motor: String) -> Double? { (json()["tarifas"] as? [String: Double])?[motor] }
    static func setTarifa(_ motor: String, _ valor: Double?) {
        var t = (json()["tarifas"] as? [String: Double]) ?? [:]
        if let valor { t[motor] = valor } else { t[motor] = nil }
        set("tarifas", to: t)
    }

    /// API key de ElevenLabs: variable de entorno → ~/.betodicta/.env
    /// (la pone la pestaña Modelos; nada de rutas de otras apps).
    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !env.isEmpty {
            return env
        }
        let key = ApiKeys.get("ELEVENLABS_API_KEY")
        return key.isEmpty ? nil : key
    }

    static func keyterms() -> [String] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("keyterms.txt"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Glosario como "initial prompt" para motores familia Whisper (Groq,
    /// whisper-cli, whisper-server, y futuros OpenAI/Mistral). Una frase en
    /// español sesga mejor que una lista pelada. Vacío si no hay términos.
    /// Tope 80 términos: el initial prompt de Whisper admite ~224 tokens y
    /// trunca por el INICIO, así que pasarse silenciosamente pierde términos.
    static func glosarioPrompt() -> String {
        let terms = keyterms().prefix(80)
        guard !terms.isEmpty else { return "" }
        return "Glosario: \(terms.joined(separator: ", "))."
    }

    struct Replacement: Decodable {
        let original: String
        let replacement: String
        let isRegex: Bool?
        let activo: Bool?
        let porSonido: Bool?     // además de variantes exactas, corregir por sonido
        let sigla: Bool?         // es un acrónimo (DGTIC): coloca por posición de audio
    }

    /// Solo las reglas activas (las desactivadas se conservan pero no se aplican).
    static func replacements() -> [Replacement] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("reemplazos.json")),
              let rules = try? JSONDecoder().decode([Replacement].self, from: data) else { return [] }
        return rules.filter { $0.activo ?? true }
    }
}


import Foundation

// MARK: - Entrenador de clones de voz (planificación inteligente) — Fase asistente por voz
//
// El usuario suelta una carpeta de audios de UNA persona; BetoDicta entrena un clon
// XTTS (pipeline de VozClonPOC internalizado, corre en el motor aislado, en background
// con resiliencia) y al final emite un PAQUETE portable. Este archivo es el CEREBRO
// de PARÁMETROS: según cuánto audio hay, recomienda etapas + checkpoints (el usuario
// puede cambiarlos). Nada se entrena aquí todavía — solo se decide el plan.
//
// Regla de Alberto (confirmada con el pipeline real, info.py):
//   < 1h  → NO sirve (ni dejar iniciar): lo genérico domina, ningún checkpoint convence.
//   1–2h  → aceptable (se reconoce a la persona).       recomendado ~3000 etapas.
//   2–4h  → bueno (la persona domina, su acento).        recomendado ~4000.
//   4–6h  → excelente (impecable).                        recomendado ~5000.
//   > 6h  → ya no mejora proporcional (desperdicio).      tope 5000, con aviso.
// Menos audio = menos etapas (más etapas sobre poca voz sobreajusta y no mejora).

struct PlanEntrenamiento {
    var minutos: Double
    var permitido: Bool            // false si < 1h → ni se deja iniciar
    var tier: String               // etiqueta legible del nivel
    var etapasRecomendadas: Int    // etapas (steps) sugeridas
    var checkpoints: [Int]         // cortes donde guardar y luego comparar
    var aviso: String              // nota para el usuario (por qué / advertencia)
}

enum Entrenador {
    /// Validación: tu spec = 10 muestras de ~30s (se pasa como env VAL_N / VAL_SEC al
    /// pipeline, que por defecto trae 5 × 20s).
    static let valN = 10
    static let valSeg = 30

    /// Recomienda el plan según los MINUTOS de audio. El usuario puede editar todo.
    static func recomendar(minutos: Double) -> PlanEntrenamiento {
        switch minutos {
        case ..<60:
            return PlanEntrenamiento(
                minutos: minutos, permitido: false, tier: "❌ Muy poco (menos de 1 hora)",
                etapasRecomendadas: 0, checkpoints: [],
                aviso: "Con menos de 1 hora de voz el clon no convence — lo genérico domina y ningún corte queda bien. Junta más audio (meta: 1 a 3 horas).")
        case 60..<120:
            return PlanEntrenamiento(
                minutos: minutos, permitido: true, tier: "🟡 Aceptable (1–2 h)",
                etapasRecomendadas: 3000, checkpoints: [500, 1500, 2000, 2500, 3000],
                aviso: "Se reconoce a la persona (aún cuela algo genérico). Con poca voz, más etapas NO mejora: tope ~3000.")
        case 120..<240:
            return PlanEntrenamiento(
                minutos: minutos, permitido: true, tier: "🟢 Bueno (2–4 h)",
                etapasRecomendadas: 4000, checkpoints: [1000, 2000, 3000, 3500, 4000],
                aviso: "La persona domina y se le nota su acento. Recomendado ~4000 etapas.")
        case 240..<360:
            return PlanEntrenamiento(
                minutos: minutos, permitido: true, tier: "⭐ Excelente (4–6 h)",
                etapasRecomendadas: 5000, checkpoints: [1500, 2500, 3500, 4500, 5000],
                aviso: "Suficiente voz para un clon impecable. Recomendado ~5000 etapas.")
        default:
            return PlanEntrenamiento(
                minutos: minutos, permitido: true, tier: "🔵 De sobra (más de 6 h)",
                etapasRecomendadas: 5000, checkpoints: [1500, 2500, 3500, 4500, 5000],
                aviso: "Ya tienes voz de sobra; más de ~5000 etapas no mejora proporcional, solo cuesta tiempo y disco. Se mantiene el tope en 5000.")
        }
    }

    /// Estimación de horas de entrenamiento (CPU) para mostrar antes de arrancar.
    /// Muy aproximada: XTTS en CPU ~2-4 s/paso según la máquina.
    static func horasEstimadas(etapas: Int, segPorPaso: Double = 3.0) -> Double {
        Double(etapas) * segPorPaso / 3600.0
    }
}

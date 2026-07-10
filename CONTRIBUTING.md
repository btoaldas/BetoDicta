# Contribuir a BetoDicta

¡Bienvenido! Este proyecto nació dictando por voz y se mantiene con esa filosofía: simple, directo y útil.

## Cómo contribuir

1. Haz fork y crea una rama: `git checkout -b mi-mejora`
2. Compila y prueba en tu Mac: `make install`
3. Manda tu Pull Request con una descripción clara de qué mejora y por qué

## Reglas de la casa

- **Español primero**: la app y sus mensajes están en español; el código se comenta en español
- **Un archivo, por ahora**: todo vive en `Sources/BetoDicta/main.swift` — si tu cambio lo amerita, proponer la división en módulos es bienvenido
- **Cero secretos en el repo**: las API keys viven en `~/.betodicta/.env`, jamás en el código
- **Privacidad**: los dictados del usuario (`historial/`, `uso.jsonl`) nunca salen de su máquina
- **GPL-3.0**: toda contribución queda bajo la misma licencia libre

## Ideas abiertas

Mira la hoja de ruta en el README — el failover multi-proveedor (con Whisper local gratuito) es la joya pendiente.

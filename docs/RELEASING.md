# Cómo se publica un release de BetoDicta (gobernanza)

Cada release pasa por un **pipeline fijo y en este orden**. No se salta ningún paso.

## Los 6 pasos

1. **Code review** — revisión adversarial del diff (bugs, regresiones, correctitud). La hace Claude con un workflow de revisión por dimensiones + verificación de cada hallazgo.
2. **Security review** — auditoría de seguridad del cambio y del sistema (fugas de credenciales, ejecución de procesos, SSRF, integridad del update, inyección, puertas traseras). Workflow con auditores + verificación de explotabilidad.
3. **Manual + README** — actualizarlos con **todo** lo mejorado hasta este release (incluidas capturas nuevas). Si el manual no se toca, el pipeline **bloquea** el release.
4. **Build + firma** — compilar, armar el DMG, y verificar que el bundle quede firmado con el certificado propio **y** que el DMG pase la MISMA verificación de firma que exige el updater (así nunca se publica algo que la app instalada rechazaría al actualizar).
5. **Publicar** — `gh release create` con el DMG **versionado** y el DMG **estable** `BetoDicta.dmg` (el que consume el tap de Homebrew: `releases/latest/download/BetoDicta.dmg`).
6. **Verificar** — `latest` apunta a la versión nueva, el redirect estable de brew da 302 a la versión nueva, y la app instalada (versión anterior) verá **"Actualizar a vX" + novedades**. **No se instala** nada en la máquina del autor: el mantenedor actualiza desde la app para ver las novedades.

## El comando

Pasos 1 y 2 (reviews) los corre Claude **antes**. Luego:

```bash
scripts/release.sh --code-review-ok --security-review-ok --notes "…novedades…"
```

El script exige esos flags (no se puede publicar sin confirmar las reviews), verifica que `Version.swift` e `Info.plist` coincidan, que el historial de novedades incluya la versión, que manual/README hayan cambiado desde el último tag, compila+firma, comprueba la firma del DMG, publica ambos DMG y verifica `latest` + brew.

Antes de correrlo: subir la versión en `Sources/BetoDicta/Version.swift` (número, fecha y una entrada en `historial`) y en `Info.plist` (`CFBundleShortVersionString` y `CFBundleVersion`).

## ¿Script o git hook?

**Script** (esto). Un git hook no encaja bien: los releases se hacen con `gh release create` (no con un push de tag que un hook intercepte), y las reviews son juicio de Claude/humano, no algo que un hook de shell pueda evaluar. El script deja **un solo comando auditable** con todos los gates. (Un `pre-push` que bloquee tags `v*` sería redundante y frágil aquí.)

## Certificado de firma

El updater solo instala un DMG firmado con el **mismo certificado** que la copia actual (`BetoDicta Self Signed`). Por eso los releases deben firmarse siempre con ese certificado (el `make` lo detecta si existe en el llavero; ver `scripts/crear-certificado.sh`). Su clave privada **nunca** sale del Mac del autor — es lo que impide que un release comprometido se instale.

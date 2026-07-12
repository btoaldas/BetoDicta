#!/usr/bin/env bash
#
# Pipeline de release de BetoDicta — GOBERNANZA (orden obligatorio).
#
#   1. Code review        (workflow de Claude — fuera de este script)
#   2. Security review     (workflow de Claude — fuera de este script)
#   3. Manual + README      al día con TODO lo del release
#   4. Build + verificar firma del bundle
#   5. Publicar release (DMG versionado + estable para brew)
#   6. Verificar: latest, brew (redirect 302), y que las novedades saldrán
#
# Los pasos 1 y 2 los ejecuta Claude (revisión adversarial de código y de
# seguridad) ANTES de correr esto; el script exige confirmarlos con flags para
# que no se salten. El resto se automatiza y se verifica.
#
# Uso:
#   scripts/release.sh --code-review-ok --security-review-ok [--notes "texto"]
#
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"

CODE_OK=0; SEC_OK=0; NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --code-review-ok) CODE_OK=1 ;;
    --security-review-ok) SEC_OK=1 ;;
    --notes) shift; NOTES="$1" ;;
    *) echo "flag desconocido: $1"; exit 2 ;;
  esac
  shift
done

fail() { echo "❌ $1"; exit 1; }
ok()   { echo "✅ $1"; }

# ── Gate 1 y 2: reviews (no automatizables — las hace Claude) ──────────────
[ "$CODE_OK" = 1 ] || fail "Falta code review. Córrela (workflow) y pasa --code-review-ok."
[ "$SEC_OK" = 1 ]  || fail "Falta security review. Córrela (workflow) y pasa --security-review-ok."
ok "Reviews confirmadas (código + seguridad)"

# Recordatorio (no bloquea): ¿los motores de terceros tienen versión nueva?
echo ""; echo "── Recordatorio: motores de terceros ──"
bash scripts/check-deps.sh 2>/dev/null || true
echo ""

# ── Versión coherente (Version.swift == Info.plist) ────────────────────────
VSWIFT=$(grep -Eo 'static let numero = "[^"]+"' Sources/BetoDicta/Version.swift | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
VPLIST=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
[ "$VSWIFT" = "$VPLIST" ] || fail "Versión no coincide: Version.swift=$VSWIFT vs Info.plist=$VPLIST"
V="$VSWIFT"
ok "Versión $V (Version.swift == Info.plist)"

# ── Gate 3: manual + README tocados en este ciclo (desde el último tag) ─────
git fetch --tags -q 2>/dev/null || true
LASTTAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LASTTAG" ]; then
  CH=$(git diff --name-only "$LASTTAG"..HEAD -- docs/MANUAL.md README.md | wc -l | tr -d ' ')
  [ "$CH" -gt 0 ] || fail "Manual/README NO cambiaron desde $LASTTAG. Actualízalos (gobernanza) antes del release."
  ok "Manual/README actualizados desde $LASTTAG"
fi
grep -q "$V" Sources/BetoDicta/Version.swift || fail "El historial de Version.swift no menciona $V"
ok "Historial de novedades incluye $V"

# ── Gate 4: build + verificar firma del bundle ─────────────────────────────
git tag | grep -qx "v$V" && fail "El tag v$V ya existe (¿versión sin subir?)"
make dmg >/tmp/bd-release.log 2>&1 || { tail -20 /tmp/bd-release.log; fail "make dmg falló"; }
DMG="build/BetoDicta-$V.dmg"
[ -f "$DMG" ] || fail "No se generó $DMG"
codesign -dvvv build/BetoDicta.app 2>&1 | grep -q "Authority=BetoDicta Self Signed" \
  || fail "El bundle NO quedó firmado con 'BetoDicta Self Signed' (revisa el certificado)"
ok "Bundle firmado con el certificado propio"

# ── Gate 4b: el DMG pasa la MISMA verificación de firma que el updater ──────
# (así nunca publicamos un DMG que la app instalada rechazaría al actualizar)
VOL=$(hdiutil attach -nobrowse -readonly -plist "$DMG" \
      | plutil -convert json -o - - | python3 -c "import sys,json;print(next(e['mount-point'] for e in json.load(sys.stdin)['system-entities'] if 'mount-point' in e))")
trap 'hdiutil detach "$VOL" >/dev/null 2>&1 || true' EXIT
if BETODICTA_VERIFYTEST="$VOL/BetoDicta.app" build/BetoDicta.app/Contents/MacOS/BetoDicta >/dev/null 2>&1; then
  ok "El DMG pasa la verificación de firma del updater (firmaConfiable)"
else
  fail "El .app del DMG NO pasa firmaConfiable — la app instalada lo rechazaría"
fi
hdiutil detach "$VOL" >/dev/null 2>&1 || true; trap - EXIT

# ── Gate 5: publicar (DMG versionado + estable para brew) ──────────────────
cp "$DMG" "build/BetoDicta.dmg"
NOTES="${NOTES:-Ver historial en Créditos.}"
gh release create "v$V" --title "BetoDicta $V" --notes "$NOTES" "$DMG" "build/BetoDicta.dmg" \
  || fail "gh release create falló"
ok "Release v$V publicado"

# ── Gate 6: verificación post-release (latest + brew) ──────────────────────
sleep 2
LATEST=$(gh api "repos/btoaldas/BetoDicta/releases/latest" --jq '.tag_name')
[ "$LATEST" = "v$V" ] || fail "latest=$LATEST (esperaba v$V)"
RED=$(curl -sI -o /dev/null -w "%{http_code} %{redirect_url}" https://github.com/btoaldas/BetoDicta/releases/latest/download/BetoDicta.dmg)
echo "$RED" | grep -q "v$V/BetoDicta.dmg" || fail "brew estable no apunta a v$V ($RED)"
ok "latest=v$V · brew estable → v$V"

echo ""
echo "🥅 Release v$V COMPLETO. La app instalada (versión anterior) verá 'Actualizar a v$V'"
echo "   y las novedades al actualizar. NO se instaló nada localmente."

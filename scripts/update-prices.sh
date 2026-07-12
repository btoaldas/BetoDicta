#!/usr/bin/env bash
#
# Actualiza los precios de los modelos de IA desde una FUENTE MANTENIDA
# (LiteLLM model_prices_and_context_window.json) — SIN usar IA/tokens.
# Escribe ~/.betodicta/precios_ia.json = { "modelo": [entrada_por_1M, salida_por_1M] }.
# La app lo lee y así CUALQUIER modelo tiene precio real (para las estadísticas
# de gasto). Correr de vez en cuando (o por el LaunchAgent).
#
# Uso: scripts/update-prices.sh
#
set -uo pipefail
DEST="$HOME/.betodicta/precios_ia.json"
URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
TMP="$(mktemp)"

# Descarga completa (el archivo es grande, ~1.6MB) con reintentos.
ok=0
for i in 1 2 3; do
  curl -s --max-time 60 --retry 2 "$URL" -o "$TMP" 2>/dev/null
  if python3 -c "import json;json.load(open('$TMP'))" 2>/dev/null; then ok=1; break; fi
  sleep 2
done
[ "$ok" = 1 ] || { echo "❌ no pude bajar/parsear la fuente de precios"; rm -f "$TMP"; exit 1; }

mkdir -p "$HOME/.betodicta"
python3 - "$TMP" "$DEST" <<'PY'
import json, sys, os
src = json.load(open(sys.argv[1]))
out = {}
for key, v in src.items():
    if not isinstance(v, dict): continue
    inp = v.get("input_cost_per_token"); o = v.get("output_cost_per_token")
    if inp is None or o is None: continue
    prov = v.get("litellm_provider", "")
    # id "desnudo" (quita SOLO el prefijo del proveedor: "groq/openai/gpt-oss-120b" → "openai/gpt-oss-120b")
    bare = key[len(prov) + 1:] if prov and key.startswith(prov + "/") else key
    # $ por 1M tokens (LiteLLM da $ por token)
    out[bare] = [round(inp * 1_000_000, 4), round(o * 1_000_000, 4)]
    # también guarda la clave completa por si el app usa el id con prefijo
    if bare != key: out.setdefault(key, out[bare])
json.dump(out, open(sys.argv[2], "w"))
os.chmod(sys.argv[2], 0o600)
print(f"✅ {len(out)} precios de modelos → {sys.argv[2]}")
PY
rm -f "$TMP"

if [ "${1:-}" = "--notify" ]; then
  n=$(python3 -c "import json;print(len(json.load(open('$DEST'))))" 2>/dev/null || echo "?")
  osascript - "Precios de IA actualizados ($n modelos)." >/dev/null 2>&1 <<'A' || true
on run argv
  display notification (item 1 of argv) with title "BetoDicta · precios"
end run
A
fi

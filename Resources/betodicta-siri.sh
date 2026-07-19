#!/bin/zsh
# Puente portable Siri/Atajos → turno limpio del asistente de BetoDicta.
# El Atajo firmado no contiene secretos: lee la capacidad local desde la
# configuración privada de esta Mac y abre únicamente la URL autenticada.
set -eu
umask 077

CONFIG="$HOME/.betodicta/config.json"
if [[ ! -f "$CONFIG" ]]; then
  print -u2 "Abre BetoDicta y configura primero el nombre de tu asistente."
  exit 2
fi

TOKEN="$(/usr/bin/plutil -extract agente_pasarela_siri_token raw "$CONFIG" 2>/dev/null || true)"
if [[ ! "$TOKEN" =~ '^[[:alnum:]]{32,128}$' ]]; then
  print -u2 "La pasarela local todavía no está preparada. Reinstálala desde BetoDicta."
  exit 3
fi

# Hook reproducible: valida lectura/formato sin abrir la app ni revelar el token.
if [[ "${BETODICTA_SIRI_DRY_RUN:-0}" == "1" ]]; then
  print "BETODICTA_SIRI_BRIDGE_OK"
  exit 0
fi

/usr/bin/open -g "betodicta://agente/escuchar?t=$TOKEN"
print "BetoDicta está listo para escucharte."

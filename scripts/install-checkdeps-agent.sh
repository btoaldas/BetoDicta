#!/usr/bin/env bash
#
# Instala (o quita) un LaunchAgent que revisa las actualizaciones de los
# motores de terceros AUTOMÁTICAMENTE: al iniciar sesión y cada lunes 10:00.
# Si hay novedades, lanza una NOTIFICACIÓN de macOS (no actualiza nada).
#
# Uso:
#   scripts/install-checkdeps-agent.sh            # instalar/activar
#   scripts/install-checkdeps-agent.sh uninstall  # quitar
#
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="ec.bto.betodicta.checkdeps"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/betodicta-checkdeps.log"

if [ "${1:-install}" = "uninstall" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "✅ LaunchAgent desinstalado ($LABEL)."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$REPO/scripts/check-deps.sh</string>
    <string>--notify</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>1</integer>
    <key>Hour</key><integer>10</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "✅ LaunchAgent activo: revisa dependencias al iniciar sesión y los LUNES 10:00."
echo "   Si hay novedades → notificación de macOS. Nunca actualiza solo."
echo "   Log:        $LOG"
echo "   Desinstalar: scripts/install-checkdeps-agent.sh uninstall"

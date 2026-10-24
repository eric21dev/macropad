#!/bin/bash
# Instala Macropad: compila la app, la copia a Aplicaciones, migra la configuración anterior, la abre y
# comprueba en vivo que el pad está conectado y que macOS ha concedido los permisos.
#   ./install.sh              instalar o actualizar
#   ./install.sh --uninstall  quitar la app (la configuración se conserva)
#   ./install.sh --purge      quitar la app y su configuración
set -euo pipefail
cd "$(dirname "$0")"
APP_NAME=Macropad; BUNDLE_ID=com.bugus.macropad
SUPPORT="$HOME/Library/Application Support/Macropad"
say() { printf '\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
ko() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

dest_dir() { if [ -w /Applications ]; then echo /Applications; else mkdir -p "$HOME/Applications"; echo "$HOME/Applications"; fi; }

if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "--purge" ]; then
  say "Quitando Macropad…"
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true; sleep 1; pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"
  tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true; tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  [ "${1:-}" = "--purge" ] && rm -rf "$SUPPORT" && echo "  Configuración borrada."
  ok "Hecho"; exit 0
fi

say "1/5 Requisitos"
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || { ko "Hace falta macOS 13 o superior"; exit 1; }
command -v swiftc >/dev/null || { ko "Falta swiftc. Instala las herramientas con:  xcode-select --install"; exit 1; }
ok "macOS $(sw_vers -productVersion), $(swiftc --version 2>&1 | head -1 | cut -c1-50)"

say "2/5 Versión anterior (demonio y web)"
U=$(id -u); found=0
for l in padd ui; do
  P="$HOME/Library/LaunchAgents/com.bugus.macropad.$l.plist"
  if [ -f "$P" ]; then launchctl bootout "gui/$U/com.bugus.macropad.$l" 2>/dev/null || true; rm -f "$P"; found=1; fi
done
pkill -f "macropad/padd" 2>/dev/null || true
[ $found = 1 ] && ok "Servicios antiguos retirados (la configuración se migra sola)" || ok "No había versión anterior"
if [ -e /etc/sudoers.d/macropad-led ] || [ -e /usr/local/bin/ch57x-keyboard-tool ]; then
  echo "  Ya no hace falta la regla sudoers del LED. Puedes quitarla con:"
  echo "    sudo rm -f /etc/sudoers.d/macropad-led /usr/local/bin/ch57x-keyboard-tool"
fi

say "3/5 Compilando"
./build.sh > /tmp/macropad-build.log 2>&1 || { ko "Falló la compilación (log: /tmp/macropad-build.log)"; tail -15 /tmp/macropad-build.log; exit 1; }
ok "Macropad.app compilada"

say "4/5 Instalando"
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true; sleep 1; pkill -x "$APP_NAME" 2>/dev/null || true
DEST="$(dest_dir)"; rm -rf "$DEST/$APP_NAME.app"; ditto build/$APP_NAME.app "$DEST/$APP_NAME.app"
ok "Instalada en $DEST/$APP_NAME.app"
rm -f "$SUPPORT/status.json"; mkdir -p "$SUPPORT"
open "$DEST/$APP_NAME.app"

say "5/5 Comprobando el pad y los permisos"
echo "  macOS va a pedir dos permisos para Macropad: Monitorización de entrada y Accesibilidad."
echo "  Concédelos en la ventana que se abre (o en Ajustes del Sistema → Privacidad y seguridad)."
get() { plutil -extract "$1" raw -o - "$SUPPORT/status.json" 2>/dev/null || echo false; }
last=""; for i in $(seq 1 120); do
  sleep 1; [ -f "$SUPPORT/status.json" ] || continue
  d=$(get device); inp=$(get input); ax=$(get accessibility); cur="$d$inp$ax"
  if [ "$cur" != "$last" ]; then
    last="$cur"; echo "  ── estado ──"
    [ "$d" = true ] && ok "Pad conectado (1189:8840)" || ko "Pad no detectado: conéctalo por USB y comprueba el interruptor ON/OFF"
    [ "$inp" = true ] && ok "Monitorización de entrada concedida" || ko "Falta Monitorización de entrada"
    [ "$ax" = true ] && ok "Accesibilidad concedida" || ko "Falta Accesibilidad"
  fi
  [ "$d$inp$ax" = "truetruetrue" ] && { say "Todo listo. Macropad queda en la barra de menú y se abre solo al iniciar sesión."; exit 0; }
done
echo
say "Instalada, pero faltan cosas por conceder (lista arriba)."
echo "Macropad sigue abierta: termina los permisos desde su ventana (pestaña Ajustes) y usa «Reiniciar Macropad» si hace falta."

#!/usr/bin/env bash
# Installs neo-login to $PREFIX/share/neo-login (default /usr/local). Does NOT edit /etc/greetd/config.toml.
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DEST="$PREFIX/share/neo-login"
SRC="$(cd "$(dirname "$0")" && pwd)/greetd-quickshell"

if [[ "${1:-}" == "--uninstall" ]]; then
  sudo rm -rf "$DEST"
  echo "Removed $DEST. /etc/neo-login/config.json (if present) was left in place."
  exit 0
fi

sudo install -d "$DEST" "$DEST/fonts"
sudo install -m 644 "$SRC/shell.qml" "$SRC/config.json" "$DEST/"
sudo install -m 644 "$SRC"/fonts/* "$DEST/fonts/"
sudo install -d /etc/neo-login
[[ -f /etc/neo-login/config.json ]] || sudo install -m 644 "$SRC/config.json" /etc/neo-login/config.json

cat <<MSG

Installed to $DEST
Config (overrides the bundled one): /etc/neo-login/config.json

1) Try it in a window first (demo mode: password "open", Esc quits):
   cage -s -- env QT_QPA_PLATFORM=wayland quickshell -p $DEST

2) Back up and edit /etc/greetd/config.toml; the [default_session] command should look like:
   command = "cage -s -- env QT_QPA_PLATFORM=wayland QT_WAYLAND_DISABLE_WINDOWDECORATION=1 quickshell -p $DEST"
   user = "greeter"
   (Some GPUs also need: env WLR_NO_HARDWARE_CURSORS=1 ... / QSG_RHI_BACKEND=opengl)

3) Keep a TTY (Ctrl+Alt+F3) handy for your first boot with it.
MSG

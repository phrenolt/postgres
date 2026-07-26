#!/usr/bin/env bash
# install-desktop-entry.sh — add a "pgAdmin 4" launcher to your desktop menu.
#
# Writes a freedesktop .desktop entry into ~/.local/share/applications that runs
# pgadmin-launch.sh (start the container if needed, wait for the port, open the
# browser). No root, no PATH changes, nothing outside your home dir.
#
#   ./install-desktop-entry.sh            # install / update the entry
#   ./install-desktop-entry.sh --remove   # uninstall it
#
# After installing, "pgAdmin 4" shows up in your application launcher; the first
# click prompts once for a login password (GUI dialog), every click after that
# just opens it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$HERE/pgadmin-launch.sh"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_FILE="$APPS_DIR/pgadmin4.desktop"
# Keep a square icon.png in sync with the source logo. Desktop icons render in a
# SQUARE box, so a non-square logo (e.g. 1080x607) gets squished. When ImageMagick
# is available we fit the newest logo.* onto a 512x512 transparent canvas —
# preserving aspect, no distortion — and (re)generate icon.png whenever the logo
# is newer or icon.png is missing. Skipped silently if no logo or no ImageMagick.
regen_icon() {
  local magick logo="" ext
  magick="$(command -v magick || command -v convert || true)"
  [ -n "$magick" ] || return 0
  for ext in png svg webp jpg jpeg; do
    [ -f "$HERE/logo.$ext" ] && { logo="$HERE/logo.$ext"; break; }
  done
  [ -n "$logo" ] || return 0
  if [ ! -f "$HERE/icon.png" ] || [ "$logo" -nt "$HERE/icon.png" ]; then
    "$magick" "$logo" -resize 512x512 -background none -gravity center \
      -extent 512x512 "$HERE/icon.png" 2>/dev/null \
      && echo "regenerated square icon.png from $(basename "$logo")" || true
  fi
}
regen_icon

# Icon resolution, in order of preference:
#   1. an explicit ICON=/path/to/icon
#   2. a purpose-made square icon.* (icons render in a SQUARE box, so a non-square
#      logo gets squished — icon.png is a padded square derived from the logo)
#   3. the raw logo.* as a fallback
#   4. a standard freedesktop icon name that exists in essentially every theme,
#      so the entry never shows a broken image.
# Note: webp/svg icons need the matching gdk-pixbuf loader installed; if the menu
# shows a blank icon, use a PNG or pass ICON=applications-databases.
if [ -z "${ICON:-}" ]; then
  ICON="applications-databases"
  for base in icon logo; do
    for ext in png svg webp jpg jpeg; do
      if [ -f "$HERE/$base.$ext" ]; then ICON="$HERE/$base.$ext"; break 2; fi
    done
  done
fi

if [ "${1:-}" = "--remove" ]; then
  rm -f "$DESKTOP_FILE"
  command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true
  echo "removed $DESKTOP_FILE"
  exit 0
fi

[ -f "$LAUNCHER" ] || { echo "missing launcher: $LAUNCHER" >&2; exit 1; }
chmod +x "$LAUNCHER"
mkdir -p "$APPS_DIR"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=pgAdmin 4
GenericName=PostgreSQL admin
Comment=Start the pgAdmin 4 container and open it in the browser
Exec=$LAUNCHER
Icon=$ICON
Terminal=false
Categories=Development;Database;
Keywords=postgres;postgresql;database;sql;pgadmin;
StartupNotify=true
EOF
chmod 644 "$DESKTOP_FILE"

# Validate if the freedesktop tools are around (non-fatal — a warning is fine).
command -v desktop-file-validate >/dev/null && desktop-file-validate "$DESKTOP_FILE" || true
# Refresh the menu cache so the entry appears without a re-login.
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null || true

echo "installed $DESKTOP_FILE"
echo "Look for \"pgAdmin 4\" in your application launcher (remove with: $0 --remove)."

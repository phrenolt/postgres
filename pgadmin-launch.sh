#!/usr/bin/env bash
# pgadmin-launch.sh — what the desktop entry actually runs.
#
# Makes pgAdmin reachable, then opens it in the browser. Safe to run repeatedly:
#   - container already provisioned -> just `podman start` it (no password needed;
#     pgAdmin's login lives in the persisted config volume after first run).
#   - not provisioned yet           -> first-time setup via run_pgadmin.sh, which
#     needs the pgAdmin login password once. Sourced from, in order:
#       PGADMIN_PASSWORD env  ->  a GUI dialog (zenity/kdialog)  ->  terminal prompt.
#
# After that first run the volume holds the login, so every later launch is a
# password-free `podman start`.
set -euo pipefail

CONTAINER_NAME="pgadmin"
# Keep in sync with run_pgadmin.sh (BIND_ADDR / LISTEN_PORT).
BIND_ADDR="127.0.0.1"
LISTEN_PORT="5050"
URL="http://${BIND_ADDR}:${LISTEN_PORT}"
HERE="$(cd "$(dirname "$0")" && pwd)"

command -v podman >/dev/null || { echo "podman not found on PATH" >&2; exit 1; }

# Ask for the pgAdmin login password (first run only). GUI first (the desktop
# entry has no terminal), then an interactive terminal, else a clear error.
prompt_password() {
  local pw=""
  if command -v zenity >/dev/null; then
    pw=$(zenity --password --title="pgAdmin — set login password (first run)" 2>/dev/null) || return 1
  elif command -v kdialog >/dev/null; then
    pw=$(kdialog --password "Set the pgAdmin login password (first run):") || return 1
  elif [ -t 0 ]; then
    read -rsp "Set the pgAdmin login password (first run): " pw && echo >&2
  else
    echo "First run needs a login password and no zenity/kdialog/terminal is available." >&2
    echo "Run this once from a terminal:  PGADMIN_PASSWORD=... ${HERE}/run_pgadmin.sh" >&2
    return 1
  fi
  [ -n "$pw" ] || { echo "empty password" >&2; return 1; }
  printf '%s' "$pw"
}

if podman container exists "$CONTAINER_NAME"; then
  # Already set up — just ensure it's running. No secrets required.
  podman start "$CONTAINER_NAME" >/dev/null 2>&1 || true
else
  if [ -z "${PGADMIN_PASSWORD:-}" ]; then
    PGADMIN_PASSWORD="$(prompt_password)" || exit 1
    export PGADMIN_PASSWORD
  fi
  "$HERE/run_pgadmin.sh"
fi

# Wait (up to ~30s) for the web UI to accept connections before opening it, so
# the browser doesn't land on a connection-refused page during cold start.
up=0
for _ in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/${BIND_ADDR}/${LISTEN_PORT}") 2>/dev/null; then
    exec 3>&- 3<&-
    up=1
    break
  fi
  # If the container has already died (e.g. bad config), stop waiting early.
  podman container exists "$CONTAINER_NAME" \
    && [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != true ] \
    && break
  sleep 1
done

if [ "$up" != 1 ]; then
  # Don't open a dead browser tab — surface the failure where a GUI user can see
  # it, with the log tail that explains why (this is how a crash-loop stops being
  # an invisible "nothing happens").
  logs="$(podman logs --tail 15 "$CONTAINER_NAME" 2>&1 || true)"
  msg="pgAdmin failed to come up on ${URL}.

Recent container log:
${logs}"
  if command -v zenity >/dev/null; then
    zenity --error --title="pgAdmin" --width=600 --text="$msg" 2>/dev/null || true
  elif command -v notify-send >/dev/null; then
    notify-send "pgAdmin failed to start" "See: podman logs $CONTAINER_NAME" || true
  fi
  echo "$msg" >&2
  exit 1
fi

# Open the browser robustly. When launched from a bare .desktop under Wayland/
# GNOME, xdg-open often silently no-ops (no inherited session bus / handler
# quirks) — which is the classic "clicked it, nothing happened". Try the DE's own
# opener first (gio, uses the session portal), then xdg-open, then at minimum
# TELL the user the URL via a dialog/notification so it's never a silent no-op.
open_url() {
  local url="$1"
  command -v gio      >/dev/null && gio open "$url"      >/dev/null 2>&1 && return 0
  command -v xdg-open >/dev/null && xdg-open "$url"      >/dev/null 2>&1 && return 0
  if command -v zenity >/dev/null; then
    zenity --info --title="pgAdmin" --text="pgAdmin is running at:\n${url}" 2>/dev/null || true
  elif command -v notify-send >/dev/null; then
    notify-send "pgAdmin is running" "$url" || true
  fi
  echo "Open $url"
}
open_url "$URL"

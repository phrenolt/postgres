#!/usr/bin/env bash
set -euo pipefail

echo "Starting pgAdmin 4 (Podman)..."

# --- Configuration ------------------------------------------------------------
CONTAINER_NAME="pgadmin"
# Pinned in lockstep with the DB server (run_postgresql.sh = postgres:18-alpine).
# pgAdmin 9.x supports PostgreSQL 18 — bump this and the server tag together.
IMAGE="docker.io/dpage/pgadmin4:9.16"
CONFIG_VOL="pgadmin_config"
# Runs in the HOST network namespace, so it reaches the DB (and any other Postgres
# you add) over host loopback — 127.0.0.1:<port> — rather than a container network.
# That's what lets one pgAdmin talk to several host-published databases at once.
LISTEN_PORT="5050"                 # pgAdmin listens here (non-privileged: no NET_BIND_SERVICE)
BIND_ADDR="127.0.0.1"              # bind the web UI to host loopback ONLY, never the wire
HERE="$(cd "$(dirname "$0")" && pwd)"
SERVERS_JSON="$HERE/servers.json"

# Client-only mode: launch a bare pgAdmin with NO pre-provisioned server, for
# when you just want the UI and will add connections yourself (or the DB is
# offline and you don't want a dead entry in the tree). Enable with either:
#   PGADMIN_NO_SERVERS=1 ./run_pgadmin.sh    or    ./run_pgadmin.sh --no-servers
# (A missing servers.json also just falls back to this — it's never fatal.)
NO_SERVERS="${PGADMIN_NO_SERVERS:-0}"
[ "${1:-}" = "--no-servers" ] && NO_SERVERS=1

# pgAdmin's OWN login (the app's auth, NOT any database password). The email is
# just the login username, but pgAdmin runs it through a real email-address
# validator at startup and REFUSES to boot on a bad one (e.g. 'admin@local'
# fails: the domain needs a dot). Default to a valid form.
PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@example.com}"

# --- Preflight ----------------------------------------------------------------
command -v podman >/dev/null || { echo "podman not found on PATH" >&2; exit 1; }
# Decide whether we pre-provision a server. servers.json is only a bookmark, so
# its absence (or --no-servers) is fine — pgAdmin just starts with an empty tree.
if [ "$NO_SERVERS" = 1 ]; then
  PRELOAD=0
  echo "client-only mode: no server will be pre-provisioned."
elif [ -f "$SERVERS_JSON" ]; then
  PRELOAD=1
else
  PRELOAD=0
  echo "note: $SERVERS_JSON not found — starting a bare client (add servers from the UI)."
fi

# Persist pgAdmin's own config/state (users, saved servers, session, storage).
# :U recursively chowns the volume to pgAdmin's mapped uid so it's writable under
# rootless podman (the entrypoint runs non-root and can't chown it itself).
#
# The login password is ONLY consumed on the first init of this volume; after
# that pgAdmin uses the stored account and IGNORES PGADMIN_DEFAULT_PASSWORD. So:
#   - first run (no volume)  -> DEMAND a real password; it becomes your login.
#   - later runs (volume set) -> the image still requires the var to be non-empty,
#                                so pass a throwaway that pgAdmin discards.
# This is why re-running never changes your password, and why you should never be
# re-prompted for one.
if podman volume exists "$CONFIG_VOL"; then
  FIRST_RUN=0
  PGADMIN_PASSWORD="${PGADMIN_PASSWORD:-ignored-after-first-init}"
else
  FIRST_RUN=1
  : "${PGADMIN_PASSWORD:?first run: set PGADMIN_PASSWORD — this becomes your pgAdmin login password}"
  podman volume create "$CONFIG_VOL" >/dev/null
fi

# --- Run ----------------------------------------------------------------------
# The servers.json pre-provision is only added when PRELOAD=1 (see preflight),
# so a bare/offline launch carries no server mount or env at all.
SERVER_ARGS=()
if [ "$PRELOAD" = 1 ]; then
  SERVER_ARGS=(
    -e PGADMIN_SERVER_JSON_FILE="/pgadmin4/servers.json"
    -v "$SERVERS_JSON:/pgadmin4/servers.json:ro,Z"
  )
fi

# Locked down: no new privileges, all caps dropped (it binds a non-privileged
# port and runs as a non-root user, so it needs none), resource caps. Rootfs is
# left writable on purpose — pgAdmin writes state across its tree in ways that
# vary by version, and its persistent data already lives in the named volume.
podman run -d \
  --name "$CONTAINER_NAME" \
  --replace \
  --network host \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  --memory="512m" \
  --pids-limit=200 \
  -e PGADMIN_DEFAULT_EMAIL="$PGADMIN_EMAIL" \
  -e PGADMIN_DEFAULT_PASSWORD="$PGADMIN_PASSWORD" \
  -e PGADMIN_LISTEN_ADDRESS="$BIND_ADDR" \
  -e PGADMIN_LISTEN_PORT="$LISTEN_PORT" \
  "${SERVER_ARGS[@]}" \
  -v "$CONFIG_VOL:/var/lib/pgadmin:Z,U" \
  "$IMAGE"

echo "pgAdmin is starting."
echo "  URL:    http://${BIND_ADDR}:${LISTEN_PORT}"
if [ "$FIRST_RUN" = 1 ]; then
  echo "  Login:  ${PGADMIN_EMAIL}  (password: the PGADMIN_PASSWORD you just set)"
else
  echo "  Login:  ${PGADMIN_EMAIL}  (password: the one from your first run — unchanged)"
fi
if [ "$PRELOAD" = 1 ]; then
  cat <<EOF

The pre-loaded server asks for the DATABASE password on first connect. If it's
the local hardened Postgres, that password is the random podman secret:
  podman exec postgres-alpine cat /run/secrets/pg_super_pass

Note: servers.json is imported only when the config volume is first created. To
re-import after editing it, remove the volume: podman volume rm ${CONFIG_VOL}
EOF
else
  echo "  (client-only: no server pre-loaded — add connections from the UI)"
fi

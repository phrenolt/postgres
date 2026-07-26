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

# pgAdmin's OWN login (the app's auth, NOT any database password). Supply the
# password via env so it never lives in this file or in `podman inspect` history
# baked into an image. Email has a sane default you can override.
PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@local}"
: "${PGADMIN_PASSWORD:?set PGADMIN_PASSWORD in the environment before running (pgAdmin login password)}"

# --- Preflight ----------------------------------------------------------------
command -v podman >/dev/null || { echo "podman not found on PATH" >&2; exit 1; }
[ -f "$SERVERS_JSON" ] || { echo "missing $SERVERS_JSON (pre-provisioned connection)" >&2; exit 1; }

# Persist pgAdmin's own config/state (users, saved servers, session, storage).
# :U recursively chowns the volume to pgAdmin's mapped uid so it's writable under
# rootless podman (the entrypoint runs non-root and can't chown it itself).
podman volume exists "$CONFIG_VOL" || podman volume create "$CONFIG_VOL" >/dev/null

# --- Run ----------------------------------------------------------------------
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
  -e PGADMIN_SERVER_JSON_FILE="/pgadmin4/servers.json" \
  -v "$CONFIG_VOL:/var/lib/pgadmin:Z,U" \
  -v "$SERVERS_JSON:/pgadmin4/servers.json:ro,Z" \
  "$IMAGE"

cat <<EOF
pgAdmin is starting.
  URL:    http://${BIND_ADDR}:${LISTEN_PORT}
  Login:  ${PGADMIN_EMAIL}  (password: the PGADMIN_PASSWORD you set)

The 'postgres-alpine' server is pre-loaded. It'll ask for the DATABASE password
on first connect — that's the random podman secret; read it with:
  podman exec postgres-alpine cat /run/secrets/pg_super_pass

Note: servers.json is imported only when the config volume is first created. To
re-import after editing it, remove the volume: podman volume rm ${CONFIG_VOL}
EOF

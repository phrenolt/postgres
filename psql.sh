#!/usr/bin/env bash
# psql.sh — open a psql shell on the hardened Postgres, with zero host deps.
#
# Runs psql *inside* the running server container (podman exec), so you need no
# psql on the host and no password: the connection goes over the container's local
# unix socket, which the official image trusts. Any extra args pass straight to
# psql, so this doubles as a one-shot query runner:
#
#   ./psql.sh                         # interactive shell
#   ./psql.sh -c 'select version();'  # one-off command
#   ./psql.sh -f /path/in/container.sql
#
# Reaches THIS project's database. For a different server, connect from the pgAdmin
# UI or point a host psql at 127.0.0.1:5432 (the published loopback port).
set -euo pipefail

# Keep in sync with run_postgresql.sh (CONTAINER_NAME / POSTGRES_USER / POSTGRES_DB).
CONTAINER_NAME="postgres-alpine"
DB_USER="db_admin"
DB_NAME="app_database"

command -v podman >/dev/null || { echo "podman not found on PATH" >&2; exit 1; }
if ! podman container exists "$CONTAINER_NAME" \
   || [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != true ]; then
  echo "'$CONTAINER_NAME' is not running — start it first with: ./run_postgresql.sh" >&2
  exit 1
fi

# -it for an interactive TTY; harmless for one-shot -c/-f too.
exec podman exec -it "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" "$@"

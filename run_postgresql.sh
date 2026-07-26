#!/usr/bin/env bash
set -euo pipefail

echo "Starting hardened PostgreSQL Podman deployment..."

# Configuration Variables
CONTAINER_NAME="postgres-alpine"
# Pinned in lockstep with the pgAdmin client (run_pgadmin.sh; pgAdmin 9.x
# supports PostgreSQL 18). Bump both together so client/server stay compatible.
IMAGE="docker.io/library/postgres:18-alpine"
PGDATA_VOL="pg_data_secure"
INIT_DIR="$(pwd)/initdb.d"
NETWORK_NAME="pg-isolated-net"
# Publish to host loopback so host-side tools (pgAdmin, psql) can connect. Bound
# to 127.0.0.1 ONLY — never on the wire. The container stays on the --internal
# network (no outbound internet); a published port is a separate host->container
# path and does not give the container egress.
HOST_BIND="127.0.0.1:5432"

# 1. Create initialization directory if it doesn't exist
mkdir -p "$INIT_DIR"

# 2. Setup Podman Secret for the Superuser Password
# (If the secret doesn't exist, create it with a secure random string)
if ! podman secret exists pg_super_pass; then
  echo "Generating secure superuser password and storing as Podman secret..."
  openssl rand -base64 32 | podman secret create pg_super_pass -
fi

# 3. Create an isolated container network (no external bridge access)
if ! podman network exists "$NETWORK_NAME"; then
  podman network create "$NETWORK_NAME" --internal
fi

# 4. Create a persistent volume
if ! podman volume exists "$PGDATA_VOL"; then
  podman volume create "$PGDATA_VOL"
fi

# 5. Run the hardened container
# NOTE: The Alpine Postgres image runs as the 'postgres' user internally.
# NOTE: PG18's image moved PGDATA into a version-scoped subdir and ERRORS if the
# volume is mounted at the legacy /var/lib/postgresql/data. Mount the PARENT
# (/var/lib/postgresql) instead.
# NOTE: POSTGRES_HOST_AUTH_METHOD=scram-sha-256 makes the entrypoint write a
# `host all all all scram-sha-256` pg_hba rule on first init. It's required for
# host tools (pgAdmin/psql) hitting the published loopback port: rootless
# netavark SNATs that connection, so Postgres sees it arriving from the
# container's own subnet IP (e.g. 10.89.x.x), NOT 127.0.0.1 — the default
# 127.0.0.1/32-only rules never match it. Still password-gated (scram); the port
# is loopback-only, so only host-local processes can reach it in the first place.
podman run -d \
  --name "$CONTAINER_NAME" \
  --replace \
  --network "$NETWORK_NAME" \
  -p "$HOST_BIND:5432" \
  --secret pg_super_pass \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid \
  --tmpfs /var/run/postgresql:rw,noexec,nosuid \
  --cap-drop=ALL \
  --cap-add=CHOWN,DAC_OVERRIDE,FOWNER,SETGID,SETUID \
  --security-opt=no-new-privileges \
  --cpus="1.5" \
  --memory="1g" \
  --pids-limit=100 \
  -e POSTGRES_PASSWORD_FILE="/run/secrets/pg_super_pass" \
  -e POSTGRES_USER="db_admin" \
  -e POSTGRES_DB="app_database" \
  -e POSTGRES_HOST_AUTH_METHOD="scram-sha-256" \
  -v "$PGDATA_VOL:/var/lib/postgresql:Z" \
  -v "$INIT_DIR:/docker-entrypoint-initdb.d:ro,Z" \
  "$IMAGE" \
  -c "listen_addresses=*" \
  -c "log_statement=mod" \
  -c "log_connections=on" \
  -c "log_disconnections=on" \
  -c "password_encryption=scram-sha-256"

echo "PostgreSQL container '$CONTAINER_NAME' is running."

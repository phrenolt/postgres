#!/usr/bin/env bash
set -euo pipefail

echo "Starting hardened PostgreSQL Podman deployment..."

# Configuration Variables
CONTAINER_NAME="postgres-alpine"
IMAGE="postgres:18.4-alpine"
PGDATA_VOL="pg_data_secure"
INIT_DIR="$(pwd)/initdb.d"
NETWORK_NAME="pg-isolated-net"

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
podman run -d \
  --name "$CONTAINER_NAME" \
  --replace \
  --network "$NETWORK_NAME" \
  --secret pg_super_pass \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid \
  --tmpfs /var/run/postgresql:rw,noexec,nosuid \
  --cap-drop=ALL \
  --cap-add=CHOWN,SETGID,SETUID,DAC_OVERRIDE \
  --security-opt=no-new-privileges \
  --cpus="1.5" \
  --memory="1g" \
  --pids-limit=100 \
  -e POSTGRES_PASSWORD_FILE="/run/secrets/pg_super_pass" \
  -e POSTGRES_USER="db_admin" \
  -e POSTGRES_DB="app_database" \
  -v "$PGDATA_VOL:/var/lib/postgresql/data:Z" \
  -v "$INIT_DIR:/docker-entrypoint-initdb.d:ro,Z" \
  "$IMAGE" \
  -c "listen_addresses='*'" \
  -c "log_statement='mod'" \
  -c "log_connections='on'" \
  -c "log_disconnections='on'" \
  -c "password_encryption='scram-sha-256'"

echo "PostgreSQL container '$CONTAINER_NAME' is running."

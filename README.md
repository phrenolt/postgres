# postgres

Hardened, rootless PostgreSQL on Podman, plus a pgAdmin 4 web client.

## What's here

- **`run_postgresql.sh`** — starts `postgres:18-alpine` locked down: password from a
  Podman secret, read-only rootfs, all caps dropped (bar the five the entrypoint
  needs), no-new-privileges, resource limits, and an `--internal` network (no
  outbound internet). Data persists in the `pg_data_secure` volume. The server is
  published on **host loopback only** (`127.0.0.1:5432`) so local tools can reach it
  without exposing it on the wire.
- **`run_pgadmin.sh`** + **`servers.json`** — pgAdmin 4 (pinned `9.16`, supports
  PostgreSQL 18) running in the host network namespace with its web UI bound to
  `127.0.0.1:5050`. `servers.json` pre-loads the local server; add more from the UI.

## Usage

```bash
./run_postgresql.sh
PGADMIN_PASSWORD='choose-a-login-password' ./run_pgadmin.sh
```

Then open <http://127.0.0.1:5050>. On first connect to the pre-loaded server it
asks for the database password (the random Podman secret):

```bash
podman exec postgres-alpine cat /run/secrets/pg_super_pass
```

Versions are pinned in lockstep — bump the Postgres tag in `run_postgresql.sh` and
the pgAdmin tag in `run_pgadmin.sh` together so client and server stay compatible.

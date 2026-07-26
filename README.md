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
- **`pgadmin-launch.sh`** + **`install-desktop-entry.sh`** — optional desktop
  integration. The installer drops a "pgAdmin 4" entry into your application menu
  that runs the launcher: it starts the container if needed, waits for the port,
  and opens the browser. First launch prompts once for the pgAdmin login password
  (GUI dialog); later launches just open it.

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

You don't need the DB running to launch pgAdmin — `servers.json` is just a
bookmark, imported once; an offline server only errors *in the UI* when you
expand it, never at startup. For a bare client with nothing pre-loaded:

```bash
PGADMIN_PASSWORD='...' ./run_pgadmin.sh --no-servers   # or PGADMIN_NO_SERVERS=1
```

(A missing `servers.json` also just falls back to a bare client — never fatal.)

To add a launcher to your desktop menu (optional):

```bash
./install-desktop-entry.sh            # install (creates ~/.local/share/applications/pgadmin4.desktop)
./install-desktop-entry.sh --remove   # uninstall
```

Versions are pinned in lockstep — bump the Postgres tag in `run_postgresql.sh` and
the pgAdmin tag in `run_pgadmin.sh` together so client and server stay compatible.

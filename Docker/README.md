# Docker compose troubleshooting (Guacamole)

If Guacamole loads but shows:

> An error has occurred and this action cannot be completed...

the two most common causes are:

1. `GUAC_DB_PASSWORD` is missing from your compose environment.
2. The Guacamole PostgreSQL schema has not been initialized yet.

## 1) Ensure environment values are set

From this folder, create `.env` from `.env.example` and set a real `GUAC_DB_PASSWORD`:

```bash
cp .env.example .env
```

## 2) Start services

```bash
docker compose up -d
```

## 3) Initialize Guacamole DB schema (first run)

Run once after the containers are up:

```bash
./init-guac-db.sh
```

PowerShell variant (Windows):

```powershell
./init-guac-db.ps1
```

This runs Guacamole's built-in `initdb.sh --postgresql` and pipes the SQL into the `postgres` service.

## 4) Restart Guacamole

```bash
docker compose restart guacamole
```

## 5) Check logs if needed

```bash
docker compose logs -f postgres guacamole
```


If your database service name is different (for example `postgresql`), pass it explicitly:

```powershell
./init-guac-db.ps1 -DbService postgresql
```

```bash
GUAC_DB_SERVICE=postgresql ./init-guac-db.sh
```

If `guacamole` is stuck restarting, run:

```bash
docker compose logs --tail=200 guacamole postgres
```

A common cause is missing/empty `GUAC_DB_PASSWORD`; the compose file now fails fast if it is not set.

If the PowerShell script reports no SQL output, the `guacamole` service may be restarting too quickly for `exec`.
The scripts now fall back to `docker compose run --rm --no-deps guacamole /opt/guacamole/bin/initdb.sh --postgresql` automatically.



If you previously saw `Bad database type: --postgres`, that indicates an older script version.
Use the current scripts, which call `initdb.sh --postgresql`.


If Guacamole still reports `relation "guacamole_user" does not exist` after running init, run:

```bash
docker compose exec -T postgres psql -U guacamole_user -d guacamole_db -c "SELECT to_regclass('public.guacamole_user');"
```

Expected output is `guacamole_user`. If it is empty/null, the schema did not apply to the target DB.


If verification fails immediately after apply, the script now checks that generated output contains expected SQL (`CREATE TABLE ... guacamole_user`).
If that check fails, review the preview text in script output and container logs:

```bash
docker compose logs --tail=200 guacamole postgres
```

The sanity check looks for both `CREATE TABLE` and `guacamole_user` anywhere in generated SQL output (not necessarily on the same line).

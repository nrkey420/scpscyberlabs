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

This runs Guacamole's built-in `initdb.sh --postgres` and pipes the SQL into the `postgres` service.

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
The scripts now fall back to `docker compose run --rm --no-deps guacamole /opt/guacamole/bin/initdb.sh --postgres` automatically.


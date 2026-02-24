#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
DB_NAME="${GUAC_DB_NAME:-guacamole_db}"
DB_USER="${GUAC_DB_USER:-guacamole_user}"
GUAC_SERVICE="${GUAC_SERVICE:-guacamole}"
DB_SERVICE="${GUAC_DB_SERVICE:-postgres}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI is required." >&2
  exit 1
fi

echo "Generating Guacamole PostgreSQL init SQL..."

# Prefer exec when service is running; fallback to one-off run when restarting/unhealthy.
set +e
init_sql="$(docker compose -f "$COMPOSE_FILE" exec -T "$GUAC_SERVICE" /opt/guacamole/bin/initdb.sh --postgres 2>/dev/null)"
set -e

if [[ -z "${init_sql// }" ]]; then
  echo "No SQL from 'exec'; falling back to one-off container run..."
  init_sql="$(docker compose -f "$COMPOSE_FILE" run --rm --no-deps "$GUAC_SERVICE" /opt/guacamole/bin/initdb.sh --postgres)"
fi

if [[ -z "${init_sql// }" ]]; then
  echo "Unable to generate Guacamole init SQL. Check: docker compose logs $GUAC_SERVICE" >&2
  exit 1
fi

echo "Applying Guacamole schema to PostgreSQL..."
printf '%s
' "$init_sql" | docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$DB_NAME"

echo "Guacamole schema initialization complete."

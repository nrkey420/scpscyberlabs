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
init_sql="$(docker compose -f "$COMPOSE_FILE" exec -T "$GUAC_SERVICE" /opt/guacamole/bin/initdb.sh --postgresql 2>/dev/null)"
exec_rc=$?
set -e

if [[ $exec_rc -ne 0 || -z "${init_sql// }" ]]; then
  echo "No SQL from 'exec'; falling back to one-off container run..."
  init_sql="$(docker compose -f "$COMPOSE_FILE" run --rm --no-deps "$GUAC_SERVICE" /opt/guacamole/bin/initdb.sh --postgresql)"
fi

if [[ -z "${init_sql// }" ]]; then
  echo "Unable to generate Guacamole init SQL. Check: docker compose logs $GUAC_SERVICE" >&2
  exit 1
fi

if ! grep -qi "CREATE TABLE.*guacamole_user" <<<"$init_sql"; then
  echo "Generated output does not look like Guacamole schema SQL." >&2
  echo "Preview:" >&2
  printf '%s\n' "${init_sql:0:400}" >&2
  exit 1
fi

echo "Applying Guacamole schema to PostgreSQL..."
printf '%s
' "$init_sql" | docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME"

echo "Verifying Guacamole schema..."
check_table="$(docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" psql -tA -U "$DB_USER" -d "$DB_NAME" -c "SELECT to_regclass('public.guacamole_user');" | tr -d '\r')"

if [[ "$check_table" != "guacamole_user" ]]; then
  echo "Schema verification failed: table 'guacamole_user' was not found in database '$DB_NAME'." >&2
  echo "Check DB service/name/user values and then inspect logs: docker compose logs $DB_SERVICE $GUAC_SERVICE" >&2
  exit 1
fi

echo "Guacamole schema initialization complete and verified."

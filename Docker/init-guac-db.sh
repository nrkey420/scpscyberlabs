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

echo "Initializing Guacamole schema in PostgreSQL..."

docker compose -f "$COMPOSE_FILE" exec -T "$GUAC_SERVICE" /opt/guacamole/bin/initdb.sh --postgres \
  | docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$DB_NAME"

echo "Guacamole schema initialization complete."

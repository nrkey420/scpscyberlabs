param(
    [string]$ComposeFile = "docker-compose.yml",
    [string]$DbName = "guacamole_db",
    [string]$DbUser = "guacamole_user",
    [string]$GuacService = "guacamole",
    [string]$DbService = "postgres"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker CLI is required."
}

Write-Host "Generating Guacamole PostgreSQL init SQL..."

# Prefer exec when service is running; fallback to one-off run when restarting/unhealthy.
$initSql = docker compose -f $ComposeFile exec -T $GuacService /opt/guacamole/bin/initdb.sh --postgres 2>$null

if ([string]::IsNullOrWhiteSpace($initSql)) {
    Write-Host "No SQL from 'exec'; falling back to one-off container run..."
    $initSql = docker compose -f $ComposeFile run --rm --no-deps $GuacService /opt/guacamole/bin/initdb.sh --postgres
}

if ([string]::IsNullOrWhiteSpace($initSql)) {
    throw "Unable to generate Guacamole init SQL. Check 'docker compose logs $GuacService'."
}

Write-Host "Applying Guacamole schema to PostgreSQL..."
$initSql | docker compose -f $ComposeFile exec -T $DbService psql -U $DbUser -d $DbName

Write-Host "Guacamole schema initialization complete."

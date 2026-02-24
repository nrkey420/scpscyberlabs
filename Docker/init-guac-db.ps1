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
$initSql = docker compose -f $ComposeFile exec -T $GuacService /opt/guacamole/bin/initdb.sh --postgresql 2>$null
$execCode = $LASTEXITCODE

if ($execCode -ne 0 -or [string]::IsNullOrWhiteSpace($initSql)) {
    Write-Host "No SQL from 'exec'; falling back to one-off container run..."
    $initSql = docker compose -f $ComposeFile run --rm --no-deps $GuacService /opt/guacamole/bin/initdb.sh --postgresql
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to generate Guacamole init SQL from one-off container run. Check 'docker compose logs $GuacService'."
    }
}

if ([string]::IsNullOrWhiteSpace($initSql)) {
    throw "Unable to generate Guacamole init SQL. Check 'docker compose logs $GuacService'."
}

Write-Host "Applying Guacamole schema to PostgreSQL..."
$tmp = New-TemporaryFile
try {
    Set-Content -Path $tmp -Value $initSql -NoNewline
    Get-Content -Raw $tmp | docker compose -f $ComposeFile exec -T $DbService psql -v ON_ERROR_STOP=1 -U $DbUser -d $DbName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply Guacamole schema to PostgreSQL. Check 'docker compose logs $DbService'."
    }
}
finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "Guacamole schema initialization complete."

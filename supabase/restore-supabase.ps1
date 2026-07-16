[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateScript({ Test-Path $_ -PathType Container })][string]$BackupPath,
  [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]{20}$')][string]$TargetProjectRef,
  [securestring]$TargetDbPassword,
  [switch]$AllowNonEmptyTarget
)

$ErrorActionPreference = 'Stop'

function Invoke-Supabase {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  & supabase @Arguments
  if ($LASTEXITCODE -ne 0) { throw 'A Supabase CLI command failed. See the preceding command output.' }
}

function Get-PlainText {
  param([Parameter(Mandatory = $true)][securestring]$Value)
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Get-LinkedDatabaseConnection {
  param([Parameter(Mandatory = $true)][string]$Password)
  $dryRun = & supabase db dump --linked --password $Password --data-only --dry-run
  if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve the linked target database connection.' }
  $text = $dryRun -join "`n"
  $dbHost = [regex]::Match($text, 'export PGHOST="([^"]+)"').Groups[1].Value
  $port = [regex]::Match($text, 'export PGPORT="([^"]+)"').Groups[1].Value
  $user = [regex]::Match($text, 'export PGUSER="([^"]+)"').Groups[1].Value
  $database = [regex]::Match($text, 'export PGDATABASE="([^"]+)"').Groups[1].Value
  if ([string]::IsNullOrWhiteSpace($dbHost) -or [string]::IsNullOrWhiteSpace($user)) { throw 'Unable to parse the target database connection.' }
  return @{ Host = $dbHost; Port = $port; User = $user; Database = $database }
}

function Test-DockerReady {
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & docker version --format '{{.Server.Version}}' *> $null
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
  return ($exitCode -eq 0)
}

function Invoke-PsqlFile {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Connection,
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$File,
    [string[]]$ExtraArguments = @()
  )
  $backupSubdirectory = Split-Path (Split-Path $File -Parent) -Leaf
  $containerFile = "/backup/$backupSubdirectory/$([IO.Path]::GetFileName($File))"
  & docker run --rm -v "${BackupPath}:/backup:ro" -e "PGPASSWORD=$Password" postgres:17-alpine `
    psql "host=$($Connection.Host) port=$($Connection.Port) dbname=$($Connection.Database) user=$($Connection.User) sslmode=require" `
    --single-transaction --variable ON_ERROR_STOP=1 @ExtraArguments --file $containerFile
  if ($LASTEXITCODE -ne 0) { throw "Database restore failed for $File" }
}

if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) { throw 'Supabase CLI is required.' }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  $dockerBin = 'C:\Program Files\Docker\Docker\resources\bin'
  if (Test-Path (Join-Path $dockerBin 'docker.exe')) { $env:Path = "$dockerBin;$env:Path" }
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop is required for the database restore.' }
if (-not (Test-DockerReady)) { throw 'Docker Desktop is installed but not running.' }

$manifestPath = Join-Path $BackupPath 'manifest.json'
$databasePath = Join-Path $BackupPath 'database'
foreach ($required in @($manifestPath, (Join-Path $databasePath 'roles.sql'), (Join-Path $databasePath 'schema.sql'), (Join-Path $databasePath 'data.sql'))) {
  if (-not (Test-Path $required)) { throw "Invalid backup: missing $required" }
}
if (-not $TargetDbPassword) { $TargetDbPassword = Read-Host 'Target Supabase database password' -AsSecureString }
$plainPassword = Get-PlainText $TargetDbPassword

try {
  $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
  Write-Warning "This writes backup '$($manifest.created_at)' to target project $TargetProjectRef. Use a new, empty project unless -AllowNonEmptyTarget is explicitly supplied."
  $confirmation = Read-Host "Type the target project ref ($TargetProjectRef) to continue"
  if ($confirmation -ne $TargetProjectRef) { throw 'Restore cancelled.' }

  Invoke-Supabase @('link', '--project-ref', $TargetProjectRef, '--password', $plainPassword)
  $connection = Get-LinkedDatabaseConnection $plainPassword
  $tableCheck = & supabase db query --linked --agent=no --output json "select count(*)::int as count from pg_tables where schemaname = 'public'"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to check whether the target project is empty.' }
  $tableJson = [regex]::Match(($tableCheck -join "`n"), '\[[\s\S]*\]').Value
  $publicTableCount = if ($tableJson) { (($tableJson | ConvertFrom-Json)[0].count) } else { 0 }
  if (($publicTableCount -gt 0) -and -not $AllowNonEmptyTarget) {
    throw "Target project already has $publicTableCount public tables. Refusing to merge. Create an empty project or rerun with -AllowNonEmptyTarget after confirming the consequences."
  }

  Write-Host 'Restoring database roles, schema, and data...'
  Invoke-PsqlFile -Connection $connection -Password $plainPassword -File (Join-Path $databasePath 'roles.sql')
  Invoke-PsqlFile -Connection $connection -Password $plainPassword -File (Join-Path $databasePath 'schema.sql')
  $managedSchemaChanges = Join-Path $databasePath 'managed-schema-changes.sql'
  if ((Test-Path $managedSchemaChanges) -and ((Get-Item $managedSchemaChanges).Length -gt 0)) {
    Invoke-PsqlFile -Connection $connection -Password $plainPassword -File $managedSchemaChanges
  }
  Invoke-PsqlFile -Connection $connection -Password $plainPassword -File (Join-Path $databasePath 'data.sql') -ExtraArguments @('--command', 'SET session_replication_role = replica')
  $migrationHistorySchema = Join-Path $databasePath 'migration-history-schema.sql'
  $migrationHistoryData = Join-Path $databasePath 'migration-history-data.sql'
  if ((Test-Path $migrationHistorySchema) -and (Test-Path $migrationHistoryData)) {
    Invoke-PsqlFile -Connection $connection -Password $plainPassword -File $migrationHistorySchema
    Invoke-PsqlFile -Connection $connection -Password $plainPassword -File $migrationHistoryData
  }

  $realtimePath = Join-Path $BackupPath 'metadata\realtime-publication-tables.json'
  if (Test-Path $realtimePath) {
    $realtimeJson = [regex]::Match((Get-Content -Raw $realtimePath), '\[[\s\S]*\]').Value
    $realtimeTables = if ($realtimeJson) { @($realtimeJson | ConvertFrom-Json) } else { @() }
    foreach ($table in $realtimeTables) {
      if (($table.schemaname -notmatch '^[A-Za-z_][A-Za-z0-9_$]*$') -or ($table.tablename -notmatch '^[A-Za-z_][A-Za-z0-9_$]*$')) {
        throw 'Invalid Realtime table identifier in the backup metadata.'
      }
      Invoke-Supabase @('db', 'query', '--linked', "alter publication supabase_realtime add table `"$($table.schemaname)`".`"$($table.tablename)`"")
    }
  }

  $storagePath = Join-Path $BackupPath 'storage'
  if (Test-Path $storagePath) {
    Get-ChildItem -Path $storagePath -Directory | ForEach-Object {
      Write-Host "Uploading Storage bucket '$($_.Name)'..."
      Invoke-Supabase @('storage', 'cp', $_.FullName, "ss:///$($_.Name)", '--recursive', '--experimental', '--jobs', '4')
    }
  }

  $functionsPath = Join-Path $BackupPath 'functions'
  $functionMetadataPath = Join-Path $BackupPath 'metadata\functions.json'
  if ((Test-Path $functionsPath) -and (Test-Path $functionMetadataPath)) {
    $stage = Join-Path ([IO.Path]::GetTempPath()) "supabase-restore-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path (Join-Path $stage 'supabase') -Force | Out-Null
    Copy-Item -Path $functionsPath -Destination (Join-Path $stage 'supabase\functions') -Recurse -Force
    $functions = Get-Content -Raw $functionMetadataPath | ConvertFrom-Json
    foreach ($function in $functions) {
      $arguments = @('functions', 'deploy', $function.slug, '--project-ref', $TargetProjectRef, '--use-api', '--workdir', $stage)
      if ($function.verify_jwt -eq $false) { $arguments += '--no-verify-jwt' }
      Invoke-Supabase $arguments
    }
    Remove-Item -LiteralPath $stage -Recurse -Force
  }

  Write-Host 'Restore completed.' -ForegroundColor Green
  Write-Warning 'Before using Edge Functions, restore the secret values listed in metadata/edge-function-secret-names.json. Supabase deliberately does not allow existing secret values to be exported.'
}
finally {
  $plainPassword = $null
}

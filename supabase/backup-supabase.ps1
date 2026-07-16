[CmdletBinding()]
param(
  [string]$ProjectRef = 'ckbftoopuyophiebamwy',
  [securestring]$DbPassword,
  [string]$BackupRoot,
  [string]$DbUrl
)

$ErrorActionPreference = 'Stop'

function Invoke-Supabase {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & supabase @Arguments
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($exitCode -ne 0) {
    throw 'A Supabase CLI command failed. See the preceding command output.'
  }
}

function Get-PlainText {
  param([Parameter(Mandatory = $true)][securestring]$Value)

  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
  }
}

function Get-LinkedDatabaseConnection {
  param(
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$DatabaseUrl
  )

  if ($DatabaseUrl) {
    $uri = [uri]$DatabaseUrl
    return @{
      Host = $uri.Host
      Port = $uri.Port
      User = ([uri]::UnescapeDataString($uri.UserInfo) -split ':')[0]
      Database = $uri.AbsolutePath.TrimStart('/')
    }
  }

  # The CLI resolves the correct pooler host for the project. Capture, never print,
  # its dry-run output because it contains the database password.
  $dryRun = & supabase db dump --linked --password $Password --data-only --dry-run
  if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve the linked database connection.' }
  $text = $dryRun -join "`n"
  $dbHost = [regex]::Match($text, 'export PGHOST="([^"]+)"').Groups[1].Value
  $port = [regex]::Match($text, 'export PGPORT="([^"]+)"').Groups[1].Value
  $user = [regex]::Match($text, 'export PGUSER="([^"]+)"').Groups[1].Value
  $database = [regex]::Match($text, 'export PGDATABASE="([^"]+)"').Groups[1].Value
  if ([string]::IsNullOrWhiteSpace($dbHost) -or [string]::IsNullOrWhiteSpace($user)) {
    throw 'Unable to parse the database connection returned by the Supabase CLI.'
  }
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

if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
  throw 'Supabase CLI is required. Install it first: https://supabase.com/docs/guides/local-development/cli/getting-started'
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  $dockerBin = 'C:\Program Files\Docker\Docker\resources\bin'
  if (Test-Path (Join-Path $dockerBin 'docker.exe')) { $env:Path = "$dockerBin;$env:Path" }
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker Desktop is required for supabase db dump. Install and start Docker Desktop, then rerun this script.'
}
if (-not (Test-DockerReady)) { throw 'Docker Desktop is installed but not running.' }
if (-not $DbPassword) { $DbPassword = Read-Host 'Supabase database password' -AsSecureString }

$supabaseRoot = $PSScriptRoot
if (-not $BackupRoot) { $BackupRoot = Join-Path $supabaseRoot 'backups' }
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = Join-Path $BackupRoot $timestamp
$plainPassword = Get-PlainText $DbPassword

try {
  New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
  $databasePath = Join-Path $backupPath 'database'
  $storagePath = Join-Path $backupPath 'storage'
  $functionsPath = Join-Path $backupPath 'functions'
  $metadataPath = Join-Path $backupPath 'metadata'
  New-Item -ItemType Directory -Force -Path $databasePath, $storagePath, $metadataPath | Out-Null

  # Reuse an existing matching link. Calling `supabase link` on every backup is
  # unnecessary and requires the Management API to be reachable.
  $linkedProjectFile = Join-Path $supabaseRoot '.temp\linked-project.json'
  $linkedProjectRef = $null
  if (Test-Path $linkedProjectFile) {
    try { $linkedProjectRef = (Get-Content -Raw $linkedProjectFile | ConvertFrom-Json).ref } catch {}
  }
  if ($linkedProjectRef -eq $ProjectRef) {
    Write-Host 'Reusing the existing source-project link...'
  }
  else {
    Write-Host 'Linking the source project...'
    Invoke-Supabase @('link', '--project-ref', $ProjectRef, '--password', $plainPassword)
  }
  $dbTarget = if ($DbUrl) { @('--db-url', $DbUrl) } else { @('--linked', '--password', $plainPassword) }
  $connection = Get-LinkedDatabaseConnection -Password $plainPassword -DatabaseUrl $DbUrl

  Write-Host 'Exporting database roles, schema, and data...'
  Invoke-Supabase (@('db', 'dump') + $dbTarget + @('--role-only', '--file', (Join-Path $databasePath 'roles.sql')))
  Invoke-Supabase (@('db', 'dump') + $dbTarget + @('--keep-comments', '--file', (Join-Path $databasePath 'schema.sql')))
  # Do not exclude any application schema or Storage metadata: this is a full logical backup.
  Invoke-Supabase (@('db', 'dump') + $dbTarget + @('--data-only', '--use-copy', '--file', (Join-Path $databasePath 'data.sql')))
  Invoke-Supabase (@('db', 'dump') + $dbTarget + @('--schema', 'supabase_migrations', '--file', (Join-Path $databasePath 'migration-history-schema.sql')))
  Invoke-Supabase (@('db', 'dump') + $dbTarget + @('--schema', 'supabase_migrations', '--data-only', '--use-copy', '--file', (Join-Path $databasePath 'migration-history-data.sql')))
  # Standard schema dumps omit managed auth/storage schemas. This records only the
  # changes made to those managed schemas, which can safely be replayed on a new project.
  Invoke-Supabase (@('db', 'diff') + $dbTarget + @('--schema', 'auth,storage', '--output', (Join-Path $databasePath 'managed-schema-changes.sql')))

  Write-Host 'Capturing deployed Edge Function source and metadata...'
  Invoke-Supabase @('functions', 'download', '--project-ref', $ProjectRef, '--use-api')
  Copy-Item -Path (Join-Path $supabaseRoot 'functions') -Destination $functionsPath -Recurse -Force
  & supabase functions list --project-ref $ProjectRef --output json | Set-Content -Path (Join-Path $metadataPath 'functions.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Unable to list Edge Functions.' }
  & supabase secrets list --project-ref $ProjectRef --output json | Set-Content -Path (Join-Path $metadataPath 'edge-function-secret-names.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Unable to list Edge Function secret names.' }
  & supabase projects list --output json | Set-Content -Path (Join-Path $metadataPath 'projects.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Unable to capture project metadata.' }
  & supabase db query @dbTarget --agent=no --output json 'select id, name, public, file_size_limit, allowed_mime_types, created_at, updated_at from storage.buckets order by id' |
    Set-Content -Path (Join-Path $metadataPath 'storage-buckets.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Unable to list Storage buckets.' }
  & supabase db query @dbTarget --agent=no --output json "select schemaname, tablename from pg_publication_tables where pubname = 'supabase_realtime' order by schemaname, tablename" |
    Set-Content -Path (Join-Path $metadataPath 'realtime-publication-tables.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Unable to list Realtime publication tables.' }

  $bucketText = Get-Content -Raw (Join-Path $metadataPath 'storage-buckets.json')
  $bucketJson = [regex]::Match($bucketText, '\[[\s\S]*\]').Value
  $buckets = if ($bucketJson) { @($bucketJson | ConvertFrom-Json) } else { @() }
  foreach ($bucket in $buckets) {
    $destination = Join-Path $storagePath $bucket.id
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Write-Host "Downloading Storage bucket '$($bucket.id)'..."
    Invoke-Supabase @('storage', 'cp', "ss:///$($bucket.id)", $destination, '--recursive', '--experimental', '--jobs', '4')
  }

  $configSource = Join-Path $supabaseRoot 'config.toml'
  if (Test-Path $configSource) { Copy-Item $configSource (Join-Path $backupPath 'config.toml') -Force }
  $connection | ConvertTo-Json | Set-Content -Path (Join-Path $metadataPath 'database-connection.json') -Encoding utf8

  $files = Get-ChildItem -Path $backupPath -File -Recurse | ForEach-Object {
    [pscustomobject]@{
      path = $_.FullName.Substring($backupPath.Length + 1)
      bytes = $_.Length
      sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }
  }
  [pscustomobject]@{
    format_version = 1
    created_at = (Get-Date).ToUniversalTime().ToString('o')
    project_ref = $ProjectRef
    supabase_cli = (& supabase --version)
    includes = @('database roles', 'database schema', 'database data', 'migration history', 'managed auth/storage schema changes', 'RLS policies/grants/functions/triggers', 'Realtime publication tables', 'Storage bucket files', 'Storage bucket metadata', 'Edge Function source and JWT settings')
    limitations = @('Edge Function secret values cannot be read back from Supabase; only their names are recorded. Re-enter their values before deploying functions.', 'Dashboard-only settings such as OAuth providers, SMTP, custom domains, and Auth URL configuration must be recreated separately.')
    files = $files
  } | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $backupPath 'manifest.json') -Encoding utf8

  @"
# Supabase backup $timestamp

Restore to a new, empty Supabase project with:

```powershell
.\supabase\restore-supabase.ps1 -BackupPath '$backupPath' -TargetProjectRef '<new-project-ref>'
```

The restore script prompts for the target database password. This backup contains application data and Storage files, so keep it outside Git and in encrypted storage.
"@ | Set-Content -Path (Join-Path $backupPath 'README.md') -Encoding utf8

  Write-Host "Backup completed: $backupPath" -ForegroundColor Green
}
finally {
  $plainPassword = $null
}

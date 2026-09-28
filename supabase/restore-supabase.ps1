[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })][string]$BackupPath,
  [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]{20}$')][string]$TargetProjectRef,
  [securestring]$TargetDbPassword,
  [switch]$AllowNonEmptyTarget,
  [switch]$VerifyBackupOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'transfer-common.ps1')

$BackupPath = (Resolve-Path -LiteralPath $BackupPath).Path

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
  if ([string]::IsNullOrWhiteSpace($dbHost) -or $port -notmatch '^\d+$' -or
      [string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($database)) {
    throw 'Unable to parse the target database connection.'
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

function Assert-BackupManifest {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)]$Manifest
  )

  if ($Manifest.format_version -ne 1 -or $Manifest.project_ref -notmatch '^[a-z0-9]{20}$') {
    throw 'Invalid backup manifest format or source project ref.'
  }
  if ($Manifest.project_ref -eq $TargetProjectRef) {
    throw 'The target project must differ from the backup source project.'
  }

  $files = @($Manifest.files)
  if ($files.Count -eq 0) { throw 'The backup manifest has no files.' }
  $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
  $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($entry in $files) {
    $relativePath = [string]$entry.path
    $normalizedPath = $relativePath.Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath) -or
        $relativePath.Contains(':') -or
        @($normalizedPath -split '/' | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
      throw "Unsafe path in backup manifest: $relativePath"
    }
    $fullPath = [IO.Path]::GetFullPath((Join-Path $Root $relativePath))
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $paths.Add($normalizedPath)) {
      throw "Duplicate or out-of-root backup path: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
      throw "Backup file is missing: $relativePath"
    }
    $file = Get-Item -LiteralPath $fullPath
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $file.Length -ne [long]$entry.bytes -or
        (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash -ne [string]$entry.sha256) {
      throw "Backup file failed integrity check: $relativePath"
    }
  }
  foreach ($required in @('config.toml', 'database/roles.sql', 'database/schema.sql',
      'database/data.sql', 'database/migration-history-schema.sql',
      'database/migration-history-data.sql', 'metadata/functions.json',
      'metadata/storage-buckets.json', 'metadata/realtime-publication-tables.json')) {
    if (-not $paths.Contains($required)) { throw "Backup manifest is missing $required" }
  }
}

function Invoke-PsqlRestore {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Connection,
    [Parameter(Mandatory = $true)][string]$Password
  )

  # Keep the SQL files in the order specified by Supabase's logical restore guide.
  # One psql session makes session_replication_role apply to the data import.
  & docker run --rm -v "${BackupPath}:/backup:ro" -e "PGPASSWORD=$Password" postgres:17-alpine `
    psql "host=$($Connection.Host) port=$($Connection.Port) dbname=$($Connection.Database) user=$($Connection.User) sslmode=require" `
    --single-transaction --variable ON_ERROR_STOP=1 `
    --file /backup/database/roles.sql `
    --file /backup/database/schema.sql `
    --command 'SET session_replication_role = replica' `
    --file /backup/database/data.sql `
    --file /backup/database/migration-history-schema.sql `
    --file /backup/database/migration-history-data.sql
  if ($LASTEXITCODE -ne 0) { throw 'Database restore failed; Storage and Functions were not imported.' }
}

function Invoke-StorageObjectUpload {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$ServiceRoleKey,
    [Parameter(Mandatory = $true)][string]$BucketId,
    [Parameter(Mandatory = $true)][string]$ObjectName,
    [Parameter(Mandatory = $true)][string]$FilePath
  )

  $encodedBucket = [uri]::EscapeDataString($BucketId)
  $encodedObject = ConvertTo-StorageApiPath $ObjectName
  $headers = @{
    apikey = $ServiceRoleKey
    Authorization = "Bearer $ServiceRoleKey"
    'x-upsert' = 'true'
  }
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Invoke-WebRequest `
        -Method Post `
        -Uri "https://$ProjectRef.supabase.co/storage/v1/object/$encodedBucket/$encodedObject" `
        -Headers $headers `
        -InFile $FilePath `
        -ContentType 'application/octet-stream' `
        -UseBasicParsing `
        -TimeoutSec 180 | Out-Null
      return
    }
    catch {
      if ($attempt -eq 3) { throw }
      Write-Warning "Storage upload failed for '$BucketId/$ObjectName' (attempt $attempt/3). Retrying..."
      Start-Sleep -Seconds (3 * $attempt)
    }
  }
}

$manifestPath = Join-Path $BackupPath 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Invalid backup: manifest.json is missing.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert-BackupManifest -Root $BackupPath -Manifest $manifest
if ($VerifyBackupOnly) {
  Write-Host "Backup verified: $BackupPath" -ForegroundColor Green
  return
}

if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) { throw 'Supabase CLI is required.' }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  $dockerBin = 'C:\Program Files\Docker\Docker\resources\bin'
  if (Test-Path (Join-Path $dockerBin 'docker.exe')) { $env:Path = "$dockerBin;$env:Path" }
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop is required for the database restore.' }
if (-not (Test-DockerReady)) { throw 'Docker Desktop is installed but not running.' }

if (-not $TargetDbPassword) { $TargetDbPassword = Read-Host 'Target Supabase database password' -AsSecureString }
$plainPassword = Get-PlainText $TargetDbPassword

$stage = Join-Path ([IO.Path]::GetTempPath()) "supabase-restore-$([guid]::NewGuid())"
$tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
if (-not [IO.Path]::GetFullPath($stage).StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path $stage -Leaf) -notmatch '^supabase-restore-[a-f0-9-]{36}$') {
  throw 'Unexpected temporary restore directory.'
}

try {
  Write-Warning "This writes backup '$($manifest.created_at)' to target project $TargetProjectRef. Use a new, empty project unless -AllowNonEmptyTarget is explicitly supplied."
  $confirmation = Read-Host "Type the target project ref ($TargetProjectRef) to continue"
  if ($confirmation -ne $TargetProjectRef) { throw 'Restore cancelled.' }

  New-Item -ItemType Directory -Path (Join-Path $stage 'supabase') -Force | Out-Null
  $backupConfig = Join-Path $BackupPath 'config.toml'
  if (-not (Test-Path -LiteralPath $backupConfig -PathType Leaf)) { throw 'Backup config.toml is missing.' }
  Copy-Item -LiteralPath $backupConfig -Destination (Join-Path $stage 'supabase\config.toml')
  Push-Location $stage
  try {
    Invoke-Supabase @('link', '--project-ref', $TargetProjectRef, '--password', $plainPassword)
    $connection = Get-LinkedDatabaseConnection $plainPassword
    $tableCheck = & supabase db query --linked --agent=no --output json "select count(*)::int as count from pg_tables where schemaname = 'public'"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to check whether the target project is empty.' }
    $tableJson = [regex]::Match(($tableCheck -join "`n"), '\[[\s\S]*\]').Value
    if (-not $tableJson) { throw 'Unable to parse the target table count; refusing to restore.' }
    $publicTableCount = (($tableJson | ConvertFrom-Json)[0].count)
    if ($null -eq $publicTableCount -or $publicTableCount -notmatch '^\d+$') {
      throw 'Invalid target table count; refusing to restore.'
    }
    if (($publicTableCount -gt 0) -and -not $AllowNonEmptyTarget) {
      throw "Target project already has $publicTableCount public tables. Refusing to merge. Create an empty project or rerun with -AllowNonEmptyTarget after confirming the consequences."
    }

    Write-Host 'Restoring database roles, schema, and data...'
    Invoke-PsqlRestore -Connection $connection -Password $plainPassword

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
      $serviceRoleKey = $null
      foreach ($bucket in @(Get-ChildItem -LiteralPath $storagePath -Directory)) {
        $bucketFiles = @(Get-ChildItem -LiteralPath $bucket.FullName -File -Recurse)
        if ($bucketFiles.Count -eq 0) { continue }
        Write-Host "Uploading Storage bucket '$($bucket.Name)'..."
        $copyResult = Invoke-SupabaseQuiet @('storage', 'cp', $bucket.FullName, "ss:///$($bucket.Name)", '--recursive', '--experimental')
        if ($copyResult.Succeeded) { continue }
        Write-Warning "Supabase CLI Storage upload failed for '$($bucket.Name)'; retrying through the Storage API. $($copyResult.Error)"
        if (-not $serviceRoleKey) { $serviceRoleKey = Get-SupabaseServiceRoleKey -ProjectRef $TargetProjectRef }
        foreach ($file in $bucketFiles) {
          $objectName = $file.FullName.Substring($bucket.FullName.Length + 1).Replace('\', '/')
          Invoke-StorageObjectUpload `
            -ProjectRef $TargetProjectRef `
            -ServiceRoleKey $serviceRoleKey `
            -BucketId $bucket.Name `
            -ObjectName $objectName `
            -FilePath $file.FullName
        }
      }
      $serviceRoleKey = $null
    }

    $functionsPath = Join-Path $BackupPath 'functions'
    $functionMetadataPath = Join-Path $BackupPath 'metadata\functions.json'
    if ((Test-Path $functionsPath) -and (Test-Path $functionMetadataPath)) {
      Copy-Item -LiteralPath $functionsPath -Destination (Join-Path $stage 'supabase\functions') -Recurse -Force
      $functions = Get-Content -Raw $functionMetadataPath | ConvertFrom-Json
      foreach ($function in $functions) {
        if ($function.slug -notmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Invalid Edge Function slug in backup metadata.' }
        $arguments = @('functions', 'deploy', $function.slug, '--project-ref', $TargetProjectRef, '--use-api')
        if ($function.verify_jwt -eq $false) { $arguments += '--no-verify-jwt' }
        Invoke-Supabase $arguments
      }
    }

    Write-Host 'Restore completed.' -ForegroundColor Green
    Write-Warning 'Before using Edge Functions, restore the secret values listed in metadata/edge-function-secret-names.json. Supabase deliberately does not allow existing secret values to be exported.'
  }
  finally {
    Pop-Location
  }
}
finally {
  $plainPassword = $null
  if (Test-Path -LiteralPath $stage -PathType Container) {
    Remove-Item -LiteralPath $stage -Recurse -Force
  }
}

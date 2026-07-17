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

function Enable-SystemProxyForSupabaseCli {
  # Supabase CLI is a Go executable and does not automatically inherit the
  # Windows Internet Settings proxy. Reuse that proxy for this script process
  # only, so Management API calls (Functions, secrets and project metadata)
  # work on networks where native DNS cannot resolve api.supabase.com.
  $settingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  try {
    $settings = Get-ItemProperty -Path $settingsPath -ErrorAction Stop
    if ($settings.ProxyEnable -ne 1 -or [string]::IsNullOrWhiteSpace($settings.ProxyServer)) { return }

    $proxy = ($settings.ProxyServer -split ';' | Select-Object -First 1).Trim()
    if ($proxy -notmatch '^[a-z]+://') { $proxy = "http://$proxy" }
    $env:HTTP_PROXY = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:http_proxy = $proxy
    $env:https_proxy = $proxy
    Write-Host 'Using the configured Windows proxy for Supabase API calls...'
  }
  catch {
    Write-Verbose 'Windows proxy settings could not be read; continuing without an HTTP proxy.'
  }
}

function Invoke-SupabaseJsonWithRetry {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [int]$Attempts = 3,
    [switch]$AllowFailure
  )

  $lastError = $null
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $errorPath = "$OutputPath.stderr.tmp"
    $previousPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $stdout = & supabase @Arguments 2> $errorPath
      $exitCode = $LASTEXITCODE
    }
    finally {
      $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -eq 0) {
      $stdout | Set-Content -Path $OutputPath -Encoding utf8
      Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
      return $true
    }

    $lastError = if (Test-Path $errorPath) {
      (Get-Content -Raw $errorPath).Trim()
    }
    else {
      "Supabase CLI exited with code $exitCode."
    }
    Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue

    if ($attempt -lt $Attempts) {
      Write-Warning "Supabase API request failed (attempt $attempt/$Attempts). Retrying..."
      Start-Sleep -Seconds (3 * $attempt)
    }
  }

  if ($AllowFailure) {
    [pscustomobject]@{
      captured = $false
      error = $lastError
      note = 'Supabase does not expose Edge Function secret values. Re-enter all secret values manually during restore.'
    } | ConvertTo-Json -Depth 3 | Set-Content -Path $OutputPath -Encoding utf8
    Write-Warning "Optional Supabase metadata could not be captured after $Attempts attempts. The backup will continue."
    return $false
  }

  throw "Supabase API request failed after $Attempts attempts: $lastError"
}

function Invoke-SupabaseQuiet {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  $errorPath = Join-Path ([IO.Path]::GetTempPath()) ("supabase-cli-$([guid]::NewGuid()).stderr.tmp")
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $stdout = & supabase @Arguments 2> $errorPath
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }

  $stderr = if (Test-Path $errorPath) { (Get-Content -Raw $errorPath).Trim() } else { '' }
  Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue

  return [pscustomobject]@{
    Succeeded = ($exitCode -eq 0)
    ExitCode = $exitCode
    Output = (($stdout | Out-String).Trim())
    Error = $stderr
  }
}

function Invoke-SupabaseQuietWithRetry {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [int]$Attempts = 3
  )

  $lastResult = $null
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    $lastResult = Invoke-SupabaseQuiet $Arguments
    if ($lastResult.Succeeded) { return $lastResult }

    if ($attempt -lt $Attempts) {
      Write-Warning "Supabase CLI request failed (attempt $attempt/$Attempts). Retrying..."
      Start-Sleep -Seconds (3 * $attempt)
    }
  }

  return $lastResult
}

function Get-SupabaseApiKeyValue {
  param(
    [Parameter(Mandatory = $true)]$KeyRecord,
    [Parameter(Mandatory = $true)][string[]]$Names
  )

  foreach ($name in $Names) {
    $property = $KeyRecord.PSObject.Properties[$name]
    if ($property -and $property.Value -isnot [System.Array] -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
      return [string]$property.Value
    }
  }

  return $null
}

function Expand-SupabaseApiKeyRecords {
  param($Value)

  if ($null -eq $Value) { return @() }

  if ($Value -is [System.Array]) {
    $items = @()
    foreach ($item in $Value) {
      $items += @(Expand-SupabaseApiKeyRecords $item)
    }
    return $items
  }

  # Windows PowerShell can preserve a JSON top-level array as one object whose
  # properties are arrays. Rebuild normal row objects before searching by name.
  $apiKeyProperty = $Value.PSObject.Properties['api_key']
  $nameProperty = $Value.PSObject.Properties['name']
  if ($apiKeyProperty -and $apiKeyProperty.Value -is [System.Array]) {
    $apiKeys = @($apiKeyProperty.Value)
    $names = if ($nameProperty) { @($nameProperty.Value) } else { @() }
    $ids = if ($Value.PSObject.Properties['id']) { @($Value.PSObject.Properties['id'].Value) } else { @() }
    $types = if ($Value.PSObject.Properties['type']) { @($Value.PSObject.Properties['type'].Value) } else { @() }

    $rows = @()
    for ($i = 0; $i -lt $apiKeys.Count; $i++) {
      $rows += [pscustomobject]@{
        api_key = $apiKeys[$i]
        name = if ($i -lt $names.Count) { $names[$i] } else { $null }
        id = if ($i -lt $ids.Count) { $ids[$i] } else { $null }
        type = if ($i -lt $types.Count) { $types[$i] } else { $null }
      }
    }
    return $rows
  }

  return @($Value)
}

function Get-SupabaseServiceRoleKey {
  param([Parameter(Mandatory = $true)][string]$ProjectRef)

  $result = Invoke-SupabaseQuietWithRetry `
    -Arguments @('projects', 'api-keys', '--project-ref', $ProjectRef, '--output', 'json') `
    -Attempts 3
  if (-not $result.Succeeded) {
    throw "Unable to read Supabase API keys for Storage download fallback. $($result.Error)"
  }

  try {
    $records = @(Expand-SupabaseApiKeyRecords ($result.Output | ConvertFrom-Json))
  }
  catch {
    throw 'Unable to parse the Supabase API key list returned by the CLI.'
  }

  foreach ($record in $records) {
    $name = Get-SupabaseApiKeyValue -KeyRecord $record -Names @('name', 'key_name', 'label', 'id')
    if ($name -and $name -match 'service[_ -]?role') {
      $value = Get-SupabaseApiKeyValue -KeyRecord $record -Names @('api_key', 'key', 'value')
      if ($value) { return $value }
    }
  }

  throw 'No service_role API key was found. Storage bucket files cannot be fully backed up without a key that can read private buckets.'
}

function ConvertTo-StorageApiPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  return (($Path -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
}

function Get-StorageLocalPath {
  param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$ObjectName
  )

  $path = $Destination
  foreach ($segment in ($ObjectName -split '/')) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..') {
      throw "Unsafe Storage object path: $ObjectName"
    }
    $path = Join-Path $path $segment
  }

  $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
  $resolved = [IO.Path]::GetFullPath($path)
  if (-not $resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe Storage object path: $ObjectName"
  }

  return $resolved
}

function Invoke-StorageList {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$ServiceRoleKey,
    [Parameter(Mandatory = $true)][string]$BucketId,
    [string]$Prefix = '',
    [int]$Offset = 0,
    [int]$Limit = 1000
  )

  $encodedBucket = [uri]::EscapeDataString($BucketId)
  $headers = @{
    apikey = $ServiceRoleKey
    Authorization = "Bearer $ServiceRoleKey"
  }
  $body = @{
    prefix = $Prefix
    limit = $Limit
    offset = $Offset
    sortBy = @{
      column = 'name'
      order = 'asc'
    }
  } | ConvertTo-Json -Depth 5

  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      return @(Invoke-RestMethod `
        -Method Post `
        -Uri "https://$ProjectRef.supabase.co/storage/v1/object/list/$encodedBucket" `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 60)
    }
    catch {
      if ($attempt -eq 3) { throw }
      Write-Warning "Storage object listing failed for bucket '$BucketId' (attempt $attempt/3). Retrying..."
      Start-Sleep -Seconds (3 * $attempt)
    }
  }
}

function Invoke-StorageObjectDownload {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$ServiceRoleKey,
    [Parameter(Mandatory = $true)][string]$BucketId,
    [Parameter(Mandatory = $true)][string]$ObjectName,
    [Parameter(Mandatory = $true)][string]$OutputPath
  )

  $encodedBucket = [uri]::EscapeDataString($BucketId)
  $encodedObject = ConvertTo-StorageApiPath $ObjectName
  $headers = @{
    apikey = $ServiceRoleKey
    Authorization = "Bearer $ServiceRoleKey"
  }
  New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null

  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Invoke-WebRequest `
        -Uri "https://$ProjectRef.supabase.co/storage/v1/object/$encodedBucket/$encodedObject" `
        -Headers $headers `
        -OutFile $OutputPath `
        -UseBasicParsing `
        -TimeoutSec 180 | Out-Null
      return
    }
    catch {
      if ($attempt -eq 3) { throw }
      Write-Warning "Storage object download failed for '$ObjectName' (attempt $attempt/3). Retrying..."
      Start-Sleep -Seconds (3 * $attempt)
    }
  }
}

function Save-StorageBucketViaApi {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$ServiceRoleKey,
    [Parameter(Mandatory = $true)][string]$BucketId,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  $downloaded = New-Object System.Collections.Generic.List[object]

  function Save-StoragePrefix {
    param([string]$Prefix)

    $offset = 0
    $limit = 1000
    do {
      $items = @(Invoke-StorageList `
        -ProjectRef $ProjectRef `
        -ServiceRoleKey $ServiceRoleKey `
        -BucketId $BucketId `
        -Prefix $Prefix `
        -Offset $offset `
        -Limit $limit)

      foreach ($item in $items) {
        $name = [string]$item.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $objectName = if ([string]::IsNullOrWhiteSpace($Prefix)) { $name } else { "$Prefix/$name" }
        $isFolder = (-not $item.id) -and (-not $item.metadata)
        if ($isFolder) {
          Save-StoragePrefix $objectName
          continue
        }

        $localPath = Get-StorageLocalPath -Destination $Destination -ObjectName $objectName
        Invoke-StorageObjectDownload `
          -ProjectRef $ProjectRef `
          -ServiceRoleKey $ServiceRoleKey `
          -BucketId $BucketId `
          -ObjectName $objectName `
          -OutputPath $localPath
        $downloaded.Add([pscustomobject]@{
          bucket = $BucketId
          object = $objectName
          path = $localPath.Substring($Destination.Length).TrimStart('\')
          bytes = (Get-Item -LiteralPath $localPath).Length
        }) | Out-Null
      }

      $offset += $items.Count
    } while ($items.Count -eq $limit)
  }

  Save-StoragePrefix ''
  return @($downloaded)
}

function Save-StorageBucket {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$BucketId,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][ref]$ServiceRoleKeyRef
  )

  New-Item -ItemType Directory -Path $Destination -Force | Out-Null

  Push-Location $Destination
  try {
    $cliResult = Invoke-SupabaseQuiet @('storage', 'cp', "ss:///$BucketId", '.', '--recursive', '--experimental', '--jobs', '4')
  }
  finally {
    Pop-Location
  }

  if ($cliResult.Succeeded) {
    if ($cliResult.Output) { Write-Host $cliResult.Output }
    return [pscustomobject]@{
      bucket = $BucketId
      method = 'supabase-cli'
      files = $null
    }
  }

  Write-Warning "Supabase CLI Storage copy failed for bucket '$BucketId'; falling back to the Storage API."
  if ($cliResult.Error) { Write-Warning $cliResult.Error }
  if ([string]::IsNullOrWhiteSpace([string]$ServiceRoleKeyRef.Value)) {
    $ServiceRoleKeyRef.Value = Get-SupabaseServiceRoleKey $ProjectRef
  }

  $files = Save-StorageBucketViaApi `
    -ProjectRef $ProjectRef `
    -ServiceRoleKey ([string]$ServiceRoleKeyRef.Value) `
    -BucketId $BucketId `
    -Destination $Destination

  return [pscustomobject]@{
    bucket = $BucketId
    method = 'storage-api'
    files = $files
  }
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
Enable-SystemProxyForSupabaseCli

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
  Invoke-SupabaseJsonWithRetry `
    -Arguments @('functions', 'list', '--project-ref', $ProjectRef, '--output', 'json') `
    -OutputPath (Join-Path $metadataPath 'functions.json') | Out-Null
  Invoke-SupabaseJsonWithRetry `
    -Arguments @('secrets', 'list', '--project-ref', $ProjectRef, '--output', 'json') `
    -OutputPath (Join-Path $metadataPath 'edge-function-secret-names.json') `
    -AllowFailure | Out-Null
  Invoke-SupabaseJsonWithRetry `
    -Arguments @('projects', 'list', '--output', 'json') `
    -OutputPath (Join-Path $metadataPath 'projects.json') | Out-Null
  & supabase db query @dbTarget --agent=no --output json 'select id, name, public, file_size_limit, allowed_mime_types, created_at, updated_at from storage.buckets order by id' |
    Set-Content -Path (Join-Path $metadataPath 'storage-buckets.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Unable to list Storage buckets.' }
  & supabase db query @dbTarget --agent=no --output json "select schemaname, tablename from pg_publication_tables where pubname = 'supabase_realtime' order by schemaname, tablename" |
    Set-Content -Path (Join-Path $metadataPath 'realtime-publication-tables.json') -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw 'Unable to list Realtime publication tables.' }

  $bucketText = Get-Content -Raw (Join-Path $metadataPath 'storage-buckets.json')
  $bucketJson = [regex]::Match($bucketText, '\[[\s\S]*\]').Value
  $buckets = if ($bucketJson) { @($bucketJson | ConvertFrom-Json) } else { @() }
  $storageDownloadReport = New-Object System.Collections.Generic.List[object]
  $serviceRoleKey = $null
  foreach ($bucket in $buckets) {
    $destination = Join-Path $storagePath $bucket.id
    Write-Host "Downloading Storage bucket '$($bucket.id)'..."
    $report = Save-StorageBucket `
      -ProjectRef $ProjectRef `
      -BucketId $bucket.id `
      -Destination $destination `
      -ServiceRoleKeyRef ([ref]$serviceRoleKey)
    $storageDownloadReport.Add($report) | Out-Null
  }
  $storageDownloadReport |
    ConvertTo-Json -Depth 8 |
    Set-Content -Path (Join-Path $metadataPath 'storage-download-report.json') -Encoding utf8
  $serviceRoleKey = $null

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

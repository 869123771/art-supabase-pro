[CmdletBinding()]
param(
  [string]$ProjectRef = 'ckbftoopuyophiebamwy',
  [securestring]$DbPassword,
  [switch]$SkipBaseline
)

# One-command bootstrap for this repository:
#   1. Check Docker and fetch the PostgreSQL image needed by the Supabase CLI.
#   2. Pull the remote schema into the first local baseline migration when needed.
#   3. Mark that pulled baseline as already applied remotely (no schema is executed).
#   4. Run backup-supabase.ps1 to save database, Storage, Functions and metadata locally.

$ErrorActionPreference = 'Stop'

function Invoke-Supabase {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  # The CLI writes informational messages (for example, "Using workdir") to
  # stderr. Under $ErrorActionPreference = Stop those are PowerShell errors,
  # even though the CLI command succeeded. Use the actual exit code instead.
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
    throw 'A Supabase CLI command failed. Read the preceding output, fix the prerequisite, then rerun this script.'
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

function Resolve-DatabaseHost {
  param([Parameter(Mandatory = $true)][string]$HostName)

  try {
    $native = Resolve-DnsName $HostName -Type A -ErrorAction Stop |
      Where-Object { $_.IPAddress } |
      Select-Object -First 1 -ExpandProperty IPAddress
    if ($native) { return $native }
  }
  catch {}

  # Bypass the broken local DNS resolver for this one lookup. `--resolve` keeps
  # TLS validation for dns.google while connecting to its well-known IP address.
  $response = & curl.exe --silent --show-error --fail --max-time 20 `
    --resolve 'dns.google:443:8.8.8.8' `
    -H 'accept: application/dns-json' `
    "https://dns.google/resolve?name=$HostName&type=A"
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to resolve database host $HostName through local DNS or DNS-over-HTTPS."
  }
  $answer = $response | ConvertFrom-Json
  $record = @($answer.Answer | Where-Object { $_.type -eq 1 -and $_.data })[0]
  if (-not $record) {
    throw "DNS-over-HTTPS returned no IPv4 address for $HostName."
  }
  return $record.data
}

function Get-DatabaseUrl {
  param(
    [Parameter(Mandatory = $true)][string]$SupabaseRoot,
    [Parameter(Mandatory = $true)][string]$Password
  )

  $poolerFile = Join-Path $SupabaseRoot '.temp\pooler-url'
  if (-not (Test-Path $poolerFile)) {
    throw 'supabase/.temp/pooler-url is missing. Run supabase link once when the Management API is reachable.'
  }
  $poolerUri = [uri](Get-Content -Raw $poolerFile).Trim()
  $address = Resolve-DatabaseHost $poolerUri.Host
  $user = [uri]::UnescapeDataString($poolerUri.UserInfo)
  $escapedUser = [uri]::EscapeDataString($user)
  $escapedPassword = [uri]::EscapeDataString($Password)
  return "postgresql://${escapedUser}:${escapedPassword}@${address}:$($poolerUri.Port)$($poolerUri.AbsolutePath)?sslmode=require"
}

function Get-MigrationTable {
  param([Parameter(Mandatory = $true)][string]$DatabaseUrl)

  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & supabase migration list --db-url $DatabaseUrl 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($exitCode -ne 0) {
    throw 'Unable to read the remote migration history.'
  }

  $rows = foreach ($line in ($output -join "`n") -split "`r?`n") {
    if ($line -notlike '*|*') { continue }
    $columns = @($line.Split('|') | ForEach-Object { $_.Trim() })
    if ($columns.Count -lt 3) { continue }
    if ($columns[0] -match '^\d{14}$' -or $columns[1] -match '^\d{14}$') {
      [pscustomobject]@{ Local = $columns[0]; Remote = $columns[1] }
    }
  }

  return @($rows)
}

function Test-DockerImage {
  param([Parameter(Mandatory = $true)][string]$Image)

  # `docker image inspect` returns exit code 1 when the image is not cached.
  # That is an expected result, not a script failure: the caller pulls it next.
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & docker image inspect $Image 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
}

if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
  throw 'Supabase CLI is required. Install it, then rerun this script.'
}

# Docker Desktop installs its CLI outside the usual PATH on some Windows setups.
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  $dockerBin = 'C:\Program Files\Docker\Docker\resources\bin'
  if (Test-Path (Join-Path $dockerBin 'docker.exe')) { $env:Path = "$dockerBin;$env:Path" }
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker Desktop is required. Install it and start it before rerunning this script.'
}

& docker version --format '{{.Server.Version}}' *> $null
if ($LASTEXITCODE -ne 0) {
  throw 'Docker Desktop is installed but not running. Start it, wait for Engine running, then rerun this script.'
}

if (-not $DbPassword) {
  $DbPassword = Read-Host 'Supabase database password' -AsSecureString
}

$supabaseRoot = $PSScriptRoot
$versionFile = Join-Path $supabaseRoot '.temp\postgres-version'
$postgresVersion = if (Test-Path $versionFile) { (Get-Content -Raw $versionFile).Trim() } else { '17.6.1.062' }
$postgresImage = "public.ecr.aws/supabase/postgres:$postgresVersion"
$plainPassword = Get-PlainText $DbPassword

try {
  # The project is normally already linked in supabase/.temp. Avoid a needless
  # management-API call on each backup, which is especially useful on unstable DNS.
  $linkedProjectFile = Join-Path $supabaseRoot '.temp\linked-project.json'
  $linkedProjectRef = $null
  if (Test-Path $linkedProjectFile) {
    try { $linkedProjectRef = (Get-Content -Raw $linkedProjectFile | ConvertFrom-Json).ref } catch {}
  }
  if ($linkedProjectRef -eq $ProjectRef) {
    Write-Host "Reusing existing link to Supabase project $ProjectRef..."
  }
  else {
    Write-Host "Linking Supabase project $ProjectRef..."
    Invoke-Supabase @('link', '--project-ref', $ProjectRef, '--password', $plainPassword)
  }

  $databaseUrl = Get-DatabaseUrl -SupabaseRoot $supabaseRoot -Password $plainPassword

  Write-Host "Ensuring Docker image $postgresImage is available..."
  if (-not (Test-DockerImage $postgresImage)) {
    Write-Host 'Docker image is not cached; downloading it now...'
    & docker pull $postgresImage
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to download $postgresImage. Check Docker Desktop networking, proxy and DNS, then rerun this script."
    }
  }

  # Preserve the old remote migration listing for troubleshooting. The CLI version in this
  # workspace prints a table even when --output json is requested, hence the .txt extension.
  $historyPath = Join-Path $supabaseRoot 'remote-migration-history.txt'
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & supabase migration list --db-url $databaseUrl | Set-Content -Path $historyPath -Encoding utf8
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($exitCode -ne 0) { throw 'Unable to save the remote migration history.' }

  $migrationFiles = @(Get-ChildItem (Join-Path $supabaseRoot 'migrations') -Filter '*.sql' -File)
  $history = Get-MigrationTable $databaseUrl

  if (-not $SkipBaseline -and $migrationFiles.Count -eq 0) {
    $remoteVersions = @($history | Where-Object { $_.Remote } | Select-Object -ExpandProperty Remote)
    if ($remoteVersions.Count -gt 0) {
      throw "Remote migration history contains $($remoteVersions.Count) version(s), but this repository has no migration SQL. The script refuses to rewrite remote history automatically. Review $historyPath first."
    }

    Write-Host 'Pulling the remote schema into the first baseline migration...'
    $pullStartedAt = Get-Date
    $previousPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      & supabase db pull baseline --db-url $databaseUrl
      $exitCode = $LASTEXITCODE
    }
    finally {
      $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) {
      # A failed db pull can leave an empty baseline file. It is never a valid migration.
      Get-ChildItem (Join-Path $supabaseRoot 'migrations') -Filter '*_baseline.sql' -File |
        Where-Object { $_.Length -eq 0 -and $_.LastWriteTime -ge $pullStartedAt } |
        Remove-Item -Force
      throw 'Baseline pull failed. The generated empty baseline (if any) was removed.'
    }

    $migrationFiles = @(Get-ChildItem (Join-Path $supabaseRoot 'migrations') -Filter '*_baseline.sql' -File |
      Where-Object { $_.Length -gt 0 } |
      Sort-Object Name)
    if ($migrationFiles.Count -ne 1) {
      throw 'Expected exactly one non-empty baseline migration after db pull.'
    }

    $baselineVersion = $migrationFiles[0].BaseName.Split('_')[0]
    $history = Get-MigrationTable $databaseUrl
    $remoteHasBaseline = @($history | Where-Object { $_.Remote -eq $baselineVersion }).Count -gt 0
    if (-not $remoteHasBaseline) {
      # The schema already exists remotely. Marking the pulled file as applied prevents a
      # future db push from attempting to recreate its objects.
      Write-Host "Marking baseline $baselineVersion as applied in remote migration history..."
      Invoke-Supabase @('migration', 'repair', '--db-url', $databaseUrl, '--status', 'applied', $baselineVersion)
    }
  }

  $baselineFiles = @(Get-ChildItem (Join-Path $supabaseRoot 'migrations') -Filter '*_baseline.sql' -File |
    Where-Object { $_.Length -gt 0 } |
    Sort-Object Name)
  if (-not $SkipBaseline -and $baselineFiles.Count -ne 1) {
    throw 'A valid baseline migration was not found. The full backup was not started.'
  }

  if (-not $SkipBaseline) {
    $baselineVersion = $baselineFiles[0].BaseName.Split('_')[0]
    $history = Get-MigrationTable $databaseUrl
    $localHasBaseline = @($history | Where-Object { $_.Local -eq $baselineVersion }).Count -gt 0
    $remoteHasBaseline = @($history | Where-Object { $_.Remote -eq $baselineVersion }).Count -gt 0
    if (-not ($localHasBaseline -and $remoteHasBaseline)) {
      throw "Migration verification failed for baseline $baselineVersion."
    }
  }

  Write-Host 'Creating complete remote backup (database, Storage, Functions and metadata)...'
  & (Join-Path $supabaseRoot 'backup-supabase.ps1') -ProjectRef $ProjectRef -DbPassword $DbPassword -DbUrl $databaseUrl
  if ($LASTEXITCODE -ne 0) {
    throw 'The backup script failed. A backup without manifest.json is incomplete and must not be used for restore.'
  }

  $latestBackup = Get-ChildItem (Join-Path $supabaseRoot 'backups') -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  $manifest = if ($latestBackup) { Join-Path $latestBackup.FullName 'manifest.json' } else { $null }
  if (-not $manifest -or -not (Test-Path $manifest)) {
    throw 'The backup command returned successfully, but manifest.json was not found.'
  }

  $baselineLabel = if ($baselineFiles.Count -gt 0) { $baselineFiles[0].FullName } else { 'skipped' }
  Write-Host "Sync completed. Baseline: $baselineLabel" -ForegroundColor Green
  Write-Host "Backup manifest: $manifest" -ForegroundColor Green
}
finally {
  $plainPassword = $null
}

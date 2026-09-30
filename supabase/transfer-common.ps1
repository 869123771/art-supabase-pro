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

  $stderrContent = if (Test-Path $errorPath) { Get-Content -Raw $errorPath } else { $null }
  $stderr = if ($null -eq $stderrContent) { '' } else { $stderrContent.Trim() }
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

function Enable-SystemProxyForSupabaseCli {
  # The Supabase CLI does not inherit the Windows Internet Settings proxy.
  $settingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  try {
    $settings = Get-ItemProperty -Path $settingsPath -ErrorAction Stop
    if ($settings.ProxyEnable -ne 1 -or [string]::IsNullOrWhiteSpace($settings.ProxyServer)) { return }

    $entries = @($settings.ProxyServer -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $selected = $entries | Where-Object { $_ -match '^https=' } | Select-Object -First 1
    if (-not $selected) { $selected = $entries | Select-Object -First 1 }
    $proxy = ($selected -replace '^(https?|all)=', '').Trim()
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

function ConvertFrom-SupabaseJsonArray {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $json = [regex]::Match($Text, '\[[\s\S]*\]').Value
  if (-not $json) { throw "Unable to read ${Description}: the CLI did not return a JSON array." }
  try {
    $parsed = ConvertFrom-Json -InputObject $json -ErrorAction Stop
    return @($parsed)
  }
  catch { throw "Unable to parse $Description returned by the Supabase CLI." }
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
    -Arguments @('projects', 'api-keys', '--project-ref', $ProjectRef, '--reveal', '--output', 'json') `
    -Attempts 3
  if (-not $result.Succeeded) {
    throw "Unable to read Supabase API keys for Storage transfer. $($result.Error)"
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

  # New projects may use an sb_secret_ key instead of a legacy service_role JWT.
  foreach ($record in $records) {
    $value = Get-SupabaseApiKeyValue -KeyRecord $record -Names @('api_key', 'key', 'value')
    if ($value -match '^sb_secret_[A-Za-z0-9_-]+$') { return $value }
  }

  throw 'No service_role or secret API key was found. Storage transfer requires a privileged server key for private buckets.'
}

function ConvertTo-StorageApiPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  return (($Path -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
}

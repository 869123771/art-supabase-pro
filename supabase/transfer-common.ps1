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

  throw 'No service_role API key was found. Storage transfer requires a service_role key for private buckets.'
}

function ConvertTo-StorageApiPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  return (($Path -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
}

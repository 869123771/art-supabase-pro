$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../supabase/transfer-common.ps1')

$projectRef = 'ckbftoopuyophiebamwy'
$originalToken = $env:SUPABASE_ACCESS_TOKEN
$script:calls = 0
$script:scenario = ''

function Invoke-SupabaseQuiet {
  param([string[]]$Arguments)

  $script:calls++
  if (($script:scenario -eq 'saved-login' -and -not $env:SUPABASE_ACCESS_TOKEN) -or
      ($script:scenario -eq 'environment-token' -and $env:SUPABASE_ACCESS_TOKEN)) {
    return [pscustomobject]@{
      Succeeded = $true
      Output = '{"projects":[{"ref":"ckbftoopuyophiebamwy"}]}'
    }
  }
  return [pscustomobject]@{ Succeeded = $false; Output = '' }
}

try {
  $script:scenario = 'saved-login'
  $env:SUPABASE_ACCESS_TOKEN = 'invalid-fixture-token'
  Assert-SupabaseCliProjectAccess -ProjectRef $projectRef
  if ($script:calls -ne 2 -or $env:SUPABASE_ACCESS_TOKEN) {
    throw 'The saved CLI login did not replace an invalid inherited token.'
  }

  $script:scenario = 'environment-token'
  $script:calls = 0
  $env:SUPABASE_ACCESS_TOKEN = 'valid-fixture-token'
  Assert-SupabaseCliProjectAccess -ProjectRef $projectRef
  if ($script:calls -ne 1 -or $env:SUPABASE_ACCESS_TOKEN -ne 'valid-fixture-token') {
    throw 'A working environment token was not preserved.'
  }

  $script:scenario = 'no-access'
  $script:calls = 0
  $env:SUPABASE_ACCESS_TOKEN = 'invalid-fixture-token'
  $failed = $false
  try { Assert-SupabaseCliProjectAccess -ProjectRef $projectRef }
  catch { $failed = $true }
  if (-not $failed -or $script:calls -ne 2 -or
      $env:SUPABASE_ACCESS_TOKEN -ne 'invalid-fixture-token') {
    throw 'An unavailable saved login did not fail and restore the environment token.'
  }

  Write-Host 'Supabase CLI project authentication fallback checks passed.' -ForegroundColor Green
}
finally {
  if ($null -eq $originalToken) {
    Remove-Item Env:SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue
  }
  else {
    $env:SUPABASE_ACCESS_TOKEN = $originalToken
  }
}

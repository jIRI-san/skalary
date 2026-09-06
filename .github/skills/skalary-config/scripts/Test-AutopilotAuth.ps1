#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($RepoRoot)
$configPath = Join-Path $root '.autopilot.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw '.autopilot.json is required before authentication validation.' }
$config = [System.IO.File]::ReadAllText($configPath) | ConvertFrom-Json
$installedAutopilot = Join-Path $root '.github/skills/autopilot/scripts'
if (-not (Test-Path -LiteralPath $installedAutopilot -PathType Container)) {
    throw 'Installed autopilot authentication scripts are unavailable. Install the autopilot plugin first.'
}
$autopilotScripts = $installedAutopilot
$credentialReader = Join-Path $autopilotScripts 'get-credential.ps1'
$validator = Join-Path $autopilotScripts 'validate-auth.ps1'
foreach ($path in @($credentialReader, $validator)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Installed autopilot auth dependency is missing: $path" }
}

$target = if ($config.gitProvider -eq 'ado') { 'ado' } elseif ($config.copilotAuth -eq 'oauth') { 'copilot-cli' } else { 'copilot-autopilot' }
$token = $null
try {
    $token = & $credentialReader -Target $target
    function Invoke-RestMethod {
        param([string]$Uri, [hashtable]$Headers, [string]$Method)
        $Headers.Authorization = "Bearer $token"
        Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters
    }
    function Invoke-WebRequest {
        param([string]$Uri, [hashtable]$Headers, [string]$Method, [switch]$UseBasicParsing)
        $Headers.Authorization = "Bearer $token"
        Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
    }
    $probe = & $validator -Config $config -Token $token 6>$null 4>$null 3>$null
    [ordered]@{
        Available = $true
        CredentialTarget = $target
        GitProvider = $config.gitProvider
        Capabilities = @('credential-read', 'authentication-validation')
        Result = if ($probe.Valid) { 'Authentication validation passed.' } else { 'Authentication validation did not report readiness.' }
    } | ConvertTo-Json -Depth 5
}
catch {
    $message = $_.Exception.Message
    if ($token) { $message = $message.Replace([string]$token, '***REDACTED***') }
    throw "Authentication validation failed for credential target '$target'. $message"
}
finally {
    Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
    Remove-Item Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
    $token = $null
}

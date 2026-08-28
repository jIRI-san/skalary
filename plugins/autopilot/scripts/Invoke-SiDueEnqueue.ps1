#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)][ValidatePattern('^(?:[0-9a-f]{6}|[0-9]{3})$')][string]$PlanId,
    [Parameter(Mandatory)][ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')][string]$SourceCommit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$writerPath = Join-Path $root '.github/skills/si/scripts/Enqueue-SiDue.ps1'
if (-not (Test-Path -LiteralPath $writerPath -PathType Leaf)) {
    throw "Dependency-installed SI due writer not found: '$writerPath'."
}

try {
    $result = & $writerPath -RepoRoot $root -PlanId $PlanId -SourceCommit $SourceCommit
}
catch {
    return [pscustomobject]@{
        Status   = 'degraded'
        DueId    = $null
        Written  = $false
        Note     = "degraded: SI due enqueue failed: $($_.Exception.Message)"
        Attempts = 0
    }
}

if ($null -eq $result -or
    -not ($result.PSObject.Properties.Name -contains 'Status') -or
    [string]$result.Status -ne 'complete') {
    $writerStatus = if ($null -ne $result -and
        $result.PSObject.Properties.Name -contains 'Status') {
        [string]$result.Status
    }
    else {
        'missing-status'
    }
    return [pscustomobject]@{
        Status   = 'degraded'
        DueId    = if ($null -ne $result -and
            $result.PSObject.Properties.Name -contains 'DueId') {
            $result.DueId
        }
        else {
            $null
        }
        Written  = $false
        Note     = "degraded: SI due enqueue failed: writer status '$writerStatus'"
        Attempts = if ($null -ne $result -and
            $result.PSObject.Properties.Name -contains 'Attempts') {
            $result.Attempts
        }
        else {
            0
        }
    }
}

return $result

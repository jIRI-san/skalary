<#
.SYNOPSIS
    Runtime dispatch + offline rebundle loop for autopilot's launch.ps1.
.DESCRIPTION
    Dot-sourceable with no side effects (defines functions only) so it can be unit
    tested without launch.ps1's mandatory parameters.

    Resolve-OfflinePackagesConfig reads the StrictMode-safe offlinePackages settings
    (absent => disabled; absent maxRebundles => 3; type-validated when enabled).

    Invoke-AutopilotDispatch runs the chosen runtime orchestrator and, when offline
    packaging is active, loops on exit code 43 (an offline rebundle request from the
    runtime): it regenerates + commits + pushes the lockfile and rebuilds the feed via
    the supplied Rebundle block, then relaunches — capped by maxRebundles. The re-prep
    must complete before the relaunch clones so the resumed runtime sees a consistent
    manifest + lock pair. Returns the final orchestrator exit code.
#>

Set-StrictMode -Version Latest

function Resolve-OfflinePackagesConfig {
    param([Parameter(Mandatory)][psobject]$Config)

    $result = [pscustomobject]@{ Enabled = $false; Ecosystems = @(); MaxRebundles = 3 }

    if (-not ($Config.PSObject.Properties.Name -contains 'offlinePackages')) { return $result }
    $op = $Config.offlinePackages
    if ($null -eq $op) { return $result }

    if (-not ($op.PSObject.Properties.Name -contains 'enabled')) {
        throw "offlinePackages.enabled is required when offlinePackages is present."
    }
    if ($op.enabled -isnot [bool]) { throw "offlinePackages.enabled must be a boolean." }
    $result.Enabled = [bool]$op.enabled
    if (-not $result.Enabled) { return $result }

    if ($op.PSObject.Properties.Name -contains 'ecosystems') {
        foreach ($e in @($op.ecosystems)) {
            if ($e -notin @('dotnet', 'npm')) {
                throw "offlinePackages.ecosystems entries must be 'dotnet' or 'npm'."
            }
        }
        $result.Ecosystems = @($op.ecosystems)
    }

    if ($op.PSObject.Properties.Name -contains 'maxRebundles') {
        if ($op.maxRebundles -isnot [int] -or [int]$op.maxRebundles -lt 1) {
            throw "offlinePackages.maxRebundles must be an integer >= 1."
        }
        $result.MaxRebundles = [int]$op.maxRebundles
    }

    return $result
}

function Invoke-AutopilotDispatch {
    param(
        # Launches the runtime orchestrator; receives the feed path (or '') and
        # returns the orchestrator's integer exit code.
        [Parameter(Mandatory)][scriptblock]$Launch,
        # Builds the initial feed (offline only); returns the feed path.
        [scriptblock]$PrepareFeed,
        # Regenerates + pushes the lockfile and rebuilds the feed on exit 43;
        # returns the new feed path.
        [scriptblock]$Rebundle,
        [int]$MaxRebundles = 3,
        [bool]$Offline = $false
    )

    $feedPath = $null
    if ($Offline -and $PrepareFeed) {
        $feedPath = & $PrepareFeed
    }

    $attempt = 0
    while ($true) {
        $code = [int](& $Launch $feedPath)

        # No offline loop for host / disabled runs: first result is final.
        if (-not $Offline) { return $code }
        if ($code -ne 43) { return $code }

        if ($attempt -ge $MaxRebundles) {
            Write-Warning "Offline rebundle cap reached ($MaxRebundles); returning exit 43 without relaunch."
            return $code
        }

        $attempt++
        Write-Host "Offline rebundle requested (attempt $attempt/$MaxRebundles): regenerating lockfile + feed..."
        $feedPath = & $Rebundle
    }
}

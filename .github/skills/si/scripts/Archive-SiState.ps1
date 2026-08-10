#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [Parameter(Mandatory)][datetime]$BeforeUtc,
    [ValidateRange(1, 32)][int]$MaximumRuns = 32
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SiStateStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$root = [System.IO.Path]::GetFullPath($RepoRoot)
try {
    return Invoke-WithAtomicStoreLock -Scope "$root|si-state" `
        -TimeoutSeconds (Get-SiStateContract).Limits.LockSeconds -Action {
            $inspection = Get-SiStoreInspection -RepoRoot $root
            if ($inspection.Status -notin @('valid', 'capacity-blocked')) {
                throw "Archive-SiState refuses store status '$($inspection.Status)'."
            }
            $manifestPath = Join-Path $root 'docs/self-improvement/state.json'
            $manifestGeneration = Get-AtomicStoreGeneration -Path $manifestPath
            $manifest = Read-SiManifest -RepoRoot $root
            $inFlightRunIds = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            foreach ($entry in @($manifest.inFlight)) {
                [void]$inFlightRunIds.Add([string]$entry.runId)
            }
            $eligible = @($inspection.RunFiles | Where-Object {
                    $run = Get-Content -LiteralPath $_.FullName -Raw |
                        ConvertFrom-Json -Depth 100
                    $_.LastWriteTimeUtc -lt $BeforeUtc -and
                    [string]$run.status -in @(
                        'declined-before-ranking', 'no-candidates', 'completed'
                    ) -and
                    -not $inFlightRunIds.Contains([string]$run.runId)
                } | Sort-Object FullName | Select-Object -First $MaximumRuns)
            if ($eligible.Count -eq 0) {
                return [pscustomobject]@{ Status = 'complete'; Archived = 0; Paths = @() }
            }

            $archiveRoot = Resolve-SiStatePath -RepoRoot $root -Segments @('archive')
            $existingArchive = @(Get-ChildItem -LiteralPath $archiveRoot -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue)
            if ($existingArchive.Count + $eligible.Count -gt (Get-SiStateContract).Limits.ArchivedRuns) {
                throw 'capacity-blocked: SI archive limit reached.'
            }

            $moves = [System.Collections.Generic.List[object]]::new()
            try {
                foreach ($file in $eligible) {
                    $run = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 100
                    $created = [datetime]$run.createdAtUtc
                    $target = Resolve-SiStatePath -RepoRoot $root -Segments @(
                        'archive', $created.ToString('yyyy'), $created.ToString('MM'), $file.Name
                    )
                    $parent = Split-Path -Parent $target
                    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                        [void](New-Item -ItemType Directory -Path $parent -Force)
                    }
                    [System.IO.File]::Move($file.FullName, $target, $false)
                    $moves.Add([pscustomobject]@{ Source = $file.FullName; Target = $target; RunId = [string]$run.runId })
                }

                $archivedIds = @($moves | ForEach-Object { $_.RunId })
                $manifest.recentRuns = @($manifest.recentRuns | Where-Object {
                        $archivedIds -notcontains [string]$_.runId
                    })
                $manifest.generation = [int]$manifest.generation + 1
                $manifestJson = ($manifest | ConvertTo-Json -Depth 100 -Compress) + "`n"
                $write = Set-AtomicStoreContent -Path $manifestPath -Content $manifestJson `
                    -ExpectedGeneration $manifestGeneration -Validate {
                        param($temp)
                        if (-not (Get-Content -LiteralPath $temp -Raw |
                                Test-Json -SchemaFile (Join-Path $PSScriptRoot '../schemas/manifest.schema.json'))) {
                            throw 'Archive-SiState produced an invalid manifest.'
                        }
                    }
                if ($write.Status -ne 'complete') {
                    throw "Archive-SiState manifest update failed with status '$($write.Status)'."
                }
            }
            catch {
                for ($index = $moves.Count - 1; $index -ge 0; $index--) {
                    $move = $moves[$index]
                    if (Test-Path -LiteralPath $move.Target -PathType Leaf) {
                        [System.IO.File]::Move($move.Target, $move.Source, $false)
                    }
                }
                throw
            }
            return [pscustomobject]@{
                Status = 'complete'
                Archived = $moves.Count
                Paths = @($moves | ForEach-Object { $_.Target })
            }
        }
}
catch [System.TimeoutException] {
    return [pscustomobject]@{ Status = 'lock-timeout'; Archived = 0; Paths = @() }
}

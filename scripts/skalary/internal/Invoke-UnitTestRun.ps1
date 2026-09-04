#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ConfinedRegularPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [switch]$AllowMissing
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $rootFull $Path))
    }
    $relative = [System.IO.Path]::GetRelativePath($rootFull, $candidate)
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or
        $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)",
            [System.StringComparison]::Ordinal)) {
        throw "$Label must stay inside the repository: '$candidate'."
    }

    $volumeRoot = [System.IO.Path]::GetPathRoot($candidate)
    $cursor = $volumeRoot
    $segments = $candidate.Substring($volumeRoot.Length).Split(
        [char[]]@(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        ),
        [System.StringSplitOptions]::RemoveEmptyEntries
    )
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $cursor = Join-Path $cursor $segments[$index]
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            if ($AllowMissing) { break }
            throw "$Label does not exist: '$candidate'."
        }
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($item.PSObject.Properties.Name -contains 'LinkType' -and $item.LinkType)) {
            throw "$Label must not traverse a link or reparse point: '$cursor'."
        }
        $isLeaf = $index -eq ($segments.Count - 1)
        if ((-not $isLeaf -and $item -isnot [System.IO.DirectoryInfo]) -or
            ($isLeaf -and $item -isnot [System.IO.FileInfo])) {
            throw "$Label must name a regular file: '$candidate'."
        }
    }
    return $candidate
}

function Invoke-SkalaryUnitTestRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string[]]$TestPath = @(),
        [string[]]$TestName = @(),
        [string[]]$EvidenceTestId = @(),
        [string]$EvidenceResultPath,
        [bool]$FullRepository,
        [string]$TestResultPath
    )

    $repo = [System.IO.Path]::GetFullPath($RepoRoot)
    $testsRoot = Join-Path $repo 'tests'
    $hasEvidenceIds = $EvidenceTestId.Count -gt 0
    $hasEvidencePath = -not [string]::IsNullOrWhiteSpace($EvidenceResultPath)

    try {
        if (-not (Test-Path -LiteralPath $testsRoot -PathType Container)) {
            throw "Unit test root does not exist: '$testsRoot'."
        }
        if ($FullRepository -and ($TestPath.Count -gt 0 -or $TestName.Count -gt 0 -or $hasEvidenceIds)) {
            throw 'Choose focused test selection or -FullRepository, not both.'
        }
        if (-not $FullRepository -and $TestPath.Count -eq 0) {
            throw 'Routine unit tests require one or more repository-relative -TestPath values.'
        }
        if (@($TestName | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            throw '-TestName values must be non-empty.'
        }
        if ($hasEvidenceIds -ne $hasEvidencePath) {
            throw '-EvidenceTestId and -EvidenceResultPath must be supplied together.'
        }
        if ($hasEvidenceIds) {
            $invalid = @($EvidenceTestId | Where-Object {
                    [string]$_ -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$'
                })
            if ($invalid.Count -gt 0 -or
                @($EvidenceTestId | Sort-Object -Unique).Count -ne $EvidenceTestId.Count) {
                throw 'Evidence IDs must be unique tokens containing letters, digits, dot, underscore, or hyphen.'
            }
            $EvidenceResultPath = Resolve-ConfinedRegularPath -Root $repo `
                -Path $EvidenceResultPath -Label 'Evidence result path' -AllowMissing
        }
        if ($TestResultPath) {
            $TestResultPath = Resolve-ConfinedRegularPath -Root $repo `
                -Path $TestResultPath -Label 'Test result path' -AllowMissing
        }
    }
    catch {
        Write-Host "FocusedScopeRequired: $($_.Exception.Message)" -ForegroundColor Red
        exit 12
    }

    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $comparer = if ($IsWindows) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }

    if ($FullRepository) {
        $selectedPaths = @(Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Filter '*.Tests.ps1' |
                ForEach-Object { $_.FullName })
    }
    else {
        $selected = [System.Collections.Generic.HashSet[string]]::new($comparer)
        try {
            foreach ($relativePath in $TestPath) {
                if ([string]::IsNullOrWhiteSpace($relativePath) -or
                    [System.IO.Path]::IsPathRooted($relativePath)) {
                    throw "Focused test path must be repository-relative: '$relativePath'."
                }
                $fullPath = Resolve-ConfinedRegularPath -Root $testsRoot -Path (
                    [System.IO.Path]::GetFullPath((Join-Path $repo $relativePath))
                ) -Label "Focused test path '$relativePath'"
                if (-not $fullPath.EndsWith('.Tests.ps1', $comparison)) {
                    throw "Focused test path must name a *.Tests.ps1 file: '$relativePath'."
                }
                [void]$selected.Add($fullPath)
            }
        }
        catch {
            Write-Host "FocusedScopeRequired: $($_.Exception.Message)" -ForegroundColor Red
            exit 12
        }
        $selectedPaths = @($selected)
    }

    if ($selectedPaths.Count -eq 0) {
        Write-Host 'NoTestsDiscovered: selection contains no *.Tests.ps1 files.' -ForegroundColor Red
        exit 3
    }
    Write-Host "Unit tests: $(if ($FullRepository) { 'full repository' } else { 'focused' }) ($($selectedPaths.Count) file(s))."

    $pesterModule = Get-Module -ListAvailable -Name Pester |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -eq $pesterModule) {
        Write-Host ('PesterNotInstalled: install with ' +
            "'Install-Module Pester -Scope CurrentUser -Force'.") -ForegroundColor Red
        exit 2
    }
    Import-Module Pester -MinimumVersion $pesterModule.Version -ErrorAction Stop

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $selectedPaths
    $configuration.Run.PassThru = $true
    $configuration.Run.Exit = $false
    $configuration.TestResult.Enabled = [bool]$TestResultPath
    if ($hasEvidenceIds) {
        $configuration.Filter.FullName = @($EvidenceTestId | ForEach-Object {
                "*test:$($_)"
                "*test:$($_) *"
            })
    }
    elseif ($TestName.Count -gt 0) {
        $configuration.Filter.FullName = @($TestName)
    }
    if ($TestResultPath) {
        $resultDirectory = Split-Path -Parent $TestResultPath
        if ($resultDirectory) {
            [void](New-Item -ItemType Directory -Path $resultDirectory -Force)
        }
        $configuration.TestResult.OutputPath = $TestResultPath
    }

    $environmentBefore = @{}
    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        $environmentBefore[[string]$entry.Key] = [string]$entry.Value
    }

    function Write-EvidenceResult {
        param([object]$PesterResult, [string]$FrameworkError)

        if (-not $hasEvidenceIds) { return $null }
        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($id in $EvidenceTestId) {
            $pattern = '^test:' + [regex]::Escape($id) + '(?:\s|$)'
            $tests = @(
                if ($PesterResult) {
                    $PesterResult.Tests | Where-Object { [string]$_.Name -cmatch $pattern }
                }
            )
            $outcomes = @($tests | ForEach-Object { [string]$_.Result })
            $status = 'unrun'
            $message = $FrameworkError
            if (-not $FrameworkError) {
                if ($tests.Count -eq 0) { $message = 'no exact leading test ID match was discovered' }
                elseif ($outcomes -contains 'Failed') { $status = 'failed'; $message = 'selected test failed' }
                elseif (@($outcomes | Where-Object { $_ -eq 'Passed' }).Count -eq $tests.Count) {
                    $status = 'passed'
                    $message = ''
                }
                elseif (($outcomes -contains 'Passed') -and
                    @($outcomes | Where-Object { $_ -ne 'Passed' }).Count -gt 0) {
                    $status = 'degraded'
                    $message = 'selected tests did not all pass'
                }
                elseif (@($outcomes | Where-Object { $_ -eq 'Skipped' }).Count -eq $tests.Count) {
                    $status = 'skipped'
                    $message = 'selected test was skipped'
                }
                else {
                    $message = 'selected test did not run'
                }
            }
            $records.Add([ordered]@{
                    marker = "test:$id"
                    status = $status
                    selectedCount = $tests.Count
                    executedCount = @($outcomes | Where-Object { $_ -in @('Passed', 'Failed') }).Count
                    outcomes = $outcomes
                    message = $message
                })
        }
        $payload = [ordered]@{
            schema = 'skalary/evidence-test-results@1'
            selectedCount = if ($FrameworkError) { 0 } else { $EvidenceTestId.Count }
            executedCount = @($records | ForEach-Object { $_.executedCount } |
                    Measure-Object -Sum).Sum
            results = $records.ToArray()
        }
        $directory = Split-Path -Parent $EvidenceResultPath
        if ($directory) { [void](New-Item -ItemType Directory -Path $directory -Force) }
        Set-Content -LiteralPath $EvidenceResultPath `
            -Value (($payload | ConvertTo-Json -Depth 8) + "`n") -Encoding utf8NoBOM
        return [pscustomobject]$payload
    }

    $result = $null
    try {
        $result = Invoke-Pester -Configuration $configuration
    }
    catch {
        [void](Write-EvidenceResult -FrameworkError "discovery error: $($_.Exception.Message)")
        Write-Host "TestFilesNotDiscoverable: $($_.Exception.Message)" -ForegroundColor Red
        exit 4
    }

    if ([int]$result.FailedContainersCount -gt 0) {
        $containerError = @($result.FailedContainers | ForEach-Object {
                [string]$_.ErrorRecord
            }) -join '; '
        [void](Write-EvidenceResult -FrameworkError "discovery error: $containerError")
        Write-Host 'TestFilesNotDiscoverable: a selected file failed to load.' -ForegroundColor Red
        exit 4
    }
    $evidence = Write-EvidenceResult -PesterResult $result
    $runnable = @($result.Tests | Where-Object {
            [string]$_.Result -in @('Passed', 'Failed', 'Skipped', 'Inconclusive')
        })
    if ([int]$result.TotalCount -le 0 -or $runnable.Count -eq 0) {
        Write-Host 'NoTestsDiscovered: selection matched 0 runnable tests.' -ForegroundColor Red
        exit 3
    }
    if ([int]$result.FailedCount -gt 0 -or [int]$result.FailedBlocksCount -gt 0) {
        exit 1
    }
    if ($evidence -and @($evidence.results | Where-Object { $_.status -ne 'passed' }).Count -gt 0) {
        Write-Host 'RequiredEvidenceSkipped: selected evidence did not fully pass.' -ForegroundColor Red
        exit 8
    }

    $environmentAfter = @{}
    foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        $environmentAfter[[string]$entry.Key] = [string]$entry.Value
    }
    $names = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($environmentBefore.Keys),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $names.UnionWith([string[]]@($environmentAfter.Keys))
    $leaks = @($names | Where-Object {
            $before = if ($environmentBefore.ContainsKey($_)) { $environmentBefore[$_] } else { $null }
            $after = if ($environmentAfter.ContainsKey($_)) { $environmentAfter[$_] } else { $null }
            $before -ne $after
        })
    if ($leaks.Count -gt 0) {
        Write-Host "EnvironmentLeaked: tests changed: $($leaks -join ', ')." -ForegroundColor Red
        exit 7
    }
    exit 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $supervision = & ([System.IO.Path]::Combine($PSScriptRoot, 'FocusedSupervision.ps1'))
    $request = & $supervision.ReadBodyRequest
    Invoke-SkalaryUnitTestRun @request
    exit 0
}

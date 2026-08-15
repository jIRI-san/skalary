#requires -Version 7.0
<#
.SYNOPSIS
    Shared helpers for the step-1.2 review-run tests: isolated scratch roots, plan/run builders, the
    input handshake and the secret-corpus reconstructor.
.DESCRIPTION
    Plan c21cdc step 1.2. Every scratch directory this kit creates lives under the repository's
    gitignored `.github/.skalary/` store, never under the system temp path, so the suite writes only
    inside the working tree. A scratch root carries a `registry.json` marker (so the module's repo-root
    walk stops there) and a copy of `PlanState.psm1` (so plan-run resolution works against the scratch
    tree rather than the real one), which keeps every freeze/publish test fully isolated.
#>

Set-StrictMode -Version Latest

function Get-ReviewKitRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..' '..')).Path
}

function New-ReviewScratchRoot {
    <#
    .SYNOPSIS
        A fresh, isolated fake repository root under the gitignored store. Serves as `-RepoRoot` for
        the module so generic runs land under it and never touch the real store.
    #>
    [CmdletBinding()]
    param()

    $repoRoot = Get-ReviewKitRepoRoot
    $scratchBase = Join-Path $repoRoot '.github/.skalary/test-scratch'
    [void](New-Item -ItemType Directory -Path $scratchBase -Force)
    $root = Join-Path $scratchBase ([guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $root -Force)

    # Repo-root marker so Get-ReviewRepoRoot stops here instead of walking up to the real repo.
    Set-Content -LiteralPath (Join-Path $root 'registry.json') -Value '{"plugins":[]}' -NoNewline

    # Plan-run resolution imports PlanState from the resolved repo root.
    $planStateDir = Join-Path $root 'scripts/skalary'
    [void](New-Item -ItemType Directory -Path $planStateDir -Force)
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Destination (Join-Path $planStateDir 'PlanState.psm1') -Force

    return $root
}

function Remove-ReviewScratchRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function New-ReviewTestPlanDir {
    <#
    .SYNOPSIS
        A minimal assets-layout plan folder inside a scratch repo, so ReviewRuns resolution has a real
        plan to confine against — one the plan inventory recognizes by folder name and plan.md marker.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScratchRoot,
        [string]$Slug = 'test-plan',
        [string]$PlanId = 'abcdef'
    )

    $planDir = Join-Path $ScratchRoot "docs/implementation-plans/2026-08-02-$PlanId-$Slug"
    [void](New-Item -ItemType Directory -Path (Join-Path $planDir 'assets') -Force)
    Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Value "# test plan`n<!-- plan-id: $PlanId -->`n"
    Set-Content -LiteralPath (Join-Path $planDir 'assets/requirements.md') -Value "# Requirements`n| ID | Requirement |`n|----|----|`n| REQ-1 | x |`n"
    return $planDir
}

function New-ReviewTestPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$ReviewType = 'code',
        [string]$Scope = '1 changed file',
        [string[]]$Roster = @('model-a', 'model-b'),
        [int]$InvocationBudget = 6,
        [Parameter(Mandatory)][object[]]$Tasks
    )
    return [ordered]@{
        schema = 'skalary/review-plan@1'
        runId = $RunId
        reviewType = $ReviewType
        scope = $Scope
        roster = $Roster
        invocationBudget = $InvocationBudget
        tasks = @($Tasks)
    }
}

function New-ReviewTestRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$PlanDigest,
        [string]$ReviewType = 'code',
        [string]$Scope = '1 changed file',
        [string[]]$Roster = @('model-a', 'model-b'),
        [int]$InvocationBudget = 6,
        [Parameter(Mandatory)][object[]]$Tasks,
        [object[]]$Findings = @()
    )
    return [ordered]@{
        schema = 'skalary/review-run@1'
        runId = $RunId
        reviewType = $ReviewType
        scope = $Scope
        roster = $Roster
        invocationBudget = $InvocationBudget
        planDigest = $PlanDigest
        tasks = @($Tasks)
        findings = @($Findings)
    }
}

function Set-ReviewHandshake {
    <#
    .SYNOPSIS
        Performs the caller half of the D16 handshake: writes the computed `.tmp` file the way the
        CR/DR orchestrator's `edit` tool would, then atomically renames it onto the fixed input name
        the engine consumes.
    .DESCRIPTION
        The rename belongs to the caller, not the engine: the engine reads only
        `review-plan.input.json` / `review-result.input.json`, so a `.tmp` that was never renamed is
        not an input at all. `Set-ReviewHandshakeTemp` exists to prove exactly that.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][ValidateSet('plan', 'result')][string]$Kind,
        [Parameter(Mandatory)][object]$Object,
        # Compact JSON keeps a maximum-size envelope inside the 2 MiB input admission cap; the default
        # (indented) shape is what an editor-authored file looks like.
        [switch]$Compress
    )
    $tmp = Set-ReviewHandshakeTemp -RunDir $RunDir -Kind $Kind -Object $Object -Compress:$Compress
    $target = Join-Path $RunDir (Get-ReviewInputName -Kind $Kind)
    [System.IO.File]::Move($tmp, $target, $true)
}

function Get-ReviewInputName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('plan', 'result')][string]$Kind)
    return $(if ($Kind -eq 'plan') { 'review-plan.input.json' } else { 'review-result.input.json' })
}

function Set-ReviewHandshakeTemp {
    <#
    .SYNOPSIS
        Writes only the caller's `.tmp` file, without the atomic rename.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][ValidateSet('plan', 'result')][string]$Kind,
        [Parameter(Mandatory)][object]$Object,
        [switch]$Compress
    )
    [void](New-Item -ItemType Directory -Path $RunDir -Force)
    $name = $(if ($Kind -eq 'plan') { '.review-plan.input.tmp' } else { '.review-result.input.tmp' })
    $path = Join-Path $RunDir $name
    $json = $(if ($Compress) { ConvertTo-Json -InputObject $Object -Depth 40 -Compress } else { ConvertTo-Json -InputObject $Object -Depth 40 })
    Set-Content -LiteralPath $path -Value $json -NoNewline
    return $path
}

function Get-ReviewRunArtifact {
    <#
    .SYNOPSIS
        The content-addressed generation file of one role in a run directory, or `$null`.
    .DESCRIPTION
        Generations are named `<role>.<sha256-hex>.<ext>` (D13), so a test locates them by role rather
        than by a fixed name; the manifest is the only fixed name a published run carries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][ValidateSet('plan', 'canonical', 'summary', 'full')][string]$Role
    )

    $prefix = @{ plan = 'review-plan'; canonical = 'review-run'; summary = 'review-summary'; full = 'review-full' }[$Role]
    $extension = $(if ($Role -in @('plan', 'canonical')) { '.json' } else { '.md' })
    $pattern = '^' + [regex]::Escape($prefix) + '\.[0-9a-f]{64}' + [regex]::Escape($extension) + '$'
    $matches = @(Get-ChildItem -LiteralPath $RunDir -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -cmatch $pattern } | Sort-Object -Property Name)
    if ($matches.Count -eq 0) { return $null }
    return $matches[0].FullName
}

function Get-ReviewFrozenDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunDir)
    $planPath = Get-ReviewRunArtifact -RunDir $RunDir -Role plan
    if (-not $planPath) { throw "No frozen plan file in '$RunDir'." }
    return 'sha256:' + ((([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.IO.File]::ReadAllBytes($planPath))) | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Copy-ReviewMap {
    <#
    .SYNOPSIS
        A shallow copy of an ordered map, so a test can vary one field of a built plan or run without
        an OrderedDictionary Clone (which does not exist) and without mutating the original.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Map)
    $copy = [ordered]@{}
    foreach ($key in $Map.Keys) { $copy[$key] = $Map[$key] }
    return $copy
}

function Build-ReviewSecretToken {
    <#
    .SYNOPSIS
        Reconstructs one allow/block corpus case's token-shaped string from its inert fragments, so no
        complete token is ever committed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Segments)

    $builder = [System.Text.StringBuilder]::new()
    foreach ($segment in $Segments) {
        $names = $segment.PSObject.Properties.Name
        if ($names -contains 'literal') { [void]$builder.Append([string]$segment.literal); continue }
        if ($names -contains 'repeat') { [void]$builder.Append(([string]$segment.repeat) * [int]$segment.count); continue }
        if ($names -contains 'cycle') {
            $alphabet = [string]$segment.cycle
            for ($i = 0; $i -lt [int]$segment.count; $i++) { [void]$builder.Append($alphabet[$i % $alphabet.Length]) }
            continue
        }
        throw "Unknown secret segment shape: $($names -join ',')"
    }
    return $builder.ToString()
}

Export-ModuleMember -Function @(
    'Get-ReviewKitRepoRoot', 'New-ReviewScratchRoot', 'Remove-ReviewScratchRoot', 'New-ReviewTestPlanDir',
    'New-ReviewTestPlan', 'New-ReviewTestRun', 'Set-ReviewHandshake', 'Set-ReviewHandshakeTemp', 'Get-ReviewInputName',
    'Get-ReviewRunArtifact', 'Get-ReviewFrozenDigest', 'Copy-ReviewMap', 'Build-ReviewSecretToken'
)

#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PathComparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
$script:PathComparer = if ($IsWindows) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:ExpectedConcernIds = @(
    'security'
    'correctness-reliability'
    'architecture-patterns'
    'performance'
    'testing-evidence'
    'maintainability-consistency'
    'operability-observability'
)
$script:SurfaceByReviewType = [ordered]@{
    cr = [ordered]@{
        Plugin = 'code-review'
        Prefix = 'cr'
        DescriptionTarget = 'code review'
        ReviewKind = 'code reviewer'
        InputDescription = 'You are given the list of changed files plus the design notes that match them, you read those files yourself with your `read` and `search` tools, and you report only findings that fall inside your lens.'
        TargetNoun = 'change'
        ArchitectureConsequence = 'is a finding regardless of which concern surfaced it.'
        ContextDiscovery = 'Map the changed file paths against the `globs` column and load the matched notes before reviewing.'
        ContextTarget = 'Read the changed files themselves. Nothing pre-extracts them for you - reading is part of your job.'
        ReferenceTarget = '[File.cs](src/path/File.cs#L10)'
        ReferenceOmission = 'omit this line if no file references apply.'
        ReviewTarget = 'code change'
    }
    dr = [ordered]@{
        Plugin = 'design-review'
        Prefix = 'dr'
        DescriptionTarget = 'design review'
        ReviewKind = 'design reviewer'
        InputDescription = 'You are given an implementation plan (or one section of one) plus the design notes it touches, and you report only findings that fall inside your lens.'
        TargetNoun = 'plan'
        ArchitectureConsequence = 'is an architectural finding, not a suggestion.'
        ContextDiscovery = 'Identify the subsystems, paths, and components the plan names, and load the matched notes before reviewing.'
        ContextTarget = 'Under the plan-assets layout, the plan body is `plan.md` and its detail lives in `assets/`. Read the assets your lens needs - do not assume the whole tree was passed to you.'
        ReferenceTarget = 'the plan step, requirement, or risk id the finding applies to'
        ReferenceOmission = 'omit this line if none apply.'
        ReviewTarget = 'implementation plan'
    }
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $rootPrefix = $Root.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($rootPrefix, $script:PathComparison)
}

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$DisplayPath
    )

    $relative = [System.IO.Path]::GetRelativePath($Root, $Path)
    $current = $Root
    foreach ($segment in $relative.Split(
            [char[]]@(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ),
            [System.StringSplitOptions]::RemoveEmptyEntries
        )) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Managed review-concern path resolves outside the repository through a reparse point: '$DisplayPath'."
        }
    }
}

function Resolve-ConfinedInput {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Root
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Review-concern input path must be repository-relative: '$RelativePath'."
    }

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    if (-not (Test-PathInsideRoot -Path $candidate -Root $Root)) {
        throw "Review-concern input path escapes the repository: '$RelativePath'."
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Review-concern input not found: '$RelativePath'."
    }
    Assert-NoReparsePoint -Path $candidate -Root $Root -DisplayPath $RelativePath

    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    if (-not (Test-PathInsideRoot -Path $resolved -Root $Root)) {
        throw "Review-concern input resolves outside the repository: '$RelativePath'."
    }
    return $resolved
}

function Resolve-ConfinedOutput {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Root
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath -notmatch '^[a-z0-9][a-z0-9./-]+$') {
        throw "Invalid managed review-concern output path: '$RelativePath'."
    }

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    if (-not (Test-PathInsideRoot -Path $candidate -Root $Root)) {
        throw "Managed review-concern output escapes the repository: '$RelativePath'."
    }
    Assert-NoReparsePoint -Path $candidate -Root $Root -DisplayPath $RelativePath

    $parent = Split-Path -Parent $candidate
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Managed review-concern output directory not found: '$RelativePath'."
    }
    $resolvedParent = (Resolve-Path -LiteralPath $parent).Path
    if (-not (Test-PathInsideRoot -Path $resolvedParent -Root $Root)) {
        throw "Managed review-concern output directory resolves outside the repository: '$RelativePath'."
    }

    if (Test-Path -LiteralPath $candidate) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Managed review-concern output is a reparse point: '$RelativePath'."
        }
        if ($item.PSIsContainer -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Managed review-concern output is not a regular file: '$RelativePath'."
        }
    }

    return $candidate
}

function Add-Replacement {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Values,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    $Values[$Name] = $Value
}

function Render-Agent {
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)]$Concern,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Surface
    )

    $reviewType = [string]$Surface['Prefix']
    $variant = $Concern.variants.$reviewType
    $values = [ordered]@{}
    Add-Replacement -Values $values -Name 'ARCHITECTURE_CONSEQUENCE' -Value ([string]$Surface['ArchitectureConsequence'])
    Add-Replacement -Values $values -Name 'CONTEXT_DISCOVERY' -Value ([string]$Surface['ContextDiscovery'])
    Add-Replacement -Values $values -Name 'CONTEXT_TARGET' -Value ([string]$Surface['ContextTarget'])
    Add-Replacement -Values $values -Name 'DESCRIPTION' -Value "$($Concern.label) reviewer for $($Surface['DescriptionTarget']) - one concern, model-agnostic. Invoked by the $reviewType orchestrator only."
    Add-Replacement -Values $values -Name 'FOCUS_AREAS' -Value ((@($variant.focusAreas) | ForEach-Object { "- $_" }) -join "`n")
    Add-Replacement -Values $values -Name 'ID' -Value ([string]$Concern.id)
    Add-Replacement -Values $values -Name 'INPUT_DESCRIPTION' -Value ([string]$Surface['InputDescription'])
    Add-Replacement -Values $values -Name 'LABEL' -Value ([string]$Concern.label)
    Add-Replacement -Values $values -Name 'PREFIX' -Value $reviewType
    Add-Replacement -Values $values -Name 'REFERENCE_OMISSION' -Value ([string]$Surface['ReferenceOmission'])
    Add-Replacement -Values $values -Name 'REFERENCE_TARGET' -Value ([string]$Surface['ReferenceTarget'])
    Add-Replacement -Values $values -Name 'REVIEW_KIND' -Value ([string]$Surface['ReviewKind'])
    Add-Replacement -Values $values -Name 'REVIEW_TARGET' -Value ([string]$Surface['ReviewTarget'])
    Add-Replacement -Values $values -Name 'SCOPE' -Value ([string]$variant.scope)
    Add-Replacement -Values $values -Name 'SHARED_GUIDANCE' -Value ([string]$Concern.sharedGuidance)
    Add-Replacement -Values $values -Name 'TARGET_NOUN' -Value ([string]$Surface['TargetNoun'])

    $rendered = $Template
    foreach ($name in $values.Keys) {
        $token = "@@$name@@"
        if (-not $rendered.Contains($token, [System.StringComparison]::Ordinal)) {
            throw "Review-concern template is missing required placeholder '$token'."
        }
        $rendered = $rendered.Replace($token, [string]$values[$name], [System.StringComparison]::Ordinal)
    }

    $unresolved = [regex]::Match($rendered, '@@[A-Z_]+@@')
    if ($unresolved.Success) {
        throw "Review-concern template contains unresolved placeholder '$($unresolved.Value)'."
    }
    return $rendered.TrimEnd("`r", "`n") + "`n"
}

function Render-LedgerMap {
    param(
        [Parameter(Mandatory)][object[]]$Concerns
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(
            '# Concern -> review-ledger category map'
            ''
            'The map is **total** (every concern has a target for both review types) and **deterministic**, but'
            'not bijective: two concerns can land in the same ledger category. Its job is to remove the judgment'
            'call from `/ci` harvest, which otherwise distils ledger entries by rubric keywords.'
            ''
            '| Concern | `cr` ledger category | `dr` ledger category |'
            '|---|---|---|'
        )) {
        $lines.Add($line)
    }
    foreach ($concern in $Concerns) {
        $lines.Add("| ``$($concern.id)`` | ``$($concern.ledger.cr)`` | ``$($concern.ledger.dr)`` |")
    }
    $lines.Add('')
    $differingConcerns = @($Concerns | Where-Object {
            [string]$_.ledger.cr -cne [string]$_.ledger.dr
        })
    if ($differingConcerns.Count -eq 1 -and
        [string]$differingConcerns[0].id -ceq 'testing-evidence' -and
        [string]$differingConcerns[0].ledger.cr -ceq 'testing.md' -and
        [string]$differingConcerns[0].ledger.dr -ceq 'plan-structure.md') {
        foreach ($line in @(
                '`testing-evidence` is the only concern whose target differs by review type: in a plan review,'
                'evidence findings are about phase gating and marker coverage (`plan-structure`), while in a code'
                'review they are about test quality (`testing`).'
            )) {
            $lines.Add($line)
        }
    }
    elseif ($differingConcerns.Count -eq 0) {
        $lines.Add('`cr` and `dr` currently use the same ledger target for every concern.')
    }
    else {
        $lines.Add('Ledger targets that differ by review type:')
        foreach ($concern in $differingConcerns) {
            $lines.Add("- ``$($concern.id)``: ``cr`` -> ``$($concern.ledger.cr)``; ``dr`` -> ``$($concern.ledger.dr)``")
        }
    }
    foreach ($line in @(
            ''
            '## Usage'
            ''
            '- **Write side (harvest):** a finding raised by concern `X` is appended to the category this table'
            '  names for the review type that produced it. Pass that category to'
            '  `scripts/skalary/Add-LedgerEntry.ps1 -Category <name>` with the file extension dropped. There is no'
            '  fallback branch: an unmapped concern is a bug in this table, not a cue to improvise.'
            '- **Read side (`ledger-consult`):** unchanged. Consulting keeps its existing keyword rubric so a'
            '  lookup stays cheap and targeted; this map governs the **write** side only.'
        )) {
        $lines.Add($line)
    }
    return ($lines -join "`n") + "`n"
}

function Render-ReviewStandards {
    param(
        [Parameter(Mandatory)][object[]]$Concerns
    )

    $standards = @(
        foreach ($concern in $Concerns) {
            $entries = if ($concern.PSObject.Properties.Name -contains 'standards') {
                @($concern.standards)
            }
            else {
                @()
            }
            foreach ($standard in $entries) {
                [ordered]@{
                    id = [string]$standard.id
                    concern = [string]$concern.id
                    guidance = [string]$standard.guidance
                    localizable = [bool]$standard.localizable
                }
            }
        }
    )
    $document = [ordered]@{
        schema = 'skalary/review-standards@1'
        standards = $standards
    }
    return (($document | ConvertTo-Json -Depth 8) -replace "`r`n", "`n") + "`n"
}

function Write-FileAtomically {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $temporary = Join-Path (Split-Path -Parent $Path) ".$([System.IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, $Content, $script:Utf8NoBom)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Test-ByteSequenceEqual {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Left,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

$repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $repoRootPath -PathType Container)) {
    throw "Repository root not found: '$RepoRoot'."
}
$repoRootPath = (Resolve-Path -LiteralPath $repoRootPath).Path

$registryPath = Resolve-ConfinedInput -RelativePath 'tools/review-concerns.json' -Root $repoRootPath
$schemaPath = Resolve-ConfinedInput -RelativePath 'schemas/review/review-concerns.schema.json' -Root $repoRootPath
$templatePath = Resolve-ConfinedInput -RelativePath 'tools/review-concern-agent.template.md' -Root $repoRootPath

$registryJson = [System.IO.File]::ReadAllText($registryPath)
if (-not (Test-Json -Json $registryJson -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
    throw "Review-concern registry does not satisfy '$schemaPath'."
}
$registry = $registryJson | ConvertFrom-Json -Depth 30
$concernIds = @($registry.concerns | ForEach-Object { [string]$_.id })
if (($concernIds.Count -ne $script:ExpectedConcernIds.Count) -or
    (($concernIds -join "`n") -cne ($script:ExpectedConcernIds -join "`n"))) {
    throw "Review-concern registry must contain the settled concern ids in canonical order: $($script:ExpectedConcernIds -join ', ')."
}

foreach ($concern in $registry.concerns) {
    foreach ($value in @(
            [string]$concern.sharedGuidance
            [string]$concern.variants.cr.scope
            [string]$concern.variants.dr.scope
            [string[]]$concern.variants.cr.focusAreas
            [string[]]$concern.variants.dr.focusAreas
        )) {
        if ($value -match '[\r\n@{}]') {
            throw "Review-concern '$($concern.id)' contains unsafe template prose."
        }
    }
    foreach ($reviewType in @('cr', 'dr')) {
        $ledgerPath = Resolve-ConfinedInput -RelativePath "docs/review-ledger/$($concern.ledger.$reviewType)" -Root $repoRootPath
        if (-not $ledgerPath) {
            throw "Review-concern '$($concern.id)' has no $reviewType ledger mapping."
        }
    }
    if ($concern.PSObject.Properties.Name -contains 'standards') {
        foreach ($standard in @($concern.standards)) {
            if ([string]$standard.guidance -match '[\r\n@{}]') {
                throw "Review standard '$($standard.id)' contains unsafe template prose."
            }
        }
    }
}

$template = [System.IO.File]::ReadAllText($templatePath)
$outputs = [System.Collections.Generic.List[object]]::new()
$expectedAgentPaths = [System.Collections.Generic.HashSet[string]]::new(
    $script:PathComparer
)
foreach ($reviewType in @('cr', 'dr')) {
    $surfaceSpec = $script:SurfaceByReviewType[$reviewType]
    foreach ($concern in $registry.concerns) {
        $relativePath = "plugins/$($surfaceSpec['Plugin'])/agents/$reviewType-$($concern.id).agent.md"
        [void]$expectedAgentPaths.Add($relativePath)
        $outputs.Add([pscustomobject]@{
                RelativePath = $relativePath
                Path = Resolve-ConfinedOutput -RelativePath $relativePath -Root $repoRootPath
                Content = Render-Agent -Template $template -Concern $concern -Surface $surfaceSpec
            })
    }
}

$mapContent = Render-LedgerMap -Concerns @($registry.concerns)
foreach ($relativePath in @(
        'plugins/code-review/skills/cr/assets/concern-ledger-map.md'
        'plugins/design-review/skills/dr/assets/concern-ledger-map.md'
    )) {
    $outputs.Add([pscustomobject]@{
            RelativePath = $relativePath
            Path = Resolve-ConfinedOutput -RelativePath $relativePath -Root $repoRootPath
            Content = $mapContent
        })
}

$standardsContent = Render-ReviewStandards -Concerns @($registry.concerns)
foreach ($relativePath in @(
        'plugins/code-review/skills/cr/assets/review-standards.json'
        'plugins/design-review/skills/dr/assets/review-standards.json'
    )) {
    $outputs.Add([pscustomobject]@{
            RelativePath = $relativePath
            Path = Resolve-ConfinedOutput -RelativePath $relativePath -Root $repoRootPath
            Content = $standardsContent
        })
}

$stale = [System.Collections.Generic.List[object]]::new()
foreach ($reviewType in @('cr', 'dr')) {
    $surfaceSpec = $script:SurfaceByReviewType[$reviewType]
    $agentDir = Resolve-Path -LiteralPath (Join-Path $repoRootPath "plugins/$($surfaceSpec['Plugin'])/agents")
    foreach ($file in Get-ChildItem -LiteralPath $agentDir -File -Filter "$reviewType-*.agent.md") {
        $relativePath = [System.IO.Path]::GetRelativePath($repoRootPath, $file.FullName).Replace('\', '/')
        if (-not $expectedAgentPaths.Contains($relativePath)) {
            $stale.Add([pscustomobject]@{
                    RelativePath = $relativePath
                    Path = Resolve-ConfinedOutput -RelativePath $relativePath -Root $repoRootPath
                })
        }
    }
}

$changed = @(
    $outputs | Where-Object {
        if (-not (Test-Path -LiteralPath $_.Path -PathType Leaf)) {
            return $true
        }
        $actualBytes = [System.IO.File]::ReadAllBytes($_.Path)
        $expectedBytes = $script:Utf8NoBom.GetBytes([string]$_.Content)
        return -not (Test-ByteSequenceEqual -Left $actualBytes -Right $expectedBytes)
    }
)

if ($WhatIfPreference) {
    if ($changed.Count -gt 0 -or $stale.Count -gt 0) {
        throw "Review-concern generation drift detected: $($changed.Count) changed or missing output(s), $($stale.Count) extra agent(s). Run scripts/skalary/Sync-ReviewConcerns.ps1."
    }
    Write-Host 'Review-concern outputs are up to date (no drift).'
    return
}

foreach ($output in $changed) {
    if ($PSCmdlet.ShouldProcess($output.Path, "Generate '$($output.RelativePath)'")) {
        Write-FileAtomically -Path $output.Path -Content $output.Content
    }
}
foreach ($file in $stale) {
    if ($PSCmdlet.ShouldProcess($file.Path, "Remove stale generated concern agent '$($file.RelativePath)'")) {
        Remove-Item -LiteralPath $file.Path -Force
    }
}

Write-Host "Review-concern generation completed. Changed: $($changed.Count). Removed stale: $($stale.Count)."

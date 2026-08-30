#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PluginFrontmatter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Frontmatter source file not found: $Path"
    }

    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -lt 3 -or [string]$lines[0] -ne '---') {
        throw "File '$Path' must start with a frontmatter delimiter '---'."
    }

    $closingDelimiterLine = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ([string]$lines[$index] -eq '---') {
            $closingDelimiterLine = $index
            break
        }
    }

    if ($closingDelimiterLine -lt 0) {
        throw "File '$Path' has an unterminated frontmatter block."
    }

    $frontmatter = [ordered]@{}
    for ($index = 1; $index -lt $closingDelimiterLine; $index++) {
        $line = [string]$lines[$index]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^\s*#') {
            continue
        }

        if ($line -match '^(?<key>[A-Za-z][\w-]*)\s*:\s*(?<value>.*)$') {
            $key = [string]$Matches.key
            $rawValue = [string]$Matches.value
            $trimmedValue = $rawValue.Trim()

            if ([string]::IsNullOrWhiteSpace($trimmedValue)) {
                $frontmatter[$key] = $null
                continue
            }

            if (($trimmedValue.StartsWith("'") -and $trimmedValue.EndsWith("'")) -or
                ($trimmedValue.StartsWith('"') -and $trimmedValue.EndsWith('"'))) {
                $frontmatter[$key] = $trimmedValue.Substring(1, $trimmedValue.Length - 2)
                continue
            }

            # Keep nested/complex YAML values opaque; only scalar presence/value is needed.
            if ($trimmedValue.StartsWith('[') -or $trimmedValue.StartsWith('{') -or
                $trimmedValue -eq '|' -or $trimmedValue -eq '>') {
                $frontmatter[$key] = $null
                continue
            }

            $frontmatter[$key] = $trimmedValue
            continue
        }

        if ($line -match '^\s+') {
            continue
        }

        throw "File '$Path' has malformed frontmatter line $($index + 1): '$line'"
    }

    if ($frontmatter.Count -eq 0) {
        throw "File '$Path' frontmatter has no top-level keys."
    }

    return $frontmatter
}

function Test-RequiredFrontmatter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('agent', 'prompt', 'skill')]
        [string]$ArtifactType,

        [Parameter(Mandatory)]
        [hashtable]$Frontmatter,

        [string]$Path = '<unknown>'
    )

    $requiredKeysByType = @{
        agent  = @('name', 'description')
        prompt = @('name', 'description', 'agent')
        skill  = @('name', 'description', 'user-invocable', 'disable-model-invocation')
    }

    foreach ($key in $requiredKeysByType[$ArtifactType]) {
        if (-not $Frontmatter.ContainsKey($key)) {
            throw "File '$Path' ($ArtifactType) is missing required frontmatter key '$key'."
        }

        $value = [string]$Frontmatter[$key]
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "File '$Path' ($ArtifactType) has empty required frontmatter key '$key'."
        }
    }

    return $true
}

function Get-ArtifactType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $normalizedPath = ($DestinationPath -replace '\\', '/').Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        throw 'Destination path is empty.'
    }

    if ($normalizedPath.EndsWith('.agent.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'agent'
    }

    if ($normalizedPath.EndsWith('.prompt.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'prompt'
    }

    if ($normalizedPath.EndsWith('/SKILL.md', [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.Equals('SKILL.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'skill'
    }

    throw "Unsupported artifact destination path '$DestinationPath'."
}

function Assert-EvalMarkerOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$BeforeMarker,

        [Parameter(Mandatory)]
        [string]$AfterMarker,

        [System.StringComparison]$Comparison = [System.StringComparison]::Ordinal
    )

    $beforeIndex = $Text.IndexOf($BeforeMarker, $Comparison)
    $afterIndex = $Text.IndexOf($AfterMarker, $Comparison)
    $beforeIndex | Should -BeGreaterOrEqual 0 -Because "'$BeforeMarker' must be present"
    $afterIndex | Should -BeGreaterOrEqual 0 -Because "'$AfterMarker' must be present"
    $beforeIndex | Should -BeLessThan $afterIndex -Because "'$BeforeMarker' must precede '$AfterMarker'"
}

function Assert-FleetConsumerParity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$PluginRoot,

        [Parameter(Mandatory)]
        [object]$Manifest,

        [Parameter(Mandatory)]
        [string]$PluginName,

        [Parameter(Mandatory)]
        [string[]]$RelativePath,

        [Parameter(Mandatory)]
        [string]$FleetModuleDest
    )

    $registry = Get-Content -LiteralPath (Join-Path $RepoRoot 'registry.json') -Raw |
        ConvertFrom-Json -Depth 100
    $marketplace = Get-Content -LiteralPath (Join-Path $RepoRoot '.github/plugin/marketplace.json') -Raw |
        ConvertFrom-Json -Depth 50

    foreach ($relative in $RelativePath) {
        $entries = @($Manifest.files | Where-Object { [string]$_.dest -ceq $relative })
        $entries.Count | Should -Be 1
        $source = Join-Path $PluginRoot ([string]$entries[0].src)
        $installed = Join-Path (Join-Path $RepoRoot '.github') $relative
        (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    }

    $catalog = @($registry.plugins | Where-Object { [string]$_.name -ceq $PluginName })
    $catalog.Count | Should -Be 1
    [string]$catalog[0].version | Should -Be ([string]$Manifest.version)
    $fleetCatalog = @($catalog[0].files | Where-Object { [string]$_.dest -ceq $FleetModuleDest })
    $fleetCatalog.Count | Should -Be 1
    [string]$fleetCatalog[0].sha256 | Should -Be (
        (Get-FileHash -LiteralPath (Join-Path $PluginRoot ([string]$fleetCatalog[0].src)) -Algorithm SHA256).Hash.ToLowerInvariant()
    )
    $market = @($marketplace.plugins | Where-Object { [string]$_.name -ceq $PluginName })
    $market.Count | Should -Be 1
    [string]$market[0].version | Should -Be ([string]$Manifest.version)
    return $true
}

function Test-ReferencedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw "Referenced path is empty (base '$BasePath')."
    }

    $normalizedBasePath = [System.IO.Path]::GetFullPath($BasePath)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $normalizedBasePath ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $baseWithSeparator = $normalizedBasePath.TrimEnd($separator) + $separator

    if (-not $candidate.StartsWith($baseWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Referenced path '$RelativePath' escapes base path '$BasePath'."
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Referenced path not found: $candidate"
    }

    return $candidate
}

function Resolve-MarkdownLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$ArtifactDestinationPath,

        [Parameter(Mandatory)]
        [string]$LinkTarget
    )

    $trimmedTarget = $LinkTarget.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedTarget)) {
        return $null
    }

    if ($trimmedTarget.StartsWith('#')) {
        return $null
    }

    if ($trimmedTarget -match '^(https?://|mailto:)') {
        return $null
    }

    $targetWithoutFragment = $trimmedTarget
    $fragmentDelimiter = $trimmedTarget.IndexOf('#')
    if ($fragmentDelimiter -ge 0) {
        $targetWithoutFragment = $trimmedTarget.Substring(0, $fragmentDelimiter)
    }

    if ([string]::IsNullOrWhiteSpace($targetWithoutFragment)) {
        return $null
    }

    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $artifactInstallPath = [System.IO.Path]::GetFullPath(
        (Join-Path (Join-Path $repoRootPath '.github') ($ArtifactDestinationPath -replace '/', [System.IO.Path]::DirectorySeparatorChar))
    )
    $artifactInstallDirectory = Split-Path -Parent $artifactInstallPath

    $normalizedTarget = $targetWithoutFragment -replace '/', [System.IO.Path]::DirectorySeparatorChar
    $candidate = if ($targetWithoutFragment.StartsWith('/')) {
        [System.IO.Path]::GetFullPath((Join-Path $repoRootPath $normalizedTarget.TrimStart('\', '/')))
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $artifactInstallDirectory $normalizedTarget))
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $repoWithSeparator = $repoRootPath.TrimEnd($separator) + $separator
    if (-not $candidate.StartsWith($repoWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Markdown link '$LinkTarget' resolves outside repo root '$RepoRoot'."
    }

    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Markdown link target not found: '$LinkTarget' -> $candidate"
    }

    return $candidate
}

function Test-BodySection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('agent', 'prompt', 'skill')]
        [string]$ArtifactType,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Artifact file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $body = $raw -replace '(?s)^---\r?\n.*?\r?\n---\r?\n?', ''
    if ([string]::IsNullOrWhiteSpace($body)) {
        throw "File '$Path' has an empty markdown body."
    }

    $hasHeading = [regex]::IsMatch($body, '(?m)^\s*#{1,6}\s+\S')
    if (-not $hasHeading) {
        throw "File '$Path' must contain at least one markdown heading."
    }

    if ($ArtifactType -eq 'agent') {
        $nonHeadingBody = ($body -split "`r?`n" | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^\s*#{1,6}\s+'
            })
        if (@($nonHeadingBody).Count -eq 0) {
            throw "Agent file '$Path' must contain non-heading body content."
        }

        return $true
    }

    $hasProcedure = (
        [regex]::IsMatch($body, '(?mi)^\s*\d+\.\s+\S') -or
        [regex]::IsMatch($body, '(?mi)^\s*##\s*step\b')
    )
    if (-not $hasProcedure) {
        throw "File '$Path' ($ArtifactType) must include a numbered or step-style procedure."
    }

    return $true
}

function Get-ReviewRunEvalContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PluginRoot,
        [Parameter(Mandatory)][ValidateSet('cr', 'dr')][string]$ReviewId
    )

    $skillRoot = Join-Path $PluginRoot "skills/$ReviewId"
    return [pscustomobject]@{
        Id         = $ReviewId
        Skill      = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw
        Agent      = Get-Content -LiteralPath (Join-Path $PluginRoot "agents/$ReviewId.agent.md") -Raw
        Collation  = Get-Content -LiteralPath (Join-Path $skillRoot 'assets/collation-guide.md') -Raw
        Dispatch   = Get-Content -LiteralPath (Join-Path $skillRoot 'assets/dispatch-guide.md') -Raw
        Writer     = Join-Path $skillRoot 'scripts/Build-ReviewReport.ps1'
        PlanSchema = Join-Path $skillRoot 'scripts/schemas/review/review-plan.schema.json'
    }
}

function Assert-ReviewEvalMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-ReviewEvalNotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

function Assert-ReviewEvalOrder {
    param([string]$Text, [string[]]$Headings)
    $previous = -1
    foreach ($heading in $Headings) {
        $index = $Text.IndexOf($heading, [System.StringComparison]::Ordinal)
        if ($index -lt 0) { throw "Required lifecycle heading is missing: $heading" }
        if ($index -le $previous) { throw "Lifecycle heading is out of order: $heading" }
        $previous = $index
    }
}

function Test-ReviewRunStructuralInvariant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]
        [ValidateSet(
            'WriterScope',
            'FreezeBeforeDispatch',
            'IndependentDispatch',
            'CompleteDispatch',
            'NonzeroTaskPlan',
            'RendererOwnedMarkdown',
            'FixedPolicyAndRoot',
            'DegradedArtifactPreservation',
            'BoundedRetry'
        )]
        [string]$Invariant
    )

    switch ($Invariant) {
        'WriterScope' {
            Assert-ReviewEvalMatch $Context.Agent '(?m)^tools:.*\bedit\b' 'The orchestrator does not declare edit.'
            Assert-ReviewEvalMatch $Context.Agent 'Absolute edit rule' 'The absolute edit rule is missing.'
            Assert-ReviewEvalMatch $Context.Agent 'only the two computed review-run temporary JSON inputs' 'The edit rule is not confined to two temporary inputs.'
            Assert-ReviewEvalMatch $Context.Collation '<run-root>/\.review-plan\.input\.tmp' 'The plan temporary input is missing.'
            Assert-ReviewEvalMatch $Context.Collation '<run-root>/\.review-result\.input\.tmp' 'The result temporary input is missing.'
            Assert-ReviewEvalMatch $Context.Collation 'must never edit reviewed code' 'The reviewed-code write prohibition is missing.'
            foreach ($text in @($Context.Agent, $Context.Skill, $Context.Collation)) {
                foreach ($line in ($text -split '\r?\n')) {
                    if ($line -match '(?i)\b(?:edit|write|modify)\b.{0,100}(?:reviewed (?:code|plan)|fixed inputs?|manifests?|generated artifacts?|any other path)' -and
                        $line -notmatch '(?i)\b(?:never|must not|cannot|do not|forbid(?:den)?)\b') {
                        throw "A broader write permission was added beside the absolute rule: $line"
                    }
                }
            }
        }
        'FreezeBeforeDispatch' {
            $step = if ($Context.Id -eq 'cr') { 3 } else { 4 }
            Assert-ReviewEvalOrder $Context.Skill @(
                "## Step ${step}: Plan and freeze the run"
                "## Step $($step + 1): Dispatch the admitted Fleet waves independently"
                "## Step $($step + 2): Publish and close out"
            )
            Assert-ReviewEvalOrder $Context.Collation @(
                '## Freeze before dispatch'
                '## Independent dispatch and in-memory collection'
                '## Publish once'
            )
        }
        'IndependentDispatch' {
            Assert-ReviewEvalMatch $Context.Skill 'Do not include any\s+prior reviewer''s result' 'Prior-result input is not forbidden.'
            Assert-ReviewEvalMatch $Context.Skill 'skip a task because\s+another reviewer found the same\s+issue' 'Dispatch suppression is not forbidden.'
            Assert-ReviewEvalMatch $Context.Collation 'Do not show one reviewer''s output to another reviewer' 'Cross-reviewer priming is not forbidden.'
            Assert-ReviewEvalMatch $Context.Dispatch 'Never prime one reviewer with another result' 'The dispatch guide permits priming.'
        }
        'CompleteDispatch' {
            Assert-ReviewEvalMatch $Context.Collation 'Dispatch every frozen task exactly once' 'The frozen task set is not dispatched exactly once.'
            Assert-ReviewEvalMatch $Context.Skill 'Dispatch each task''s frozen concern once with its exact frozen\s+model binding' 'Concern/model slots are not dispatched once.'
            Assert-ReviewEvalMatch $Context.Skill 'Submit\s+exactly one structured projection per admitted task' 'The caller need not settle every admitted task.'
        }
        'NonzeroTaskPlan' {
            $schema = Get-Content -LiteralPath $Context.PlanSchema -Raw | ConvertFrom-Json -Depth 30
            if ([int]$schema.'$defs'.plannedTasks.minItems -ne 1) { throw 'The frozen plan permits zero tasks.' }
            $type = if ($Context.Id -eq 'cr') { 'code' } else { 'design' }
            Assert-ReviewEvalMatch $Context.Skill "complete ``$type`` task plan" 'The skill does not require a complete typed task plan.'
            Assert-ReviewEvalMatch $Context.Collation 'Build the complete task matrix' 'The caller does not build the complete matrix.'
        }
        'RendererOwnedMarkdown' {
            Assert-ReviewEvalMatch $Context.Collation 'Do not hand-build Markdown' 'Caller-authored Markdown is not forbidden.'
            Assert-ReviewEvalMatch $Context.Collation 'Get-ReviewRun\.ps1 -View Summary\|Full' 'The caller does not require both verifying reader modes.'
            foreach ($text in @($Context.Skill, $Context.Agent, $Context.Dispatch, $Context.Collation)) {
                Assert-ReviewEvalNotMatch $text '###\s*\[\d+\]|\|\s*\*\*Severity\*\*\s*\||(?m)^##\s+Recommendations\s*$' 'Report layout leaked into caller prose.'
            }
        }
        'FixedPolicyAndRoot' {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $Context.Writer, [ref]$tokens, [ref]$errors
            )
            if (@($errors).Count -gt 0) { throw "The installed writer does not parse: $($errors -join '; ')" }
            $parameters = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            if (($parameters -join ',') -cne 'Mode,RunId,PlanDir') {
                throw "The installed writer exposes alternate parameters: $($parameters -join ', ')"
            }
            Assert-ReviewEvalMatch $Context.Collation 'Use only the returned `runRoot`; never derive a generic or plan layout in the caller' 'The engine-owned root is not authoritative.'
            Assert-ReviewEvalNotMatch $Context.Collation '(?i)-(Schema|Policy|RepoRoot|OutputRoot)\b' 'Caller-selectable policy or roots are documented.'
        }
        'DegradedArtifactPreservation' {
            Assert-ReviewEvalMatch $Context.Collation '\| `5` \| Read and deliver the degraded summary and verified full detail with `-View Full`' 'Exit 5 does not deliver verified full detail before failure propagation.'
            Assert-ReviewEvalMatch $Context.Collation 'remove a generic run only after both are delivered' 'Generic cleanup can precede verified summary/full delivery.'
            Assert-ReviewEvalMatch $Context.Skill 'Preserve plan-associated\s+artifacts' 'Plan-associated degraded artifacts are not preserved.'
        }
        'BoundedRetry' {
            Assert-ReviewEvalMatch $Context.Collation '\| `4` \| Surface the lock/publication failure; retry the same UUID and unchanged input only after the fault is corrected' 'Exit 4 retry is not bounded to corrected identical input.'
            Assert-ReviewEvalMatch $Context.Collation '\| `3` \| Terminal for this UUID' 'Exit 3 is not terminal.'
            Assert-ReviewEvalNotMatch $Context.Collation '(?i)\bwhile\b.{0,80}\bretry\b|retry (forever|indefinitely)' 'The caller permits an unbounded retry loop.'
        }
        default { throw "No structural assertion implements invariant '$Invariant'." }
    }

    return $true
}

Export-ModuleMember -Function @(
    'Get-PluginFrontmatter',
    'Test-RequiredFrontmatter',
    'Get-ArtifactType',
    'Test-ReferencedFile',
    'Assert-EvalMarkerOrder',
    'Assert-FleetConsumerParity',
    'Resolve-MarkdownLink',
    'Test-BodySection',
    'Get-ReviewRunEvalContext',
    'Test-ReviewRunStructuralInvariant'
)

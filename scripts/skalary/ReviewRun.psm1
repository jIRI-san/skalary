#requires -Version 7.0
<#
.SYNOPSIS
    Production engine for the v1 review-run data contract: validation, canonicalization, rendering,
    publication and reading.
.DESCRIPTION
    Plan c21cdc, step 1.2. `Build-ReviewReport.ps1 -Mode Freeze|Publish` is a thin CLI over this
    module; `Get-ReviewRun.ps1` and `Remove-ReviewRun.ps1` are thin CLIs over the reader and cleanup
    functions here. Keeping the logic in a module rather than the scripts is what lets the failure
    matrix (RISK-14) and the deterministic fault seams (RISK-5) run in-process instead of spawning a
    child per case, and it keeps `Build-ReviewReport.ps1` a pure formatter whose own text carries no
    file I/O (the legacy contract the b0c0d3 tests still pin).

    The rendering half (projection, both views, encoding) is the production counterpart of the
    test-only `tests/skalary/fixtures/review-run/ReviewLayoutReference.psm1`. It is a deliberate
    verbatim port of the *layout*: step 1.1 committed byte goldens the reference renderer produces, and
    this module must reproduce those exact bytes, so the two derivations are held equal by
    `ReviewReportCorpus.Tests.ps1` rather than allowed to drift. Where the reference would lose data —
    case-insensitive maps, a dictionary keyed by a merge tuple two legal findings can share — this
    module is ordinal and lossless instead; those paths are unreachable for the corpus, so the goldens
    are unaffected and the collision cases are pinned by their own tests.

    Trust model (decisions/review-run-contract.md):
      * reviewer text is data, never source or a shell argument — it only ever reaches a JSON parser,
        an encoder or a byte writer here, and it is scanned for credential shapes before anything
        persists it (the frozen plan included);
      * the caller chooses only a run id and, for a plan run, a plan directory validated against the
        repository's plan inventory; repo, schema and output roots are derived from this module's
        installed location, and no write, removal or verified read happens through a symlinked
        ancestor;
      * the caller owns the input handshake (D16): it renames its own `.tmp` onto the fixed input name,
        and this module consumes only that name — never a `.tmp`;
      * generations are immutable and content-addressed (`<role>.<sha256>.<ext>`), so the frozen plan
        `Publish` binds every result to is tamper-evident on its own name;
      * the manifest is the sole commit point, replaced last under an exclusive lock whose file is
        never unlinked; every state decision happens under that lock, and a reader trusts nothing else
        in the run directory and verifies every name, digest, byte count and identity;
      * every path is bounded: 0/2/3/4/5 with exactly one terminal-status object, and a byte-budget
        admission is terminal for the run id and persisted as such.
#>

Set-StrictMode -Version Latest

$script:PlanDiscriminator = 'skalary/review-plan@1'
$script:RunDiscriminator = 'skalary/review-run@1'
$script:ManifestDiscriminator = 'skalary/review-manifest@1'
$script:TerminalDiscriminator = 'skalary/review-terminal-status@1'
$script:SummaryDiscriminator = 'skalary/review-summary@1'

$script:SeverityRank = @{ 'Critical' = 4; 'High' = 3; 'Medium' = 2; 'Low' = 1 }
$script:SeverityByRank = @{ 4 = 'Critical'; 3 = 'High'; 2 = 'Medium'; 1 = 'Low' }
$script:Outcomes = @('completed', 'failed', 'timed-out', 'omitted', 'cancelled', 'pending')
$script:Unit = [string][char]1

# Run-directory names. The caller controls only the two fixed `.input.json` handshakes (D16).
# Generations are content-addressed; fixed engine-owned markers commit frozen, admitted and published
# state so removing one generation cannot reopen an accepted UUID.
$script:PlanInputName = 'review-plan.input.json'
$script:ResultInputName = 'review-result.input.json'
$script:PlanPrefix = 'review-plan'
$script:CanonicalPrefix = 'review-run'
$script:SummaryPrefix = 'review-summary'
$script:FullPrefix = 'review-full'
$script:AdmissionSourcePrefix = 'review-admission-source'
$script:ManifestName = 'review-run.manifest.json'
$script:FrozenName = '.review-run.frozen'
$script:LockName = '.review-run.lock'
# Admission (exit 3) is terminal for a UUID (D21), so it has to survive the process that decided it.
$script:AdmissionName = '.review-run.admission.json'
$script:AdmissionDiscriminator = 'skalary/review-admission@1'

$script:ArtifactRole = [ordered]@{
    plan            = [pscustomobject]@{ Prefix = $script:PlanPrefix; Extension = '.json' }
    canonical       = [pscustomobject]@{ Prefix = $script:CanonicalPrefix; Extension = '.json' }
    summary         = [pscustomobject]@{ Prefix = $script:SummaryPrefix; Extension = '.md' }
    full            = [pscustomobject]@{ Prefix = $script:FullPrefix; Extension = '.md' }
    admissionSource = [pscustomobject]@{ Prefix = $script:AdmissionSourcePrefix; Extension = '.json' }
}

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Limits = $null
$script:VerifiedAuthorityToken = [object]::new()
$script:RemoveTreeProvider = $null

# These literal paths are the closed schema sidecar closure copied by Sync-PluginScripts. Root
# execution still uses the canonical schemas/review directory; installed execution uses these copies.
$script:BundledSchemaPath = [ordered]@{
    'review-limits.schema.json'    = Join-Path $PSScriptRoot 'schemas/review/review-limits.schema.json'
    'review-admission.schema.json' = Join-Path $PSScriptRoot 'schemas/review/review-admission.schema.json'
    'review-manifest.schema.json'  = Join-Path $PSScriptRoot 'schemas/review/review-manifest.schema.json'
    'review-plan.schema.json'      = Join-Path $PSScriptRoot 'schemas/review/review-plan.schema.json'
    'review-run.schema.json'       = Join-Path $PSScriptRoot 'schemas/review/review-run.schema.json'
    'terminal-status.schema.json'  = Join-Path $PSScriptRoot 'schemas/review/terminal-status.schema.json'
}
$script:BundledPlanStatePath = Join-Path $PSScriptRoot 'PlanState.psm1'
$canonicalModulePath = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..' '..' 'scripts' 'skalary' 'ReviewRun.psm1')
)
$script:IsCanonicalSource = [string]::Equals(
    [System.IO.Path]::GetFullPath($PSCommandPath),
    $canonicalModulePath,
    [System.StringComparison]::OrdinalIgnoreCase
)
if (-not $script:IsCanonicalSource) {
    $script:SchemaRoot = Join-Path $PSScriptRoot 'schemas/review'
    foreach ($schemaPath in $script:BundledSchemaPath.Values) {
        if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
            throw "Installed review-run schema sidecar is missing: $([System.IO.Path]::GetFileName($schemaPath))"
        }
    }
}
else {
    $script:SchemaRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' 'schemas' 'review'))
    if (-not (Test-Path -LiteralPath $script:SchemaRoot -PathType Container)) {
        throw "Canonical review schema directory is missing: $script:SchemaRoot"
    }
}

function Get-ReviewLimits {
    if ($null -ne $script:Limits) { return $script:Limits }
    $path = Join-Path $script:SchemaRoot 'review-limits.schema.json'
    $vocabulary = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 20
    $script:Limits = $vocabulary['x-skalary-limits']
    return $script:Limits
}

# --------------------------------------------------------------------------------------------------
# Schema capability (D12/RISK-12). The wrapper stays `#requires -Version 7.0`, so the engine has to
# check for the 7.6+ `Test-Json -SchemaFile` capability itself rather than assume it: a host without
# it must get a bounded exit `2` terminal status, never an unhandled `Test-Json` parameter error.
# The simulation seam follows `Test-ReviewSchemaCapability.ps1` exactly — it can only *lower* the
# reported capability (the version is applied as a minimum against the real one and the switch can
# only remove a parameter), so no invocation can talk a real host into skipping a check.
# --------------------------------------------------------------------------------------------------
$script:MinimumSchemaVersion = [version]'7.6'
$script:SimulatedSchemaVersion = $null
$script:SimulateMissingSchemaFile = $false

function Set-ReviewSchemaCapabilitySimulation {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Version,
        [switch]$MissingSchemaFile,
        [switch]$Clear
    )

    if ($Clear) {
        $script:SimulatedSchemaVersion = $null
        $script:SimulateMissingSchemaFile = $false
        return
    }
    if ($PSBoundParameters.ContainsKey('Version')) {
        $script:SimulatedSchemaVersion = $(if ([string]::IsNullOrWhiteSpace($Version)) { $null } else { [version]$Version })
    }
    if ($MissingSchemaFile) { $script:SimulateMissingSchemaFile = $true }
}

function Test-ReviewHostSchemaCapability {
    <#
    .SYNOPSIS
        Whether this host can validate a document against a schema file. Returns a record carrying the
        decision and, when it is negative, the bounded reason a terminal status may quote.
    #>
    [CmdletBinding()]
    param()

    $real = [version]$PSVersionTable.PSVersion
    $effective = $real
    if ($null -ne $script:SimulatedSchemaVersion -and $script:SimulatedSchemaVersion -lt $effective) {
        $effective = $script:SimulatedSchemaVersion
    }

    $hasSchemaFile = $false
    $command = Get-Command -Name 'Test-Json' -ErrorAction SilentlyContinue
    if ($command -and $command.Parameters.ContainsKey('SchemaFile')) { $hasSchemaFile = $true }
    if ($script:SimulateMissingSchemaFile) { $hasSchemaFile = $false }

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($effective -lt $script:MinimumSchemaVersion) {
        $reasons.Add("PowerShell $effective is older than the required $($script:MinimumSchemaVersion) for native schema validation")
    }
    if (-not $hasSchemaFile) { $reasons.Add('Test-Json does not expose -SchemaFile on this host') }

    return [pscustomobject]@{
        Capable = ($reasons.Count -eq 0)
        Version = $effective.ToString()
        Reasons = @($reasons)
    }
}


# --------------------------------------------------------------------------------------------------
# Module-scoped fault seams (RISK-5). Tests set an action for a named publication edge; the CLI never
# does, so there is no production failpoint. Every edge that could crash mid-publication is named.
# --------------------------------------------------------------------------------------------------
$script:FaultSeams = @{}
$script:LockTimeoutOverrideSeconds = $null
$script:PathItemProvider = $null

function Set-ReviewPathItemProvider {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Provider)
    $script:PathItemProvider = $Provider
}

function Clear-ReviewPathItemProvider {
    $script:PathItemProvider = $null
}

function Get-ReviewPathItem {
    param([Parameter(Mandatory)][string]$Path)
    if ($script:PathItemProvider) { return & $script:PathItemProvider $Path }
    return Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Set-ReviewRunFaultSeam {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('after-canonical', 'after-summary', 'after-full', 'before-manifest-swap', 'during-lock', 'after-final-report', 'during-finalize-cleanup', 'during-generic-cleanup')][string]$Edge,
        [ValidateSet('throw')][string]$Action = 'throw'
    )
    $script:FaultSeams[$Edge] = $Action
}

function Clear-ReviewRunFaultSeam {
    [CmdletBinding()]
    param([string]$Edge)
    if ($Edge) { [void]$script:FaultSeams.Remove($Edge); return }
    $script:FaultSeams = @{}
}

function Set-ReviewRunLockTimeoutOverride {
    [CmdletBinding()]
    param([AllowNull()][System.Nullable[double]]$Seconds)
    $script:LockTimeoutOverrideSeconds = $Seconds
}

function Invoke-ReviewFaultSeam {
    param([Parameter(Mandatory)][string]$Edge)
    if ($script:FaultSeams.ContainsKey($Edge)) {
        throw "review-run-fault-seam:$Edge"
    }
}

# --------------------------------------------------------------------------------------------------
# Reading parsed JSON nodes (verbatim contract with the reference renderer).
# --------------------------------------------------------------------------------------------------
function Get-ReviewValue {
    param([object]$Node, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Node) { return $null }
    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains($Name)) { return $Node[$Name] }
        return $null
    }
    if ($Node.PSObject.Properties.Name -contains $Name) { return $Node.$Name }
    return $null
}

function Format-ReviewInvariant {
    param([Parameter(Mandatory)][int]$Value)
    return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function Sort-ReviewOrdinal {
    param([AllowEmptyCollection()][string[]]$Value)

    $copy = [string[]]@($Value)
    [array]::Sort($copy, [System.StringComparer]::Ordinal)
    return $copy
}

function Get-ReviewOrdinalTupleKey {
    param([AllowEmptyCollection()][string[]]$Value)

    $builder = [System.Text.StringBuilder]::new()
    foreach ($item in @($Value)) {
        $text = [string]$item
        [void]$builder.Append((Format-ReviewInvariant -Value $text.Length))
        [void]$builder.Append(':')
        [void]$builder.Append($text)
        [void]$builder.Append(';')
    }
    return $builder.ToString()
}

function Get-ReviewNormalizedKey {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    # Canonical text rather than a bare `Normalize`: an unpaired surrogate makes `String.Normalize`
    # throw, and a grouping key must be a total function of legal input. Neither the surrogate
    # substitution nor the LF normalization can change the result, because the character class below
    # keeps only `[a-z0-9]` runs anyway.
    $canonical = ConvertTo-ReviewCanonicalText -Value $Value
    return ([regex]::Replace($canonical.ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim()
}

function Repair-ReviewSurrogate {
    <#
    .SYNOPSIS
        Replaces every unpaired surrogate with U+FFFD, so the text can be normalized and encoded.
    .DESCRIPTION
        A JSON parser accepts `\uD800` on its own, but a lone surrogate is neither normalizable
        (`String.Normalize` throws) nor encodable (UTF-8 substitutes U+FFFD anyway). Repairing it here
        makes canonicalization total: the same substitution the byte encoder would perform silently is
        performed once, before the digest is taken, so the canonical text and the canonical bytes agree.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $builder = [System.Text.StringBuilder]::new($Value.Length)
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $char = $Value[$i]
        if (-not [char]::IsSurrogate($char)) { [void]$builder.Append($char); continue }
        if ([char]::IsHighSurrogate($char) -and ($i + 1) -lt $Value.Length -and [char]::IsLowSurrogate($Value[$i + 1])) {
            [void]$builder.Append($char)
            [void]$builder.Append($Value[$i + 1])
            $i++
            continue
        }
        [void]$builder.Append([char]0xFFFD)
    }
    return $builder.ToString()
}

function ConvertTo-ReviewCanonicalText {
    <#
    .SYNOPSIS
        The canonical form of one untrusted string: LF line endings and NFC.
    .DESCRIPTION
        D15. Two envelopes that are the same document to every consumer must produce the same bytes and
        therefore the same digest, so the two representational differences a JSON string can carry —
        the line ending (`\r\n`/`\r` versus `\n`) and the Unicode composition of the same grapheme —
        are removed here rather than left to whoever compares them later. Everything else is preserved
        exactly: canonicalization is lossless apart from these two normalizations (and the U+FFFD
        substitution an unpaired surrogate would receive from the UTF-8 encoder in any case).
    #>
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return $Value }

    $text = $Value
    if ($text.IndexOf([char]13) -ge 0) { $text = $text -replace "`r`n", "`n" -replace "`r", "`n" }
    try { return $text.Normalize([System.Text.NormalizationForm]::FormC) }
    catch [System.ArgumentException] { return (Repair-ReviewSurrogate -Value $text).Normalize([System.Text.NormalizationForm]::FormC) }
}

function ConvertTo-ReviewControlSafe {
    <#
    .SYNOPSIS
        Replaces the C0 controls and DEL a rendered view must never emit raw with their Unicode
        Control Pictures (U+2400 + code point; DEL becomes U+2421).
    .DESCRIPTION
        Every leaf string in the contract is `type: string` with a length bound, so a schema-valid
        model, title or body may legally carry `U+0001`. Emitting it raw would put an invisible,
        non-printable byte into Markdown a human and a downstream parser read differently. The
        substitution is deterministic and injective over the replaced range (one control, one picture),
        so attribution stays readable and complete instead of being truncated at the control. Canonical
        JSON is unaffected — it keeps the original character, and this runs only in the render path.
    #>
    param(
        [AllowEmptyString()][string]$Value,
        # Block rendering keeps the line breaks and tabs its layout depends on.
        [switch]$KeepLayoutWhitespace
    )

    if ([string]::IsNullOrEmpty($Value)) { return $Value }

    # Most review text has no control characters. Let the native regex engine prove that before the
    # PowerShell fallback walks every character; this avoids scanning megabytes of ordinary finding
    # bodies one character at a time while preserving the exact hostile-input substitution below.
    $controlPattern = $(if ($KeepLayoutWhitespace) { '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' } else { '[\x00-\x1F\x7F]' })
    if (-not [regex]::IsMatch($Value, $controlPattern)) { return $Value }

    $builder = $null
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $char = $Value[$i]
        $code = [int]$char
        $replace = ($code -lt 0x20 -or $code -eq 0x7F)
        if ($replace -and $KeepLayoutWhitespace -and ($char -eq "`n" -or $char -eq "`t")) { $replace = $false }
        if (-not $replace) {
            if ($null -ne $builder) { [void]$builder.Append($char) }
            continue
        }
        if ($null -eq $builder) { $builder = [System.Text.StringBuilder]::new($Value.Substring(0, $i), $Value.Length) }
        [void]$builder.Append([char]($(if ($code -eq 0x7F) { 0x2421 } else { 0x2400 + $code })))
    }
    if ($null -eq $builder) { return $Value }
    return $builder.ToString()
}

function ConvertTo-ReviewInlineText {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return '' }

    $text = ConvertTo-ReviewCanonicalText -Value $Value
    $text = ([regex]::Replace($text, '\s+', ' ')).Trim()
    $text = ConvertTo-ReviewControlSafe -Value $text
    $text = $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    $text = $text.Replace('\', '\\')
    foreach ($char in @('`', '*', '_', '[', ']', '|', '~', '!', '#')) {
        $text = $text.Replace($char, '\' + $char)
    }
    return $text
}

function ConvertTo-ReviewCodeSpan {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($Value -notmatch '^[A-Za-z0-9:._-]+$') {
        throw "Refusing to render '$Value' as a code span: it is not a schema-patterned identifier."
    }
    return '`' + $Value + '`'
}

function ConvertTo-ReviewFencedBlock {
    param([AllowEmptyString()][string]$Value)

    $text = ConvertTo-ReviewCanonicalText -Value ([string]$Value)
    $text = ConvertTo-ReviewControlSafe -Value $text -KeepLayoutWhitespace
    $text = $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')

    $longestRun = 0
    foreach ($match in [regex]::Matches($text, '`+')) {
        if ($match.Length -gt $longestRun) { $longestRun = $match.Length }
    }
    $fence = '`' * ([Math]::Max(3, $longestRun + 1))

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($fence + 'text')
    foreach ($line in ($text -split "`n")) { $lines.Add($line) }
    $lines.Add($fence)
    return , $lines.ToArray()
}

function Get-ReviewMergeKey {
    <#
    .SYNOPSIS
        The grouping key the renderer merges findings by, with the contract's fallbacks applied.
    .DESCRIPTION
        One definition, two callers: `ConvertTo-ReviewProjection` groups by it, and the semantic layer
        counts distinct keys to enforce the vocabulary's `maxMergedFindings`. Deriving the cap from any
        other approximation of "how many merged findings will this produce" would let a run pass
        validation and then render a different number of groups, so the two must be the same function.

        Both fallbacks are part of the key: an absent or blank `rootCause` falls back to the trimmed
        title, and an absent or blank `component` falls back to the first non-blank reference. Each half
        is then reduced by `Get-ReviewNormalizedKey`, whose output is `[a-z0-9 ]*` — which is also why
        the `U+0001` join below cannot be forged by untrusted text.

        The reference fallback is taken from canonical reference order, not the caller's order. Publish
        canonicalizes the complete envelope before both semantic validation and rendering, so this helper
        only needs the same ordinal sort in both callers. Re-normalizing every reference here would repeat
        the most expensive Unicode work once during validation and again during rendering.
    #>
    param([Parameter(Mandatory)][object]$Finding)

    $title = ([string](Get-ReviewValue -Node $Finding -Name 'title')).Trim()
    $references = @(@(Sort-ReviewOrdinal -Value @(Get-ReviewValue -Node $Finding -Name 'references')) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { ([string]$_).Trim() })

    $rootCause = [string](Get-ReviewValue -Node $Finding -Name 'rootCause')
    if ([string]::IsNullOrWhiteSpace($rootCause)) { $rootCause = $title }
    $component = [string](Get-ReviewValue -Node $Finding -Name 'component')
    if ([string]::IsNullOrWhiteSpace($component) -and $references.Count -gt 0) { $component = $references[0] }

    return (Get-ReviewNormalizedKey -Value $rootCause) + $script:Unit + (Get-ReviewNormalizedKey -Value $component)
}

function Get-ReviewFindingSimilarityProfile {
    <#
    .SYNOPSIS
        Normalizes the reviewer-authored title, body, and action for corroboration comparison.
    .DESCRIPTION
        Similarity is observable evidence, not proof of served-model identity. Each field is
        canonicalized, lowercased invariantly, reduced to Unicode letter/decimal-number words, and
        kept in a length-prefixed tuple so untrusted text cannot forge a field boundary.
    #>
    param([Parameter(Mandatory)][object]$Finding)

    $normalized = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('Title', 'Body', 'Action')) {
        $value = [string](Get-ReviewValue -Node $Finding -Name $name)
        $canonical = ConvertTo-ReviewCanonicalText -Value $value
        $normalized.Add(([regex]::Replace($canonical.ToLowerInvariant(), '[^\p{L}\p{Nd}]+', ' ')).Trim())
    }

    $content = ([regex]::Replace(($normalized -join ' '), '\s+', ' ')).Trim()
    $tokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($content.Length -gt 0) {
        foreach ($token in $content.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)) {
            [void]$tokens.Add($token)
        }
    }

    return [pscustomobject]@{
        ExactKey = Get-ReviewOrdinalTupleKey -Value $normalized.ToArray()
        Content = $content
        Tokens = $tokens
    }
}

function Get-ReviewFindingSimilarity {
    <#
    .SYNOPSIS
        Classifies two findings as exact, clearly near-duplicate, or unrelated.
    .DESCRIPTION
        Exact normalized title/body/action tuples always flag. The conservative near-duplicate rule
        applies only when both normalized records contain at least 8 distinct tokens and 48
        characters, then requires token-set Jaccard similarity of at least 0.90. The fixed minimums
        keep short shared boilerplate from looking like independent corroboration.
    #>
    param(
        [Parameter(Mandatory)][object]$LeftProfile,
        [Parameter(Mandatory)][object]$RightProfile
    )

    if ([string]::Equals($leftProfile.ExactKey, $rightProfile.ExactKey, [System.StringComparison]::Ordinal)) {
        return 'exact'
    }
    if ($leftProfile.Content.Length -lt 48 -or $rightProfile.Content.Length -lt 48 -or
        $leftProfile.Tokens.Count -lt 8 -or $rightProfile.Tokens.Count -lt 8) {
        return 'none'
    }

    $intersection = 0
    foreach ($token in $leftProfile.Tokens) {
        if ($rightProfile.Tokens.Contains($token)) { $intersection++ }
    }
    $union = $leftProfile.Tokens.Count + $rightProfile.Tokens.Count - $intersection
    if ($union -gt 0 -and ($intersection * 10) -ge ($union * 9)) { return 'near-duplicate' }
    return 'none'
}

function ConvertTo-ReviewProjection {
    param([Parameter(Mandatory)][object]$Run)

    $tasks = @(Get-ReviewValue -Node $Run -Name 'tasks')
    $findings = @(Get-ReviewValue -Node $Run -Name 'findings')
    $roster = @(Get-ReviewValue -Node $Run -Name 'roster' | ForEach-Object { [string]$_ })

    # Ordinal maps throughout: PowerShell's default hashtable and `[ordered]@{}` compare keys
    # case-insensitively, which would let two case-distinct task ids, merge keys or sort keys collide
    # and silently drop one of them.
    $taskById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($task in $tasks) { $taskById[[string](Get-ReviewValue -Node $task -Name 'taskId')] = $task }

    $findingsByTask = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    foreach ($finding in $findings) {
        $taskId = [string](Get-ReviewValue -Node $finding -Name 'taskId')
        if (-not $findingsByTask.ContainsKey($taskId)) { $findingsByTask[$taskId] = 0 }
        $findingsByTask[$taskId]++
    }

    $orderedTasks = [System.Collections.Generic.List[object]]::new()
    foreach ($taskId in (Sort-ReviewOrdinal -Value @($taskById.Keys | ForEach-Object { [string]$_ }))) {
        $task = $taskById[$taskId]
        $diagnostic = [string](Get-ReviewValue -Node $task -Name 'diagnostic')
        $orderedTasks.Add([pscustomobject]@{
                TaskId      = $taskId
                Concern     = [string](Get-ReviewValue -Node $task -Name 'concern')
                Model       = [string](Get-ReviewValue -Node $task -Name 'model')
                Outcome     = [string](Get-ReviewValue -Node $task -Name 'outcome')
                Diagnostic  = $diagnostic
                RawFindings = $(if ($findingsByTask.ContainsKey($taskId)) { [int]$findingsByTask[$taskId] } else { 0 })
            })
    }

    $attendance = [ordered]@{}
    foreach ($outcome in $script:Outcomes) {
        $attendance[$outcome] = @($orderedTasks | Where-Object { $_.Outcome -eq $outcome }).Count
    }
    $state = $(if ([int]$attendance['completed'] -eq $orderedTasks.Count) { 'clean' } else { 'degraded' })

    $groups = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    foreach ($finding in $findings) {
        $taskId = [string](Get-ReviewValue -Node $finding -Name 'taskId')
        $task = $taskById[$taskId]
        $title = ([string](Get-ReviewValue -Node $finding -Name 'title')).Trim()
        $severity = [string](Get-ReviewValue -Node $finding -Name 'severity')
        $body = [string](Get-ReviewValue -Node $finding -Name 'body')
        $action = [string](Get-ReviewValue -Node $finding -Name 'action')
        $references = @(@(Get-ReviewValue -Node $finding -Name 'references') |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim() })

        $rootCause = [string](Get-ReviewValue -Node $finding -Name 'rootCause')
        if ([string]::IsNullOrWhiteSpace($rootCause)) { $rootCause = $title }
        $component = [string](Get-ReviewValue -Node $finding -Name 'component')
        if ([string]::IsNullOrWhiteSpace($component) -and $references.Count -gt 0) { $component = $references[0] }

        $key = Get-ReviewMergeKey -Finding $finding
        if (-not $groups.Contains($key)) {
            $groups[$key] = [pscustomobject]@{
                Key        = $key
                Titles     = [System.Collections.Generic.List[string]]::new()
                Bodies     = [System.Collections.Generic.List[string]]::new()
                Actions    = [System.Collections.Generic.List[string]]::new()
                Concerns   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                Models     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                References = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                Raw        = [System.Collections.Generic.List[object]]::new()
                Rank       = 0
            }
        }

        $group = $groups[$key]
        $group.Titles.Add($title)
        if (-not [string]::IsNullOrWhiteSpace($body)) { $group.Bodies.Add($body.Trim()) }
        if (-not [string]::IsNullOrWhiteSpace($action)) { $group.Actions.Add($action.Trim()) }
        [void]$group.Concerns.Add(([string](Get-ReviewValue -Node $task -Name 'concern')).Trim())
        [void]$group.Models.Add([string](Get-ReviewValue -Node $task -Name 'model'))
        foreach ($reference in $references) { [void]$group.References.Add($reference) }
        if ($script:SeverityRank[$severity] -gt $group.Rank) { $group.Rank = $script:SeverityRank[$severity] }
        $group.Raw.Add([pscustomobject]@{
                TaskId     = $taskId
                Concern    = [string](Get-ReviewValue -Node $task -Name 'concern')
                Model      = [string](Get-ReviewValue -Node $task -Name 'model')
                Severity   = $severity
                Title      = $title
                Body       = $body
                Action     = $action
                RootCause  = $rootCause
                Component  = $component
                References = $references
            })
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($group in $groups.Values) {
        # Model attribution is decided on structured records, never on a packed string: a model name is
        # `type: string` with no character class, so a schema-valid `U+0001` inside one used to be read
        # back as the delimiter and truncate the model to whatever followed it — corrupting the Models
        # cell and, through it, the unanimity elevation. The sort key is derived from the record and
        # thrown away; the value carried forward is the original, unmodified model string.
        $models = @(Sort-ReviewArrayByKey -Items @($group.Models | ForEach-Object { [pscustomobject]@{ Model = [string]$_ } }) -KeyScript {
                param($record)
                $index = [array]::IndexOf([string[]]$roster, [string]$record.Model)
                if ($index -lt 0) { return '1' + (Get-ReviewOrdinalTupleKey -Value @([string]$record.Model)) }
                return '0' + (Format-ReviewInvariant -Value $index).PadLeft(4, '0')
            } | ForEach-Object { [string]$_.Model })
        $concerns = @(Sort-ReviewOrdinal -Value @($group.Concerns))

        $observedModels = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$models,
            [System.StringComparer]::Ordinal
        )
        $unanimous = $roster.Count -ge 2 -and
        @($roster | Where-Object { -not $observedModels.Contains([string]$_) }).Count -eq 0

        # Longest body first, then ordinal — decided on records, so the value that survives is the
        # original body rather than a substring of a packed key.
        $orderedBodies = @(Sort-ReviewArrayByKey -Items @($group.Bodies | ForEach-Object { [pscustomobject]@{ Body = [string]$_ } }) -KeyScript {
                param($record)
                (Format-ReviewInvariant -Value (999999 - [Math]::Min($record.Body.Length, 999999))).PadLeft(6, '0') +
                (Get-ReviewOrdinalTupleKey -Value @([string]$record.Body))
            } | ForEach-Object { [string]$_.Body })
        $distinctBodies = [System.Collections.Generic.List[string]]::new()
        foreach ($body in $orderedBodies) {
            if (-not $distinctBodies.Contains($body)) { $distinctBodies.Add($body) }
        }

        $title = @(Sort-ReviewArrayByKey -Items @($group.Titles | ForEach-Object { [pscustomobject]@{ Title = [string]$_ } }) -KeyScript {
                param($record)
                (Format-ReviewInvariant -Value (999999 - [Math]::Min($record.Title.Length, 999999))).PadLeft(6, '0') +
                (Get-ReviewOrdinalTupleKey -Value @([string]$record.Title))
            } | ForEach-Object { [string]$_.Title })[0]

        $action = ''
        if ($group.Actions.Count -gt 0) { $action = @(Sort-ReviewOrdinal -Value @($group.Actions))[0] }
        elseif ($distinctBodies.Count -gt 0) {
            $flat = [regex]::Replace($distinctBodies[0].Trim(), '\s+', ' ')
            $match = [regex]::Match($flat, '^(?<sentence>.+?[.!?])(\s|$)')
            $action = $(if ($match.Success) { $match.Groups['sentence'].Value } else { $flat })
        }

        # Every raw record is preserved. Two structurally distinct findings can normalize to the same
        # ordinal tuple (a title differing only by surrounding whitespace, or an explicit rootCause
        # equal to another finding's defaulted one), so keying a dictionary by that tuple would throw
        # on collision and take the whole publication down. Decorate-sort keeps the ordinal order and
        # keeps colliding records in input order instead of dropping or crashing on them.
        $raw = @(Sort-ReviewArrayByKey -Items @($group.Raw) -KeyScript {
                param($record)
                $referenceKey = Get-ReviewOrdinalTupleKey -Value @($record.References | ForEach-Object { [string]$_ })
                Get-ReviewOrdinalTupleKey -Value @(
                    $record.TaskId, $record.Concern, $record.Model, $record.Severity, $record.Title,
                    $record.Body, $record.Action, $record.RootCause, $record.Component, $referenceKey
                )
            })

        $similarityProfiles = @($raw | ForEach-Object { Get-ReviewFindingSimilarityProfile -Finding $_ })
        $similarity = 'none'
        $modelsByExactKey = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new(
            [System.StringComparer]::Ordinal
        )
        for ($index = 0; $index -lt $raw.Count; $index++) {
            $exactKey = [string]$similarityProfiles[$index].ExactKey
            if (-not $modelsByExactKey.ContainsKey($exactKey)) {
                $modelsByExactKey[$exactKey] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            }
            $exactModels = $modelsByExactKey[$exactKey]
            if ($exactModels.Count -gt 0 -and -not $exactModels.Contains([string]$raw[$index].Model)) {
                $similarity = 'exact'
                break
            }
            [void]$exactModels.Add([string]$raw[$index].Model)
        }
        for ($leftIndex = 0; $leftIndex -lt $raw.Count -and $similarity -eq 'none'; $leftIndex++) {
            for ($rightIndex = $leftIndex + 1; $rightIndex -lt $raw.Count; $rightIndex++) {
                if ([string]::Equals($raw[$leftIndex].Model, $raw[$rightIndex].Model, [System.StringComparison]::Ordinal)) {
                    continue
                }
                $pairSimilarity = Get-ReviewFindingSimilarity `
                    -LeftProfile $similarityProfiles[$leftIndex] `
                    -RightProfile $similarityProfiles[$rightIndex]
                if ($pairSimilarity -eq 'near-duplicate') {
                    $similarity = 'near-duplicate'
                    break
                }
            }
        }

        $support = if ($similarity -ne 'none') {
            'suspicious'
        }
        elseif ($state -ne 'clean') {
            'degraded'
        }
        elseif ($models.Count -ge 2) {
            'corroborated'
        }
        else {
            'single-source'
        }
        $elevated = $support -eq 'corroborated' -and $unanimous -and $group.Rank -lt 4
        $rank = $group.Rank + $(if ($elevated) { 1 } else { 0 })
        $reason = switch ($support) {
            'suspicious' {
                "needs-review: $similarity normalized finding text appears under distinct declared model labels; severity elevation suppressed"
            }
            'degraded' {
                'review attendance is degraded; severity elevation suppressed'
            }
            'corroborated' {
                if ($unanimous) {
                    'every declared model label reported this finding with complete attendance; no suspicious similarity observed'
                }
                else {
                    'multiple declared model labels reported this finding with complete attendance; no suspicious similarity observed'
                }
            }
            default {
                'one declared model label reported this finding with complete attendance'
            }
        }

        $entries.Add([pscustomobject]@{
                Key        = $group.Key
                Title      = $title
                Rank       = $rank
                Severity   = $script:SeverityByRank[$rank]
                Elevated   = $elevated
                Concerns   = $concerns
                Models     = $models
                Bodies     = @($distinctBodies)
                References = @(Sort-ReviewOrdinal -Value @($group.References))
                Action     = $action
                Raw        = @($raw)
                RawCount   = $group.Raw.Count
                Similarity = $similarity
                Support    = $support
                SupportCount = $models.Count
                AttendanceState = $state
                RawRank    = $group.Rank
                RawSeverity = $script:SeverityByRank[$group.Rank]
                EffectiveSeverity = $script:SeverityByRank[$rank]
                NeedsReview = $support -eq 'suspicious'
                Reason     = $reason
            })
    }

    # The merged entries are ordered by one composite ordinal key. Both maps are ordinal for the same
    # reason the merge map is: a title differing only in case must not collapse two merged groups into
    # one, which a case-insensitive hashtable would do silently. The composite is delimited, so nothing
    # untrusted that could contain the delimiter is packed into it: the two numeric fields are fixed
    # width, the title is control-safe (its C0 range is already replaced), and the merge key that closes
    # it is two `[a-z0-9 ]*` halves around one delimiter. Ordering is the only thing this key decides —
    # every displayed value comes from the entry itself.
    $sortKeys = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        $sortKeys[$entry.Key] = (Format-ReviewInvariant -Value (9 - $entry.Rank)).PadLeft(2, '0') + $script:Unit +
        (Format-ReviewInvariant -Value (9999 - [Math]::Min($entry.Models.Count, 9999))).PadLeft(4, '0') + $script:Unit +
        (ConvertTo-ReviewControlSafe -Value $entry.Title) + $script:Unit + $entry.Key
    }
    $sorted = @(Sort-ReviewArrayByKey -Items @($entries) -KeyScript { param($entry) $sortKeys[$entry.Key] })

    return [pscustomobject]@{
        RunId            = [string](Get-ReviewValue -Node $Run -Name 'runId')
        ReviewType       = [string](Get-ReviewValue -Node $Run -Name 'reviewType')
        ContentTrust     = [string](Get-ReviewValue -Node $Run -Name 'contentTrust')
        Scope            = [string](Get-ReviewValue -Node $Run -Name 'scope')
        ScopeAuthority   = Get-ReviewValue -Node $Run -Name 'scopeAuthority'
        PlanDigest       = [string](Get-ReviewValue -Node $Run -Name 'planDigest')
        InvocationBudget = [int](Get-ReviewValue -Node $Run -Name 'invocationBudget')
        ModelSelection   = @(Get-ReviewValue -Node $Run -Name 'modelSelection')
        Roster           = $roster
        Tasks            = @($orderedTasks)
        Attendance       = $attendance
        State            = $state
        Findings         = $sorted
        RawFindingCount  = $findings.Count
    }
}

function Get-ReviewReportTitle {
    param([Parameter(Mandatory)][string]$ReviewType)
    return $(if ($ReviewType -eq 'design') { 'Design Review' } else { 'Code Review' })
}

function Get-ReviewHeaderTable {
    param([Parameter(Mandatory)][object]$Projection)

    $models = @($Projection.ModelSelection | ForEach-Object {
            $requested = ConvertTo-ReviewInlineText -Value ([string](Get-ReviewValue -Node $_ -Name 'requested'))
            $declared = ConvertTo-ReviewInlineText -Value ([string](Get-ReviewValue -Node $_ -Name 'declared'))
            $preflight = ConvertTo-ReviewInlineText -Value ([string](Get-ReviewValue -Node $_ -Name 'preflight'))
            $degradation = ConvertTo-ReviewInlineText -Value ([string](Get-ReviewValue -Node $_ -Name 'degradation'))
            "$requested → $declared (preflight: $preflight; degradation: $degradation; served identity: unverified)"
        })
    $rows = [System.Collections.Generic.List[string]]::new()
    $rows.Add('| | |')
    $rows.Add('|---|---|')
    $rows.Add("| **Run** | $(ConvertTo-ReviewCodeSpan -Value $Projection.RunId) |")
    $rows.Add("| **Review type** | $(ConvertTo-ReviewCodeSpan -Value $Projection.ReviewType) |")
    $rows.Add("| **State** | $(ConvertTo-ReviewCodeSpan -Value $Projection.State) |")
    $rows.Add("| **Plan digest** | $(ConvertTo-ReviewCodeSpan -Value $Projection.PlanDigest) |")
    $rows.Add("| **Scope digest** | $(ConvertTo-ReviewCodeSpan -Value ([string](Get-ReviewValue -Node $Projection.ScopeAuthority -Name 'digest'))) |")
    $rows.Add("| **Scope** | $(ConvertTo-ReviewInlineText -Value $Projection.Scope) |")
    $rows.Add("| **Content trust** | $(ConvertTo-ReviewCodeSpan -Value $Projection.ContentTrust) |")
    $rows.Add("| **Requested → declared models** | $($models -join ' · ') |")
    $rows.Add("| **Invocations** | $(Format-ReviewInvariant -Value $Projection.Tasks.Count) of $(Format-ReviewInvariant -Value $Projection.InvocationBudget) budgeted |")
    return , $rows.ToArray()
}

function Get-ReviewSeverityCell {
    param([Parameter(Mandatory)][object]$Entry)

    if ($Entry.Elevated) { return "$($Entry.Severity) (elevated — flagged under every declared model label)" }
    return [string]$Entry.Severity
}

function Get-ReviewRunSummaryView {
    [CmdletBinding()]
    param(
        [object]$Run,
        [object]$Projection
    )

    $projection = if ($null -ne $Projection) { $Projection } else {
        if ($null -eq $Run) { throw 'Run or Projection is required.' }
        ConvertTo-ReviewProjection -Run $Run
    }
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# $(Get-ReviewReportTitle -ReviewType $projection.ReviewType) — summary")
    $lines.Add('')
    $lines.Add('<!-- skalary/review-summary@1 -->')
    $lines.Add('')
    foreach ($row in (Get-ReviewHeaderTable -Projection $projection)) { $lines.Add($row) }
    $lines.Add('')

    $lines.Add('## Attendance')
    $lines.Add('')
    $lines.Add('| Outcome | Tasks |')
    $lines.Add('|---|---|')
    foreach ($outcome in $script:Outcomes) {
        $lines.Add("| $(ConvertTo-ReviewCodeSpan -Value $outcome) | $(Format-ReviewInvariant -Value ([int]$projection.Attendance[$outcome])) |")
    }
    $lines.Add("| **planned** | $(Format-ReviewInvariant -Value $projection.Tasks.Count) |")
    $lines.Add('')

    $merged = @($projection.Findings)
    $lines.Add("## Merged findings ($(Format-ReviewInvariant -Value $merged.Count) of $(Format-ReviewInvariant -Value $projection.RawFindingCount) raw)")
    $lines.Add('')
    if ($merged.Count -eq 0) {
        $lines.Add('None.')
        $lines.Add('')
        return (($lines -join "`n") + "`n")
    }

    $lines.Add('| # | Severity | Title |')
    $lines.Add('|---|---|---|')
    $index = 0
    foreach ($entry in $merged) {
        $index++
        $severity = $(if ($entry.Elevated) { "$($entry.Severity) (elevated)" } else { [string]$entry.Severity })
        $lines.Add("| $(Format-ReviewInvariant -Value $index) | $severity | $(ConvertTo-ReviewInlineText -Value $entry.Title) |")
    }
    $lines.Add('')

    return (($lines -join "`n") + "`n")
}

function Get-ReviewRunFullView {
    [CmdletBinding()]
    param(
        [object]$Run,
        [object]$Projection
    )

    $projection = if ($null -ne $Projection) { $Projection } else {
        if ($null -eq $Run) { throw 'Run or Projection is required.' }
        ConvertTo-ReviewProjection -Run $Run
    }
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# $(Get-ReviewReportTitle -ReviewType $projection.ReviewType) — full report")
    $lines.Add('')
    $lines.Add('<!-- skalary/review-full@1 -->')
    $lines.Add('<!-- content-trust: reviewer-authored-data -->')
    $lines.Add('')
    foreach ($row in (Get-ReviewHeaderTable -Projection $projection)) { $lines.Add($row) }
    $lines.Add('')

    $lines.Add("## Tasks ($(Format-ReviewInvariant -Value $projection.Tasks.Count))")
    $lines.Add('')
    $lines.Add('| # | Task | Concern | Declared model | Outcome | Raw findings | Diagnostic |')
    $lines.Add('|---|---|---|---|---|---|---|')
    $index = 0
    foreach ($task in $projection.Tasks) {
        $index++
        $diagnostic = $(if ([string]::IsNullOrWhiteSpace($task.Diagnostic)) { '—' } else { ConvertTo-ReviewInlineText -Value $task.Diagnostic })
        $lines.Add("| $(Format-ReviewInvariant -Value $index) | $(ConvertTo-ReviewCodeSpan -Value $task.TaskId) | " +
            "$(ConvertTo-ReviewCodeSpan -Value $task.Concern) | $(ConvertTo-ReviewInlineText -Value $task.Model) | " +
            "$(ConvertTo-ReviewCodeSpan -Value $task.Outcome) | $(Format-ReviewInvariant -Value $task.RawFindings) | $diagnostic |")
    }
    $lines.Add('')

    $merged = @($projection.Findings)
    $lines.Add("## Merged findings ($(Format-ReviewInvariant -Value $merged.Count) of $(Format-ReviewInvariant -Value $projection.RawFindingCount) raw)")
    $lines.Add('')
    if ($merged.Count -eq 0) {
        $lines.Add('None.')
        $lines.Add('')
        $lines.Add('## Recommendations')
        $lines.Add('')
        $lines.Add('None.')
        $lines.Add('')
        return (($lines -join "`n") + "`n")
    }

    $index = 0
    foreach ($entry in $merged) {
        $index++
        $lines.Add("### [$(Format-ReviewInvariant -Value $index)] $(ConvertTo-ReviewInlineText -Value $entry.Title)")
        $lines.Add('')
        $lines.Add('| | |')
        $lines.Add('|---|---|')
        $lines.Add("| **Severity** | $(Get-ReviewSeverityCell -Entry $entry) |")
        $lines.Add("| **Concerns** | $(@($entry.Concerns | ForEach-Object { ConvertTo-ReviewCodeSpan -Value $_ }) -join ' · ') |")
        $lines.Add("| **Declared model labels** | $(@($entry.Models | ForEach-Object { ConvertTo-ReviewInlineText -Value $_ }) -join ' · ') |")
        $lines.Add("| **Raw findings** | $(Format-ReviewInvariant -Value $entry.RawCount) |")
        $lines.Add('')

        if ($entry.Bodies.Count -gt 0) {
            $lines.Add('**Description:**')
            $lines.Add('')
            foreach ($line in (ConvertTo-ReviewFencedBlock -Value $entry.Bodies[0])) { $lines.Add($line) }
            $lines.Add('')
            foreach ($extra in @($entry.Bodies | Select-Object -Skip 1)) {
                $lines.Add('**Also noted:**')
                $lines.Add('')
                foreach ($line in (ConvertTo-ReviewFencedBlock -Value $extra)) { $lines.Add($line) }
                $lines.Add('')
            }
        }

        if ($entry.References.Count -gt 0) {
            $lines.Add('**References:**')
            $lines.Add('')
            foreach ($reference in $entry.References) { $lines.Add("- $(ConvertTo-ReviewInlineText -Value $reference)") }
            $lines.Add('')
        }

        $lines.Add('**Raw records:**')
        $lines.Add('')
        $lines.Add('| Task | Severity | Title |')
        $lines.Add('|---|---|---|')
        foreach ($record in $entry.Raw) {
            $lines.Add("| $(ConvertTo-ReviewCodeSpan -Value $record.TaskId) | $(ConvertTo-ReviewCodeSpan -Value $record.Severity) | " +
                "$(ConvertTo-ReviewInlineText -Value $record.Title) |")
        }
        $lines.Add('')
        $lines.Add('---')
        $lines.Add('')
    }

    $lines.Add('## Recommendations')
    $lines.Add('')
    $index = 0
    foreach ($entry in $merged) {
        $index++
        $action = $(if ([string]::IsNullOrWhiteSpace($entry.Action)) { $entry.Title } else { $entry.Action })
        $lines.Add("$(Format-ReviewInvariant -Value $index). **\[$($entry.Severity)\] $(ConvertTo-ReviewInlineText -Value $entry.Title)** — $(ConvertTo-ReviewInlineText -Value $action)")
    }
    $lines.Add('')

    return (($lines -join "`n") + "`n")
}

# --------------------------------------------------------------------------------------------------
# Canonicalization (D15): NFC strings, ordinal object keys, deterministic ordering for the arrays the
# contract treats as sets, integer numbers, compact JSON, LF, UTF-8 without BOM.
# --------------------------------------------------------------------------------------------------
function Sort-ReviewArrayByKey {
    <#
    .SYNOPSIS
        Orders array items by an ordinal string key, so the canonical order never depends on culture.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [Parameter(Mandatory)][scriptblock]$KeyScript
    )

    $decorated = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Items) {
        $decorated.Add([pscustomobject]@{ Key = [string](& $KeyScript $item); Item = $item })
    }
    $keys = @(Sort-ReviewOrdinal -Value @($decorated | ForEach-Object { $_.Key }))
    $byKey = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.Queue[object]]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $decorated) {
        if (-not $byKey.ContainsKey($entry.Key)) { $byKey[$entry.Key] = [System.Collections.Generic.Queue[object]]::new() }
        $byKey[$entry.Key].Enqueue($entry.Item)
    }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $keys) { $result.Add($byKey[$key].Dequeue()) }
    return $result.ToArray()
}

function ConvertTo-ReviewCanonicalNode {
    param([object]$Node, [string]$ArrayRole = '')

    if ($Node -is [System.Collections.IDictionary]) {
        # An ordinal-keyed map, not `[ordered]@{}`: PowerShell's ordered dictionary compares keys
        # case-insensitively, so two case-distinct JSON members would collapse into one and the
        # "lossless" canonical form would quietly drop data.
        $ordered = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
        # Ordinal, never Sort-Object: object key order decides the canonical bytes, and a
        # culture-sensitive comparison would give cs-CZ, tr-TR and de-DE hosts different digests for
        # the same document (D15).
        foreach ($key in (Sort-ReviewOrdinal -Value @($Node.Keys | ForEach-Object { [string]$_ }))) {
            $childRole = $(switch ([string]$key) {
                    'tasks' { 'tasks' }
                    'findings' { 'findings' }
                    'roster' { 'strings' }
                    'references' { 'strings' }
                    'paths' { 'scopePaths' }
                    'modelSelection' { 'modelSelection' }
                    default { '' }
                })
            $ordered[[string]$key] = ConvertTo-ReviewCanonicalNode -Node $Node[$key] -ArrayRole $childRole
        }
        return $ordered
    }

    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Node) { $items.Add((ConvertTo-ReviewCanonicalNode -Node $item)) }
        $array = $items.ToArray()

        switch ($ArrayRole) {
            'strings' {
                $array = @(Sort-ReviewOrdinal -Value @($array | ForEach-Object { [string]$_ }))
            }
            'tasks' {
                $array = @(Sort-ReviewArrayByKey -Items $array -KeyScript { param($t) [string]$t['taskId'] })
            }
            'findings' {
                $array = @(Sort-ReviewArrayByKey -Items $array -KeyScript { param($f) Get-ReviewFindingSortKey -Finding $f })
            }
            'scopePaths' {
                $array = @(Sort-ReviewArrayByKey -Items $array -KeyScript {
                        param($record) Get-ReviewOrdinalTupleKey -Value @([string]$record['path'], [string]$record['status'])
                    })
            }
            'modelSelection' {
                $array = @(Sort-ReviewArrayByKey -Items $array -KeyScript {
                        param($record) Get-ReviewOrdinalTupleKey -Value @([string]$record['declared'], [string]$record['requested'])
                    })
            }
        }
        return , $array
    }

    if ($Node -is [string]) {
        return (ConvertTo-ReviewCanonicalText -Value $Node)
    }

    # Semantic equivalence for numbers (D15). Draft 2020-12 accepts `1.0` wherever it accepts `1`, and
    # `ConvertFrom-Json` hands that back as a double, so two envelopes that are the same document would
    # otherwise serialize as `1.0` and `1` and hash differently. Every schema-valid integral value is
    # therefore written in its integer form; a genuinely fractional number, and anything too large for
    # an exact round trip, is left untouched.
    if ($Node -is [double] -or $Node -is [single]) {
        $value = [double]$Node
        if ([double]::IsFinite($value) -and $value -eq [Math]::Floor($value) -and [Math]::Abs($value) -le 9007199254740992d) {
            return [long]$value
        }
        return $Node
    }
    if ($Node -is [decimal]) {
        if ([Math]::Floor($Node) -eq $Node -and $Node -ge [decimal]([long]::MinValue) -and $Node -le [decimal]([long]::MaxValue)) {
            return [long]$Node
        }
        return $Node
    }
    return $Node
}

function Get-ReviewFindingSortKey {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Finding)

    $references = @()
    if ($Finding.Contains('references')) {
        $references = @(Sort-ReviewOrdinal -Value @($Finding['references'] | ForEach-Object { [string]$_ }))
    }
    return Get-ReviewOrdinalTupleKey -Value @(
        [string]$Finding['taskId'],
        [string]$Finding['severity'],
        [string]$Finding['title'],
        [string]$(if ($Finding.Contains('body')) { $Finding['body'] } else { '' }),
        [string]$(if ($Finding.Contains('action')) { $Finding['action'] } else { '' }),
        [string]$(if ($Finding.Contains('rootCause')) { $Finding['rootCause'] } else { '' }),
        [string]$(if ($Finding.Contains('component')) { $Finding['component'] } else { '' }),
        (Get-ReviewOrdinalTupleKey -Value $references)
    )
}

function ConvertTo-ReviewCanonicalJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Node)

    $canonical = ConvertTo-ReviewCanonicalNode -Node $Node
    $json = ConvertTo-Json -InputObject $canonical -Depth 40 -Compress
    return $json + "`n"
}

function Get-ReviewSha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Get-ReviewDigest {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return 'sha256:' + (Get-ReviewSha256Hex -Bytes $Bytes)
}

function Get-ReviewScopeDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$ScopeAuthority)

    $copy = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    foreach ($key in @($ScopeAuthority.Keys)) {
        if ([string]::Equals([string]$key, 'digest', [System.StringComparison]::Ordinal)) { continue }
        $copy[[string]$key] = $ScopeAuthority[$key]
    }
    return Get-ReviewDigest -Bytes $script:Utf8NoBom.GetBytes((ConvertTo-ReviewCanonicalJson -Node $copy))
}

function Invoke-ReviewGit {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'
    $start.WorkingDirectory = $RepoRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $script:Utf8NoBom
    $start.StandardErrorEncoding = $script:Utf8NoBom
    foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "git $($Arguments[0]) failed while deriving review scope: $($stderr.Trim())"
    }
    return $stdout
}

function Resolve-ReviewBranchScopeAuthority {
    param(
        [Parameter(Mandatory)][object]$ScopeAuthority,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    if ([string](Get-ReviewValue -Node $ScopeAuthority -Name 'mode') -ne 'branch') { return }
    $resolved = [ordered]@{}
    foreach ($name in @('base', 'head')) {
        $identity = [string](Get-ReviewValue -Node $ScopeAuthority -Name $name)
        if ([string]::IsNullOrWhiteSpace($identity)) { throw "branch scope authority requires a $name identity" }
        $resolved[$name] = (Invoke-ReviewGit -RepoRoot $RepoRoot -Arguments @('rev-parse', '--verify', '--end-of-options', "$identity^{commit}" )).Trim()
    }

    $raw = Invoke-ReviewGit -RepoRoot $RepoRoot -Arguments @('diff', '--name-status', '--no-renames', '-z', "$($resolved.base)...$($resolved.head)", '--')
    $parts = @($raw.Split([char]0) | Where-Object { -not [string]::IsNullOrEmpty($_) })
    if (($parts.Count % 2) -ne 0) { throw 'git returned a malformed branch scope record stream' }
    $paths = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $parts.Count; $index += 2) {
        $status = switch -Regex ($parts[$index]) {
            '^A' { 'added'; break }
            '^D' { 'deleted'; break }
            default { 'modified' }
        }
        $paths.Add([ordered]@{ path = $parts[$index + 1].Replace('\', '/'); status = $status })
    }
    if ($paths.Count -eq 0) { throw 'branch scope resolves to no changed paths' }
    $ScopeAuthority['base'] = $resolved.base
    $ScopeAuthority['head'] = $resolved.head
    $ScopeAuthority['paths'] = @($paths | Sort-Object { [string]$_.path }, { [string]$_.status })
    $ScopeAuthority['digest'] = Get-ReviewScopeDigest -ScopeAuthority $ScopeAuthority
}

# --------------------------------------------------------------------------------------------------
# Structural validation via native Test-Json.
# --------------------------------------------------------------------------------------------------
function Test-ReviewSchema {
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$SchemaName
    )
    return [bool](Test-Json -Json $Json -SchemaFile (Join-Path $script:SchemaRoot $SchemaName) -ErrorAction SilentlyContinue)
}

# --------------------------------------------------------------------------------------------------
# Semantic validation (the layer no single-document schema can decide). Returns @() on success or a
# list of human-readable failures.
# --------------------------------------------------------------------------------------------------
function Test-ReviewPlanSemantic {
    param([Parameter(Mandatory)][object]$Plan)

    $limits = Get-ReviewLimits
    $failures = [System.Collections.Generic.List[string]]::new()
    $tasks = @(Get-ReviewValue -Node $Plan -Name 'tasks')

    if ($tasks.Count -lt 1) { $failures.Add('a frozen plan needs at least one task'); return $failures }
    if ($tasks.Count -gt [int]$limits.maxTasks) { $failures.Add("a frozen plan admits at most $($limits.maxTasks) tasks") }
    if ($tasks.Count -gt [int](Get-ReviewValue -Node $Plan -Name 'invocationBudget')) {
        $failures.Add('the planned task count exceeds invocationBudget')
    }

    $reviewType = [string](Get-ReviewValue -Node $Plan -Name 'reviewType')
    $scopeAuthority = Get-ReviewValue -Node $Plan -Name 'scopeAuthority'
    $scopeMode = [string](Get-ReviewValue -Node $scopeAuthority -Name 'mode')
    $scopePaths = @(Get-ReviewValue -Node $scopeAuthority -Name 'paths')
    $scopeDigest = [string](Get-ReviewValue -Node $scopeAuthority -Name 'digest')
    if (-not [string]::Equals($scopeDigest, (Get-ReviewScopeDigest -ScopeAuthority $scopeAuthority), [System.StringComparison]::Ordinal)) {
        $failures.Add('scopeAuthority digest does not match its canonical source descriptor and path records')
    }
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($record in $scopePaths) {
        $path = [string](Get-ReviewValue -Node $record -Name 'path')
        if ([System.IO.Path]::IsPathRooted($path) -or $path.Contains('\') -or @($path -split '/' | Where-Object { $_ -in @('.', '..') }).Count -gt 0) {
            $failures.Add("scope path '$path' is not a canonical repository-relative path")
        }
        if (-not $seenPaths.Add($path)) { $failures.Add("scope path '$path' appears more than once") }
    }
    if ($reviewType -eq 'code') {
        if ($scopeMode -eq 'design') { $failures.Add('a code review cannot use design scope authority') }
        if ($scopePaths.Count -eq 0) { $failures.Add('a code review scope needs at least one canonical path record') }
        if ($scopeMode -eq 'branch' -and
            ([string]::IsNullOrWhiteSpace([string](Get-ReviewValue -Node $scopeAuthority -Name 'base')) -or
            [string]::IsNullOrWhiteSpace([string](Get-ReviewValue -Node $scopeAuthority -Name 'head')))) {
            $failures.Add('branch scope authority requires base and head identities')
        }
        if ($null -ne (Get-ReviewValue -Node $scopeAuthority -Name 'designSource')) {
            $failures.Add('a code review scope cannot carry a design source descriptor')
        }
    }
    else {
        if ($scopeMode -ne 'design') { $failures.Add('a design review requires design scope authority') }
        if ($null -eq (Get-ReviewValue -Node $scopeAuthority -Name 'designSource')) {
            $failures.Add('a design review requires a canonical design source descriptor')
        }
    }

    # The roster is the closed set of dispatch models the plan declares (D4/D9): a task naming a model
    # outside it would freeze an attendance claim about a model this run never declared, and Publish
    # binds to the frozen set, so the lie would survive into the published artifact.
    $roster = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@(Get-ReviewValue -Node $Plan -Name 'roster' | ForEach-Object { [string]$_ }),
        [System.StringComparer]::Ordinal
    )
    $selectedModels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($selection in @(Get-ReviewValue -Node $Plan -Name 'modelSelection')) {
        $requested = [string](Get-ReviewValue -Node $selection -Name 'requested')
        $declared = [string](Get-ReviewValue -Node $selection -Name 'declared')
        $preflight = [string](Get-ReviewValue -Node $selection -Name 'preflight')
        $degradation = [string](Get-ReviewValue -Node $selection -Name 'degradation')
        $fallback = [string](Get-ReviewValue -Node $selection -Name 'fallback')
        if (-not $selectedModels.Add($declared)) { $failures.Add("declared model '$declared' has more than one selection record") }
        if (-not $roster.Contains($declared)) { $failures.Add("declared model '$declared' is outside the roster") }
        if ($degradation -eq 'none' -and (-not [string]::Equals($requested, $declared, [System.StringComparison]::Ordinal) -or -not [string]::IsNullOrEmpty($fallback))) {
            $failures.Add("model '$declared' claims no degradation but requested/fallback state disagrees")
        }
        if ($degradation -eq 'fallback' -and ([string]::IsNullOrWhiteSpace($fallback) -or -not [string]::Equals($fallback, $declared, [System.StringComparison]::Ordinal))) {
            $failures.Add("model '$declared' fallback degradation does not name the declared fallback")
        }
        if ($degradation -eq 'preflight-unavailable' -and $preflight -ne 'unavailable') {
            $failures.Add("model '$declared' preflight-unavailable degradation lacks an unavailable preflight")
        }
    }
    if ($selectedModels.Count -ne $roster.Count) { $failures.Add('modelSelection does not cover the declared roster exactly') }

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $slots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($task in $tasks) {
        $id = [string](Get-ReviewValue -Node $task -Name 'taskId')
        $model = [string](Get-ReviewValue -Node $task -Name 'model')
        if (-not $ids.Add($id)) { $failures.Add("duplicate task id '$id'") }
        # A length-prefixed tuple, never a delimiter join: a model is unconstrained text, so a packed
        # key could otherwise be forged into another slot's key.
        $slot = Get-ReviewOrdinalTupleKey -Value @([string](Get-ReviewValue -Node $task -Name 'concern'), $model)
        if (-not $slots.Add($slot)) { $failures.Add("duplicate concern/model slot for task '$id'") }
        if (-not $roster.Contains($model)) { $failures.Add("task '$id' names model '$model' outside the roster") }
    }
    return $failures
}

function Test-ReviewRunSemantic {
    param(
        [Parameter(Mandatory)][object]$Run,
        [Parameter(Mandatory)][object]$FrozenPlan,
        [Parameter(Mandatory)][string]$FrozenPlanDigest
    )

    $limits = Get-ReviewLimits
    $failures = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::Equals(
            [string](Get-ReviewValue -Node $Run -Name 'planDigest'),
            $FrozenPlanDigest,
            [System.StringComparison]::Ordinal)) {
        $failures.Add('planDigest does not match the frozen plan bytes')
    }

    foreach ($field in @('reviewType', 'contentTrust', 'scope')) {
        if (-not [string]::Equals(
                [string](Get-ReviewValue -Node $Run -Name $field),
                [string](Get-ReviewValue -Node $FrozenPlan -Name $field),
                [System.StringComparison]::Ordinal)) {
            $failures.Add("$field differs from the frozen plan")
        }
    }
    foreach ($field in @('scopeAuthority', 'modelSelection', 'restart')) {
        $runValue = Get-ReviewValue -Node $Run -Name $field
        $planValue = Get-ReviewValue -Node $FrozenPlan -Name $field
        if ($null -eq $runValue -and $null -eq $planValue) { continue }
        if ($null -eq $runValue -or $null -eq $planValue) {
            $failures.Add("$field differs from the frozen plan")
            continue
        }
        if (-not [string]::Equals(
                (ConvertTo-ReviewCanonicalJson -Node $runValue),
                (ConvertTo-ReviewCanonicalJson -Node $planValue),
                [System.StringComparison]::Ordinal)) {
            $failures.Add("$field differs from the frozen plan")
        }
    }
    if ([int](Get-ReviewValue -Node $Run -Name 'invocationBudget') -ne
        [int](Get-ReviewValue -Node $FrozenPlan -Name 'invocationBudget')) {
        $failures.Add('invocationBudget differs from the frozen plan')
    }
    $runRoster = @(Get-ReviewValue -Node $Run -Name 'roster' | ForEach-Object { [string]$_ })
    $planRoster = @(Get-ReviewValue -Node $FrozenPlan -Name 'roster' | ForEach-Object { [string]$_ })
    # Length-prefixed tuples, never a `U+0001` join: a model name is unconstrained text, so a roster of
    # one model containing the delimiter would compare equal to a two-model roster and let a result
    # claim an attendance set the frozen plan never declared.
    if (-not [string]::Equals(
            (Get-ReviewOrdinalTupleKey -Value @(Sort-ReviewOrdinal -Value $runRoster)),
            (Get-ReviewOrdinalTupleKey -Value @(Sort-ReviewOrdinal -Value $planRoster)),
            [System.StringComparison]::Ordinal)) {
        $failures.Add('roster differs from the frozen plan')
    }

    $rosterSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$runRoster, [System.StringComparer]::Ordinal)

    # Exact frozen-set equality: every planned slot present, no extra task, nothing mutated.
    $planTaskById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($task in @(Get-ReviewValue -Node $FrozenPlan -Name 'tasks')) {
        $planTaskById[[string](Get-ReviewValue -Node $task -Name 'taskId')] = $task
    }
    $runTaskById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $slots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $completed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($task in @(Get-ReviewValue -Node $Run -Name 'tasks')) {
        $id = [string](Get-ReviewValue -Node $task -Name 'taskId')
        $concern = [string](Get-ReviewValue -Node $task -Name 'concern')
        $model = [string](Get-ReviewValue -Node $task -Name 'model')
        $outcome = [string](Get-ReviewValue -Node $task -Name 'outcome')
        $runTaskById[$id] = $task
        if (-not $ids.Add($id)) { $failures.Add("duplicate task id '$id'") }
        if (-not $slots.Add((Get-ReviewOrdinalTupleKey -Value @($concern, $model)))) { $failures.Add("duplicate concern/model slot for task '$id'") }
        if (-not $rosterSet.Contains($model)) { $failures.Add("task '$id' names model '$model' outside the roster") }
        if ($outcome -eq 'completed') { [void]$completed.Add($id) }

        if (-not $planTaskById.ContainsKey($id)) {
            $failures.Add("task '$id' is not in the frozen plan")
        }
        else {
            $planTask = $planTaskById[$id]
            if (-not [string]::Equals(
                    $concern,
                    [string](Get-ReviewValue -Node $planTask -Name 'concern'),
                    [System.StringComparison]::Ordinal) -or
                -not [string]::Equals(
                    $model,
                    [string](Get-ReviewValue -Node $planTask -Name 'model'),
                    [System.StringComparison]::Ordinal)) {
                $failures.Add("task '$id' mutated its concern or model after freeze")
            }
        }

        $diagnostic = [string](Get-ReviewValue -Node $task -Name 'diagnostic')
        if (-not [string]::IsNullOrEmpty($diagnostic)) {
            if ([System.Text.Encoding]::UTF8.GetByteCount($diagnostic) -gt [int]$limits.maxTaskDiagnosticBytes) {
                $failures.Add("task '$id' diagnostic exceeds $($limits.maxTaskDiagnosticBytes) UTF-8 bytes")
            }
        }
    }
    foreach ($id in $planTaskById.Keys) {
        if (-not $runTaskById.ContainsKey($id)) { $failures.Add("frozen task '$id' is absent from the result") }
    }

    $findingRefs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    # The vocabulary's `maxMergedFindings` is a property of the *merged* set, which no single-document
    # keyword can count: 256 raw findings are legal, and they may collapse into anything between one
    # group and 256. It is decided here, with the renderer's own grouping key, so a run that would
    # render more groups than the contract admits is exit 2 before anything is canonicalized, rendered
    # or written — not an over-budget render, and never a silently reduced report.
    $mergeKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($finding in @(Get-ReviewValue -Node $Run -Name 'findings')) {
        $taskId = [string](Get-ReviewValue -Node $finding -Name 'taskId')
        [void]$mergeKeys.Add((Get-ReviewMergeKey -Finding $finding))
        if (-not $runTaskById.ContainsKey($taskId)) {
            $failures.Add("finding names task '$taskId' which the run does not contain")
        }
        elseif (-not $completed.Contains($taskId)) {
            $failures.Add("finding is owned by task '$taskId' whose outcome is not completed")
        }
        $body = [string](Get-ReviewValue -Node $finding -Name 'body')
        if (-not [string]::IsNullOrEmpty($body)) {
            if ([System.Text.Encoding]::UTF8.GetByteCount($body) -gt [int]$limits.maxBodyBytes) {
                $failures.Add("a finding body exceeds $($limits.maxBodyBytes) UTF-8 bytes")
            }
        }
        [void]$findingRefs.Add($taskId)
    }
    if ($mergeKeys.Count -gt [int]$limits.maxMergedFindings) {
        $failures.Add("the findings merge into $($mergeKeys.Count) groups, over the $($limits.maxMergedFindings) merged-finding maximum")
    }

    return $failures
}

function Test-ReviewRestartAuthority {
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$Boundary
    )

    $restart = Get-ReviewValue -Node $Plan -Name 'restart'
    if ($null -eq $restart) { return @() }
    $failures = [System.Collections.Generic.List[string]]::new()
    $partitionIndex = [int](Get-ReviewValue -Node $restart -Name 'partitionIndex')
    $partitionCount = [int](Get-ReviewValue -Node $restart -Name 'partitionCount')
    if ($partitionIndex -gt $partitionCount) { $failures.Add('restart partitionIndex exceeds partitionCount') }

    $parentRunId = [string](Get-ReviewValue -Node $restart -Name 'parentRunId')
    $parentDir = Join-Path (Split-Path -Parent $RunDir) $parentRunId
    try { $admission = Read-ReviewAdmissionMarker -RunDir $parentDir -Boundary $Boundary }
    catch { $failures.Add("restart parent admission does not verify: $($_.Exception.Message)"); return $failures }
    if (-not [bool]$admission.Marker['restartable']) { $failures.Add('restart parent admission is not restartable') }
    if (-not [string]::Equals([string](Get-ReviewValue -Node $restart -Name 'parentRunDigest'), [string]$admission.Marker['parentRunDigest'], [System.StringComparison]::Ordinal)) {
        $failures.Add('restart parentRunDigest does not match the verified admission source')
    }

    try { $parentFrozen = Read-ReviewFrozenPlan -RunDir $parentDir }
    catch { $failures.Add("restart parent frozen plan does not verify: $($_.Exception.Message)"); return $failures }
    if ($null -ne (Get-ReviewValue -Node $parentFrozen.Plan -Name 'restart')) {
        $failures.Add('restart depth exceeds the hard maximum of one')
    }
    foreach ($field in @('reviewType', 'contentTrust', 'roster', 'modelSelection', 'invocationBudget', 'tasks')) {
        if (-not [string]::Equals(
                (ConvertTo-ReviewCanonicalJson -Node (Get-ReviewValue -Node $Plan -Name $field)),
                (ConvertTo-ReviewCanonicalJson -Node (Get-ReviewValue -Node $parentFrozen.Plan -Name $field)),
                [System.StringComparison]::Ordinal)) {
            $failures.Add("restart child changed frozen field '$field'")
        }
    }

    $parentScope = Get-ReviewValue -Node $parentFrozen.Plan -Name 'scopeAuthority'
    $childScope = Get-ReviewValue -Node $Plan -Name 'scopeAuthority'
    foreach ($field in @('mode', 'base', 'head', 'designSource')) {
        $childValue = Get-ReviewValue -Node $childScope -Name $field
        $parentValue = Get-ReviewValue -Node $parentScope -Name $field
        if ($null -eq $childValue -and $null -eq $parentValue) { continue }
        if ($null -eq $childValue -or $null -eq $parentValue) {
            $failures.Add("restart child changed scope source field '$field'")
            continue
        }
        if (-not [string]::Equals(
                (ConvertTo-ReviewCanonicalJson -Node $childValue),
                (ConvertTo-ReviewCanonicalJson -Node $parentValue),
                [System.StringComparison]::Ordinal)) {
            $failures.Add("restart child changed scope source field '$field'")
        }
    }
    $parentPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($record in @(Get-ReviewValue -Node $parentScope -Name 'paths')) {
        [void]$parentPaths.Add((Get-ReviewOrdinalTupleKey -Value @([string](Get-ReviewValue -Node $record -Name 'path'), [string](Get-ReviewValue -Node $record -Name 'status'))))
    }
    foreach ($record in @(Get-ReviewValue -Node $childScope -Name 'paths')) {
        $key = Get-ReviewOrdinalTupleKey -Value @([string](Get-ReviewValue -Node $record -Name 'path'), [string](Get-ReviewValue -Node $record -Name 'status'))
        if (-not $parentPaths.Contains($key)) { $failures.Add('restart child contains a path record outside the parent scope') }
    }
    return $failures
}

# --------------------------------------------------------------------------------------------------
# Secret guard (D18/RISK-16). Deterministic, high-confidence credential shapes only. The block/allow
# behavior is pinned by a versioned corpus whose committed fixtures carry only inert fragments; the
# patterns below are character classes, never a literal token.
# --------------------------------------------------------------------------------------------------
$script:SecretBlockPatterns = @(
    [pscustomobject]@{ Type = 'github-pat-classic'; Pattern = 'gh[pousr]_[0-9A-Za-z]{36}' }
    [pscustomobject]@{ Type = 'github-pat-fine-grained'; Pattern = 'github_pat_[0-9A-Za-z_]{22,}' }
    [pscustomobject]@{ Type = 'aws-access-key-id'; Pattern = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b' }
    [pscustomobject]@{ Type = 'google-api-key'; Pattern = '\bAIza[0-9A-Za-z_\-]{35}\b' }
    [pscustomobject]@{ Type = 'slack-token'; Pattern = 'xox[baprs]-[0-9A-Za-z-]{10,}' }
    [pscustomobject]@{ Type = 'stripe-secret-key'; Pattern = '\bsk_(?:live|test)_[0-9A-Za-z]{24,}\b' }
    [pscustomobject]@{ Type = 'npm-token'; Pattern = '\bnpm_[0-9A-Za-z]{36}\b' }
    [pscustomobject]@{ Type = 'private-key-block'; Pattern = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----' }
)

# Known non-secrets that share a high-confidence shape. The rule is exactness, not resemblance: a
# real credential that happens to contain the letters `example` anywhere in its body used to be
# allowed by a substring match, which is precisely the value the guard exists to stop. An allowed
# token is now either the one published AWS documentation key verbatim, or a provider prefix whose
# entire body is a mask run or an exact repetition of a synthetic marker word.
$script:SecretAllowLiterals = @('AKIAIOSFODNN7EXAMPLE')
$script:SecretPrefixPattern = '^(?:gh[pousr]_|github_pat_|AKIA|ASIA|AIza|xox[baprs]-|sk_(?:live|test)_|npm_)'
$script:SecretMaskPattern = '^(?:X+|x+|\*+|0+|\.+|#+|_+|-+)$'
$script:SecretSyntheticMarkers = @('REDACTED', 'EXAMPLE', 'PLACEHOLDER', 'DUMMY', 'SAMPLE', 'NOTAREALTOKEN')

function Test-ReviewSecretAllowed {
    <#
    .SYNOPSIS
        Whether one matched credential-shaped token is a known synthetic value rather than a secret.
    .DESCRIPTION
        Exact shapes only (D18): the published AWS documentation key, or a recognized provider prefix
        followed by a body that is entirely a mask run (`XXXX…`, `****…`) or an exact repetition of a
        synthetic marker (`REDACTEDREDACTED…`, truncated at the shape's fixed length). Anything else
        — including a token that merely *contains* `example` or `redacted` — is treated as a secret.
    #>
    param([Parameter(Mandatory)][string]$Token)

    foreach ($literal in $script:SecretAllowLiterals) {
        if ($Token -ceq $literal) { return $true }
    }

    $prefix = [regex]::Match($Token, $script:SecretPrefixPattern)
    if (-not $prefix.Success) { return $false }
    $body = $Token.Substring($prefix.Length)
    if ($body.Length -lt 8) { return $false }

    if ([regex]::IsMatch($body, $script:SecretMaskPattern)) { return $true }

    foreach ($marker in $script:SecretSyntheticMarkers) {
        $repeats = [int][Math]::Ceiling($body.Length / [double]$marker.Length)
        $expanded = ($marker * $repeats).Substring(0, $body.Length)
        if ($body -ceq $expanded) { return $true }
    }
    return $false
}

function Test-ReviewValueForSecret {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return @() }
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($rule in $script:SecretBlockPatterns) {
        foreach ($match in [regex]::Matches($Value, $rule.Pattern)) {
            if (Test-ReviewSecretAllowed -Token $match.Value) { continue }
            $hits.Add($rule.Type)
        }
    }
    return @($hits | Select-Object -Unique)
}

function Find-ReviewSecret {
    <#
    .SYNOPSIS
        Scans every untrusted string in a plan or result envelope for a high-confidence credential
        shape. Returns redacted findings — the credential type and the field it appeared in, never the
        value.
    .DESCRIPTION
        Freeze persists reviewer- and orchestrator-authored strings (scope, roster, task models) into a
        committed artifact before Publish ever runs, so the guard has to cover the plan envelope too:
        a credential quoted in a scope line would otherwise be frozen into the repository and only
        noticed one mode later, when the plan is already immutable (RISK-16).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Run)

    $results = [System.Collections.Generic.List[object]]::new()

    function Add-Hit([string]$Field, [string]$Value) {
        foreach ($type in (Test-ReviewValueForSecret -Value $Value)) {
            $results.Add([pscustomobject]@{ Type = $type; Location = $Field })
        }
    }

    Add-Hit -Field 'scope' -Value ([string](Get-ReviewValue -Node $Run -Name 'scope'))
    $scopeAuthority = Get-ReviewValue -Node $Run -Name 'scopeAuthority'
    foreach ($field in @('base', 'head')) { Add-Hit -Field "scopeAuthority/$field" -Value ([string](Get-ReviewValue -Node $scopeAuthority -Name $field)) }
    foreach ($record in @(Get-ReviewValue -Node $scopeAuthority -Name 'paths')) {
        Add-Hit -Field 'scopeAuthority/path' -Value ([string](Get-ReviewValue -Node $record -Name 'path'))
    }
    $designSource = Get-ReviewValue -Node $scopeAuthority -Name 'designSource'
    Add-Hit -Field 'scopeAuthority/designSource/path' -Value ([string](Get-ReviewValue -Node $designSource -Name 'path'))
    foreach ($selection in @(Get-ReviewValue -Node $Run -Name 'modelSelection')) {
        foreach ($field in @('requested', 'declared', 'fallback')) {
            Add-Hit -Field "modelSelection/$field" -Value ([string](Get-ReviewValue -Node $selection -Name $field))
        }
    }
    $rosterIndex = 0
    foreach ($model in @(Get-ReviewValue -Node $Run -Name 'roster')) {
        $rosterIndex++
        Add-Hit -Field "roster:$rosterIndex" -Value ([string]$model)
    }
    foreach ($task in @(Get-ReviewValue -Node $Run -Name 'tasks')) {
        $taskId = [string](Get-ReviewValue -Node $task -Name 'taskId')
        Add-Hit -Field "task:$taskId/model" -Value ([string](Get-ReviewValue -Node $task -Name 'model'))
        Add-Hit -Field "task:$taskId/diagnostic" -Value ([string](Get-ReviewValue -Node $task -Name 'diagnostic'))
    }
    $index = 0
    foreach ($finding in @(Get-ReviewValue -Node $Run -Name 'findings')) {
        $index++
        foreach ($field in @('title', 'body', 'action', 'rootCause', 'component')) {
            Add-Hit -Field "finding:$index/$field" -Value ([string](Get-ReviewValue -Node $finding -Name $field))
        }
        foreach ($reference in @(Get-ReviewValue -Node $finding -Name 'references')) {
            Add-Hit -Field "finding:$index/references" -Value ([string]$reference)
        }
    }

    # Distinct (type, location) pairs, ordinal-ordered so the diagnostic is deterministic on every
    # culture — `Sort-Object` would order these by the operator's locale.
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $distinct = [System.Collections.Generic.List[object]]::new()
    foreach ($hit in (Sort-ReviewArrayByKey -Items @($results) -KeyScript {
                param($item) Get-ReviewOrdinalTupleKey -Value @([string]$item.Type, [string]$item.Location)
            })) {
        if ($seen.Add((Get-ReviewOrdinalTupleKey -Value @([string]$hit.Type, [string]$hit.Location)))) { $distinct.Add($hit) }
    }
    return @($distinct)
}

# --------------------------------------------------------------------------------------------------
# Terminal status (D7/D17): one closed JSON object, ordinal keys, compact, LF, UTF-8, at most 8 KiB.
# Diagnostics are dropped from the end until it fits rather than truncated mid-string.
# --------------------------------------------------------------------------------------------------
function Get-ReviewTerminalStatusShape {
    <#
    .SYNOPSIS
        The schema-valid (exit code, state, run-id) combination for one terminal status.
    .DESCRIPTION
        `Get-ReviewTerminalStatusJson` and `Write-ReviewTerminalStatus` are exported, so they are
        reachable from callers the CLIs do not control. A rejected run id is never echoed — it is
        unbounded caller-controlled text and the status schema admits only a UUID there — and the
        schema binds `runIdRejected` to exactly one shape: exit `2`, state `invalid`. Any other exit or
        state offered with a rejected id is therefore normalized to that combination rather than
        serialized into a status object that fails its own schema. Bounded, schema-valid output is the
        contract; throwing before serialization would leave a caller with no terminal object at all.
        The capability mode has no run to name, so a run id is ignored there entirely.
    #>
    param(
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$State,
        [string]$RunId
    )

    $hasValidRunId = $false
    $rejectedRunId = $false
    if ($Mode -ne 'capability' -and -not [string]::IsNullOrEmpty($RunId)) {
        if (Test-ReviewRunId -RunId $RunId) { $hasValidRunId = $true } else { $rejectedRunId = $true }
    }

    $exitCode = $ExitCode
    $state = $State
    if ($rejectedRunId) {
        $exitCode = 2
        $state = 'invalid'
    }

    return [pscustomobject]@{
        ExitCode      = $exitCode
        State         = $state
        HasValidRunId = $hasValidRunId
        RejectedRunId = $rejectedRunId
    }
}

function Get-ReviewTerminalStatusJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('capability', 'freeze', 'publish')][string]$Mode,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [string]$RunId,
        [string[]]$Diagnostic = @()
    )

    $limits = Get-ReviewLimits
    $maxBytes = [int]$limits.maxTerminalStatusBytes

    $trimmedMessage = ([string]$Message) -replace '\s+', ' '
    if ($trimmedMessage.Length -gt [int]$limits.maxScopeLength) { $trimmedMessage = $trimmedMessage.Substring(0, [int]$limits.maxScopeLength) }
    if ([string]::IsNullOrEmpty($trimmedMessage)) { $trimmedMessage = '.' }

    # A rejected run id is never echoed. It is caller-controlled and unbounded — a 9 KiB argument
    # would both blow the 8 KiB stdout budget (nothing else in the object can shrink far enough to
    # compensate, so the old shrink loop spun forever) and violate the status schema, whose `runId`
    # is a UUID. The status instead records that an id was rejected, which is the true fact, and the
    # exit/state pair is normalized to the one combination the schema binds to that fact.
    $shape = Get-ReviewTerminalStatusShape -Mode $Mode -ExitCode $ExitCode -State $State -RunId $RunId
    $hasValidRunId = $shape.HasValidRunId
    $rejectedRunId = $shape.RejectedRunId
    $effectiveExitCode = $shape.ExitCode
    $effectiveState = $shape.State

    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Diagnostic) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        if ($entries.Count -ge 16) { break }
        $flat = ([string]$item) -replace '\s+', ' '
        if ($flat.Length -gt 512) { $flat = $flat.Substring(0, 512) }
        $entries.Add($flat)
    }

    # Strictly monotonic shrinking with a terminating floor: every iteration removes a diagnostic or
    # makes the message shorter, and once neither can shrink the loop stops rather than spinning on a
    # size it cannot reach.
    $json = $null
    while ($true) {
        $status = [ordered]@{}
        if ($entries.Count -gt 0) { $status['diagnostics'] = @($entries) }
        $status['exitCode'] = $effectiveExitCode
        $status['message'] = $trimmedMessage
        $status['mode'] = $Mode
        if ($hasValidRunId) { $status['runId'] = $RunId }
        if ($rejectedRunId) { $status['runIdRejected'] = $true }
        $status['schema'] = $script:TerminalDiscriminator
        $status['state'] = $effectiveState

        $json = ConvertTo-Json -InputObject $status -Depth 4 -Compress
        if ($script:Utf8NoBom.GetByteCount($json) + 1 -le $maxBytes) { break }
        if ($entries.Count -gt 0) { $entries.RemoveAt($entries.Count - 1); continue }
        if ($trimmedMessage.Length -le 1) { break }
        $shorter = [int]($trimmedMessage.Length / 2)
        if ($shorter -ge $trimmedMessage.Length) { $shorter = $trimmedMessage.Length - 1 }
        $trimmedMessage = $trimmedMessage.Substring(0, [Math]::Max(1, $shorter))
    }
    return $json
}

function Write-ReviewTerminalStatus {
    <#
    .SYNOPSIS
        Writes exactly one terminal-status object to stdout as raw LF-terminated UTF-8 bytes, so the
        output never depends on the host console encoding, then returns the exit code for the caller
        to `exit` with.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('capability', 'freeze', 'publish')][string]$Mode,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [string]$RunId,
        [string[]]$Diagnostic = @()
    )

    $json = Get-ReviewTerminalStatusJson -Mode $Mode -ExitCode $ExitCode -State $State -Message $Message -RunId $RunId -Diagnostic $Diagnostic
    $bytes = $script:Utf8NoBom.GetBytes($json + "`n")
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
    # The exit code the caller returns is the one the object states: a rejected run id normalizes both
    # halves together, so stdout and the process exit can never disagree.
    return (Get-ReviewTerminalStatusShape -Mode $Mode -ExitCode $ExitCode -State $State -RunId $RunId).ExitCode
}

function New-ReviewResult {
    param(
        [Parameter(Mandatory)][ValidateSet('freeze', 'publish')][string]$Mode,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [string]$RunId,
        [string[]]$Diagnostic = @(),
        [object]$Summary
    )
    return [pscustomobject]@{
        Mode        = $Mode
        ExitCode    = $ExitCode
        State       = $State
        Message     = $Message
        RunId       = $RunId
        Diagnostics = @($Diagnostic)
        Summary     = $Summary
    }
}

# --------------------------------------------------------------------------------------------------
# Path resolution. The caller supplies only a run id and, for a plan run, a plan directory; every
# root is derived here from this module's installed location and the repository inventory.
# --------------------------------------------------------------------------------------------------
function Get-ReviewRepoRoot {
    [CmdletBinding()]
    param([string]$StartPath = (Split-Path -Parent $PSCommandPath))

    $current = [System.IO.Path]::GetFullPath($StartPath)
    while ($true) {
        if ((Test-Path -LiteralPath (Join-Path $current '.git')) -or
            (Test-Path -LiteralPath (Join-Path $current 'registry.json'))) {
            return $current
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSCommandPath) '..' '..'))
}

function Test-ReviewRunId {
    param([string]$RunId)
    return ($RunId -cmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
}

function Assert-ReviewPathSafe {
    <#
    .SYNOPSIS
        Refuses to act on a path any of whose existing ancestors, up to and including the boundary, is
        a symlink or other reparse point.
    .DESCRIPTION
        RISK-6. Confinement is computed from resolved-free full paths, so a local process that swaps an
        ancestor for a link after resolution would redirect a write outside the store while every
        earlier string check still passes. This walk runs immediately before a write, a removal or a
        verified read — as close to the operation as a user-mode process can get — and same-user TOCTOU
        in the remaining window stays a documented residual risk.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Boundary
    )

    $current = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $stop = [System.IO.Path]::GetFullPath($Boundary).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    while ($true) {
        $item = Get-ReviewPathItem -Path $current
        if ($item -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing to use '$current': a path component is a symlink or reparse point."
        }
        if ($current -eq $stop) { break }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Import-ReviewPlanState {
    <#
    .SYNOPSIS
        Loads the plan-inventory module, preferring the resolved repository's copy and falling back to
        the one installed beside this module.
    #>
    param([Parameter(Mandatory)][string]$RepoRoot)

    $candidates = if ($script:IsCanonicalSource) {
        @(
            (Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) (Join-Path 'scripts' (Join-Path 'skalary' 'PlanState.psm1')))
        )
    }
    else {
        @($script:BundledPlanStatePath)
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Import-Module $candidate -Force -DisableNameChecking
            return
        }
    }
    throw 'PlanState.psm1 is not available, so a plan directory cannot be validated against the plan inventory.'
}

function Resolve-ReviewStoreRoot {
    <#
    .SYNOPSIS
        The directory that holds every run of one store: a plan folder's `ReviewRuns` asset directory,
        or the gitignored generic store. Every caller of a run path goes through here, so confinement
        and inventory validation cannot be bypassed by one entry point.
    .DESCRIPTION
        A plan directory is not trusted because it sits under `docs/implementation-plans/` and contains
        a `plan.md`: it must be a plan the repository inventory actually knows, and that inventory
        entry must resolve back to the same folder through `Resolve-Plan`. A path-prefix test alone
        accepts a hand-made folder, a traversal that lands back inside the tree, or an ambiguous
        duplicate id; the inventory is the same source of truth every other plan writer uses.
    #>
    [CmdletBinding()]
    param(
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    $repoFull = [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $RepoRoot))
    if (-not $PlanDir) {
        return [System.IO.Path]::GetFullPath((Join-Path $repoFull (Join-Path '.github' (Join-Path '.skalary' 'review-runs'))))
    }

    $planFull = [System.IO.Path]::GetFullPath($PlanDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $plansRoot = [System.IO.Path]::GetFullPath((Join-Path $repoFull (Join-Path 'docs' 'implementation-plans')))
    if (-not $planFull.StartsWith($plansRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::Ordinal)) {
        throw "Plan directory '$PlanDir' is outside the repository's implementation-plans tree."
    }
    # Confinement precedes every plan read. Inventory and layout resolution inspect plan.md and the
    # assets anchor, so each candidate path is checked before either subsystem can follow it.
    $planFile = Join-Path $planFull 'plan.md'
    $assetsDir = Join-Path $planFull 'assets'
    $requirementsFile = Join-Path $assetsDir 'requirements.md'
    foreach ($candidate in @($planFull, $planFile, $assetsDir, $requirementsFile)) {
        Assert-ReviewPathSafe -Path $candidate -Boundary $repoFull
    }
    if (-not (Test-Path -LiteralPath $planFile -PathType Leaf)) {
        throw "Plan directory '$PlanDir' has no plan.md; it is not a plan folder."
    }

    Import-ReviewPlanState -RepoRoot $repoFull
    $inventory = @(Get-PlanInventory -RepoRoot $repoFull)
    $entry = @($inventory | Where-Object {
            [System.IO.Path]::GetFullPath($_.Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar) -eq $planFull
        })
    if ($entry.Count -ne 1) {
        throw "Plan directory '$PlanDir' is not a plan in the repository inventory."
    }
    if ([string]::IsNullOrWhiteSpace($entry[0].Id)) {
        throw "Plan directory '$PlanDir' has no resolvable plan id."
    }
    # Round-trip through the resolver every other plan tool uses: an id that resolves elsewhere (or
    # ambiguously) means this folder is not the plan it claims to be.
    $resolved = Resolve-Plan -Reference $entry[0].Id -RepoRoot $repoFull -Inventory $inventory
    if ([System.IO.Path]::GetFullPath($resolved.Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar) -ne $planFull) {
        throw "Plan directory '$PlanDir' does not resolve to itself through the plan inventory."
    }

    return [System.IO.Path]::GetFullPath((Resolve-PlanAssetPath -PlanDir $planFull -Kind ReviewRuns))
}

function Resolve-ReviewRunRoot {
    <#
    .SYNOPSIS
        The on-disk run directory for a run id. A plan run resolves through the `ReviewRuns` asset
        kind of the plan folder (validated against the plan inventory); a generic run resolves under
        the gitignored generic store. No caller can choose any other root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    if (-not (Test-ReviewRunId -RunId $RunId)) {
        throw 'The run id is not a lowercase UUID.'
    }

    $store = Resolve-ReviewStoreRoot -PlanDir $PlanDir -RepoRoot $RepoRoot
    return (Join-Path $store $RunId)
}

function Resolve-ReviewRunPreparation {
    <#
    .SYNOPSIS
        Read-only initialization preflight. Returns the sole run root callers may create after every
        existing ancestor and leaf has passed confinement.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    if (-not (Test-ReviewRunId -RunId $RunId)) { throw 'The run id is not a lowercase UUID.' }
    $repoFull = [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $RepoRoot))
    $store = Resolve-ReviewStoreRoot -PlanDir $PlanDir -RepoRoot $repoFull
    $runRoot = Join-Path $store $RunId
    foreach ($candidate in @($store, $runRoot)) { Assert-ReviewPathSafe -Path $candidate -Boundary $repoFull }

    return [pscustomobject]@{
        schema  = 'skalary/review-prepare@1'
        runId   = $RunId
        runRoot = [System.IO.Path]::GetFullPath($runRoot)
    }
}

# --------------------------------------------------------------------------------------------------
# Content-addressed generations, input destruction and atomic writes.
# --------------------------------------------------------------------------------------------------
function Get-ReviewContentName {
    <#
    .SYNOPSIS
        The immutable file name for one generation: `<role>.<sha256-hex>.<ext>` (D13). The name is a
        claim about the bytes, so a reader can reject a file whose content no longer matches its name
        without consulting anything else.
    #>
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $descriptor = $script:ArtifactRole[$Role]
    if (-not $descriptor) { throw "Unknown artifact role '$Role'." }
    return $descriptor.Prefix + '.' + (Get-ReviewSha256Hex -Bytes $Bytes) + $descriptor.Extension
}

function Get-ReviewContentNamePattern {
    param([Parameter(Mandatory)][string]$Role)

    $descriptor = $script:ArtifactRole[$Role]
    if (-not $descriptor) { throw "Unknown artifact role '$Role'." }
    return '^' + [regex]::Escape($descriptor.Prefix) + '\.(?<hex>[0-9a-f]{64})' + [regex]::Escape($descriptor.Extension) + '$'
}

function Get-ReviewContentNameDigest {
    <#
    .SYNOPSIS
        The digest a content-addressed name claims, or `$null` when the name is not one.
    #>
    param([Parameter(Mandatory)][string]$Role, [Parameter(Mandatory)][string]$Name)

    $match = [regex]::Match($Name, (Get-ReviewContentNamePattern -Role $Role))
    if (-not $match.Success) { return $null }
    return 'sha256:' + $match.Groups['hex'].Value
}

function Write-ReviewBytesAtomic {
    <#
    .SYNOPSIS
        Writes bytes through a uniquely named temporary file in the same directory and renames it into
        place. The temporary is this call's own and is removed by this call alone — a sweep of every
        `*.tmp-*` in the directory would delete a concurrent process's in-flight staging.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)

    $dir = Split-Path -Parent $Path
    $tmp = Join-Path $dir ('.' + [System.IO.Path]::GetFileName($Path) + '.tmp-' + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllBytes($tmp, $Bytes)
        [System.IO.File]::Move($tmp, $Path, $true)
    }
    finally {
        if ([System.IO.File]::Exists($tmp)) { [System.IO.File]::Delete($tmp) }
    }
}

function Assert-ReviewInputLeafSafe {
    <#
    .SYNOPSIS
        Refuses a fixed input leaf that is a symlink or other reparse point, and re-confines its
        concrete path immediately before the caller accepts, reads, overwrites or unlinks it.
    .DESCRIPTION
        RISK-6. The two fixed input names are the one place an untrusted caller chooses the *content*
        of a path inside a run directory this engine owns, and the engine both reads that leaf and
        destroys it in place (`Remove-ReviewInputSecurely` overwrites the bytes before unlinking).
        A leaf swapped for a symlink therefore turned the handshake into an arbitrary-file read and,
        worse, an arbitrary-file shredder outside the store — the ancestor walk alone never saw it,
        because every ancestor was still a real directory this engine created.

        The link is never followed: its attributes are read with `-Force` (which stats the link, not
        its target), and a hit throws before anything opens, overwrites or deletes it. The external
        target is left exactly as it was, and the refusal surfaces as the contract's bounded exit `4`.
        The `Assert-ReviewPathSafe` walk still runs on the concrete path, so an ancestor swapped
        between resolution and use is refused by the same call.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Boundary
    )

    $item = Get-ReviewPathItem -Path $Path
    if ($item -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to use '$Path': the fixed input file is a symlink or reparse point."
    }
    Assert-ReviewPathSafe -Path $Path -Boundary $Boundary
}

function Get-ReviewInputPath {
    <#
    .SYNOPSIS
        The fixed input file a mode consumes, or `$null` when the caller has not put one in place.
    .DESCRIPTION
        D16 assigns the atomic rename to the caller: it writes `.review-plan.input.tmp` /
        `.review-result.input.tmp` and renames it onto the fixed name below. The engine consumes only
        the fixed name, so a half-written `.tmp` is never read, and a `.tmp` the caller never renamed
        is not an input at all.

        The leaf is confined before it is admitted as an input at all (RISK-6): a fixed name that is a
        symlink or reparse point is refused here rather than read, overwritten and unlinked through.
    #>
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$InputName,
        [Parameter(Mandatory)][string]$Boundary
    )

    $target = Join-Path $RunDir $InputName
    $item = Get-ReviewPathItem -Path $target
    if (-not $item) { return $null }
    Assert-ReviewInputLeafSafe -Path $target -Boundary $Boundary
    if ($item -isnot [System.IO.FileInfo]) { return $null }
    return $target
}

function Remove-ReviewInputSecurely {
    <#
    .SYNOPSIS
        Irreversibly destroys a rejected input: the bytes are overwritten before the file is unlinked,
        so a reviewer-quoted credential does not linger on disk after a secret rejection.
    .DESCRIPTION
        The leaf is re-confined immediately before the overwrite (RISK-6). This call shreds bytes, so a
        leaf swapped for a link between admission and destruction would destroy the link's target
        rather than the input; it is refused instead, and the link is left alone rather than followed.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Boundary
    )

    Assert-ReviewInputLeafSafe -Path $Path -Boundary $Boundary
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try {
        $length = (Get-Item -LiteralPath $Path).Length
        if ($length -gt 0) {
            $zero = [byte[]]::new([int][Math]::Min($length, [int]2097152))
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
            try {
                $remaining = $length
                while ($remaining -gt 0) {
                    $chunk = [int][Math]::Min($remaining, $zero.Length)
                    $stream.Write($zero, 0, $chunk)
                    $remaining -= $chunk
                }
                $stream.Flush()
            }
            finally { $stream.Dispose() }
        }
    }
    finally {
        [System.IO.File]::Delete($Path)
    }
}

function Remove-ReviewCommittedInput {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Boundary
    )

    try {
        Remove-ReviewInputSecurely -Path $Path -Boundary $Boundary
        return @()
    }
    catch {
        return @("Committed review authority is intact, but the consumed input could not be removed: $($_.Exception.Message)")
    }
}

# --------------------------------------------------------------------------------------------------
# Exclusive run lock. The default timeout is the vocabulary's 5 seconds; a test may lower it through
# the module scope to prove the timeout without stalling the suite. The CLI never lowers it.
#
# The lock file is stable: it is created once and never unlinked. Deleting it on release is what
# breaks mutual exclusion — a second process that opens the path after the delete holds a handle to a
# different inode than a third process that opened it before, and both believe they hold the lock.
# --------------------------------------------------------------------------------------------------
function Get-ReviewLockTimeoutSeconds {
    if ($null -ne $script:LockTimeoutOverrideSeconds) { return [double]$script:LockTimeoutOverrideSeconds }
    return [double](Get-ReviewLimits).lockTimeoutSeconds
}

function Enter-ReviewLock {
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [string]$LockName = $script:LockName
    )

    $path = Join-Path $RunDir $LockName
    $timeout = Get-ReviewLockTimeoutSeconds
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try {
            return [System.IO.File]::Open($path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        }
        catch [System.IO.IOException] {
            if ($stopwatch.Elapsed.TotalSeconds -ge $timeout) {
                throw [System.TimeoutException]::new("review-run publication lock not acquired within $timeout seconds")
            }
            Start-Sleep -Milliseconds 50
        }
    }
}

function Exit-ReviewLock {
    param([System.IO.FileStream]$Lock)
    if ($Lock) { $Lock.Dispose() }
}

# --------------------------------------------------------------------------------------------------
# State inspection: new -> frozen -> published, with admission as a terminal side state. Engine-owned
# markers decide accepted state; a content-addressed plan generation without its marker is only an
# interrupted Freeze candidate.
# --------------------------------------------------------------------------------------------------
function Get-ReviewFrozenPlanFile {
    <#
    .SYNOPSIS
        The content-addressed frozen plan files present in a run directory (normally exactly one).
    #>
    param([Parameter(Mandatory)][string]$RunDir)

    $pattern = Get-ReviewContentNamePattern -Role 'plan'
    return @(Get-ChildItem -LiteralPath $RunDir -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -cmatch $pattern } |
        Sort-Object -Property Name)
}

function Get-ReviewFrozenMarkerDigest {
    <#
    .SYNOPSIS
        Reads the independent marker that commits a frozen plan digest.
    #>
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [switch]$AllowMissing
    )

    $path = Join-Path $RunDir $script:FrozenName
    $item = Get-ReviewPathItem -Path $path
    if (-not $item) {
        if ($AllowMissing) { return $null }
        throw 'the frozen-state marker is missing'
    }
    if ($item -isnot [System.IO.FileInfo] -or
        (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint)) {
        throw 'the frozen-state marker is not a regular file'
    }

    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = $script:Utf8NoBom.GetString($bytes)
    if ($text -cnotmatch '^sha256:[0-9a-f]{64}\n$') {
        throw 'the frozen-state marker is malformed'
    }
    return $text.TrimEnd("`n")
}

function Write-ReviewFrozenMarker {
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$PlanDigest
    )

    $bytes = $script:Utf8NoBom.GetBytes($PlanDigest + "`n")
    Write-ReviewBytesAtomic -Path (Join-Path $RunDir $script:FrozenName) -Bytes $bytes
}

function Read-ReviewFrozenPlan {
    <#
    .SYNOPSIS
        The frozen plan of a run, verified against its own content address. Throws a bounded, quotable
        message when the plan is missing, duplicated, tampered with or unparsable.
    .DESCRIPTION
        The frozen plan is the authority `Publish` binds every result to, so it is verified before it
        is trusted: exactly one `review-plan.<sha256>.json` must exist and its bytes must hash to the
        digest in its own name. A mutable fixed-name file could be edited in place and would still
        look like a plan; a content-addressed one cannot be edited without either breaking its name or
        creating a second file, and both are detected here.
    #>
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [switch]$AllowMissingMarker
    )

    $files = @(Get-ReviewFrozenPlanFile -RunDir $RunDir)
    if ($files.Count -eq 0) { throw 'no frozen plan exists for this run id' }
    if ($files.Count -gt 1) { throw 'the run directory holds more than one frozen plan file' }

    $bytes = [System.IO.File]::ReadAllBytes($files[0].FullName)
    $digest = Get-ReviewDigest -Bytes $bytes
    if ($digest -ne (Get-ReviewContentNameDigest -Role 'plan' -Name $files[0].Name)) {
        throw 'the frozen plan bytes do not match the digest in its own file name'
    }
    $markerDigest = Get-ReviewFrozenMarkerDigest -RunDir $RunDir -AllowMissing:$AllowMissingMarker
    if ($markerDigest -and -not [string]::Equals($markerDigest, $digest, [System.StringComparison]::Ordinal)) {
        throw 'the frozen plan digest does not match the frozen-state marker'
    }
    try { $plan = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -AsHashtable -Depth 40 }
    catch { throw 'the frozen plan is not parsable JSON' }
    if ($null -eq $plan -or $plan -isnot [System.Collections.IDictionary]) {
        throw 'the frozen plan is not a JSON object'
    }

    return [pscustomobject]@{
        Path   = $files[0].FullName
        Name   = $files[0].Name
        Bytes  = $bytes
        Digest = $digest
        Plan   = $plan
    }
}

function Get-ReviewRunState {
    param([Parameter(Mandatory)][string]$RunDir)

    if (-not (Test-Path -LiteralPath $RunDir -PathType Container)) { return 'new' }
    if (Test-Path -LiteralPath (Join-Path $RunDir $script:ManifestName) -PathType Leaf) { return 'published' }
    if (Test-Path -LiteralPath (Join-Path $RunDir $script:AdmissionName) -PathType Leaf) {
        [void](Read-ReviewAdmissionMarker -RunDir $RunDir)
        return 'admission'
    }
    if (Test-Path -LiteralPath (Join-Path $RunDir $script:FrozenName) -PathType Leaf) { return 'frozen' }
    return 'new'
}

function Write-ReviewAdmissionMarker {
    <#
    .SYNOPSIS
        Persists the fact that a run id reached a terminal byte-budget admission (D21), so a later
        invocation on the same UUID cannot publish a quietly reduced set instead.
    .DESCRIPTION
        The marker is small, deterministic and derived only from the contract: the run id, the mode
        that decided, and the machine-readable reason codes. No reviewer text, no byte counts taken
        from rejected content and no diagnostics are stored, because the marker outlives the input
        that was rejected — including one rejected for carrying a credential shape.
    #>
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][ValidateSet('freeze', 'publish')][string]$Mode,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Reason,
        [string]$PlanDigest,
        [string]$ScopeDigest,
        [byte[]]$SourceBytes,
        [int]$FindingCount
    )

    $marker = [ordered]@{
        maxPartitions = 16
        maxRestarts   = 1
        mode          = $Mode
        reasons       = @(Sort-ReviewOrdinal -Value @($Reason))
        restartable   = ($null -ne $SourceBytes -and $SourceBytes.Length -gt 0)
        runId         = $RunId
        schema        = $script:AdmissionDiscriminator
        state         = 'admission'
    }
    $sourcePath = $null
    try {
        if ($marker.restartable) {
            $sourceName = Get-ReviewContentName -Role admissionSource -Bytes $SourceBytes
            $sourceDigest = Get-ReviewDigest -Bytes $SourceBytes
            $sourcePath = Join-Path $RunDir $sourceName
            Write-ReviewBytesAtomic -Path $sourcePath -Bytes $SourceBytes
            $marker['findingCount'] = $FindingCount
            $marker['parentRunDigest'] = $sourceDigest
            $marker['planDigest'] = $PlanDigest
            $marker['scopeDigest'] = $ScopeDigest
            $marker['source'] = [ordered]@{ name = $sourceName; digest = $sourceDigest; bytes = $SourceBytes.Length }
        }
        $json = (ConvertTo-Json -InputObject $marker -Depth 8 -Compress) + "`n"
        if (-not (Test-ReviewSchema -Json $json -SchemaName 'review-admission.schema.json')) {
            throw 'the generated admission marker fails its schema'
        }
        Write-ReviewBytesAtomic -Path (Join-Path $RunDir $script:AdmissionName) -Bytes $script:Utf8NoBom.GetBytes($json)
    }
    catch {
        if ($sourcePath -and [System.IO.File]::Exists($sourcePath)) { [System.IO.File]::Delete($sourcePath) }
        throw
    }
}

function Read-ReviewAdmissionMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [string]$Boundary
    )

    $runDirFull = [System.IO.Path]::GetFullPath($RunDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $boundaryFull = $(if ([string]::IsNullOrWhiteSpace($Boundary)) { Get-ReviewRepoRoot -StartPath $runDirFull } else { [System.IO.Path]::GetFullPath($Boundary) })
    Assert-ReviewPathSafe -Path $runDirFull -Boundary $boundaryFull
    $path = Join-Path $runDirFull $script:AdmissionName
    $item = Get-ReviewPathItem -Path $path
    if (-not $item) { throw 'the admission marker is missing' }
    if ($item -isnot [System.IO.FileInfo] -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'the admission marker is not a regular file'
    }
    if ($item.Length -gt 8192) { throw 'the admission marker exceeds its 8 KiB bound' }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    Assert-ReviewArtifactContent -Role admissionMarker -Bytes $bytes
    $json = $script:Utf8NoBom.GetString($bytes)
    if (-not (Test-ReviewSchema -Json $json -SchemaName 'review-admission.schema.json')) { throw 'the admission marker fails its schema' }
    $marker = $json | ConvertFrom-Json -AsHashtable -Depth 20
    if (-not [string]::Equals([string]$marker['runId'], (Split-Path -Leaf $runDirFull), [System.StringComparison]::Ordinal)) {
        throw 'the admission marker runId is not this run directory'
    }

    $sourcePath = $null
    $sourceBytes = $null
    if ([bool]$marker['restartable']) {
        $source = $marker['source']
        $name = [string]$source['name']
        $claimed = Get-ReviewContentNameDigest -Role admissionSource -Name $name
        if (-not $claimed -or $claimed -ne [string]$source['digest']) { throw 'the admission source name and digest disagree' }
        $sourcePath = Join-Path $runDirFull $name
        Assert-ReviewPathSafe -Path $sourcePath -Boundary $boundaryFull
        $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
        if ($sourceBytes.Length -ne [int]$source['bytes'] -or (Get-ReviewDigest -Bytes $sourceBytes) -ne [string]$source['digest']) {
            throw 'the admission source bytes do not match the marker'
        }
        Assert-ReviewArtifactContent -Role admissionSource -Bytes $sourceBytes
    }

    $sourceDocument = if ($null -ne $sourceBytes) { $script:Utf8NoBom.GetString($sourceBytes) | ConvertFrom-Json -AsHashtable -Depth 40 } else { $null }
    return [pscustomobject]@{ Marker = $marker; Path = $path; SourcePath = $sourcePath; SourceBytes = $sourceBytes; SourceDocument = $sourceDocument; Boundary = $boundaryFull }
}

function Set-ReviewRemoveTreeProvider { param([scriptblock]$Provider) $script:RemoveTreeProvider = $Provider }
function Clear-ReviewRemoveTreeProvider { $script:RemoveTreeProvider = $null }
function Remove-ReviewTree {
    param([Parameter(Mandatory)][string]$Path)
    if ($null -ne $script:RemoveTreeProvider) { & $script:RemoveTreeProvider $Path; return }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
}

function Remove-ReviewOwnStaging {
    <#
    .SYNOPSIS
        Removes the generation files this attempt wrote that no committed manifest names.
    .DESCRIPTION
        Cleanup is scoped to paths this call created: a directory-wide sweep would delete a concurrent
        process's staging, and deleting a file the committed manifest references would break the very
        authority a fault is supposed to preserve.
    #>
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Written
    )

    $protected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $manifestPath = Join-Path $RunDir $script:ManifestName
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        [void]$protected.Add($script:ManifestName)
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20
            foreach ($role in @($manifest['files'].Keys)) { [void]$protected.Add([string]$manifest['files'][$role]['name']) }
        }
        catch {
            # An unreadable manifest is not a licence to delete: treat everything as protected.
            return
        }
    }

    foreach ($path in @($Written)) {
        if ([string]::IsNullOrEmpty($path)) { continue }
        if ($protected.Contains([System.IO.Path]::GetFileName($path))) { continue }
        if ([System.IO.File]::Exists($path)) { [System.IO.File]::Delete($path) }
    }
}

# --------------------------------------------------------------------------------------------------
# Shared mode helpers: capability, input admission and the terminal admission decision.
# --------------------------------------------------------------------------------------------------
function Test-ReviewModeCapability {
    <#
    .SYNOPSIS
        The bounded exit-2 result a mode returns on a host without native schema-file validation, or
        `$null` when the host is capable.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('freeze', 'publish')][string]$Mode,
        [string]$RunId
    )

    $capability = Test-ReviewHostSchemaCapability
    if ($capability.Capable) { return $null }
    return New-ReviewResult -Mode $Mode -ExitCode 2 -State invalid `
        -Message 'This host cannot validate review documents: native Test-Json -SchemaFile is unavailable.' `
        -RunId $RunId -Diagnostic @($capability.Reasons)
}

function New-ReviewAdmissionTerminal {
    <#
    .SYNOPSIS
        The terminal admission decision, taken *and* persisted atomically with the run's state under
        the run lock.
    .DESCRIPTION
        D6/D21: admission is a property of the input, so a decision that is actually recorded is exit
        `3` — turning it into a retryable `4` would invite exactly the same-UUID retry the contract
        forbids. But the marker is a state transition like any other, so it is written only from the
        mode's legal prior state, decided under the same lock every other transition is decided under:
        `Freeze` may admit only a `new` run, `Publish` only a `frozen` one.

        The three other outcomes are what an unconditional write got wrong:
          * an already-`admission` run repeats its own terminal answer and rewrites nothing;
          * any other state — a `published` run above all — is exit `2` with **no marker written**, so
            an oversized or over-budget retry cannot stamp `admission` onto committed authority and
            make a verified publication unreadable;
          * a lock or a marker write that fails is exit `4` `failed`, not an exit `3` that claims a
            terminal decision no later invocation could see.

        The caller destroys the rejected input before asking for this decision, so nothing here is
        recoverable from disk; that is stated plainly in the diagnostics of the paths that record
        nothing.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('freeze', 'publish')][string]$Mode,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$Boundary,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Reason,
        [string[]]$Diagnostic = @(),
        [string]$PlanDigest,
        [string]$ScopeDigest,
        [byte[]]$SourceBytes,
        [int]$FindingCount
    )

    $diagnostics = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @($Diagnostic)) { $diagnostics.Add([string]$item) }
    $legalPriorState = $(if ($Mode -eq 'freeze') { 'new' } else { 'frozen' })

    $lock = $null
    try {
        try { $lock = Enter-ReviewLock -RunDir $RunDir }
        catch {
            $diagnostics.Add("the admission marker could not be persisted: $($_.Exception.Message)")
            $diagnostics.Add('the rejected input was already destroyed, so nothing was accepted and nothing was recorded')
            return New-ReviewResult -Mode $Mode -ExitCode 4 -State failed `
                -Message 'Could not acquire the run lock to record the admission decision; nothing recorded.' `
                -RunId $RunId -Diagnostic @($diagnostics)
        }

        $state = Get-ReviewRunState -RunDir $RunDir
        if ($state -eq 'admission') {
            return New-ReviewResult -Mode $Mode -ExitCode 3 -State admission `
                -Message 'This run id already reached a terminal admission decision; start a new run id.' `
                -RunId $RunId -Diagnostic @($diagnostics)
        }

        if ($state -ne $legalPriorState) {
            $diagnostics.Add("the run id is '$state', not '$legalPriorState', so no admission marker was written")
            $diagnostics.Add('the rejected input was already destroyed; the committed state under this run id is unchanged')
            return New-ReviewResult -Mode $Mode -ExitCode 2 -State invalid `
                -Message "This run id is already '$state'; an over-budget input cannot change its committed state." `
                -RunId $RunId -Diagnostic @($diagnostics)
        }

        try {
            Assert-ReviewPathSafe -Path $RunDir -Boundary $Boundary
            Write-ReviewAdmissionMarker -RunDir $RunDir -Mode $Mode -RunId $RunId -Reason $Reason `
                -PlanDigest $PlanDigest -ScopeDigest $ScopeDigest -SourceBytes $SourceBytes -FindingCount $FindingCount
        }
        catch {
            $diagnostics.Add("the admission marker could not be persisted: $($_.Exception.Message)")
            $diagnostics.Add('the rejected input was already destroyed, so nothing was accepted and nothing was recorded')
            return New-ReviewResult -Mode $Mode -ExitCode 4 -State failed `
                -Message 'The admission decision could not be recorded; nothing accepted and nothing published.' `
                -RunId $RunId -Diagnostic @($diagnostics)
        }
    }
    finally { Exit-ReviewLock -Lock $lock }

    return New-ReviewResult -Mode $Mode -ExitCode 3 -State admission -Message $Message -RunId $RunId -Diagnostic @($diagnostics)
}

function Read-ReviewInputText {
    <#
    .SYNOPSIS
        The decoded text of an input file, read as bytes so the decoding never depends on host
        settings, with any byte-order mark removed.
    .DESCRIPTION
        The leaf is re-confined immediately before the read (RISK-6), so a fixed input name swapped
        for a symlink is refused rather than followed into an arbitrary file whose contents would then
        be parsed, validated and — on rejection — quoted back in diagnostics.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Boundary
    )

    Assert-ReviewInputLeafSafe -Path $Path -Boundary $Boundary
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}

function Remove-ReviewPendingInput {
    <#
    .SYNOPSIS
        Destroys the caller's fixed input file for a mode, if one is in place.
    .DESCRIPTION
        Used by the terminal decisions a mode reaches *before* it reads the input at all. The result
        input is untrusted reviewer text that has not been scanned for credential shapes yet, so a
        terminal exit must not leave it on disk to be found later; a retryable exit `4` deliberately
        does, because the caller is expected to run the same input again.

        This is the earliest destruction in either mode — it runs before the input is read, let alone
        scanned — so it is also the first place a linked leaf could have been followed. It goes through
        the same confined lookup every other caller uses, and a link is refused rather than shredded
        through.
    #>
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$InputName,
        [Parameter(Mandatory)][string]$Boundary
    )

    $pending = Get-ReviewInputPath -RunDir $RunDir -InputName $InputName -Boundary $Boundary
    if ($pending) { Remove-ReviewInputSecurely -Path $pending -Boundary $Boundary }
}

# --------------------------------------------------------------------------------------------------
# Freeze.
# --------------------------------------------------------------------------------------------------
function Invoke-ReviewFreeze {
    <#
    .SYNOPSIS
        Commits the planned task set for a run id, before any reviewer is dispatched.
    .DESCRIPTION
        Every path returns one of the contract's exits (0/2/3/4) — an unexpected failure is caught here
        and reported as exit `4` rather than escaping as an unhandled error with no terminal status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    try { return Invoke-ReviewFreezeCore -RunId $RunId -PlanDir $PlanDir -RepoRoot $RepoRoot }
    catch {
        return New-ReviewResult -Mode freeze -ExitCode 4 -State failed `
            -Message "Freeze failed unexpectedly: $($_.Exception.Message)" -RunId $RunId
    }
}

function Invoke-ReviewFreezeCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    $incapable = Test-ReviewModeCapability -Mode freeze -RunId $RunId
    if ($incapable) { return $incapable }

    $limits = Get-ReviewLimits
    if (-not (Test-ReviewRunId -RunId $RunId)) {
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message 'Run id must be a lowercase UUID.' -RunId $RunId
    }

    $repoFull = [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $RepoRoot))
    try {
        $store = Resolve-ReviewStoreRoot -PlanDir $PlanDir -RepoRoot $RepoRoot
        $runDir = Join-Path $store $RunId
    }
    catch { return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message "Cannot resolve run root: $($_.Exception.Message)" -RunId $RunId }

    if (-not (Test-Path -LiteralPath $runDir -PathType Container)) {
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
            -Message 'Run root is not initialized. Call the read-only Prepare operation, then create only its returned runRoot before authoring input.' -RunId $RunId
    }
    Assert-ReviewPathSafe -Path $runDir -Boundary $repoFull

    $inputPath = Get-ReviewInputPath -RunDir $runDir -InputName $script:PlanInputName -Boundary $repoFull
    if (-not $inputPath) {
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
            -Message "No plan input: the caller renames its handshake file onto $($script:PlanInputName) before Freeze." -RunId $RunId
    }

    # Byte admission first, on the bytes actually on disk: an oversized envelope must never be parsed,
    # and it is terminal (exit 3), not a retryable failure.
    $inputBytes = (Get-Item -LiteralPath $inputPath).Length
    if ($inputBytes -gt [int]$limits.maxEnvelopeBytes) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewAdmissionTerminal -Mode freeze -RunId $RunId -RunDir $runDir -Boundary $repoFull `
            -Message 'Plan input exceeds the maximum envelope size; nothing frozen.' -Reason @('input-bytes-over-limit') `
            -Diagnostic @("plan input is $inputBytes bytes, over the $($limits.maxEnvelopeBytes) budget")
    }

    $rawText = Read-ReviewInputText -Path $inputPath -Boundary $repoFull
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message 'Plan input is empty.' -RunId $RunId
    }

    try { $plan = $rawText | ConvertFrom-Json -AsHashtable -Depth 40 }
    catch {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message 'Plan input is not valid JSON.' -RunId $RunId
    }

    # Scan caller text before any value can reach Git or another diagnostic-producing subsystem.
    $secrets = @(Find-ReviewSecret -Run $plan)
    if ($secrets.Count -gt 0) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
            -Message 'Plan input carries a high-confidence credential shape; rejected and destroyed before acceptance.' `
            -RunId $RunId -Diagnostic @($secrets | ForEach-Object { "$($_.Type) at $($_.Location)" })
    }

    # The digest is engine-owned: callers author the source descriptor and ordered path records, then
    # Freeze computes the canonical digest that the frozen schema and every result must carry.
    $scopeAuthority = Get-ReviewValue -Node $plan -Name 'scopeAuthority'
    try { Resolve-ReviewBranchScopeAuthority -ScopeAuthority $scopeAuthority -RepoRoot $repoFull }
    catch {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message 'Branch scope authority could not be derived from Git.' -RunId $RunId -Diagnostic @($_.Exception.Message)
    }
    if ($scopeAuthority -is [System.Collections.IDictionary] -and -not $scopeAuthority.Contains('digest')) {
        $scopeAuthority['digest'] = Get-ReviewScopeDigest -ScopeAuthority $scopeAuthority
    }
    $structuralText = ConvertTo-Json -InputObject $plan -Depth 40 -Compress
    if (-not (Test-ReviewSchema -Json $structuralText -SchemaName 'review-plan.schema.json')) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message 'Plan input fails the review-plan schema.' -RunId $RunId
    }

    # Canonicalization can collapse values that were distinct in the caller's representation (for
    # example composed and decomposed NFC strings). Validate the exact node that will be persisted,
    # never only the pre-canonical input.
    $canonicalJson = ConvertTo-ReviewCanonicalJson -Node $plan
    if (-not (Test-ReviewSchema -Json $canonicalJson -SchemaName 'review-plan.schema.json')) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message 'Canonical plan fails the review-plan schema.' -RunId $RunId
    }
    $plan = $canonicalJson | ConvertFrom-Json -AsHashtable -Depth 40

    if ([string](Get-ReviewValue -Node $plan -Name 'runId') -ne $RunId) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message 'Plan runId does not match the requested run id.' -RunId $RunId
    }

    $failures = @(
        @(Test-ReviewPlanSemantic -Plan $plan)
        @(Test-ReviewRestartAuthority -Plan $plan -RunDir $runDir -Boundary $repoFull)
    )
    if ($failures.Count -gt 0) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid -Message 'Plan input fails semantic validation.' -RunId $RunId -Diagnostic $failures
    }

    $canonicalBytes = $script:Utf8NoBom.GetBytes($canonicalJson)
    if ($canonicalBytes.Length -gt [int]$limits.maxEnvelopeBytes) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewAdmissionTerminal -Mode freeze -RunId $RunId -RunDir $runDir -Boundary $repoFull `
            -Message 'Canonical plan exceeds the maximum envelope size; nothing frozen.' -Reason @('canonical-bytes-over-limit') `
            -Diagnostic @("canonical plan is $($canonicalBytes.Length) bytes, over the $($limits.maxEnvelopeBytes) budget")
    }
    $canonicalDigest = Get-ReviewDigest -Bytes $canonicalBytes

    # Immutable state is decided and written under the same lock a publication takes, so two Freeze
    # calls with different plans cannot both believe they won.
    $lock = $null
    try {
        try { $lock = Enter-ReviewLock -RunDir $runDir }
        catch {
            return New-ReviewResult -Mode freeze -ExitCode 4 -State failed -Message 'Could not acquire the run lock within its timeout.' -RunId $RunId
        }

        Assert-ReviewPathSafe -Path $runDir -Boundary $repoFull

        $state = Get-ReviewRunState -RunDir $runDir
        if ($state -eq 'admission') {
            Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
            return New-ReviewResult -Mode freeze -ExitCode 3 -State admission `
                -Message 'This run id already reached a terminal admission decision; start a new run id.' -RunId $RunId
        }

        # A published run id is committed authority. Freeze must decide it explicitly rather than infer
        # "no frozen plan file, therefore new": a published run whose plan generation was removed or
        # renamed presents exactly that way, and writing a fresh plan into it would manufacture a
        # replacement plan under a manifest that still names the old one. The committed manifest is
        # verified in full by the same reader a consumer uses, and no generation is written on any
        # branch below.
        if ($state -eq 'published') {
            try { $published = Read-ReviewManifest -RunDir $runDir -Boundary $repoFull }
            catch {
                Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
                return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
                    -Message "This run id is published and its committed manifest does not verify; refusing to write a replacement plan: $($_.Exception.Message)" -RunId $RunId
            }
            if ($published.PlanDigest -ne $canonicalDigest) {
                Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
                return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
                    -Message 'A different plan is already frozen and published under this run id; freeze is immutable.' -RunId $RunId
            }
            $cleanup = @(Remove-ReviewCommittedInput -Path $inputPath -Boundary $repoFull)
            return New-ReviewResult -Mode freeze -ExitCode 0 -State clean `
                -Message 'Plan already frozen under a published run (idempotent).' -RunId $RunId -Diagnostic $cleanup
        }

        if ($state -eq 'frozen') {
            try { $existing = Read-ReviewFrozenPlan -RunDir $runDir }
            catch {
                Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
                return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
                    -Message "The frozen plan under this run id is not trustworthy: $($_.Exception.Message)" -RunId $RunId
            }
            if ($existing.Digest -ne $canonicalDigest) {
                Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
                return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
                    -Message 'A different plan is already frozen under this run id; freeze is immutable.' -RunId $RunId
            }
            # Idempotent replay of an identical plan.
            $cleanup = @(Remove-ReviewCommittedInput -Path $inputPath -Boundary $repoFull)
            return New-ReviewResult -Mode freeze -ExitCode 0 -State clean -Message 'Plan already frozen (idempotent).' -RunId $RunId -Diagnostic $cleanup
        }

        # A generation without its marker is an interrupted Freeze. It can be completed only by an
        # identical replay; a different plan cannot adopt the UUID.
        if (@(Get-ReviewFrozenPlanFile -RunDir $runDir).Count -gt 0) {
            try { $existing = Read-ReviewFrozenPlan -RunDir $runDir -AllowMissingMarker }
            catch {
                Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
                return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
                    -Message "The uncommitted plan generation under this run id is not trustworthy: $($_.Exception.Message)" -RunId $RunId
            }
            if (-not [string]::Equals($existing.Digest, $canonicalDigest, [System.StringComparison]::Ordinal)) {
                Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
                return New-ReviewResult -Mode freeze -ExitCode 2 -State invalid `
                    -Message 'A different plan generation already exists under this run id; freeze is immutable.' -RunId $RunId
            }
            Write-ReviewFrozenMarker -RunDir $runDir -PlanDigest $canonicalDigest
            $cleanup = @(Remove-ReviewCommittedInput -Path $inputPath -Boundary $repoFull)
            return New-ReviewResult -Mode freeze -ExitCode 0 -State clean -Message 'Plan freeze completed (idempotent).' -RunId $RunId -Diagnostic $cleanup
        }

        Write-ReviewBytesAtomic -Path (Join-Path $runDir (Get-ReviewContentName -Role 'plan' -Bytes $canonicalBytes)) -Bytes $canonicalBytes
        Write-ReviewFrozenMarker -RunDir $runDir -PlanDigest $canonicalDigest
    }
    finally { Exit-ReviewLock -Lock $lock }

    $cleanup = @(Remove-ReviewCommittedInput -Path $inputPath -Boundary $repoFull)
    return New-ReviewResult -Mode freeze -ExitCode 0 -State clean -Message 'Plan frozen.' -RunId $RunId -Diagnostic $cleanup
}

# --------------------------------------------------------------------------------------------------
# Publish.
# --------------------------------------------------------------------------------------------------
function Invoke-ReviewPublish {
    <#
    .SYNOPSIS
        Publishes a result against the frozen plan of a run id.
    .DESCRIPTION
        Every path returns one of the contract's exits (0/2/3/4/5); an unexpected failure is caught
        here and reported as exit `4` rather than escaping with no terminal status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    try { return Invoke-ReviewPublishCore -RunId $RunId -PlanDir $PlanDir -RepoRoot $RepoRoot }
    catch {
        return New-ReviewResult -Mode publish -ExitCode 4 -State failed `
            -Message "Publication failed unexpectedly: $($_.Exception.Message)" -RunId $RunId
    }
}

function Invoke-ReviewPublishCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    $incapable = Test-ReviewModeCapability -Mode publish -RunId $RunId
    if ($incapable) { return $incapable }

    $limits = Get-ReviewLimits
    if (-not (Test-ReviewRunId -RunId $RunId)) {
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'Run id must be a lowercase UUID.' -RunId $RunId
    }

    $repoFull = [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $RepoRoot))
    try {
        $store = Resolve-ReviewStoreRoot -PlanDir $PlanDir -RepoRoot $RepoRoot
        $runDir = Join-Path $store $RunId
    }
    catch { return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message "Cannot resolve run root: $($_.Exception.Message)" -RunId $RunId }

    if (-not (Test-Path -LiteralPath $runDir -PathType Container)) {
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'Publish before Freeze: no frozen plan exists for this run id.' -RunId $RunId
    }
    Assert-ReviewPathSafe -Path $runDir -Boundary $repoFull

    # An admission decision is terminal for the UUID (D21): a later Publish on it can only repeat the
    # same answer, never publish a quietly reduced set. It is terminal, so the untrusted result input
    # the caller staged is destroyed here rather than left on disk unscanned.
    $initialState = Get-ReviewRunState -RunDir $runDir
    if ($initialState -eq 'admission') {
        Remove-ReviewPendingInput -RunDir $runDir -InputName $script:ResultInputName -Boundary $repoFull
        return New-ReviewResult -Mode publish -ExitCode 3 -State admission `
            -Message 'This run id already reached a terminal admission decision; start a new run id.' -RunId $RunId
    }

    if (@(Get-ReviewFrozenPlanFile -RunDir $runDir).Count -eq 0) {
        Remove-ReviewPendingInput -RunDir $runDir -InputName $script:ResultInputName -Boundary $repoFull
        $message = if ($initialState -in @('frozen', 'published')) {
            'The committed frozen state has no plan generation; refusing to publish against untrustworthy state.'
        }
        else {
            'Publish before Freeze: no frozen plan exists for this run id.'
        }
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message $message -RunId $RunId
    }
    try { $frozen = Read-ReviewFrozenPlan -RunDir $runDir }
    catch {
        Remove-ReviewPendingInput -RunDir $runDir -InputName $script:ResultInputName -Boundary $repoFull
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid `
            -Message "The frozen plan under this run id is not trustworthy: $($_.Exception.Message)" -RunId $RunId
    }
    $planBytes = $frozen.Bytes
    $frozenPlanDigest = $frozen.Digest
    $frozenPlan = $frozen.Plan

    $inputPath = Get-ReviewInputPath -RunDir $runDir -InputName $script:ResultInputName -Boundary $repoFull
    if (-not $inputPath) {
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid `
            -Message "No result input: the caller renames its handshake file onto $($script:ResultInputName) before Publish." -RunId $RunId
    }

    # Byte admission on the bytes actually on disk, before anything parses them.
    $inputByteCount = (Get-Item -LiteralPath $inputPath).Length
    if ($inputByteCount -gt [int]$limits.maxEnvelopeBytes) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewAdmissionTerminal -Mode publish -RunId $RunId -RunDir $runDir -Boundary $repoFull `
            -Message 'Result input exceeds the maximum envelope size; nothing published.' -Reason @('input-bytes-over-limit') `
            -Diagnostic @("result input is $inputByteCount bytes, over the $($limits.maxEnvelopeBytes) budget")
    }

    $rawText = Read-ReviewInputText -Path $inputPath -Boundary $repoFull
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'Result input is empty.' -RunId $RunId
    }

    try { $run = $rawText | ConvertFrom-Json -AsHashtable -Depth 40 }
    catch {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'Result input is not valid JSON.' -RunId $RunId
    }

    # Error precedence: input-byte admission -> parse -> canonical schema -> secret -> semantic/state
    # -> render admission -> publication. Validate the representation that will be persisted: NFC/LF
    # normalization can collapse identities that were distinct in the raw JSON, while a second full
    # schema pass over the raw 2 MiB envelope adds no authority and doubles the dominant validation cost.
    $canonicalJson = ConvertTo-ReviewCanonicalJson -Node $run
    if (-not (Test-ReviewSchema -Json $canonicalJson -SchemaName 'review-run.schema.json')) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'Canonical result fails the review-run schema.' -RunId $RunId
    }
    $run = $canonicalJson | ConvertFrom-Json -AsHashtable -Depth 40

    if ([string](Get-ReviewValue -Node $run -Name 'runId') -ne $RunId) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'Result runId does not match the requested run id.' -RunId $RunId
    }

    # Secrets are rejected before any lossless artifact is written, and the input is destroyed at once.
    $secrets = @(Find-ReviewSecret -Run $run)
    if ($secrets.Count -gt 0) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        $redacted = @($secrets | ForEach-Object { "$($_.Type) at $($_.Location)" })
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'Result input carries a high-confidence credential shape; rejected and destroyed before acceptance.' -RunId $RunId -Diagnostic $redacted
    }

    $failures = @(Test-ReviewRunSemantic -Run $run -FrozenPlan $frozenPlan -FrozenPlanDigest $frozenPlanDigest)
    if ($failures.Count -gt 0) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'Result input fails semantic validation.' -RunId $RunId -Diagnostic $failures
    }

    # Canonical authority and both views are rendered before the manifest can change (D6).
    $canonicalBytes = $script:Utf8NoBom.GetBytes($canonicalJson)
    if ($canonicalBytes.Length -gt [int]$limits.maxEnvelopeBytes) {
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewAdmissionTerminal -Mode publish -RunId $RunId -RunDir $runDir -Boundary $repoFull `
            -Message 'Canonical result exceeds the maximum envelope size; nothing published.' -Reason @('canonical-bytes-over-limit') `
            -Diagnostic @("canonical result is $($canonicalBytes.Length) bytes, over the $($limits.maxEnvelopeBytes) budget")
    }
    $canonicalRun = $run
    $projection = ConvertTo-ReviewProjection -Run $canonicalRun
    $summaryText = Get-ReviewRunSummaryView -Projection $projection
    $fullText = Get-ReviewRunFullView -Projection $projection
    $summaryBytes = $script:Utf8NoBom.GetBytes($summaryText)
    $fullBytes = $script:Utf8NoBom.GetBytes($fullText)

    $admissionFailures = [System.Collections.Generic.List[string]]::new()
    $admissionReasons = [System.Collections.Generic.List[string]]::new()
    if ($summaryBytes.Length -gt [int]$limits.maxSummaryBytes) {
        $admissionFailures.Add("summary is $($summaryBytes.Length) bytes, over the $($limits.maxSummaryBytes) budget")
        $admissionReasons.Add('summary-over-budget')
    }
    if ($fullBytes.Length -gt [int]$limits.maxFullBytes) {
        $admissionFailures.Add("full view is $($fullBytes.Length) bytes, over the $($limits.maxFullBytes) budget")
        $admissionReasons.Add('full-over-budget')
    }
    if ($admissionFailures.Count -gt 0) {
        # Admission (exit 3) is terminal and never mutates the accepted set or the manifest.
        Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
        return New-ReviewAdmissionTerminal -Mode publish -RunId $RunId -RunDir $runDir -Boundary $repoFull `
            -Message 'Rendered views exceed their byte budget; nothing published.' -Reason @($admissionReasons) `
            -Diagnostic @($admissionFailures) -PlanDigest $frozenPlanDigest `
            -ScopeDigest ([string](Get-ReviewValue -Node (Get-ReviewValue -Node $canonicalRun -Name 'scopeAuthority') -Name 'digest')) `
            -SourceBytes $canonicalBytes -FindingCount @((Get-ReviewValue -Node $canonicalRun -Name 'findings')).Count
    }

    $runDigest = Get-ReviewDigest -Bytes $canonicalBytes
    $runState = [string]$projection.State

    # Everything that decides state — admission, idempotent replay, changed reuse and the publication
    # itself — happens under one exclusive lock, so two concurrent Publish calls with different results
    # cannot both pass their checks and then both commit.
    $lock = $null
    $written = [System.Collections.Generic.List[string]]::new()
    try {
        try { $lock = Enter-ReviewLock -RunDir $runDir }
        catch {
            return New-ReviewResult -Mode publish -ExitCode 4 -State failed -Message 'Could not acquire the publication lock within its timeout.' -RunId $RunId
        }

        Assert-ReviewPathSafe -Path $runDir -Boundary $repoFull

        $state = Get-ReviewRunState -RunDir $runDir
        if ($state -eq 'admission') {
            Remove-ReviewInputSecurely -Path $inputPath -Boundary $repoFull
            return New-ReviewResult -Mode publish -ExitCode 3 -State admission `
                -Message 'This run id already reached a terminal admission decision; start a new run id.' -RunId $RunId
        }

        if ($state -eq 'published') {
            # The committed manifest is verified in full before it is allowed to answer for this run:
            # schema, confined content-addressed names, byte counts, every digest, the run-directory
            # identity and the canonical envelope's own run/plan binding. Reading the file directly and
            # comparing `runDigest` alone — the earlier behavior — let a tampered or foreign manifest
            # turn a replay into "already published" over an authority nothing had verified, and it
            # trusted a field beside the files instead of the files themselves.
            try { $prior = Read-ReviewManifest -RunDir $runDir -Boundary $repoFull }
            catch {
                return New-ReviewResult -Mode publish -ExitCode 2 -State invalid `
                    -Message "The published manifest under this run id is unreadable; refusing to overwrite committed authority: $($_.Exception.Message)" -RunId $RunId
            }
            if ($prior.RunDigest -eq $runDigest) {
                $cleanup = @(Remove-ReviewCommittedInput -Path $inputPath -Boundary $repoFull)
                $exit = $(if ($runState -eq 'clean') { 0 } else { 5 })
                return New-ReviewResult -Mode publish -ExitCode $exit -State $runState -Message 'Run already published (idempotent).' -RunId $RunId -Summary $summaryText -Diagnostic $cleanup
            }
            $cleanup = @(Remove-ReviewCommittedInput -Path $inputPath -Boundary $repoFull)
            return New-ReviewResult -Mode publish -ExitCode 2 -State invalid -Message 'A different result is already published under this run id; publication is immutable.' -RunId $RunId -Diagnostic $cleanup
        }

        # The frozen plan is re-verified under the lock: it is the authority this result was bound to.
        try { $lockedPlan = Read-ReviewFrozenPlan -RunDir $runDir }
        catch {
            return New-ReviewResult -Mode publish -ExitCode 2 -State invalid `
                -Message "The frozen plan under this run id is not trustworthy: $($_.Exception.Message)" -RunId $RunId
        }
        if ($lockedPlan.Digest -ne $frozenPlanDigest) {
            return New-ReviewResult -Mode publish -ExitCode 2 -State invalid `
                -Message 'The frozen plan changed while this result was being prepared; nothing published.' -RunId $RunId
        }

        try {
            Invoke-ReviewFaultSeam -Edge 'during-lock'

            $canonicalName = Get-ReviewContentName -Role 'canonical' -Bytes $canonicalBytes
            $summaryName = Get-ReviewContentName -Role 'summary' -Bytes $summaryBytes
            $fullName = Get-ReviewContentName -Role 'full' -Bytes $fullBytes

            $canonicalPath = Join-Path $runDir $canonicalName
            $written.Add($canonicalPath)
            Write-ReviewBytesAtomic -Path $canonicalPath -Bytes $canonicalBytes
            Invoke-ReviewFaultSeam -Edge 'after-canonical'

            $summaryPath = Join-Path $runDir $summaryName
            $written.Add($summaryPath)
            Write-ReviewBytesAtomic -Path $summaryPath -Bytes $summaryBytes
            Invoke-ReviewFaultSeam -Edge 'after-summary'

            $fullPath = Join-Path $runDir $fullName
            $written.Add($fullPath)
            Write-ReviewBytesAtomic -Path $fullPath -Bytes $fullBytes
            Invoke-ReviewFaultSeam -Edge 'after-full'

            $manifest = [ordered]@{
                schema       = $script:ManifestDiscriminator
                runId        = $RunId
                state        = 'published'
                contentTrust = [string](Get-ReviewValue -Node $canonicalRun -Name 'contentTrust')
                scopeDigest  = [string](Get-ReviewValue -Node (Get-ReviewValue -Node $canonicalRun -Name 'scopeAuthority') -Name 'digest')
                planDigest   = $frozenPlanDigest
                runDigest    = $runDigest
                files        = [ordered]@{
                    plan      = [ordered]@{ name = $lockedPlan.Name; digest = $frozenPlanDigest; bytes = $planBytes.Length }
                    canonical = [ordered]@{ name = $canonicalName; digest = $runDigest; bytes = $canonicalBytes.Length }
                    summary   = [ordered]@{ name = $summaryName; digest = (Get-ReviewDigest -Bytes $summaryBytes); bytes = $summaryBytes.Length }
                    full      = [ordered]@{ name = $fullName; digest = (Get-ReviewDigest -Bytes $fullBytes); bytes = $fullBytes.Length }
                }
            }
            $manifestJson = (ConvertTo-Json -InputObject $manifest -Depth 10 -Compress) + "`n"
            if (-not (Test-ReviewSchema -Json $manifestJson -SchemaName 'review-manifest.schema.json')) {
                throw 'the generated manifest fails its own schema'
            }

            Invoke-ReviewFaultSeam -Edge 'before-manifest-swap'
            Write-ReviewBytesAtomic -Path (Join-Path $runDir $script:ManifestName) -Bytes $script:Utf8NoBom.GetBytes($manifestJson)
        }
        catch {
            # Only this attempt's own generations are removed, and only while no manifest names them.
            Remove-ReviewOwnStaging -RunDir $runDir -Written @($written)
            return New-ReviewResult -Mode publish -ExitCode 4 -State failed -Message "Publication failed and was rolled back to prior authority: $($_.Exception.Message)" -RunId $RunId
        }
    }
    finally { Exit-ReviewLock -Lock $lock }

    $cleanup = @(Remove-ReviewCommittedInput -Path $inputPath -Boundary $repoFull)
    $exit = $(if ($runState -eq 'clean') { 0 } else { 5 })
    return New-ReviewResult -Mode publish -ExitCode $exit -State $runState -Message $(if ($runState -eq 'clean') { 'Run published (clean).' } else { 'Run published (degraded).' }) -RunId $RunId -Summary $summaryText -Diagnostic $cleanup
}

# --------------------------------------------------------------------------------------------------
# Reader and cleanup.
# --------------------------------------------------------------------------------------------------
function Get-ReviewRoleByteBudget {
    <#
    .SYNOPSIS
        The maximum byte count one artifact role may occupy, taken from the schema-owned vocabulary.
    #>
    param([Parameter(Mandatory)][string]$Role)

    $limits = Get-ReviewLimits
    switch ($Role) {
        'plan' { return [int]$limits.maxEnvelopeBytes }
        'canonical' { return [int]$limits.maxEnvelopeBytes }
        'admissionSource' { return [int]$limits.maxEnvelopeBytes }
        'admissionMarker' { return [int]$limits.maxTerminalStatusBytes }
        'summary' { return [int]$limits.maxSummaryBytes }
        'full' { return [int]$limits.maxFullBytes }
        default { throw "Unknown artifact role '$Role'." }
    }
}

function Assert-ReviewArtifactContent {
    <#
    .SYNOPSIS
        Enforces the reader's own bounds on one verified artifact: its role's byte budget and the text
        encoding every review artifact is written in.
    .DESCRIPTION
        The manifest's `byteCount` is only bounded by the vocabulary's generic 2 MiB maximum, which is
        the *envelope* budget — a summary of 900 KiB or a full view of 1.9 MiB is a structurally valid
        manifest entry, and a digest-consistent one if the artifact really carries those bytes. A reader
        that checked nothing but "the file is as long as the manifest says" would therefore hand a
        consumer a view far outside the budget the publisher admits. The role budget is re-derived here
        from the same vocabulary the publisher used, so the reader is an independent enforcement point
        rather than a mirror of the manifest.

        The same applies to the encoding: every artifact this contract writes is UTF-8 without a BOM,
        LF-only and NFC (D15), so an artifact that is not is not one this engine produced, whatever its
        digest agrees with.
    #>
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $budget = Get-ReviewRoleByteBudget -Role $Role
    if ($Bytes.Length -gt $budget) {
        throw "the '$Role' artifact is $($Bytes.Length) bytes, over its $budget budget"
    }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        throw "the '$Role' artifact carries a UTF-8 byte-order mark"
    }

    $strict = [System.Text.UTF8Encoding]::new($false, $true)
    try { $text = $strict.GetString($Bytes) }
    catch { throw "the '$Role' artifact is not valid UTF-8" }
    if ($text.IndexOf([char]13) -ge 0) {
        throw "the '$Role' artifact carries a carriage return; review artifacts are LF-only"
    }
    try { $normalized = $text.Normalize([System.Text.NormalizationForm]::FormC) }
    catch { throw "the '$Role' artifact cannot be normalized; it carries an unpaired surrogate" }
    # Ordinal, never `-cne`: PowerShell's comparison operators are culture-sensitive, and a
    # culture-sensitive comparison treats a decomposed string as equal to its composed form — which is
    # precisely the difference being checked for.
    if (-not [string]::Equals($normalized, $text, [System.StringComparison]::Ordinal)) {
        throw "the '$Role' artifact is not NFC-normalized"
    }
}

function Read-ReviewManifest {
    <#
    .SYNOPSIS
        Validates a run's manifest and verifies every file it names against its content-addressed
        name, its recorded digest and its byte count. Returns a verified descriptor or throws.
    .DESCRIPTION
        The manifest is the only thing a reader trusts, so the reader checks that it is internally
        consistent *and* that it describes this directory: the run id must be the directory's own id,
        each name must be the content address of the bytes it names, `runDigest`/`planDigest` must be
        the digests of the canonical and plan files, and the canonical envelope's own `runId` and
        `planDigest` must agree with the manifest. A manifest that names files belonging to another
        run — or that was copied wholesale into a different run directory — fails here. Each artifact is
        additionally held to its own role budget and to the text encoding the contract writes.

        Confinement applies to a verified read exactly as it does to a write (RISK-6): the run
        directory and every concrete file are re-checked for a reparse point immediately before they
        are opened, so a run directory or a leaf artifact swapped for a symlink cannot make this reader
        read outside the store. `Boundary` is where that walk stops; callers that already resolved a
        repository root pass it, and a direct call derives one from the run directory itself, which can
        only make the walk longer and therefore stricter. Same-user TOCTOU inside the remaining window
        stays a documented residual risk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [string]$Boundary,
        [byte[]]$ManifestBytes
    )

    $runDirFull = [System.IO.Path]::GetFullPath($RunDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $boundaryFull = $(if ([string]::IsNullOrWhiteSpace($Boundary)) {
            [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $runDirFull))
        }
        else { [System.IO.Path]::GetFullPath($Boundary) })

    Assert-ReviewPathSafe -Path $runDirFull -Boundary $boundaryFull
    $manifestPath = Join-Path $runDirFull $script:ManifestName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'no manifest: this run is not published'
    }
    Assert-ReviewPathSafe -Path $manifestPath -Boundary $boundaryFull
    if ($null -eq $ManifestBytes) { $ManifestBytes = [System.IO.File]::ReadAllBytes($manifestPath) }
    $manifestText = [System.Text.Encoding]::UTF8.GetString($ManifestBytes)
    if (-not (Test-ReviewSchema -Json $manifestText -SchemaName 'review-manifest.schema.json')) {
        throw 'the manifest fails the review-manifest schema'
    }
    $manifest = $manifestText | ConvertFrom-Json -AsHashtable -Depth 20

    $directoryId = Split-Path -Leaf $runDirFull
    # Ordinal identity: PowerShell's comparison operators are culture-sensitive, and a culture-sensitive
    # comparison ignores characters (zero-width joiners among them) that make two ids different names.
    if (-not [string]::Equals([string]$manifest['runId'], $directoryId, [System.StringComparison]::Ordinal)) {
        throw 'the manifest runId is not this run directory'
    }

    $verified = [ordered]@{}
    $verifiedBytes = [ordered]@{}
    foreach ($role in @('plan', 'canonical', 'summary', 'full')) {
        $artifact = $manifest['files'][$role]
        $name = [string]$artifact['name']
        # Confinement: a manifest name is a single path segment, never a separator, drive or parent.
        if ($name -ne [System.IO.Path]::GetFileName($name) -or $name -match '[\\/]' -or $name.Contains('..')) {
            throw "manifest names a non-confined file for role '$role'"
        }
        # And it is a content address: the digest is in the name, so a swapped file is detectable
        # before its bytes are read and independently of the digest field beside it.
        $claimed = Get-ReviewContentNameDigest -Role $role -Name $name
        if (-not $claimed) {
            throw "manifest names a file for role '$role' that is not content-addressed"
        }
        if ($claimed -ne [string]$artifact['digest']) {
            throw "manifest name and digest disagree for role '$role'"
        }
        $filePath = Join-Path $runDirFull $name
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "manifest names a missing file for role '$role'"
        }
        Assert-ReviewPathSafe -Path $filePath -Boundary $boundaryFull
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        if ($bytes.Length -ne [int]$artifact['bytes']) {
            throw "byte count mismatch for role '$role'"
        }
        if ((Get-ReviewDigest -Bytes $bytes) -ne [string]$artifact['digest']) {
            throw "digest mismatch for role '$role'"
        }
        # Independent of the manifest: the role's own byte budget and the artifact encoding.
        Assert-ReviewArtifactContent -Role $role -Bytes $bytes
        $verified[$role] = $filePath
        $verifiedBytes[$role] = $bytes
    }

    if ([string]$manifest['runDigest'] -ne (Get-ReviewDigest -Bytes $verifiedBytes['canonical'])) {
        throw 'runDigest is not the digest of the canonical file'
    }
    if ([string]$manifest['planDigest'] -ne (Get-ReviewDigest -Bytes $verifiedBytes['plan'])) {
        throw 'planDigest is not the digest of the plan file'
    }

    # Identity binding: the canonical envelope must name this run and the plan the manifest names.
    $canonical = [System.Text.Encoding]::UTF8.GetString($verifiedBytes['canonical']) |
    ConvertFrom-Json -AsHashtable -Depth 40
    $plan = [System.Text.Encoding]::UTF8.GetString($verifiedBytes['plan']) |
    ConvertFrom-Json -AsHashtable -Depth 40
    if (-not [string]::Equals([string](Get-ReviewValue -Node $canonical -Name 'runId'), [string]$manifest['runId'], [System.StringComparison]::Ordinal)) {
        throw 'the canonical envelope names a different run id than the manifest'
    }
    if (-not [string]::Equals([string](Get-ReviewValue -Node $canonical -Name 'planDigest'), [string]$manifest['planDigest'], [System.StringComparison]::Ordinal)) {
        throw 'the canonical envelope is bound to a different plan digest than the manifest'
    }
    foreach ($document in @($plan, $canonical)) {
        if (-not [string]::Equals([string](Get-ReviewValue -Node $document -Name 'contentTrust'), [string]$manifest['contentTrust'], [System.StringComparison]::Ordinal)) {
            throw 'manifest contentTrust does not match the plan and canonical envelope'
        }
        $documentScopeDigest = [string](Get-ReviewValue -Node (Get-ReviewValue -Node $document -Name 'scopeAuthority') -Name 'digest')
        if (-not [string]::Equals($documentScopeDigest, [string]$manifest['scopeDigest'], [System.StringComparison]::Ordinal)) {
            throw 'manifest scopeDigest does not match the plan and canonical envelope'
        }
    }

    return [pscustomobject]@{
        RunId      = [string]$manifest['runId']
        PlanDigest = [string]$manifest['planDigest']
        RunDigest  = [string]$manifest['runDigest']
        Files      = $verified
        Bytes      = $verifiedBytes
        Documents  = [ordered]@{ plan = $plan; canonical = $canonical }
        Boundary   = $boundaryFull
        Manifest   = $manifest
        VerificationToken = $script:VerifiedAuthorityToken
    }
}

function Get-ReviewRunViewText {
    <#
    .SYNOPSIS
        A verified bounded view of a published run. Reads only the manifest and the files it names,
        after verifying every digest and role bound.
    .DESCRIPTION
        `Boundary` is passed straight to `Read-ReviewManifest`, which re-checks the run directory and
        every concrete file for a reparse point immediately before reading it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [ValidateSet('Summary', 'Full')][string]$View = 'Summary',
        [string]$Boundary
    )

    $verified = Read-ReviewManifest -RunDir $RunDir -Boundary $Boundary
    $role = $View.ToLowerInvariant()
    return [System.Text.Encoding]::UTF8.GetString($verified.Bytes[$role])
}

function Get-ReviewRunSummaryText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [string]$Boundary
    )

    return Get-ReviewRunViewText -RunDir $RunDir -View Summary -Boundary $Boundary
}

function Limit-ReviewRetainedInlineText {
    param(
        [AllowEmptyString()][string]$Value,
        [int]$MaxBytes = 192
    )

    $text = ConvertTo-ReviewInlineText -Value $Value
    if ($script:Utf8NoBom.GetByteCount($text) -le $MaxBytes) { return $text }

    $builder = [System.Text.StringBuilder]::new()
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($text)
    while ($enumerator.MoveNext()) {
        $candidate = $builder.ToString() + [string]$enumerator.Current + '...'
        if ($script:Utf8NoBom.GetByteCount($candidate) -gt $MaxBytes) { break }
        [void]$builder.Append([string]$enumerator.Current)
    }
    return $builder.ToString() + '...'
}

function Get-ReviewRetainedReportText {
    param(
        [Parameter(Mandatory)][object]$Projection,
        [ValidateSet('approved', 'blocked')][string]$Verdict
    )

    $severity = [ordered]@{ Critical = 0; High = 0; Medium = 0; Low = 0 }
    foreach ($finding in @($Projection.Findings)) { $severity[[string]$finding.Severity]++ }
    $blocking = @($Projection.Findings | Where-Object { $_.Severity -in @('Critical', 'High') })
    $needsReview = @($Projection.Findings | Where-Object { $_.NeedsReview })
    if ($Verdict -eq 'approved' -and ($Projection.State -ne 'clean' -or $blocking.Count -gt 0 -or $needsReview.Count -gt 0)) {
        throw 'An approved review result requires a clean run with no Critical or High findings and no finding marked needs-review.'
    }

    $authority = $Projection.ScopeAuthority
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# $(Get-ReviewReportTitle -ReviewType $Projection.ReviewType) result")
    $lines.Add('')
    $lines.Add('<!-- skalary/review-result@1 -->')
    $lines.Add('')
    $lines.Add('| | |')
    $lines.Add('|---|---|')
    $lines.Add("| **Run** | $(ConvertTo-ReviewCodeSpan -Value $Projection.RunId) |")
    $lines.Add("| **Review type** | $(ConvertTo-ReviewCodeSpan -Value $Projection.ReviewType) |")
    $lines.Add("| **Gate verdict** | **$Verdict** |")
    $lines.Add("| **Run state** | $(ConvertTo-ReviewCodeSpan -Value $Projection.State) |")
    $lines.Add("| **Scope mode** | $(ConvertTo-ReviewCodeSpan -Value ([string](Get-ReviewValue -Node $authority -Name 'mode'))) |")
    foreach ($name in @('base', 'head')) {
        $value = [string](Get-ReviewValue -Node $authority -Name $name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $lines.Add("| **$($name.Substring(0, 1).ToUpperInvariant() + $name.Substring(1))** | $(Limit-ReviewRetainedInlineText -Value $value -MaxBytes 256) |")
        }
    }
    $lines.Add("| **Scope paths** | $(Format-ReviewInvariant -Value @((Get-ReviewValue -Node $authority -Name 'paths')).Count) |")
    $lines.Add("| **Scope digest** | $(ConvertTo-ReviewCodeSpan -Value ([string](Get-ReviewValue -Node $authority -Name 'digest'))) |")
    $lines.Add("| **Plan digest** | $(ConvertTo-ReviewCodeSpan -Value $Projection.PlanDigest) |")
    $lines.Add('')
    $lines.Add('## Attendance')
    $lines.Add('')
    $attendance = @($script:Outcomes | ForEach-Object { "$_=$([int]$Projection.Attendance[$_])" }) -join '; '
    $lines.Add("$attendance; planned=$($Projection.Tasks.Count).")
    $lines.Add('')
    $lines.Add('## Findings')
    $lines.Add('')
    $lines.Add('| Critical | High | Medium | Low | Merged | Raw |')
    $lines.Add('|---:|---:|---:|---:|---:|---:|')
    $lines.Add("| $($severity.Critical) | $($severity.High) | $($severity.Medium) | $($severity.Low) | $($Projection.Findings.Count) | $($Projection.RawFindingCount) |")
    $lines.Add('')
    $lines.Add('## Blocking findings')
    $lines.Add('')
    if ($blocking.Count -eq 0) {
        $lines.Add('None.')
    }
    else {
        $shown = [Math]::Min($blocking.Count, 20)
        for ($index = 0; $index -lt $shown; $index++) {
            $finding = $blocking[$index]
            $lines.Add("$($index + 1). **$($finding.Severity)** — $(Limit-ReviewRetainedInlineText -Value $finding.Title)")
        }
        if ($shown -lt $blocking.Count) { $lines.Add("- $($blocking.Count - $shown) additional blocking finding(s) omitted from this compact result.") }
    }
    $text = ($lines -join "`n") + "`n"
    $maximum = [int](Get-ReviewLimits)['maxRetainedReportBytes']
    if ($script:Utf8NoBom.GetByteCount($text) -gt $maximum) { throw "The compact review result exceeds its $maximum-byte bound." }
    return $text
}

function Read-ReviewManifestForFinalization {
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$Boundary
    )

    $runDirFull = [System.IO.Path]::GetFullPath($RunDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    Assert-ReviewPathSafe -Path $runDirFull -Boundary $Boundary
    $manifestPath = Join-Path $runDirFull $script:ManifestName
    Assert-ReviewPathSafe -Path $manifestPath -Boundary $Boundary
    $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
    $verified = Read-ReviewManifest -RunDir $RunDir -Boundary $Boundary -ManifestBytes $manifestBytes
    return [pscustomobject]@{
        RunId = $verified.RunId
        PlanDigest = $verified.PlanDigest
        RunDigest = $verified.RunDigest
        Files = $verified.Files
        Boundary = $verified.Boundary
        Manifest = $verified.Manifest
        ManifestDigest = Get-ReviewDigest -Bytes $manifestBytes
        Run = $verified.Documents['canonical']
    }
}

function Get-ReviewFinalizationMaterial {
    param(
        [Parameter(Mandatory)][object]$Verified,
        [Parameter(Mandatory)][ValidateSet('approved', 'blocked')][string]$Verdict,
        [Parameter(Mandatory)][string]$ReportPath
    )

    $projection = ConvertTo-ReviewProjection -Run $Verified.Run
    $reportBytes = $script:Utf8NoBom.GetBytes((Get-ReviewRetainedReportText -Projection $projection -Verdict $Verdict))
    $authority = $projection.ScopeAuthority
    $severity = [ordered]@{ critical = 0; high = 0; medium = 0; low = 0 }
    foreach ($finding in @($projection.Findings)) { $severity[[string]$finding.Severity.ToLowerInvariant()]++ }
    $source = [ordered]@{
        mode = [string](Get-ReviewValue -Node $authority -Name 'mode')
        pathCount = @((Get-ReviewValue -Node $authority -Name 'paths')).Count
        digest = [string](Get-ReviewValue -Node $authority -Name 'digest')
    }
    foreach ($name in @('base', 'head')) {
        $identity = [string](Get-ReviewValue -Node $authority -Name $name)
        if (-not [string]::IsNullOrWhiteSpace($identity)) { $source[$name] = $identity }
    }
    $receipt = [ordered]@{
        schema = 'skalary/review-result-receipt@1'
        runId = $Verified.RunId
        reviewType = $projection.ReviewType
        verdict = $Verdict
        state = $projection.State
        source = $source
        planDigest = $Verified.PlanDigest
        runDigest = $Verified.RunDigest
        manifestDigest = $Verified.ManifestDigest
        legacySource = $false
        attendance = $projection.Attendance
        findings = [ordered]@{
            merged = $projection.Findings.Count
            raw = $projection.RawFindingCount
            severity = $severity
        }
        report = [ordered]@{
            name = [System.IO.Path]::GetFileName($ReportPath)
            bytes = $reportBytes.Length
            digest = Get-ReviewDigest -Bytes $reportBytes
        }
    }
    return [pscustomobject]@{
        ReportBytes = $reportBytes
        ReceiptBytes = $script:Utf8NoBom.GetBytes((ConvertTo-ReviewCanonicalJson -Node $receipt))
    }
}

function Test-ReviewFinalizedPair {
    param(
        [Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [byte[]]$ExpectedReportBytes,
        [byte[]]$ExpectedReceiptBytes
    )

    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf) -or -not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { return $false }
    $reportBytes = [System.IO.File]::ReadAllBytes($ReportPath)
    $receiptBytes = [System.IO.File]::ReadAllBytes($ReceiptPath)
    if ($null -ne $ExpectedReportBytes -and
        ($reportBytes.Length -ne $ExpectedReportBytes.Length -or (Get-ReviewDigest -Bytes $reportBytes) -ne (Get-ReviewDigest -Bytes $ExpectedReportBytes))) { return $false }
    if ($null -ne $ExpectedReceiptBytes -and
        ($receiptBytes.Length -ne $ExpectedReceiptBytes.Length -or (Get-ReviewDigest -Bytes $receiptBytes) -ne (Get-ReviewDigest -Bytes $ExpectedReceiptBytes))) { return $false }
    try { $receipt = [System.Text.Encoding]::UTF8.GetString($receiptBytes) | ConvertFrom-Json -AsHashtable -Depth 20 }
    catch { return $false }
    return $receipt['schema'] -eq 'skalary/review-result-receipt@1' -and
        $receipt['report']['bytes'] -eq $reportBytes.Length -and
        $receipt['report']['digest'] -eq (Get-ReviewDigest -Bytes $reportBytes)
}

function Get-ReviewCleanupMarker {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Verdict,
        [Parameter(Mandatory)][object]$Material,
        [Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][string]$ReceiptPath
    )

    return [ordered]@{
        schema = 'skalary/review-cleanup@1'
        runId = $RunId
        verdict = $Verdict
        report = [ordered]@{ name = [System.IO.Path]::GetFileName($ReportPath); bytes = $Material.ReportBytes.Length; digest = Get-ReviewDigest -Bytes $Material.ReportBytes }
        receipt = [ordered]@{ name = [System.IO.Path]::GetFileName($ReceiptPath); bytes = $Material.ReceiptBytes.Length; digest = Get-ReviewDigest -Bytes $Material.ReceiptBytes }
    }
}

function Read-ReviewCleanupMarker {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Verdict,
        [Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [switch]$SkipPairValidation
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Cleanup marker is missing for '$RunId'." }
    $marker = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 10
    if ($marker['schema'] -ne 'skalary/review-cleanup@1' -or $marker['runId'] -ne $RunId -or $marker['verdict'] -ne $Verdict) {
        throw "Cleanup marker for '$RunId' has a different verdict or identity."
    }
    if ($SkipPairValidation) { return $marker }
    foreach ($entry in @(@('report', $ReportPath), @('receipt', $ReceiptPath))) {
        $role = [string]$entry[0]
        $path = [string]$entry[1]
        if ([string]$marker[$role]['name'] -ne [System.IO.Path]::GetFileName($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Cleanup marker '$role' is missing or names a different file."
        }
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($marker[$role]['bytes'] -ne $bytes.Length -or $marker[$role]['digest'] -ne (Get-ReviewDigest -Bytes $bytes)) {
            throw "Cleanup marker '$role' does not match retained evidence."
        }
    }
    return $marker
}

function Assert-ReviewCleanupMarkerMaterial {
    param([Parameter(Mandatory)][object]$Marker, [Parameter(Mandatory)][object]$Material)
    foreach ($entry in @(@('report', $Material.ReportBytes), @('receipt', $Material.ReceiptBytes))) {
        $role = [string]$entry[0]
        $bytes = [byte[]]$entry[1]
        if ($Marker[$role]['bytes'] -ne $bytes.Length -or $Marker[$role]['digest'] -ne (Get-ReviewDigest -Bytes $bytes)) {
            throw "Cleanup marker '$role' is bound to different finalization material."
        }
    }
}

function New-ReviewFinalizationResult {
    param([string]$RunId, [string]$Verdict, [string]$Report, [string]$Receipt, [bool]$Replayed = $false, [bool]$Preview = $false, [bool]$CleanupPending = $false, [AllowNull()][string]$CleanupDiagnostic)
    return [pscustomobject]@{ RunId = $RunId; Verdict = $Verdict; Report = $Report; Receipt = $Receipt; Replayed = $Replayed; Preview = $Preview; CleanupPending = $CleanupPending; CleanupDiagnostic = $CleanupDiagnostic }
}

function Finalize-ReviewPlanRun {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$PlanDir,
        [ValidateSet('approved', 'blocked')][string]$Verdict,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    if (-not (Test-ReviewRunId -RunId $RunId)) { throw "Run id '$RunId' is not a lowercase UUID." }
    $repoFull = [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $RepoRoot))
    $store = Resolve-ReviewStoreRoot -PlanDir $PlanDir -RepoRoot $repoFull
    $runDir = Join-Path $store $RunId
    $cleanupRoot = Join-Path $store '.cleanup'
    $cleanupDir = Join-Path $cleanupRoot $RunId
    $cleanupMarkerPath = Join-Path $store ".$RunId.cleanup.json"
    $reportPath = Join-Path $store "$RunId.review.md"
    $receiptPath = Join-Path $store "$RunId.receipt.json"
    $lock = Enter-ReviewLock -RunDir $store -LockName ".$RunId.finalize.lock"
    try {
        $liveExists = Test-Path -LiteralPath $runDir -PathType Container
        if (-not $liveExists) {
            if (Test-Path -LiteralPath $cleanupDir -PathType Container) {
                [void](Read-ReviewCleanupMarker -Path $cleanupMarkerPath -RunId $RunId -Verdict $Verdict `
                        -ReportPath $reportPath -ReceiptPath $receiptPath -SkipPairValidation)
                $pairExists = $true
                try {
                    $verified = Read-ReviewManifestForFinalization -RunDir $cleanupDir -Boundary $repoFull
                    $material = Get-ReviewFinalizationMaterial -Verified $verified -Verdict $Verdict -ReportPath $reportPath
                    $pairExists = Test-ReviewFinalizedPair -ReportPath $reportPath -ReceiptPath $receiptPath `
                        -ExpectedReportBytes $material.ReportBytes -ExpectedReceiptBytes $material.ReceiptBytes
                    if (-not $pairExists -and $PSCmdlet.ShouldProcess($cleanupDir, 'Repair compact evidence from cleanup authority')) {
                        Write-ReviewBytesAtomic -Path $reportPath -Bytes $material.ReportBytes
                        Write-ReviewBytesAtomic -Path $receiptPath -Bytes $material.ReceiptBytes
                    }
                }
                catch {
                    [void](Read-ReviewCleanupMarker -Path $cleanupMarkerPath -RunId $RunId -Verdict $Verdict -ReportPath $reportPath -ReceiptPath $receiptPath)
                }
                [void](Read-ReviewCleanupMarker -Path $cleanupMarkerPath -RunId $RunId -Verdict $Verdict -ReportPath $reportPath -ReceiptPath $receiptPath)
                $cleanupPending = $true
                $cleanupDiagnostic = $null
                if ($PSCmdlet.ShouldProcess($cleanupDir, 'Complete pending live-authority cleanup')) {
                    try {
                        Remove-ReviewTree -Path $cleanupDir
                        Remove-Item -LiteralPath $cleanupMarkerPath -Force -ErrorAction Stop
                        $cleanupPending = $false
                    }
                    catch { $cleanupPending = $true; $cleanupDiagnostic = $_.Exception.Message }
                }
                return New-ReviewFinalizationResult -RunId $RunId -Verdict $Verdict -Report $reportPath -Receipt $receiptPath -Replayed $pairExists -Preview $WhatIfPreference -CleanupPending $cleanupPending -CleanupDiagnostic $cleanupDiagnostic
            }
            if (Test-ReviewFinalizedPair -ReportPath $reportPath -ReceiptPath $receiptPath) {
                $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20
                if ($receipt['runId'] -ne $RunId -or $receipt['verdict'] -ne $Verdict) {
                    throw "Finalized review result '$RunId' has a different verdict or identity."
                }
                $cleanupPending = Test-Path -LiteralPath $cleanupDir -PathType Container
                if (Test-Path -LiteralPath $cleanupMarkerPath -PathType Leaf) {
                    [void](Read-ReviewCleanupMarker -Path $cleanupMarkerPath -RunId $RunId -Verdict $Verdict -ReportPath $reportPath -ReceiptPath $receiptPath)
                    try { Remove-Item -LiteralPath $cleanupMarkerPath -Force -ErrorAction Stop } catch { $cleanupPending = $true }
                }
                if ($cleanupPending -and $PSCmdlet.ShouldProcess($cleanupDir, 'Complete pending live-authority cleanup')) {
                    try {
                        Remove-Item -LiteralPath $cleanupDir -Recurse -Force -ErrorAction Stop
                        $cleanupPending = $false
                    }
                    catch { $cleanupPending = $true }
                }
                return New-ReviewFinalizationResult -RunId $RunId -Verdict $Verdict -Report $reportPath -Receipt $receiptPath -Replayed $true -Preview $WhatIfPreference -CleanupPending $cleanupPending
            }
            throw "No live or finalized plan review run for '$RunId'."
        }

        $runLock = Enter-ReviewLock -RunDir $runDir
        try {
            $verified = Read-ReviewManifestForFinalization -RunDir $runDir -Boundary $repoFull
            $material = Get-ReviewFinalizationMaterial -Verified $verified -Verdict $Verdict -ReportPath $reportPath
            $existingMarker = $null
            if (Test-Path -LiteralPath $cleanupMarkerPath -PathType Leaf) {
                $existingMarker = Read-ReviewCleanupMarker -Path $cleanupMarkerPath -RunId $RunId -Verdict $Verdict `
                    -ReportPath $reportPath -ReceiptPath $receiptPath -SkipPairValidation
                Assert-ReviewCleanupMarkerMaterial -Marker $existingMarker -Material $material
            }
            $pairExists = Test-ReviewFinalizedPair -ReportPath $reportPath -ReceiptPath $receiptPath `
                -ExpectedReportBytes $material.ReportBytes -ExpectedReceiptBytes $material.ReceiptBytes

            if (-not $PSCmdlet.ShouldProcess($runDir, "Finalize plan review as '$Verdict', write compact evidence, and remove the live run")) {
                return New-ReviewFinalizationResult -RunId $RunId -Verdict $Verdict -Report $reportPath -Receipt $receiptPath -Preview $true -CleanupPending $true
            }

            if (-not $pairExists) {
                if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
                    $existing = $null
                    try { $existing = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20 } catch { }
                    if ($null -ne $existing -and $existing['runId'] -eq $RunId -and $existing['verdict'] -ne $Verdict) {
                        throw "Finalized review result '$RunId' has a different verdict."
                    }
                }
                foreach ($path in @($reportPath, $receiptPath)) {
                    if (Test-Path -LiteralPath $path) { Assert-ReviewPathSafe -Path $path -Boundary $repoFull }
                }
                Write-ReviewBytesAtomic -Path $reportPath -Bytes $material.ReportBytes
                Invoke-ReviewFaultSeam -Edge 'after-final-report'
                Write-ReviewBytesAtomic -Path $receiptPath -Bytes $material.ReceiptBytes
                if (-not (Test-ReviewFinalizedPair -ReportPath $reportPath -ReceiptPath $receiptPath `
                        -ExpectedReportBytes $material.ReportBytes -ExpectedReceiptBytes $material.ReceiptBytes)) {
                    throw "Finalized review result '$RunId' did not verify after publication."
                }
            }
        }
        finally { Exit-ReviewLock -Lock $runLock }

        $cleanupPending = $false
        $cleanupDiagnostic = $null
        try {
            if (Test-Path -LiteralPath $cleanupDir) { throw "Cleanup tombstone already exists for '$RunId'." }
            if (-not (Test-Path -LiteralPath $cleanupRoot -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $cleanupRoot -Force -ErrorAction Stop)
            }
            Assert-ReviewPathSafe -Path $cleanupRoot -Boundary $repoFull
            if ($null -eq $existingMarker) {
                $cleanupMarker = Get-ReviewCleanupMarker -RunId $RunId -Verdict $Verdict -Material $material -ReportPath $reportPath -ReceiptPath $receiptPath
                Write-ReviewBytesAtomic -Path $cleanupMarkerPath -Bytes $script:Utf8NoBom.GetBytes((ConvertTo-ReviewCanonicalJson -Node $cleanupMarker))
            }
            Move-Item -LiteralPath $runDir -Destination $cleanupDir -ErrorAction Stop
            Invoke-ReviewFaultSeam -Edge 'during-finalize-cleanup'
            Remove-ReviewTree -Path $cleanupDir
            Remove-Item -LiteralPath $cleanupMarkerPath -Force -ErrorAction Stop
        }
        catch { $cleanupPending = $true; $cleanupDiagnostic = $_.Exception.Message }
        return New-ReviewFinalizationResult -RunId $RunId -Verdict $Verdict -Report $reportPath -Receipt $receiptPath -Replayed $pairExists -CleanupPending $cleanupPending -CleanupDiagnostic $cleanupDiagnostic
    }
    finally { Exit-ReviewLock -Lock $lock }
}

function Assert-ReviewAdmissionRollupContent {
    param(
        [Parameter(Mandatory)][object[]]$Children,
        [Parameter(Mandatory)][object]$ParentPlan,
        [Parameter(Mandatory)][object]$ParentRun,
        [Parameter(Mandatory)][int]$MaxPartitions
    )

    if ($Children.Count -eq 0) { throw 'no published admission partitions were found' }
    $partitionCounts = @($Children | ForEach-Object { [int](Get-ReviewValue -Node $_.Restart -Name 'partitionCount') } | Sort-Object -Unique)
    if ($partitionCounts.Count -ne 1 -or $partitionCounts[0] -gt $MaxPartitions) { throw 'partitionCount is inconsistent or over the hard maximum' }
    $partitionCount = $partitionCounts[0]
    if ($Children.Count -ne $partitionCount) { throw "expected $partitionCount published partitions but found $($Children.Count)" }
    $orderedChildren = @($Children | Sort-Object { [int](Get-ReviewValue -Node $_.Restart -Name 'partitionIndex') })
    $indexes = @($orderedChildren | ForEach-Object { [int](Get-ReviewValue -Node $_.Restart -Name 'partitionIndex') })
    if (($indexes -join ',') -ne ((1..$partitionCount) -join ',')) { throw 'partition indexes are not exactly the ordered closed range' }

    $expectedPaths = @((Get-ReviewValue -Node (Get-ReviewValue -Node $ParentPlan -Name 'scopeAuthority') -Name 'paths') | ForEach-Object {
            Get-ReviewOrdinalTupleKey -Value @([string](Get-ReviewValue -Node $_ -Name 'path'), [string](Get-ReviewValue -Node $_ -Name 'status'))
        })
    $actualPaths = @($orderedChildren | ForEach-Object {
            @(Get-ReviewValue -Node (Get-ReviewValue -Node $_.Plan -Name 'scopeAuthority') -Name 'paths') | ForEach-Object {
                Get-ReviewOrdinalTupleKey -Value @([string](Get-ReviewValue -Node $_ -Name 'path'), [string](Get-ReviewValue -Node $_ -Name 'status'))
            }
        })
    if (($actualPaths -join "`n") -cne ($expectedPaths -join "`n")) { throw 'partition path records do not exactly cover the parent scope in canonical order' }

    $expectedFindings = @(Get-ReviewValue -Node $ParentRun -Name 'findings' | ForEach-Object { ConvertTo-ReviewCanonicalJson -Node $_ })
    $actualFindings = @($orderedChildren | ForEach-Object { @(Get-ReviewValue -Node $_.Run -Name 'findings') } | ForEach-Object { ConvertTo-ReviewCanonicalJson -Node $_ })
    if (((Sort-ReviewOrdinal -Value $actualFindings) -join "`n") -cne ((Sort-ReviewOrdinal -Value $expectedFindings) -join "`n")) {
        throw 'partition findings do not exactly preserve the parent admission source'
    }

    $expectedTasks = @((Get-ReviewValue -Node $ParentRun -Name 'tasks') | ForEach-Object { ConvertTo-ReviewCanonicalJson -Node $_ })
    foreach ($child in $orderedChildren) {
        $actualTasks = @((Get-ReviewValue -Node $child.Run -Name 'tasks') | ForEach-Object { ConvertTo-ReviewCanonicalJson -Node $_ })
        if (($actualTasks -join "`n") -cne ($expectedTasks -join "`n")) {
            throw "partition '$($child.RunId)' task outcomes do not exactly preserve the parent admission source"
        }
    }
    return $orderedChildren
}

function Get-ReviewAdmissionRollup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ParentRunId,
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    $boundary = [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $RepoRoot))
    $parentDir = Resolve-ReviewRunRoot -RunId $ParentRunId -PlanDir $PlanDir -RepoRoot $boundary
    $admission = Read-ReviewAdmissionMarker -RunDir $parentDir -Boundary $boundary
    if (-not [bool]$admission.Marker['restartable']) { throw 'the parent admission has no verifiable restart source' }
    $parentPlan = (Read-ReviewFrozenPlan -RunDir $parentDir).Plan
    $parentRun = $admission.SourceDocument
    $store = Split-Path -Parent $parentDir

    $children = [System.Collections.Generic.List[object]]::new()
    foreach ($dir in @(Get-ChildItem -LiteralPath $store -Directory -Force)) {
        if (-not (Test-ReviewRunId -RunId $dir.Name) -or $dir.Name -eq $ParentRunId) { continue }
        Assert-ReviewPathSafe -Path $dir.FullName -Boundary $boundary
        try { $frozen = Read-ReviewFrozenPlan -RunDir $dir.FullName } catch { continue }
        $restart = Get-ReviewValue -Node $frozen.Plan -Name 'restart'
        if ($null -eq $restart -or -not [string]::Equals([string](Get-ReviewValue -Node $restart -Name 'parentRunId'), $ParentRunId, [System.StringComparison]::Ordinal)) { continue }
        if (-not [string]::Equals([string](Get-ReviewValue -Node $restart -Name 'parentRunDigest'), [string]$admission.Marker['parentRunDigest'], [System.StringComparison]::Ordinal)) {
            throw "child run '$($dir.Name)' carries the wrong parent digest"
        }
        $verified = Read-ReviewManifest -RunDir $dir.FullName -Boundary $boundary
        $childRun = $verified.Documents['canonical']
        $children.Add([pscustomobject]@{ RunId = $dir.Name; Restart = $restart; Plan = $frozen.Plan; Run = $childRun; RunDigest = $verified.RunDigest })
    }
    $orderedChildren = @(Assert-ReviewAdmissionRollupContent -Children @($children) -ParentPlan $parentPlan -ParentRun $parentRun `
            -MaxPartitions ([int]$admission.Marker['maxPartitions']))
    $expectedFindings = @(Get-ReviewValue -Node $parentRun -Name 'findings')

    return [pscustomobject]@{
        schema          = 'skalary/review-admission-rollup@1'
        state           = 'verified'
        parentRunId     = $ParentRunId
        parentRunDigest = [string]$admission.Marker['parentRunDigest']
        scopeDigest     = [string]$admission.Marker['scopeDigest']
        findingCount    = $expectedFindings.Count
        partitions      = @($orderedChildren | ForEach-Object { [pscustomobject]@{ index = [int](Get-ReviewValue -Node $_.Restart -Name 'partitionIndex'); runId = $_.RunId; runDigest = $_.RunDigest } })
    }
}

function Find-IncompleteReviewRun {
    <#
    .SYNOPSIS
        Frozen but unpublished runs under a store root: a plan folder's reviews directory or the
        generic store. The caller publishes each as cancelled/orchestrator-interrupted at review start.
    .DESCRIPTION
        Resolution goes through `Resolve-ReviewStoreRoot`, the same confinement and inventory
        validation `Freeze`/`Publish` use — a listing path that resolved a plan directory on its own
        would be a second, weaker way to point the engine at a directory. A run that reached a terminal
        admission decision is *not* incomplete: it is finished, and reporting it would invite the caller
        to publish a reduced set under the same UUID.

        Enumeration is a read of the store, so it is confined like every other read: the store root and
        each candidate run directory are checked for a reparse point *before* they are enumerated or
        their state is decided. A symlinked run directory is a loud failure rather than an entry the
        caller is invited to finalize somewhere outside the store.
    #>
    [CmdletBinding()]
    param(
        [string]$PlanDir,
        [string]$RepoRoot = (Get-ReviewRepoRoot)
    )

    $repoFull = [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $RepoRoot))
    $root = Resolve-ReviewStoreRoot -PlanDir $PlanDir -RepoRoot $RepoRoot

    $incomplete = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $root -PathType Container) {
        Assert-ReviewPathSafe -Path $root -Boundary $repoFull
        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
            if (-not (Test-ReviewRunId -RunId $dir.Name)) { continue }
            Assert-ReviewPathSafe -Path $dir.FullName -Boundary $repoFull
            if ((Get-ReviewRunState -RunDir $dir.FullName) -eq 'frozen') {
                $incomplete.Add($dir.Name)
            }
        }
    }
    return @(Sort-ReviewOrdinal -Value @($incomplete))
}

function Remove-ReviewRunDirectory {
    <#
    .SYNOPSIS
        Generic cleanup: removes a published generic run directory after verifying its manifest and
        that it lives under the generic store. Refuses to touch a plan-associated (committed) run.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$RepoRoot = (Get-ReviewRepoRoot),
        [bool]$RequirePublished = $true,
        [object]$VerifiedManifest
    )

    if (-not (Test-ReviewRunId -RunId $RunId)) { throw "Run id '$RunId' is not a lowercase UUID." }
    $repoFull = [System.IO.Path]::GetFullPath((Get-ReviewRepoRoot -StartPath $RepoRoot))
    $genericRoot = Resolve-ReviewStoreRoot -RepoRoot $RepoRoot
    $runDir = Join-Path $genericRoot $RunId
    if (-not (Test-Path -LiteralPath $runDir -PathType Container)) {
        throw "No generic run directory for '$RunId'."
    }
    # Confinement: only ever a child of the generic store, and no ancestor may be a reparse point that
    # would turn this removal into a delete somewhere else.
    $full = [System.IO.Path]::GetFullPath($runDir)
    if (-not $full.StartsWith($genericRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::Ordinal)) {
        throw 'Refusing to remove a directory outside the generic review store.'
    }
    Assert-ReviewPathSafe -Path $full -Boundary $repoFull
    if ($RequirePublished) {
        if ($null -eq $VerifiedManifest -or
            -not [object]::ReferenceEquals($VerifiedManifest.VerificationToken, $script:VerifiedAuthorityToken)) {
            throw 'Generic cleanup requires authority returned by Read-ReviewManifest.'
        }
        $fullBytes = [byte[]]$VerifiedManifest.Bytes['full']
        $stdout = [Console]::OpenStandardOutput()
        $stdout.Write($fullBytes, 0, $fullBytes.Length)
        $stdout.Flush()
    }
    elseif (Test-Path -LiteralPath (Join-Path $runDir $script:ManifestName) -PathType Leaf) {
        throw 'Force cleanup is limited to unpublished abandoned runs; published authority requires verified delivery.'
    }
    if (-not $PSCmdlet.ShouldProcess($runDir, 'Remove verified generic review run recursively')) {
        return $RunId
    }
    Invoke-ReviewFaultSeam -Edge 'during-generic-cleanup'
    Remove-ReviewTree -Path $runDir
    return $RunId
}

Export-ModuleMember -Function @(
    'Invoke-ReviewFreeze', 'Invoke-ReviewPublish',
    'Get-ReviewRunViewText', 'Get-ReviewRunSummaryText', 'Read-ReviewManifest', 'Get-ReviewAdmissionRollup', 'Assert-ReviewAdmissionRollupContent', 'Find-IncompleteReviewRun', 'Finalize-ReviewPlanRun', 'Remove-ReviewRunDirectory',
    'Get-ReviewRunSummaryView', 'Get-ReviewRunFullView', 'ConvertTo-ReviewProjection', 'ConvertTo-ReviewCanonicalJson',
    'Get-ReviewDigest', 'Get-ReviewSha256Hex', 'Get-ReviewScopeDigest', 'Test-ReviewSchema', 'Test-ReviewPlanSemantic', 'Test-ReviewRunSemantic',
    'Get-ReviewMergeKey', 'ConvertTo-ReviewCanonicalText',
    'Find-ReviewSecret', 'Test-ReviewValueForSecret', 'Get-ReviewTerminalStatusJson', 'Write-ReviewTerminalStatus',
    'Resolve-ReviewRunRoot', 'Resolve-ReviewStoreRoot', 'Resolve-ReviewRunPreparation', 'Get-ReviewRepoRoot', 'Get-ReviewRunState', 'Get-ReviewLimits',
    'Get-ReviewLockTimeoutSeconds', 'Get-ReviewContentName', 'Get-ReviewContentNamePattern', 'Get-ReviewContentNameDigest',
    'Get-ReviewFrozenPlanFile', 'Read-ReviewFrozenPlan', 'Read-ReviewAdmissionMarker', 'Test-ReviewHostSchemaCapability', 'Assert-ReviewPathSafe',
    'Set-ReviewSchemaCapabilitySimulation', 'Set-ReviewRunFaultSeam', 'Clear-ReviewRunFaultSeam',
    'Set-ReviewPathItemProvider', 'Clear-ReviewPathItemProvider',
    'Set-ReviewRemoveTreeProvider', 'Clear-ReviewRemoveTreeProvider',
    'Set-ReviewRunLockTimeoutOverride', 'Enter-ReviewLock', 'Exit-ReviewLock'
)

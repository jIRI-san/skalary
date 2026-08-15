#requires -Version 7.0
<#
.SYNOPSIS
    Proves this host's native JSON Schema support before any review run uses it.
.DESCRIPTION
    Plan c21cdc REQ-1/D12, RISK-12. `Build-ReviewReport.ps1` stays `#requires -Version 7.0` so a
    consumer on 7.0 still loads it and fails with a diagnosis instead of a parse error, which means
    the schema capability itself has to be checked rather than assumed. Two things are checked
    explicitly, because they fail differently: the host is PowerShell 7.6 or newer, and `Test-Json`
    actually exposes `-SchemaFile`. A host missing either writes exactly one bounded terminal-status
    JSON object and exits `2` — the same rejection exit an invalid input gets, because a review that
    cannot be validated must not be dispatched.

    On a capable host every keyword the four committed schemas rely on is proven against those
    schemas themselves, not against synthetic stand-ins: each probe validates one instance the
    contract accepts or one twin it must reject. The keyword inventory is read out of the schema
    files, so a schema that starts using a keyword no probe covers fails this gate rather than
    silently trusting an unproven feature. Nothing is written to disk: the probes run against the
    committed schema files, so this script is safe to run anywhere, in any order.

    Simulation switches exist for the suite. Both can only *lower* the capability this script
    reports — `-SimulateVersion` is applied as a minimum against the real version and
    `-SimulateMissingSchemaFile` can only remove a parameter, never add one — so no invocation can
    talk a real host into skipping a check it would otherwise fail.
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-ReviewSchemaCapability.ps1
.EXAMPLE
    pwsh -NoProfile -File scripts/skalary/Test-ReviewSchemaCapability.ps1 -SimulateVersion 7.5.9
#>
[CmdletBinding()]
param(
    # Test seam: reports capability as if the host were this version when that is *older* than the
    # real one. A newer value changes nothing.
    [string]$SimulateVersion,

    # Test seam: reports `Test-Json -SchemaFile` as absent even where it exists.
    [switch]$SimulateMissingSchemaFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:MinimumVersion = [version]'7.6'
$script:SchemaRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'schemas/review'
$script:Dialect = 'https://json-schema.org/draft/2020-12/schema'
$script:IdPrefix = 'https://github.com/jIRI-san/skalary/schemas/review/'
$script:MaxStatusBytes = 8192

# The keywords that decide acceptance. Annotations (`title`, `description`, `$id`) are not proven
# because they assert nothing; `properties`, `items` and `$defs` are containers whose effect is only
# visible through the keywords inside them, and are proven by the instances that exercise those.
$script:AssertionKeyword = @(
    '$ref', 'additionalProperties', 'allOf', 'const', 'else', 'enum', 'if', 'items', 'maxItems',
    'maxLength', 'maximum', 'minItems', 'minLength', 'minimum', 'not', 'pattern', 'properties',
    'required', 'then', 'type', 'uniqueItems'
)

function Write-TerminalStatus {
    <#
    .SYNOPSIS
        Writes the one bounded terminal-status object this script is allowed to print, then exits.
    .DESCRIPTION
        D17: stdout carries exactly one JSON object of at most 8 KiB. Keys are ordinal-sorted and the
        object is compact, LF-terminated UTF-8 without BOM, written through the raw stdout stream so
        the bytes do not depend on the host's console encoding. Diagnostics are dropped from the end
        until the object fits rather than truncated mid-string, which would emit invalid JSON exactly
        when the diagnostics matter most.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][ValidateSet('capable', 'incapable')][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [string[]]$Diagnostic = @()
    )

    $trimmedMessage = $Message -replace '\s+', ' '
    if ($trimmedMessage.Length -gt 1024) { $trimmedMessage = $trimmedMessage.Substring(0, 1024) }

    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Diagnostic) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        if ($entries.Count -ge 16) { break }
        $flat = ([string]$item) -replace '\s+', ' '
        if ($flat.Length -gt 512) { $flat = $flat.Substring(0, 512) }
        $entries.Add($flat)
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $json = $null
    while ($true) {
        $status = [ordered]@{}
        if ($entries.Count -gt 0) { $status['diagnostics'] = @($entries) }
        $status['exitCode'] = $ExitCode
        $status['message'] = $trimmedMessage
        $status['mode'] = 'capability'
        $status['schema'] = 'skalary/review-terminal-status@1'
        $status['state'] = $State

        $json = ConvertTo-Json -InputObject $status -Depth 4 -Compress
        if ($utf8.GetByteCount($json) + 1 -le $script:MaxStatusBytes) { break }
        if ($entries.Count -gt 0) { $entries.RemoveAt($entries.Count - 1); continue }
        $trimmedMessage = $trimmedMessage.Substring(0, [Math]::Max(1, [int]($trimmedMessage.Length / 2)))
    }

    $bytes = $utf8.GetBytes($json + "`n")
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
    exit $ExitCode
}

function Get-SchemaKeywordInventory {
    <#
    .SYNOPSIS
        The assertion keywords a schema document actually uses.
    .DESCRIPTION
        Read from the parsed document rather than from a maintained list, so a schema that starts
        relying on a keyword nothing probes turns this gate red instead of trusting it.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][object]$Node)

    $found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $unknown = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $annotation = @('$schema', '$id', 'title', 'description', 'default', 'examples', '$comment')
    $visit = $null
    $visit = {
        param([object]$Schema)

        if ($Schema -is [bool] -or $Schema -isnot [System.Collections.IDictionary]) { return }
        foreach ($keyObject in @($Schema.Keys)) {
            $key = [string]$keyObject
            $value = $Schema[$keyObject]
            if ($script:AssertionKeyword -contains $key) {
                [void]$found.Add($key)
            }
            elseif ($annotation -notcontains $key -and $key -ne '$defs' -and $key -notlike 'x-skalary-*') {
                [void]$unknown.Add($key)
            }

            if ($key -in @('$defs', 'properties')) {
                foreach ($child in @($value.Values)) { & $visit $child }
            }
            elseif ($key -in @('allOf')) {
                foreach ($child in @($value)) { & $visit $child }
            }
            elseif ($key -in @('items', 'not', 'if', 'then', 'else')) {
                & $visit $value
            }
        }
    }
    & $visit $Node

    return [pscustomobject]@{
        Used = @($found | Sort-Object -CaseSensitive)
        Unknown = @($unknown | Sort-Object -CaseSensitive)
    }
}

function New-PlanInstance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([int]$TaskCount = 1)

    $tasks = @(1..$TaskCount | ForEach-Object {
            @{ taskId = ('t{0:d3}' -f $_); concern = 'security'; model = 'model-a' }
        })
    return @{
        schema = 'skalary/review-plan@1'
        runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
        reviewType = 'code'
        contentTrust = 'reviewer-authored-data'
        scope = '1 changed file'
        scopeAuthority = @{ mode = 'branch'; base = 'main'; head = 'HEAD'; paths = @(@{ path = 'README.md'; status = 'modified' }); digest = 'sha256:' + ('0' * 64) }
        roster = @('model-a')
        modelSelection = @(@{ requested = 'model-a'; declared = 'model-a'; preflight = 'available'; degradation = 'none'; servedIdentity = 'unverified' })
        invocationBudget = 1
        tasks = $tasks
    }
}

function New-RunInstance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        schema = 'skalary/review-run@1'
        runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
        reviewType = 'code'
        contentTrust = 'reviewer-authored-data'
        scope = '1 changed file'
        scopeAuthority = @{ mode = 'branch'; base = 'main'; head = 'HEAD'; paths = @(@{ path = 'README.md'; status = 'modified' }); digest = 'sha256:' + ('0' * 64) }
        roster = @('model-a')
        modelSelection   = @(@{ requested = 'model-a'; declared = 'model-a'; preflight = 'available'; degradation = 'none'; servedIdentity = 'unverified' })
        invocationBudget = 1
        planDigest       = 'sha256:' + ('0' * 64)
        tasks            = @(@{ taskId = 't001'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
        findings         = @(@{ taskId = 't001'; severity = 'High'; title = 'One finding' })
    }
}

function New-ManifestInstance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        schema       = 'skalary/review-manifest@1'
        runId        = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
        state        = 'published'
        contentTrust = 'reviewer-authored-data'
        scopeDigest  = 'sha256:' + ('0' * 64)
        planDigest   = 'sha256:' + ('0' * 64)
        runDigest    = 'sha256:' + ('1' * 64)
        files        = @{
            plan      = @{ name = 'review-plan.json'; digest = 'sha256:' + ('0' * 64); bytes = 128 }
            canonical = @{ name = 'review-run.0123456789abcdef.json'; digest = 'sha256:' + ('1' * 64); bytes = 256 }
            summary   = @{ name = 'summary.0123456789abcdef.md'; digest = 'sha256:' + ('2' * 64); bytes = 64 }
            full      = @{ name = 'full.0123456789abcdef.md'; digest = 'sha256:' + ('3' * 64); bytes = 512 }
        }
    }
}

function New-StatusInstance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        schema   = 'skalary/review-terminal-status@1'
        mode     = 'capability'
        exitCode = 0
        state    = 'capable'
        message  = 'probe'
    }
}

function New-AdmissionInstance {
    return @{
        schema        = 'skalary/review-admission@1'
        state         = 'admission'
        runId         = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
        mode          = 'freeze'
        reasons       = @('input-bytes-over-limit')
        restartable   = $false
        maxRestarts   = 1
        maxPartitions = 16
    }
}

function New-Probe {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Schema,
        [Parameter(Mandatory)][object]$Instance,
        [Parameter(Mandatory)][bool]$Expected,
        [Parameter(Mandatory)][string[]]$Proves
    )

    return [pscustomobject]@{ Id = $Id; Schema = $Schema; Instance = $Instance; Expected = $Expected; Proves = $Proves }
}

function Get-Probe {
    <#
    .SYNOPSIS
        Every probe, as data: one accepted instance or one rejected twin per feature.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $probes = [System.Collections.Generic.List[object]]::new()

    $plan = New-PlanInstance
    $probes.Add((New-Probe -Id 'plan-minimum-accepted' -Schema 'review-plan.schema.json' -Instance $plan -Expected $true -Proves @('type', 'properties', 'items', '$ref')))

    $planExtra = New-PlanInstance; $planExtra['taskCount'] = 1
    $probes.Add((New-Probe -Id 'plan-aggregate-property-rejected' -Schema 'review-plan.schema.json' -Instance $planExtra -Expected $false -Proves @('additionalProperties')))

    $planVersion = New-PlanInstance; $planVersion['schema'] = 'skalary/review-plan@2'
    $probes.Add((New-Probe -Id 'plan-unknown-version-rejected' -Schema 'review-plan.schema.json' -Instance $planVersion -Expected $false -Proves @('const')))

    $planNoTasks = New-PlanInstance; $planNoTasks['tasks'] = @()
    $probes.Add((New-Probe -Id 'plan-zero-tasks-rejected' -Schema 'review-plan.schema.json' -Instance $planNoTasks -Expected $false -Proves @('minItems')))

    $planTooMany = New-PlanInstance -TaskCount 129
    $probes.Add((New-Probe -Id 'plan-one-above-task-maximum-rejected' -Schema 'review-plan.schema.json' -Instance $planTooMany -Expected $false -Proves @('maxItems')))

    $planMaximum = New-PlanInstance -TaskCount 128
    $probes.Add((New-Probe -Id 'plan-task-maximum-accepted' -Schema 'review-plan.schema.json' -Instance $planMaximum -Expected $true -Proves @('maxItems')))

    $planDuplicate = New-PlanInstance
    $planDuplicate['tasks'] = @(
        @{ taskId = 't001'; concern = 'security'; model = 'model-a' }
        @{ taskId = 't001'; concern = 'security'; model = 'model-a' }
    )
    $probes.Add((New-Probe -Id 'plan-identical-task-rejected' -Schema 'review-plan.schema.json' -Instance $planDuplicate -Expected $false -Proves @('uniqueItems')))

    $planRunId = New-PlanInstance; $planRunId['runId'] = '8F3C1D2E-5A47-4B90-9C61-2D7E0F4A6B35'
    $probes.Add((New-Probe -Id 'plan-uppercase-run-id-rejected' -Schema 'review-plan.schema.json' -Instance $planRunId -Expected $false -Proves @('pattern')))

    $planEmptyScope = New-PlanInstance; $planEmptyScope['scope'] = ''
    $probes.Add((New-Probe -Id 'plan-empty-scope-rejected' -Schema 'review-plan.schema.json' -Instance $planEmptyScope -Expected $false -Proves @('minLength')))

    $planLongScope = New-PlanInstance; $planLongScope['scope'] = 'a' * 1025
    $probes.Add((New-Probe -Id 'plan-one-above-scope-maximum-rejected' -Schema 'review-plan.schema.json' -Instance $planLongScope -Expected $false -Proves @('maxLength')))

    $planZeroBudget = New-PlanInstance; $planZeroBudget['invocationBudget'] = 0
    $probes.Add((New-Probe -Id 'plan-zero-budget-rejected' -Schema 'review-plan.schema.json' -Instance $planZeroBudget -Expected $false -Proves @('minimum')))

    $planHighBudget = New-PlanInstance; $planHighBudget['invocationBudget'] = 129
    $probes.Add((New-Probe -Id 'plan-one-above-budget-maximum-rejected' -Schema 'review-plan.schema.json' -Instance $planHighBudget -Expected $false -Proves @('maximum')))

    $planFractional = New-PlanInstance; $planFractional['invocationBudget'] = 1.5
    $probes.Add((New-Probe -Id 'plan-fractional-budget-rejected' -Schema 'review-plan.schema.json' -Instance $planFractional -Expected $false -Proves @('type')))

    $planMissing = New-PlanInstance; $planMissing.Remove('runId')
    $probes.Add((New-Probe -Id 'plan-missing-run-id-rejected' -Schema 'review-plan.schema.json' -Instance $planMissing -Expected $false -Proves @('required')))

    $run = New-RunInstance
    $probes.Add((New-Probe -Id 'run-minimum-accepted' -Schema 'review-run.schema.json' -Instance $run -Expected $true -Proves @('type', 'properties', 'items', '$ref')))

    $runNoFindings = New-RunInstance; $runNoFindings['findings'] = @()
    $probes.Add((New-Probe -Id 'run-completed-without-findings-accepted' -Schema 'review-run.schema.json' -Instance $runNoFindings -Expected $true -Proves @('minItems')))

    $runOutcome = New-RunInstance
    $runOutcome['tasks'] = @(@{ taskId = 't001'; concern = 'security'; model = 'model-a'; outcome = 'skipped'; diagnostic = 'd' })
    $runOutcome['findings'] = @()
    $probes.Add((New-Probe -Id 'run-unknown-outcome-rejected' -Schema 'review-run.schema.json' -Instance $runOutcome -Expected $false -Proves @('enum')))

    $runCompletedDiagnostic = New-RunInstance
    $runCompletedDiagnostic['tasks'] = @(@{ taskId = 't001'; concern = 'security'; model = 'model-a'; outcome = 'completed'; diagnostic = 'd' })
    $probes.Add((New-Probe -Id 'run-completed-with-diagnostic-rejected' -Schema 'review-run.schema.json' -Instance $runCompletedDiagnostic -Expected $false -Proves @('if', 'then', 'not')))

    $runFailedBare = New-RunInstance
    $runFailedBare['tasks'] = @(@{ taskId = 't001'; concern = 'security'; model = 'model-a'; outcome = 'failed' })
    $runFailedBare['findings'] = @()
    $probes.Add((New-Probe -Id 'run-failed-without-diagnostic-rejected' -Schema 'review-run.schema.json' -Instance $runFailedBare -Expected $false -Proves @('if', 'else')))

    $runFailedDiagnostic = New-RunInstance
    $runFailedDiagnostic['tasks'] = @(@{ taskId = 't001'; concern = 'security'; model = 'model-a'; outcome = 'failed'; diagnostic = 'reviewer returned no parsable output' })
    $runFailedDiagnostic['findings'] = @()
    $probes.Add((New-Probe -Id 'run-failed-with-diagnostic-accepted' -Schema 'review-run.schema.json' -Instance $runFailedDiagnostic -Expected $true -Proves @('if', 'else')))

    $runAggregate = New-RunInstance; $runAggregate['completedCount'] = 1
    $probes.Add((New-Probe -Id 'run-aggregate-spoof-rejected' -Schema 'review-run.schema.json' -Instance $runAggregate -Expected $false -Proves @('additionalProperties')))

    $runLongTitle = New-RunInstance
    $runLongTitle['findings'] = @(@{ taskId = 't001'; severity = 'High'; title = 'a' * 161 })
    $probes.Add((New-Probe -Id 'run-one-above-title-maximum-rejected' -Schema 'review-run.schema.json' -Instance $runLongTitle -Expected $false -Proves @('maxLength')))

    $runManyReferences = New-RunInstance
    $runManyReferences['findings'] = @(@{ taskId = 't001'; severity = 'High'; title = 'One finding'; references = @(1..9 | ForEach-Object { "src/file$_.ps1" }) })
    $probes.Add((New-Probe -Id 'run-one-above-reference-maximum-rejected' -Schema 'review-run.schema.json' -Instance $runManyReferences -Expected $false -Proves @('maxItems')))

    $manifest = New-ManifestInstance
    $probes.Add((New-Probe -Id 'manifest-minimum-accepted' -Schema 'review-manifest.schema.json' -Instance $manifest -Expected $true -Proves @('type', 'properties', '$ref')))

    $manifestTraversal = New-ManifestInstance
    $manifestTraversal['files']['canonical']['name'] = '../review-run.json'
    $probes.Add((New-Probe -Id 'manifest-traversal-name-rejected' -Schema 'review-manifest.schema.json' -Instance $manifestTraversal -Expected $false -Proves @('pattern')))

    $manifestMissingRole = New-ManifestInstance
    $manifestMissingRole['files'].Remove('full')
    $probes.Add((New-Probe -Id 'manifest-missing-role-rejected' -Schema 'review-manifest.schema.json' -Instance $manifestMissingRole -Expected $false -Proves @('required')))

    $manifestExtraRole = New-ManifestInstance
    $manifestExtraRole['files']['scratch'] = @{ name = 'scratch.json'; digest = 'sha256:' + ('4' * 64); bytes = 1 }
    $probes.Add((New-Probe -Id 'manifest-unknown-role-rejected' -Schema 'review-manifest.schema.json' -Instance $manifestExtraRole -Expected $false -Proves @('additionalProperties')))

    $status = New-StatusInstance
    $probes.Add((New-Probe -Id 'status-capability-accepted' -Schema 'terminal-status.schema.json' -Instance $status -Expected $true -Proves @('allOf', 'if', 'then', 'else')))

    $statusRunId = New-StatusInstance; $statusRunId['runId'] = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
    $probes.Add((New-Probe -Id 'status-capability-with-run-id-rejected' -Schema 'terminal-status.schema.json' -Instance $statusRunId -Expected $false -Proves @('not', 'if', 'then')))

    $statusMismatch = New-StatusInstance; $statusMismatch['exitCode'] = 2
    $probes.Add((New-Probe -Id 'status-exit-state-mismatch-rejected' -Schema 'terminal-status.schema.json' -Instance $statusMismatch -Expected $false -Proves @('allOf', 'enum')))

    $statusFreezeDegraded = @{
        schema = 'skalary/review-terminal-status@1'; mode = 'freeze'
        runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'; exitCode = 5
        state = 'degraded'; message = 'invalid freeze status'
    }
    $probes.Add((New-Probe -Id 'status-freeze-degraded-rejected' -Schema 'terminal-status.schema.json' -Instance $statusFreezeDegraded -Expected $false -Proves @('allOf', 'if', 'then', 'enum')))

    $admission = New-AdmissionInstance
    $probes.Add((New-Probe -Id 'admission-minimum-accepted' -Schema 'review-admission.schema.json' -Instance $admission -Expected $true -Proves @('allOf', 'if', 'then', 'else')))
    $admissionUnbound = New-AdmissionInstance; $admissionUnbound['restartable'] = $true
    $probes.Add((New-Probe -Id 'admission-restart-without-source-rejected' -Schema 'review-admission.schema.json' -Instance $admissionUnbound -Expected $false -Proves @('required', 'if', 'then')))

    return $probes.ToArray()
}

# --- capability, explicitly and in two parts -------------------------------------------------
$version = $PSVersionTable.PSVersion
if (-not [string]::IsNullOrWhiteSpace($SimulateVersion)) {
    $simulated = $null
    if (-not [version]::TryParse($SimulateVersion, [ref]$simulated)) {
        Write-TerminalStatus -ExitCode 2 -State 'incapable' -Message "-SimulateVersion '$SimulateVersion' is not a version." -Diagnostic @('simulate-version-unparsable')
    }
    if ($simulated -lt $version) { $version = $simulated }
}

$testJson = Get-Command -Name 'Test-Json' -ErrorAction SilentlyContinue
$hasSchemaFile = ($null -ne $testJson) -and $testJson.Parameters.ContainsKey('SchemaFile') -and (-not $SimulateMissingSchemaFile)

$absent = [System.Collections.Generic.List[string]]::new()
if ($version -lt $script:MinimumVersion) {
    $absent.Add("powershell-below-minimum: host reports $version, review schema validation requires $($script:MinimumVersion) or newer")
}
if (-not $hasSchemaFile) {
    $absent.Add('test-json-schemafile-absent: Test-Json on this host exposes no -SchemaFile parameter')
}

if ($absent.Count -gt 0) {
    Write-TerminalStatus -ExitCode 2 -State 'incapable' `
        -Message "Review schema validation is unavailable on this host; no review run may be dispatched from it." `
        -Diagnostic $absent
}

# --- the committed schemas, on this host ------------------------------------------------------
$failures = [System.Collections.Generic.List[string]]::new()
$schemaFiles = @('review-plan.schema.json', 'review-run.schema.json', 'review-manifest.schema.json', 'review-admission.schema.json', 'terminal-status.schema.json')
$usedKeywords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

foreach ($name in $schemaFiles) {
    $path = Join-Path $script:SchemaRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("schema-missing: $name")
        continue
    }

    $document = $null
    try { $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 30 }
    catch {
        $failures.Add("schema-unparsable: $name - $($_.Exception.Message)")
        continue
    }

    if ([string]$document['$schema'] -ne $script:Dialect) {
        $failures.Add("schema-dialect: $name declares '$($document['$schema'])' rather than draft 2020-12")
    }
    if ([string]$document['$id'] -ne ($script:IdPrefix + $name)) {
        $failures.Add("schema-id: $name declares '$($document['$id'])' rather than its repository URL")
    }
    if ($document['additionalProperties'] -ne $false) {
        $failures.Add("schema-open-root: $name does not close its root object")
    }

    $keywordInventory = Get-SchemaKeywordInventory -Node $document
    foreach ($keyword in $keywordInventory.Used) { [void]$usedKeywords.Add($keyword) }
    foreach ($keyword in $keywordInventory.Unknown) {
        $failures.Add("keyword-unknown: $name uses '$keyword', which this preflight does not classify or prove")
    }
}

if ($failures.Count -gt 0) {
    Write-TerminalStatus -ExitCode 2 -State 'incapable' `
        -Message 'The committed review schemas did not load as the contract requires.' -Diagnostic $failures
}

# --- every keyword those schemas rely on, proven against them ---------------------------------
$probes = @(Get-Probe)
$proven = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

foreach ($probe in $probes) {
    $json = ConvertTo-Json -InputObject $probe.Instance -Depth 30
    $schemaPath = Join-Path $script:SchemaRoot $probe.Schema
    $actual = $false
    try { $actual = [bool](Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction SilentlyContinue) }
    catch {
        $failures.Add("probe-error: $($probe.Id) - $($probe.Schema) raised $($_.Exception.GetType().Name)")
        continue
    }

    if ($actual -ne $probe.Expected) {
        $verdict = if ($probe.Expected) { 'accepted' } else { 'rejected' }
        $failures.Add("probe-failed: $($probe.Id) - $($probe.Schema) should have $verdict this instance")
        continue
    }

    foreach ($keyword in $probe.Proves) { [void]$proven.Add($keyword) }
}

$unproven = @($usedKeywords | Where-Object { -not $proven.Contains($_) } | Sort-Object -CaseSensitive)
foreach ($keyword in $unproven) {
    $failures.Add("keyword-unproven: the committed schemas use '$keyword' and no probe demonstrates it on this host")
}

if ($failures.Count -gt 0) {
    Write-TerminalStatus -ExitCode 2 -State 'incapable' `
        -Message 'This host does not implement every JSON Schema feature the review contract depends on.' `
        -Diagnostic $failures
}

# The status object this script itself emits is part of the contract, so it is validated by the
# schema that owns it rather than trusted.
$selfCheck = @{
    schema = 'skalary/review-terminal-status@1'
    mode = 'capability'
    exitCode = 0
    state = 'capable'
    message = 'self-check'
}
if (-not (Test-Json -Json (ConvertTo-Json -InputObject $selfCheck -Depth 4) -SchemaFile (Join-Path $script:SchemaRoot 'terminal-status.schema.json') -ErrorAction SilentlyContinue)) {
    Write-TerminalStatus -ExitCode 2 -State 'incapable' `
        -Message 'The terminal-status schema rejected this script''s own status object.' -Diagnostic @('self-check-failed')
}

$platform = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } elseif ($IsMacOS) { 'macOS' } else { 'unknown' }
Write-TerminalStatus -ExitCode 0 -State 'capable' `
    -Message ("PowerShell $($PSVersionTable.PSVersion) on ${platform}: $($schemaFiles.Count) schema(s), $($probes.Count) probe(s), $($usedKeywords.Count) keyword(s) proven.")

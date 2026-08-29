#requires -Version 7.0
<#
.SYNOPSIS
    Child-process worker for test:ReviewReport.MaximumEnvelopeBudget.
.DESCRIPTION
    Plan c21cdc REQ-12/D6, step 1.2. Runs in its own process so the parent can sample its private
    bytes: it builds the largest structurally legal envelope from the committed recipe, freezes the
    matching plan and publishes the result, timing the publish with a Stopwatch, then writes a result
    record (OS/PowerShell identity, exit codes, wall clock, rendered view sizes) for the parent to
    assert against. It never skips: an unbuildable or unpublishable envelope is a failure, not a pass.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ModulePath,
    [Parameter(Mandatory)][string]$SpecPath,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module $ModulePath -Force -DisableNameChecking

function New-Filler {
    param([Parameter(Mandatory)][int]$Length, [Parameter(Mandatory)][string]$Seed)
    $builder = [System.Text.StringBuilder]::new()
    while ($builder.Length -lt $Length) { [void]$builder.Append("$Seed-") }
    return $builder.ToString(0, $Length)
}

$spec = Get-Content -LiteralPath $SpecPath -Raw | ConvertFrom-Json -AsHashtable -Depth 40
$g = $spec.generation
$similaritySeed = 'alpha-bravo-charlie-delta-echo-foxtrot-golf-hotel-india-juliet-kilo-lima-mike-november-oscar-papa-quebec-romeo-sierra-tango'

$roster = @(1..$g.rosterModels | ForEach-Object { New-Filler -Length $g.modelLength -Seed "model-$_" })

$planTasks = @(1..$g.tasks | ForEach-Object {
        [ordered]@{ concern = ('concern-{0:d3}' -f $_); model = $roster[($_ - 1) % $g.rosterModels]; taskId = ('t{0:d3}' -f $_) }
    })
$resultTasks = @(1..$g.tasks | ForEach-Object {
        $task = [ordered]@{
            concern = ('concern-{0:d3}' -f $_)
            model = $roster[($_ - 1) % $g.rosterModels]
            outcome = $(if ($_ -le $g.diagnosticTasks) { 'failed' } else { 'completed' })
            taskId = ('t{0:d3}' -f $_)
        }
        if ($_ -le $g.diagnosticTasks) { $task['diagnostic'] = New-Filler -Length $g.diagnosticLength -Seed "diagnostic-$_" }
        $task
    })
$findings = @(1..$g.findings | ForEach-Object {
        $index = $_
        $group = ('{0:d3}' -f ((($index - 1) % $g.mergedGroups) + 1))
        $groupOccurrence = [Math]::Floor(($index - 1) / $g.mergedGroups)
        $taskOrdinal = [int]($g.diagnosticTasks + 1 + ($groupOccurrence % 2))
        [ordered]@{
            action = New-Filler -Length $g.actionLength -Seed "$similaritySeed-action-$index"
            body = New-Filler -Length $g.bodyLength -Seed "$similaritySeed-body-$index"
            component = New-Filler -Length $g.componentLength -Seed "component-$group"
            references = @(1..$g.references | ForEach-Object { New-Filler -Length $g.referenceLength -Seed "ref-$index-$_" })
            rootCause = New-Filler -Length $g.rootCauseLength -Seed "root-$group"
            severity = 'Critical'
            taskId = ('t{0:d3}' -f $taskOrdinal)
            title = New-Filler -Length $g.titleLength -Seed "$similaritySeed-title-$index"
        }
    })

$scopeAuthority = [ordered]@{ mode = 'paths'; paths = @([ordered]@{ path = 'README.md'; status = 'modified' }) }
$scopeAuthority['digest'] = Get-ReviewScopeDigest -ScopeAuthority $scopeAuthority
$modelSelection = @($roster | ForEach-Object { [ordered]@{ requested = $_; declared = $_; preflight = 'available'; degradation = 'none'; servedIdentity = 'unverified' } })
$plan = [ordered]@{
    schema = 'skalary/review-plan@1'; runId = $RunId; reviewType = 'code'
    contentTrust = 'reviewer-authored-data'
    scope = New-Filler -Length $g.scopeLength -Seed 'scope'; roster = $roster
    scopeAuthority = $scopeAuthority; modelSelection = $modelSelection
    invocationBudget = $g.invocationBudget; tasks = $planTasks
}

$runDir = Join-Path $RepoRoot ".github/.skalary/review-runs/$RunId"
[void](New-Item -ItemType Directory -Path $runDir -Force)
# D16: the caller writes its `.tmp` and atomically renames it onto the fixed input name. The JSON is
# compact because the recipe's byte arithmetic is compact-JSON arithmetic: an indented copy of the
# maximum envelope would be over the 2 MiB input admission cap and would be rejected before the
# render budget this fixture exists to measure.
$planTmp = Join-Path $runDir '.review-plan.input.tmp'
Set-Content -LiteralPath $planTmp -Value (ConvertTo-Json -InputObject $plan -Depth 40 -Compress) -NoNewline
[System.IO.File]::Move($planTmp, (Join-Path $runDir 'review-plan.input.json'), $true)
$freeze = Invoke-ReviewFreeze -RunId $RunId -RepoRoot $RepoRoot
$planFile = @(Get-ChildItem -LiteralPath $runDir -File -Force | Where-Object { $_.Name -cmatch '^review-plan\.[0-9a-f]{64}\.json$' })[0]
$planDigest = 'sha256:' + ((([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.IO.File]::ReadAllBytes($planFile.FullName))) | ForEach-Object { $_.ToString('x2') }) -join '')

$run = [ordered]@{
    schema = 'skalary/review-run@1'; runId = $RunId; reviewType = 'code'
    contentTrust = 'reviewer-authored-data'
    scope = New-Filler -Length $g.scopeLength -Seed 'scope'; roster = $roster
    scopeAuthority = $scopeAuthority; modelSelection = $modelSelection
    invocationBudget = $g.invocationBudget; planDigest = $planDigest
    tasks = $resultTasks; findings = $findings
}
$resultJson = ConvertTo-Json -InputObject $run -Depth 40 -Compress
$inputBytes = [System.Text.Encoding]::UTF8.GetByteCount($resultJson)
$resultTmp = Join-Path $runDir '.review-result.input.tmp'
Set-Content -LiteralPath $resultTmp -Value $resultJson -NoNewline
[System.IO.File]::Move($resultTmp, (Join-Path $runDir 'review-result.input.json'), $true)
$resultJson = $null

# Record the summary size (it fits, D5) directly; the full view size comes back from the admission
# diagnostic so we do not hold a second 1.8 MiB string alongside the publish allocations.
$projection = ConvertTo-ReviewProjection -Run $run
$suspiciousFindings = @($projection.Findings | Where-Object { $_.CorroborationState -eq 'suspicious' }).Count
$summaryBytes = [System.Text.Encoding]::UTF8.GetByteCount((Get-ReviewRunSummaryView -Run $run))

# Free the in-memory envelope the harness built so the sampled growth is the publication's own cost —
# reading the input from disk, canonicalizing, rendering both views and deciding admission — rather
# than the test harness's hashtable construction.
$plan = $null; $run = $null; $findings = $null; $resultTasks = $null; $planTasks = $null; $roster = $null; $scopeAuthority = $null; $modelSelection = $null
[System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()

$baseline = [System.Diagnostics.Process]::GetCurrentProcess().PrivateMemorySize64
$stopFlag = Join-Path $RepoRoot 'budget-sampler-stop'
Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue
# A same-process sampler thread reads this worker's private bytes while the main thread publishes, so
# the peak is captured by sampling rather than a single before/after reading.
$sampler = Start-ThreadJob -ScriptBlock {
    param($stop)
    $peak = 0
    while (-not (Test-Path -LiteralPath $stop)) {
        $sample = [int64][System.Diagnostics.Process]::GetCurrentProcess().PrivateMemorySize64
        if ($sample -gt $peak) { $peak = $sample }
        Start-Sleep -Milliseconds 15
    }
    return $peak
} -ArgumentList $stopFlag

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$publish = Invoke-ReviewPublish -RunId $RunId -RepoRoot $RepoRoot
$stopwatch.Stop()

Set-Content -LiteralPath $stopFlag -Value 'stop' -NoNewline
# Waited, received and removed in three explicit steps: `-AutoRemoveJob` races the thread job's own
# child-job teardown and intermittently fails the whole worker with "cannot remove the job", which
# would report a publication failure that never happened.
[void](Wait-Job -Job $sampler -Timeout 60)
$peak = [int64](@(Receive-Job -Job $sampler) | Select-Object -Last 1)
Remove-Job -Job $sampler -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue
$growthBytes = [Math]::Max(0, $peak - $baseline)

# The full view size is reported inside the admission diagnostic (never truncated).
$fullBytes = 0
foreach ($d in @($publish.Diagnostics)) {
    $m = [regex]::Match([string]$d, 'full view is (?<n>\d+) bytes')
    if ($m.Success) { $fullBytes = [int64]$m.Groups['n'].Value }
}

$result = [ordered]@{
    schema = 'skalary/review-max-envelope-budget@1'
    os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    isWindows = $IsWindows
    powerShell = $PSVersionTable.PSVersion.ToString()
    pid = $PID
    freezeExit = $freeze.ExitCode
    publishExit = $publish.ExitCode
    publishState = $publish.State
    publishSeconds = $stopwatch.Elapsed.TotalSeconds
    tasks = $g.tasks
    findings = $g.findings
    inputBytes = $inputBytes
    summaryBytes = $summaryBytes
    suspiciousFindings = $suspiciousFindings
    fullBytes = $fullBytes
    baselinePrivateBytes = $baseline
    peakPrivateBytes = $peak
    publishGrowthBytes = $growthBytes
}
Set-Content -LiteralPath $ResultPath -Value (ConvertTo-Json -InputObject $result -Depth 5) -NoNewline

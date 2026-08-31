#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$script:StateFields = @('epic', 'target', 'currentChild', 'branch', 'run', 'outcome')
$script:PortableExitCodePattern = '^(?:0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'

function ConvertFrom-EpicAutopilotStateJson {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    try {
        $document = [System.Text.Json.JsonDocument]::Parse($Json)
    }
    catch {
        throw "Epic autopilot state is malformed JSON: $($_.Exception.Message)"
    }

    try {
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw 'Epic autopilot state must be one JSON object.'
        }

        $properties = @($document.RootElement.EnumerateObject())
        if ($properties.Count -ne $script:StateFields.Count) {
            throw "Epic autopilot state must contain exactly: $($script:StateFields -join ', ')."
        }

        $seen = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $values = [ordered]@{}
        foreach ($property in $properties) {
            if (-not $seen.Add($property.Name) -or $script:StateFields -cnotcontains $property.Name) {
                throw "Epic autopilot state has an unexpected or duplicate field '$($property.Name)'."
            }
            if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                throw "Epic autopilot state field '$($property.Name)' must be a string."
            }
            $values[$property.Name] = $property.Value.GetString()
        }

        foreach ($field in $script:StateFields) {
            if (-not $seen.Contains($field)) {
                throw "Epic autopilot state is missing field '$field'."
            }
        }

        if ($values.epic -cnotmatch '^[0-9a-f]{6}$') {
            throw "Epic autopilot state field 'epic' must be a canonical six-character id."
        }
        if ($values.target -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
            throw "Epic autopilot state field 'target' must be a full Git commit id."
        }
        if ($values.currentChild -cnotmatch '^[0-9a-f]{6}$') {
            throw "Epic autopilot state field 'currentChild' must be a canonical six-character id."
        }
        if ($values.branch -cnotmatch '^feature/[a-z0-9][a-z0-9-]*$') {
            throw "Epic autopilot state field 'branch' is invalid."
        }
        $parsedRun = [guid]::Empty
        if (-not [guid]::TryParseExact($values.run, 'D', [ref]$parsedRun) -or
            $parsedRun.ToString('D') -cne $values.run) {
            throw "Epic autopilot state field 'run' must be a canonical GUID."
        }
        if ($values.outcome -cnotin @(
                'selected', 'running', 'awaiting-merge', 'invocation-failed'
            )) {
            if (-not $values.outcome.StartsWith('exit:', [System.StringComparison]::Ordinal) -or
                $values.outcome.Substring(5) -cnotmatch $script:PortableExitCodePattern) {
                throw "Epic autopilot state field 'outcome' is invalid."
            }
        }

        return [pscustomobject]$values
    }
    finally {
        $document.Dispose()
    }
}

function Read-EpicAutopilotState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return ConvertFrom-EpicAutopilotStateJson -Json ([System.IO.File]::ReadAllText($Path))
}

function ConvertFrom-EpicRollupJson {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    try {
        $rollup = $Json | ConvertFrom-Json -Depth 20
    }
    catch {
        throw "Get-PlanState returned malformed epic JSON: $($_.Exception.Message)"
    }
    if ($null -eq $rollup -or $rollup -is [array] -or
        $rollup.PSObject.Properties.Name -notcontains 'Kind' -or $rollup.Kind -cne 'epic') {
        throw "Get-PlanState did not return an epic rollup (Kind must be 'epic')."
    }
    if ($rollup.PSObject.Properties.Name -notcontains 'EpicId' -or
        $rollup.EpicId -isnot [string] -or
        [string]$rollup.EpicId -cnotmatch '^[0-9a-f]{6}$') {
        throw 'Get-PlanState returned an invalid canonical EpicId.'
    }
    if ($rollup.PSObject.Properties.Name -notcontains 'NextChild') {
        throw 'Get-PlanState epic rollup is missing NextChild.'
    }
    if ($rollup.PSObject.Properties.Name -notcontains 'Rollup' -or
        $null -eq $rollup.Rollup -or
        $rollup.Rollup -isnot [pscustomobject]) {
        throw 'Get-PlanState epic rollup is missing Rollup.'
    }
    foreach ($field in @('ChildCount', 'CompleteCount', 'BlockedCount')) {
        if ($rollup.Rollup.PSObject.Properties.Name -notcontains $field -or
            $rollup.Rollup.$field -isnot [long] -or
            [long]$rollup.Rollup.$field -lt 0) {
            throw "Get-PlanState Rollup.$field must be a nonnegative integer."
        }
    }
    if ($rollup.Rollup.PSObject.Properties.Name -notcontains 'IsComplete' -or
        $rollup.Rollup.IsComplete -isnot [bool]) {
        throw 'Get-PlanState Rollup.IsComplete must be boolean.'
    }
    if ($rollup.PSObject.Properties.Name -notcontains 'Children') {
        throw 'Get-PlanState epic rollup is missing Children.'
    }
    $children = @($rollup.Children)
    $childIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $completeCount = 0
    $blockedCount = 0
    $expectedNextChild = $null
    foreach ($child in $children) {
        if ($null -eq $child -or $child -isnot [pscustomobject]) {
            throw 'Get-PlanState Children must contain child objects.'
        }
        foreach ($field in @('Id', 'IsComplete', 'IsBlocked')) {
            if ($child.PSObject.Properties.Name -notcontains $field) {
                throw "Get-PlanState child is missing '$field'."
            }
        }
        if ($child.Id -isnot [string] -or
            [string]$child.Id -cnotmatch '^[0-9a-f]{6}$') {
            throw 'Get-PlanState child has an invalid canonical Id.'
        }
        if (-not $childIds.Add([string]$child.Id)) {
            throw "Get-PlanState Children contains duplicate Id '$($child.Id)'."
        }
        if ($child.IsComplete -isnot [bool] -or $child.IsBlocked -isnot [bool]) {
            throw 'Get-PlanState child completion and block fields must be boolean.'
        }
        if ([bool]$child.IsComplete -and [bool]$child.IsBlocked) {
            throw "Get-PlanState child '$($child.Id)' cannot be both complete and blocked."
        }
        if ([bool]$child.IsComplete) {
            $completeCount++
        }
        elseif ([bool]$child.IsBlocked) {
            $blockedCount++
        }
        elseif ($null -eq $expectedNextChild) {
            $expectedNextChild = $child
        }
    }

    $derivedCounts = [ordered]@{
        ChildCount    = $children.Count
        CompleteCount = $completeCount
        BlockedCount  = $blockedCount
    }
    foreach ($field in $derivedCounts.Keys) {
        if ([long]$rollup.Rollup.$field -ne [long]$derivedCounts[$field]) {
            throw "Get-PlanState Rollup.$field does not match Children (expected $($derivedCounts[$field]))."
        }
    }
    $expectedIsComplete = $children.Count -gt 0 -and
    $completeCount -eq $children.Count
    if ([bool]$rollup.Rollup.IsComplete -ne $expectedIsComplete) {
        throw "Get-PlanState Rollup.IsComplete does not match Children (expected $expectedIsComplete)."
    }

    if ($null -ne $rollup.NextChild) {
        if ($rollup.NextChild -isnot [pscustomobject]) {
            throw 'Get-PlanState NextChild must be one child object or null.'
        }
        foreach ($field in @('Id', 'FolderName')) {
            if ($rollup.NextChild.PSObject.Properties.Name -notcontains $field) {
                throw "Get-PlanState NextChild is missing '$field'."
            }
        }
        if ($rollup.NextChild.Id -isnot [string] -or
            [string]$rollup.NextChild.Id -cnotmatch '^[0-9a-f]{6}$') {
            throw 'Get-PlanState NextChild has an invalid canonical Id.'
        }
        if ($rollup.NextChild.FolderName -isnot [string] -or
            [string]$rollup.NextChild.FolderName -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
            throw 'Get-PlanState NextChild has an invalid FolderName.'
        }
        if ($null -eq $expectedNextChild) {
            throw 'Get-PlanState NextChild is non-null but no child is eligible.'
        }
        if ([string]$rollup.NextChild.Id -cne [string]$expectedNextChild.Id) {
            throw "Get-PlanState NextChild must be the first incomplete, unblocked child '$($expectedNextChild.Id)'."
        }
        if ($expectedNextChild.PSObject.Properties.Name -contains 'FolderName' -and (
                $expectedNextChild.FolderName -isnot [string] -or
                [string]$expectedNextChild.FolderName -cne
                [string]$rollup.NextChild.FolderName
            )) {
            throw "Get-PlanState NextChild FolderName does not match child '$($expectedNextChild.Id)'."
        }
    }
    elseif ($null -ne $expectedNextChild) {
        throw "Get-PlanState NextChild is null but child '$($expectedNextChild.Id)' is eligible."
    }
    return $rollup
}

function Resolve-EpicAutopilotStatePath {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$StatePath
    )

    if ($StatePath) {
        return [System.IO.Path]::GetFullPath($StatePath)
    }

    $gitCommonDir = @(& git -C $RepoRoot rev-parse --git-common-dir 2>&1)
    if ($LASTEXITCODE -ne 0 -or $gitCommonDir.Count -ne 1) {
        throw "Unable to resolve the Git common directory: $(($gitCommonDir -join ' ').Trim())"
    }
    $common = [string]$gitCommonDir[0]
    if (-not [System.IO.Path]::IsPathRooted($common)) {
        $common = Join-Path $RepoRoot $common
    }
    return [System.IO.Path]::GetFullPath(
        (Join-Path $common 'skalary/epic-autopilot.json')
    )
}

function New-EpicAutopilotState {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Outcome
    )

    return [pscustomobject][ordered]@{
        epic         = [string]$State.epic
        target       = [string]$State.target
        currentChild = [string]$State.currentChild
        branch       = [string]$State.branch
        run          = [string]$State.run
        outcome      = $Outcome
    }
}

function ConvertTo-EpicAutopilotStateJson {
    param([Parameter(Mandatory)]$State)

    $content = $State | ConvertTo-Json -Compress
    [void](ConvertFrom-EpicAutopilotStateJson -Json $content)
    return $content
}

function Set-EpicAutopilotState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$ExpectedGeneration,
        [Parameter(Mandatory)][string]$Operation
    )

    $write = Set-AtomicStoreContent -Path $Path `
        -Content (ConvertTo-EpicAutopilotStateJson -State $State) `
        -ExpectedGeneration $ExpectedGeneration -Validate {
        param($candidatePath)
        [void](ConvertFrom-EpicAutopilotStateJson -Json (
                [System.IO.File]::ReadAllText($candidatePath)
            ))
    }
    if ($write.Status -ne 'complete') {
        throw "Epic autopilot $Operation failed with status '$($write.Status)'."
    }
    return $write
}

function Remove-EpicAutopilotState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedGeneration
    )

    $actualGeneration = Get-AtomicStoreGeneration -Path $Path
    if (-not [string]::Equals(
            $actualGeneration,
            $ExpectedGeneration,
            [System.StringComparison]::Ordinal
        )) {
        return [pscustomobject]@{
            Status             = 'cas-conflict'
            Path               = $Path
            ExpectedGeneration = $ExpectedGeneration
            ActualGeneration   = $actualGeneration
        }
    }

    Remove-Item -LiteralPath $Path -Force
    return [pscustomobject]@{
        Status = 'complete'
        Path   = $Path
    }
}

function Test-EpicAutopilotAncestor {
    param(
        [Parameter(Mandatory)][string]$Ancestor,
        [Parameter(Mandatory)][string]$Descendant,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    & git -C $RepoRoot merge-base --is-ancestor $Ancestor $Descendant 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return $true
    }
    if ($LASTEXITCODE -eq 1) {
        return $false
    }
    throw "Unable to prove target ancestry from '$Ancestor' to '$Descendant'."
}

function Test-EpicAutopilotStateIdentity {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected
    )

    foreach ($field in @('epic', 'target', 'currentChild', 'branch', 'run')) {
        if ([string]$Actual.$field -cne [string]$Expected.$field) {
            return $false
        }
    }
    return $true
}

function Set-EpicAutopilotTerminalState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$RunningState,
        [Parameter(Mandatory)][string]$RunningGeneration,
        [Parameter(Mandatory)][string]$Outcome
    )

    return Invoke-WithAtomicStoreLock -Scope $Path -Action {
        $generation = Get-AtomicStoreGeneration -Path $Path
        $current = Read-EpicAutopilotState -Path $Path
        if ($null -eq $current -or
            $generation -cne $RunningGeneration -or
            -not (Test-EpicAutopilotStateIdentity -Actual $current -Expected $RunningState) -or
            $current.outcome -cne 'running') {
            throw 'Epic autopilot running state changed before its terminal result could be persisted.'
        }

        $terminal = New-EpicAutopilotState -State $current -Outcome $Outcome
        [void](Set-EpicAutopilotState -Path $Path -State $terminal `
                -ExpectedGeneration $RunningGeneration -Operation 'terminal state write')
        return $terminal
    }
}

function New-EpicAutopilotRunMutex {
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][string]$Run
    )

    $scope = "$([System.IO.Path]::GetFullPath($StatePath))`n$Run"
    $digest = [System.Security.Cryptography.SHA256]::HashData(
        [System.Text.Encoding]::UTF8.GetBytes($scope)
    )
    $name = 'skalary-epic-run-' +
    [Convert]::ToHexString($digest).ToLowerInvariant().Substring(0, 32)
    foreach ($prefix in @('Global\', 'Local\', '')) {
        try {
            return [System.Threading.Mutex]::new($false, "$prefix$name")
        }
        catch {
            continue
        }
    }
    throw "Unable to create epic autopilot run lease '$name'."
}

function Enter-EpicAutopilotRunLease {
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][string]$Run
    )

    $mutex = New-EpicAutopilotRunMutex -StatePath $StatePath -Run $Run
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne([TimeSpan]::Zero)
        }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw "Epic autopilot run '$Run' already has an active host launcher."
        }
        return $mutex
    }
    catch {
        if ($acquired) {
            [void]$mutex.ReleaseMutex()
        }
        $mutex.Dispose()
        throw
    }
}

function Test-EpicAutopilotRunLeaseActive {
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][string]$Run
    )

    $mutex = New-EpicAutopilotRunMutex -StatePath $StatePath -Run $Run
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne([TimeSpan]::Zero)
        }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }
        return -not $acquired
    }
    finally {
        if ($acquired) {
            [void]$mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Exit-EpicAutopilotRunLease {
    param([Parameter(Mandatory)][System.Threading.Mutex]$Lease)

    try {
        [void]$Lease.ReleaseMutex()
    }
    finally {
        $Lease.Dispose()
    }
}

function Invoke-EpicChildLauncher {
    param(
        [Parameter(Mandatory)][string]$LaunchScript,
        [Parameter(Mandatory)][string[]]$Argument,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    if (-not (Test-Path -LiteralPath $LaunchScript -PathType Leaf)) {
        throw "Per-plan launcher not found: $LaunchScript"
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($LaunchScript)
    foreach ($item in $Argument) {
        $startInfo.ArgumentList.Add($item)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Unable to start per-plan launcher '$LaunchScript'."
        }
        $process.WaitForExit()
        return $process.ExitCode
    }
    finally {
        $process.Dispose()
    }
}

function Get-EpicAutopilotContainerName {
    param([Parameter(Mandatory)][string]$Run)

    $parsedRun = [guid]::Empty
    if (-not [guid]::TryParseExact($Run, 'D', [ref]$parsedRun) -or
        $parsedRun.ToString('D') -cne $Run) {
        throw "Cannot derive an epic container name from noncanonical run '$Run'."
    }
    return "autopilot-run-$Run"
}

function Assert-EpicAutopilotWorktree {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$TargetCommit
    )

    $headOutput = @(& git -C $RepoRoot rev-parse --verify 'HEAD^{commit}' 2>&1)
    if ($LASTEXITCODE -ne 0 -or $headOutput.Count -ne 1) {
        throw "Unable to resolve the repository worktree HEAD: $(($headOutput -join ' ').Trim())"
    }
    $headCommit = ([string]$headOutput[0]).Trim().ToLowerInvariant()
    if ($headCommit -cne $TargetCommit) {
        throw "Repository worktree HEAD '$headCommit' does not equal resolved target '$TargetCommit'."
    }

    $statusOutput = @(
        & git -C $RepoRoot status --porcelain=v1 --untracked-files=normal 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the repository worktree: $(($statusOutput -join ' ').Trim())"
    }
    if ($statusOutput.Count -ne 0) {
        throw 'Repository worktree must be clean before epic child selection.'
    }
}

function Test-EpicAutopilotContainerActive {
    param([Parameter(Mandatory)][string]$ContainerName)

    $output = @(
        & docker container ls --all --filter "name=^/$ContainerName$" `
            --format '{{.Names}}|{{.State}}' 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect epic container '$ContainerName': $(($output -join ' ').Trim())"
    }
    if ($output.Count -eq 0) {
        return $false
    }
    if ($output.Count -ne 1) {
        throw "Container probe returned multiple records for '$ContainerName'."
    }

    $parts = ([string]$output[0]).Split('|', 2)
    if ($parts.Count -ne 2 -or $parts[0] -cne $ContainerName) {
        throw "Container probe returned an unexpected record for '$ContainerName'."
    }
    return $parts[1] -cnotin @('exited', 'dead')
}

function Resolve-EpicAutopilotTargetBranch {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $branch = $Target
    if ($branch -ceq 'HEAD') {
        $branchOutput = @(& git -C $RepoRoot symbolic-ref --quiet --short HEAD 2>&1)
        if ($LASTEXITCODE -ne 0 -or $branchOutput.Count -ne 1) {
            throw 'Target HEAD does not name a local branch.'
        }
        $branch = ([string]$branchOutput[0]).Trim()
    }
    elseif ($branch.StartsWith('refs/heads/', [System.StringComparison]::Ordinal)) {
        $branch = $branch.Substring('refs/heads/'.Length)
    }

    if ($branch -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or
        $branch.Contains('..') -or $branch.Contains('//') -or
        $branch.EndsWith('/') -or $branch.EndsWith('.') -or
        $branch.EndsWith('.lock', [System.StringComparison]::OrdinalIgnoreCase) -or
        $branch.Contains('@{')) {
        throw "Target '$Target' must name a valid local branch or refs/heads/<branch> ref."
    }
    & git -C $RepoRoot check-ref-format --branch $branch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Target '$Target' must name a valid local branch or refs/heads/<branch> ref."
    }
    return $branch
}

function Invoke-EpicAutopilotHostLoopCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Epic,
        [string]$Target = 'HEAD',
        [string]$RepoRoot,
        [string]$StatePath,
        [string]$PlanStateScript = (Join-Path $PSScriptRoot 'Get-PlanState.ps1'),
        [scriptblock]$PlanStateInvoker,
        [scriptblock]$TargetResolver,
        [scriptblock]$WorktreeValidator,
        [scriptblock]$RunFactory,
        [scriptblock]$LauncherInvoker,
        [scriptblock]$ContainerProbe,
        [scriptblock]$RunLeaseProbe,
        [scriptblock]$AncestorTester,
        [scriptblock]$StateDeleteInvoker
    )

    if ($env:AUTOPILOT_CONTAINER -ceq 'true') {
        throw 'Epic autopilot is host-owned and cannot run inside an autopilot container.'
    }

    if (-not $RepoRoot) {
        $rootOutput = @(& git rev-parse --show-toplevel 2>&1)
        if ($LASTEXITCODE -ne 0 -or $rootOutput.Count -ne 1) {
            throw "Unable to resolve the repository root: $(($rootOutput -join ' ').Trim())"
        }
        $RepoRoot = [string]$rootOutput[0]
    }
    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $stateFile = Resolve-EpicAutopilotStatePath -RepoRoot $repoRootPath -StatePath $StatePath
    $targetBranch = Resolve-EpicAutopilotTargetBranch -Target $Target -RepoRoot $repoRootPath

    if (-not $PlanStateInvoker) {
        $PlanStateInvoker = {
            param($EpicReference, $Root, $ScriptPath)
            if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
                throw "Get-PlanState script not found: $ScriptPath"
            }
            $output = @(
                & $ScriptPath -Reference $EpicReference -RepoRoot $Root -Epic -Json
            )
            return ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        }
    }
    if (-not $TargetResolver) {
        $TargetResolver = {
            param($BranchName, $Root)
            $output = @(
                & git -C $Root rev-parse --verify "refs/heads/$BranchName`^{commit}" 2>&1
            )
            if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) {
                throw "Unable to resolve target branch '$BranchName': $(($output -join ' ').Trim())"
            }
            return ([string]$output[0]).Trim().ToLowerInvariant()
        }
    }
    if (-not $WorktreeValidator) {
        $WorktreeValidator = {
            param($Root, $Commit)
            Assert-EpicAutopilotWorktree -RepoRoot $Root -TargetCommit $Commit
        }
    }
    if (-not $RunFactory) {
        $RunFactory = { [guid]::NewGuid().ToString('D') }
    }
    if (-not $LauncherInvoker) {
        $LauncherInvoker = {
            param($LaunchScript, $Argument, $Root)
            Invoke-EpicChildLauncher -LaunchScript $LaunchScript -Argument $Argument `
                -WorkingDirectory $Root
        }
    }
    if (-not $ContainerProbe) {
        $ContainerProbe = {
            param($ContainerName)
            Test-EpicAutopilotContainerActive -ContainerName $ContainerName
        }
    }
    if (-not $RunLeaseProbe) {
        $RunLeaseProbe = {
            param($Path, $Run)
            Test-EpicAutopilotRunLeaseActive -StatePath $Path -Run $Run
        }
    }
    if (-not $AncestorTester) {
        $AncestorTester = {
            param($Ancestor, $Descendant, $Root)
            Test-EpicAutopilotAncestor -Ancestor $Ancestor -Descendant $Descendant `
                -RepoRoot $Root
        }
    }
    if (-not $StateDeleteInvoker) {
        $StateDeleteInvoker = {
            param($Path, $ExpectedGeneration)
            Remove-EpicAutopilotState -Path $Path `
                -ExpectedGeneration $ExpectedGeneration
        }
    }

    $runLease = [pscustomobject]@{ Value = $null }
    try {
        $admission = Invoke-WithAtomicStoreLock -Scope $stateFile -Action {
            $generation = Get-AtomicStoreGeneration -Path $stateFile
            $existing = Read-EpicAutopilotState -Path $stateFile

            $targetCommit = [string](& $TargetResolver $targetBranch $repoRootPath)
            $targetCommit = $targetCommit.Trim().ToLowerInvariant()
            if ($targetCommit -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
                throw "Target '$Target' resolved to invalid commit id '$targetCommit'."
            }
            try {
                & $WorktreeValidator $repoRootPath $targetCommit
            }
            catch {
                throw "Epic target worktree validation failed: $($_.Exception.Message)"
            }

            try {
                $rollupJson = & $PlanStateInvoker $Epic $repoRootPath $PlanStateScript
            }
            catch {
                throw "Get-PlanState epic rollup failed: $($_.Exception.Message)"
            }
            $rollup = ConvertFrom-EpicRollupJson -Json ([string]$rollupJson)
            if ($Epic -cmatch '^[0-9a-f]{6}$' -and $Epic -cne [string]$rollup.EpicId) {
                throw "Get-PlanState resolved epic '$($rollup.EpicId)', not requested epic '$Epic'."
            }

            if ($existing) {
                if ($existing.epic -cne [string]$rollup.EpicId) {
                    throw "Existing epic autopilot state belongs to epic '$($existing.epic)', not '$($rollup.EpicId)'."
                }

                $isSuccessfulCheckpoint = $existing.outcome -ceq 'awaiting-merge' -or
                $existing.outcome -ceq 'exit:0'
                $isTerminalFailure = $existing.outcome -ceq 'invocation-failed' -or (
                    $existing.outcome.StartsWith('exit:', [System.StringComparison]::Ordinal) -and
                    $existing.outcome -cne 'exit:0'
                )

                if ($isTerminalFailure) {
                    $storedExit = if ($existing.outcome.StartsWith(
                            'exit:',
                            [System.StringComparison]::Ordinal
                        )) {
                        [int]$existing.outcome.Substring(5)
                    }
                    else { $null }
                    return [pscustomobject]@{
                        State           = $existing
                        NextChild       = $rollup.NextChild
                        Resumed         = $true
                        StatePath       = $stateFile
                        Launch          = $false
                        LaunchAttempted = $false
                        Replayed        = $true
                        ExitCode        = $storedExit
                        Failed          = $existing.outcome -ceq 'invocation-failed'
                        Completed       = $false
                        Blocked         = $false
                        Message         = if ($existing.outcome -ceq 'invocation-failed') {
                            "Epic autopilot run '$($existing.run)' has terminal outcome 'invocation-failed'."
                        }
                        else { $null }
                    }
                }

                if ($isSuccessfulCheckpoint) {
                    if ($existing.target -ceq $targetCommit) {
                        return [pscustomobject]@{
                            State           = $existing
                            NextChild       = $rollup.NextChild
                            Resumed         = $true
                            StatePath       = $stateFile
                            Launch          = $false
                            LaunchAttempted = $false
                            Replayed        = $true
                            ExitCode        = 0
                            Failed          = $false
                            Completed       = $false
                            Blocked         = $false
                            Message         = $null
                        }
                    }

                    $ancestryOutput = @(
                        & $AncestorTester $existing.target $targetCommit $repoRootPath
                    )
                    if ($ancestryOutput.Count -ne 1 -or
                        $ancestryOutput[0] -isnot [bool]) {
                        throw 'Target ancestry probe returned an invalid result.'
                    }
                    if (-not [bool]$ancestryOutput[0]) {
                        throw "Refreshed target '$targetCommit' is not a forward descendant of prior target '$($existing.target)'."
                    }

                    $priorChildren = @(
                        $rollup.Children |
                            Where-Object { [string]$_.Id -ceq $existing.currentChild }
                    )
                    if ($priorChildren.Count -ne 1) {
                        throw "Refreshed epic graph must contain prior child '$($existing.currentChild)' exactly once; found $($priorChildren.Count)."
                    }
                    if (-not [bool]$priorChildren[0].IsComplete) {
                        throw "Refreshed epic graph still reports prior child '$($existing.currentChild)' incomplete."
                    }
                    if ($null -ne $rollup.NextChild -and
                        [string]$rollup.NextChild.Id -ceq $existing.currentChild) {
                        throw "Refreshed epic graph still selects prior child '$($existing.currentChild)' as NextChild."
                    }

                    if ($null -eq $rollup.NextChild) {
                        if (-not [bool]$rollup.Rollup.IsComplete) {
                            return [pscustomobject]@{
                                State           = $existing
                                NextChild       = $null
                                Resumed         = $true
                                StatePath       = $stateFile
                                Launch          = $false
                                LaunchAttempted = $false
                                Replayed        = $true
                                ExitCode        = 42
                                Failed          = $false
                                Completed       = $false
                                Blocked         = $true
                                Message         = 'Epic graph is incomplete but has no eligible NextChild; prior success checkpoint is retained for explicit resume.'
                            }
                        }

                        $deleteOutput = @(
                            & $StateDeleteInvoker $stateFile $generation
                        )
                        if ($deleteOutput.Count -ne 1 -or
                            $null -eq $deleteOutput[0] -or
                            $deleteOutput[0].PSObject.Properties.Name -notcontains 'Status' -or
                            [string]$deleteOutput[0].Status -cne 'complete') {
                            $status = if ($deleteOutput.Count -eq 1 -and
                                $null -ne $deleteOutput[0] -and
                                $deleteOutput[0].PSObject.Properties.Name -contains 'Status') {
                                [string]$deleteOutput[0].Status
                            }
                            else { 'invalid' }
                            throw "Epic autopilot completed-state delete failed with status '$status'."
                        }
                        return [pscustomobject]@{
                            State           = $null
                            NextChild       = $null
                            Resumed         = $true
                            StatePath       = $stateFile
                            Launch          = $false
                            LaunchAttempted = $false
                            Replayed        = $false
                            ExitCode        = 0
                            Failed          = $false
                            Completed       = $true
                            Blocked         = $false
                            Message         = 'Epic graph is complete after the operator merge.'
                        }
                    }

                    if ([bool]$rollup.Rollup.IsComplete) {
                        throw 'Get-PlanState reports a complete epic with a non-null NextChild.'
                    }

                    $selected = [pscustomobject][ordered]@{
                        epic         = [string]$rollup.EpicId
                        target       = $targetCommit
                        currentChild = [string]$rollup.NextChild.Id
                        branch       = "feature/$($rollup.NextChild.FolderName)"
                        run          = [string](& $RunFactory)
                        outcome      = 'selected'
                    }
                    $selectedWrite = Set-EpicAutopilotState -Path $stateFile `
                        -State $selected -ExpectedGeneration $generation `
                        -Operation 'next-child selected state replacement'
                    $generation = $selectedWrite.Generation
                    $existing = $selected
                }

                if ($existing.target -cne $targetCommit) {
                    throw "Existing epic autopilot state targets '$($existing.target)', but '$Target' is now '$targetCommit'."
                }
                if ($null -eq $rollup.NextChild) {
                    throw "Existing epic autopilot state selects '$($existing.currentChild)', but Get-PlanState has no NextChild."
                }

                $expectedBranch = "feature/$($rollup.NextChild.FolderName)"
                if ($existing.currentChild -cne [string]$rollup.NextChild.Id -or
                    $existing.branch -cne $expectedBranch) {
                    throw "Existing epic autopilot state selects '$($existing.currentChild)' on '$($existing.branch)'; refusing conflicting NextChild '$($rollup.NextChild.Id)' on '$expectedBranch'."
                }

                if ($existing.outcome -ceq 'running') {
                    $containerName = Get-EpicAutopilotContainerName -Run $existing.run
                    try {
                        $leaseOutput = @(& $RunLeaseProbe $stateFile $existing.run)
                    }
                    catch {
                        throw "Unable to determine whether epic autopilot run '$($existing.run)' has an active host launcher: $($_.Exception.Message)"
                    }
                    if ($leaseOutput.Count -ne 1 -or $leaseOutput[0] -isnot [bool]) {
                        throw "Unable to determine whether epic autopilot run '$($existing.run)' has an active host launcher: run lease probe returned an invalid result."
                    }
                    if ([bool]$leaseOutput[0]) {
                        throw "Epic autopilot run '$($existing.run)' already has an active host launcher; refusing a second child launcher."
                    }
                    try {
                        $probeOutput = @(& $ContainerProbe $containerName)
                    }
                    catch {
                        throw "Unable to determine whether epic autopilot run '$($existing.run)' is active: $($_.Exception.Message)"
                    }
                    if ($probeOutput.Count -ne 1 -or $probeOutput[0] -isnot [bool]) {
                        throw "Unable to determine whether epic autopilot run '$($existing.run)' is active: container probe returned an invalid result."
                    }
                    if ([bool]$probeOutput[0]) {
                        throw "Epic autopilot run '$($existing.run)' is already running in container '$containerName'; refusing a second child launcher."
                    }

                    $reconciled = New-EpicAutopilotState -State $existing `
                        -Outcome 'invocation-failed'
                    [void](Set-EpicAutopilotState -Path $stateFile -State $reconciled `
                            -ExpectedGeneration $generation `
                            -Operation 'running-state reconciliation')
                    return [pscustomobject]@{
                        State           = $reconciled
                        NextChild       = $rollup.NextChild
                        Resumed         = $true
                        StatePath       = $stateFile
                        Launch          = $false
                        LaunchAttempted = $false
                        Replayed        = $true
                        ExitCode        = $null
                        Failed          = $true
                        Message         = "Interrupted epic autopilot run '$($existing.run)' has no active container '$containerName'; reconciled to invocation-failed without relaunch."
                    }
                }
            }
            elseif ($null -eq $rollup.NextChild) {
                return [pscustomobject]@{
                    State           = $null
                    NextChild       = $null
                    Resumed         = $false
                    StatePath       = $stateFile
                    Launch          = $false
                    LaunchAttempted = $false
                    Replayed        = $false
                    ExitCode        = $null
                    Failed          = $false
                    Completed       = [bool]$rollup.Rollup.IsComplete
                    Blocked         = -not [bool]$rollup.Rollup.IsComplete
                    Message         = if ([bool]$rollup.Rollup.IsComplete) {
                        'Epic graph is complete; no child launch is needed.'
                    }
                    else {
                        'Epic graph is incomplete but has no eligible NextChild.'
                    }
                }
            }

            $resumed = $null -ne $existing
            $selected = $existing
            if (-not $selected) {
                $selected = [pscustomobject][ordered]@{
                    epic         = [string]$rollup.EpicId
                    target       = $targetCommit
                    currentChild = [string]$rollup.NextChild.Id
                    branch       = "feature/$($rollup.NextChild.FolderName)"
                    run          = [string](& $RunFactory)
                    outcome      = 'selected'
                }
                $selectedWrite = Set-EpicAutopilotState -Path $stateFile -State $selected `
                    -ExpectedGeneration 'absent' -Operation 'selected state write'
                $generation = $selectedWrite.Generation
            }

            $runLease.Value = Enter-EpicAutopilotRunLease `
                -StatePath $stateFile -Run $selected.run
            $running = New-EpicAutopilotState -State $selected -Outcome 'running'
            $runningWrite = Set-EpicAutopilotState -Path $stateFile -State $running `
                -ExpectedGeneration $generation -Operation 'running state write'

            return [pscustomobject]@{
                State           = $running
                NextChild       = $rollup.NextChild
                Resumed         = $resumed
                StatePath       = $stateFile
                Launch          = $true
                LaunchAttempted = $false
                Replayed        = $false
                ExitCode        = $null
                Failed          = $false
                Message         = $null
                Generation      = $runningWrite.Generation
            }
        }

        if (-not $admission.Launch) {
            return $admission
        }

        $launchScript = Join-Path $repoRootPath '.github/skills/autopilot/scripts/launch.ps1'
        $launchArguments = @(
            '-PlanSlug', [string]$admission.NextChild.FolderName,
            '-Mode', 'whole-plan',
            '-Runtime', 'container',
            '-Branch', $targetBranch,
            '-ExpectedStartCommit', [string]$admission.State.target,
            '-Run', [string]$admission.State.run
        )
        try {
            $launcherOutput = @(
                & $LauncherInvoker $launchScript $launchArguments $repoRootPath
            )
            if ($launcherOutput.Count -ne 1) {
                throw 'Per-plan launcher invoker must return exactly one exit code.'
            }
            $launcherExitText = [string]$launcherOutput[0]
            if ($launcherExitText -cnotmatch $script:PortableExitCodePattern) {
                throw "Per-plan launcher invoker returned invalid exit code '$($launcherOutput[0])'."
            }
            $launcherExit = [int]::Parse(
                $launcherExitText,
                [System.Globalization.NumberStyles]::None,
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        }
        catch {
            $launchError = $_.Exception.Message
            try {
                $failedState = Set-EpicAutopilotTerminalState -Path $stateFile `
                    -RunningState $admission.State -RunningGeneration $admission.Generation `
                    -Outcome 'invocation-failed'
            }
            catch {
                throw "Per-plan launcher invocation failed ('$launchError') and its terminal state could not be persisted: $($_.Exception.Message)"
            }
            return [pscustomobject]@{
                State           = $failedState
                NextChild       = $admission.NextChild
                Resumed         = $admission.Resumed
                StatePath       = $stateFile
                Launch          = $false
                LaunchAttempted = $true
                Replayed        = $false
                ExitCode        = $null
                Failed          = $true
                Message         = "Per-plan launcher invocation failed: $launchError"
            }
        }

        $terminalOutcome = if ($launcherExit -eq 0) {
            'awaiting-merge'
        }
        else {
            "exit:$launcherExit"
        }
        $terminal = Set-EpicAutopilotTerminalState -Path $stateFile `
            -RunningState $admission.State -RunningGeneration $admission.Generation `
            -Outcome $terminalOutcome
        return [pscustomobject]@{
            State           = $terminal
            NextChild       = $admission.NextChild
            Resumed         = $admission.Resumed
            StatePath       = $stateFile
            Launch          = $true
            LaunchAttempted = $true
            Replayed        = $false
            ExitCode        = $launcherExit
            Failed          = $false
            Message         = $null
        }
    }
    finally {
        if ($null -ne $runLease.Value) {
            Exit-EpicAutopilotRunLease -Lease $runLease.Value
        }
    }
}

function Invoke-EpicAutopilotHostLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Epic,
        [string]$Target = 'HEAD',
        [string]$RepoRoot
    )

    return Invoke-EpicAutopilotHostLoopCore @PSBoundParameters
}

Export-ModuleMember -Function Invoke-EpicAutopilotHostLoop

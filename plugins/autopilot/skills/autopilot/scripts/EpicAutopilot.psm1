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
        if ($values.outcome -cnotin @('selected', 'running', 'invocation-failed')) {
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
    if ($null -ne $rollup.NextChild) {
        if ($rollup.NextChild -is [array]) {
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
        epic = [string]$State.epic
        target = [string]$State.target
        currentChild = [string]$State.currentChild
        branch = [string]$State.branch
        run = [string]$State.run
        outcome = $Outcome
    }
}

function ConvertTo-EpicAutopilotStateJson {
    param([Parameter(Mandatory)]$State)

    $content = $State | ConvertTo-Json -Compress
    [void](ConvertFrom-EpicAutopilotStateJson -Json $content)
    return $content
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
        $write = Set-AtomicStoreContent -Path $Path `
            -Content (ConvertTo-EpicAutopilotStateJson -State $terminal) `
            -ExpectedGeneration $RunningGeneration -Validate {
            param($candidatePath)
            [void](ConvertFrom-EpicAutopilotStateJson -Json (
                    [System.IO.File]::ReadAllText($candidatePath)
                ))
        }
        if ($write.Status -ne 'complete') {
            throw "Epic autopilot terminal state write failed with status '$($write.Status)'."
        }
        return $terminal
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

function Invoke-EpicAutopilotHostLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Epic,
        [string]$Target = 'HEAD',
        [string]$RepoRoot,
        [string]$StatePath,
        [string]$PlanStateScript = (Join-Path $PSScriptRoot 'Get-PlanState.ps1'),
        [scriptblock]$PlanStateInvoker,
        [scriptblock]$TargetResolver,
        [scriptblock]$RunFactory,
        [scriptblock]$LauncherInvoker
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
            param($TargetReference, $Root)
            $output = @(& git -C $Root rev-parse --verify "$TargetReference^{commit}" 2>&1)
            if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) {
                throw "Unable to resolve target '$TargetReference': $(($output -join ' ').Trim())"
            }
            return ([string]$output[0]).Trim().ToLowerInvariant()
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

    $admission = Invoke-WithAtomicStoreLock -Scope $stateFile -Action {
        $generation = Get-AtomicStoreGeneration -Path $stateFile
        $existing = Read-EpicAutopilotState -Path $stateFile

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

        $targetCommit = [string](& $TargetResolver $Target $repoRootPath)
        $targetCommit = $targetCommit.Trim().ToLowerInvariant()
        if ($targetCommit -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
            throw "Target '$Target' resolved to invalid commit id '$targetCommit'."
        }

        if ($existing) {
            if ($existing.epic -cne [string]$rollup.EpicId) {
                throw "Existing epic autopilot state belongs to epic '$($existing.epic)', not '$($rollup.EpicId)'."
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
                throw "Epic autopilot run '$($existing.run)' is already running; refusing a second child launcher."
            }
            if ($existing.outcome -cne 'selected') {
                $storedExit = $null
                if ($existing.outcome.StartsWith('exit:', [System.StringComparison]::Ordinal)) {
                    $storedExit = [int]$existing.outcome.Substring(5)
                }
                return [pscustomobject]@{
                    State = $existing
                    NextChild = $rollup.NextChild
                    Resumed = $true
                    StatePath = $stateFile
                    Launch = $false
                    Replayed = $true
                    ExitCode = $storedExit
                }
            }
        }
        elseif ($null -eq $rollup.NextChild) {
            return [pscustomobject]@{
                State = $null
                NextChild = $null
                Resumed = $false
                StatePath = $stateFile
                Launch = $false
                Replayed = $false
                ExitCode = $null
            }
        }

        $resumed = $null -ne $existing
        $selected = $existing
        if (-not $selected) {
            $selected = [pscustomobject][ordered]@{
                epic = [string]$rollup.EpicId
                target = $targetCommit
                currentChild = [string]$rollup.NextChild.Id
                branch = "feature/$($rollup.NextChild.FolderName)"
                run = [string](& $RunFactory)
                outcome = 'selected'
            }
            $selectedWrite = Set-AtomicStoreContent -Path $stateFile `
                -Content (ConvertTo-EpicAutopilotStateJson -State $selected) `
                -ExpectedGeneration 'absent' -Validate {
                param($candidatePath)
                [void](ConvertFrom-EpicAutopilotStateJson -Json (
                        [System.IO.File]::ReadAllText($candidatePath)
                    ))
            }
            if ($selectedWrite.Status -ne 'complete') {
                throw "Epic autopilot selected state write failed with status '$($selectedWrite.Status)'."
            }
            $generation = $selectedWrite.Generation
        }

        $running = New-EpicAutopilotState -State $selected -Outcome 'running'
        $runningWrite = Set-AtomicStoreContent -Path $stateFile `
            -Content (ConvertTo-EpicAutopilotStateJson -State $running) `
            -ExpectedGeneration $generation -Validate {
            param($candidatePath)
            [void](ConvertFrom-EpicAutopilotStateJson -Json (
                    [System.IO.File]::ReadAllText($candidatePath)
                ))
        }
        if ($runningWrite.Status -ne 'complete') {
            throw "Epic autopilot running state write failed with status '$($runningWrite.Status)'."
        }

        return [pscustomobject]@{
            State = $running
            NextChild = $rollup.NextChild
            Resumed = $resumed
            StatePath = $stateFile
            Launch = $true
            Replayed = $false
            ExitCode = $null
            Generation = $runningWrite.Generation
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
        '-Branch', $Target
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
            [void](Set-EpicAutopilotTerminalState -Path $stateFile `
                    -RunningState $admission.State -RunningGeneration $admission.Generation `
                    -Outcome 'invocation-failed')
        }
        catch {
            throw "Per-plan launcher invocation failed ('$launchError') and its terminal state could not be persisted: $($_.Exception.Message)"
        }
        throw "Per-plan launcher invocation failed: $launchError"
    }

    $terminal = Set-EpicAutopilotTerminalState -Path $stateFile `
        -RunningState $admission.State -RunningGeneration $admission.Generation `
        -Outcome "exit:$launcherExit"
    return [pscustomobject]@{
        State = $terminal
        NextChild = $admission.NextChild
        Resumed = $admission.Resumed
        StatePath = $stateFile
        Launch = $true
        Replayed = $false
        ExitCode = $launcherExit
    }
}

Export-ModuleMember -Function Invoke-EpicAutopilotHostLoop, Read-EpicAutopilotState

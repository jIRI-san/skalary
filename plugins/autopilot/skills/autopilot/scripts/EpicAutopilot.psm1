#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AtomicStore.psm1') -Force

$script:StateFields = @('epic', 'target', 'currentChild', 'branch', 'run', 'outcome')

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
        if ($values.outcome -cne 'selected') {
            throw "Epic autopilot state field 'outcome' must be 'selected' before launch."
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
        [scriptblock]$RunFactory
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

    return Invoke-WithAtomicStoreLock -Scope $stateFile -Action {
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

            return [pscustomobject]@{
                State = $existing
                NextChild = $rollup.NextChild
                Resumed = $true
                StatePath = $stateFile
            }
        }

        if ($null -eq $rollup.NextChild) {
            return [pscustomobject]@{
                State = $null
                NextChild = $null
                Resumed = $false
                StatePath = $stateFile
            }
        }

        $state = [pscustomobject][ordered]@{
            epic = [string]$rollup.EpicId
            target = $targetCommit
            currentChild = [string]$rollup.NextChild.Id
            branch = "feature/$($rollup.NextChild.FolderName)"
            run = [string](& $RunFactory)
            outcome = 'selected'
        }
        $content = $state | ConvertTo-Json -Compress
        [void](ConvertFrom-EpicAutopilotStateJson -Json $content)

        $write = Set-AtomicStoreContent -Path $stateFile -Content $content `
            -ExpectedGeneration 'absent' -Validate {
            param($candidatePath)
            [void](ConvertFrom-EpicAutopilotStateJson -Json (
                    [System.IO.File]::ReadAllText($candidatePath)
                ))
        }
        if ($write.Status -ne 'complete') {
            throw "Epic autopilot state write failed with status '$($write.Status)'."
        }

        return [pscustomobject]@{
            State = $state
            NextChild = $rollup.NextChild
            Resumed = $false
            StatePath = $stateFile
        }
    }
}

Export-ModuleMember -Function Invoke-EpicAutopilotHostLoop, Read-EpicAutopilotState

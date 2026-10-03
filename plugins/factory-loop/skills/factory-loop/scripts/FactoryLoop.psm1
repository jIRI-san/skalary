#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FactoryLoopConsumerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Consumer repository does not exist: $root"
    }
    if (((Get-Item -LiteralPath $root -Force).Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Consumer repository root cannot be a link or reparse point: $root"
    }
    if ([System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath -match '(^|[\\/])\.\.([\\/]|$)' -or
        $RelativePath -match '^[A-Za-z]:' -or
        $RelativePath -match '[<>:"|?*]') {
        throw "Consumer path must be a confined repository-relative factory-loop path: $RelativePath"
    }
    $normalized = $RelativePath.Replace('\', '/').Trim('/')
    if (-not ($normalized.StartsWith('.factory-loop/', [System.StringComparison]::Ordinal) -or
            $normalized.StartsWith('scripts/factory-loop/', [System.StringComparison]::Ordinal))) {
        throw "Consumer path is outside factory-loop setup ownership: $RelativePath"
    }

    $candidate = [System.IO.Path]::GetFullPath(
        (Join-Path $root ($normalized.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
    )
    $prefix = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Consumer path escapes the selected repository: $RelativePath"
    }

    $cursor = $root
    $relativeSegments = $normalized -split '/'
    foreach ($segment in $relativeSegments) {
        $cursor = Join-Path $cursor $segment
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Consumer path traverses a link or reparse point: $RelativePath"
            }
        }
    }
    return $candidate
}

function Get-FactoryLoopTemplateRoot {
    [CmdletBinding()]
    param()

    $root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\templates'))
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Factory-loop templates are missing from the installed plugin payload: $root"
    }
    return $root
}

function Get-FactoryLoopSetupFiles {
    [CmdletBinding()]
    param()

    $templateRoot = Get-FactoryLoopTemplateRoot
    return @(
        [pscustomobject]@{
            RelativePath = '.factory-loop/factory-loop.json'
            SourcePath = Join-Path $templateRoot 'factory-loop.json'
        }
        [pscustomobject]@{
            RelativePath = 'scripts/factory-loop/FactoryLoop.Adapter.ps1'
            SourcePath = Join-Path $templateRoot 'FactoryLoop.Adapter.ps1'
        }
        [pscustomobject]@{
            RelativePath = 'scripts/factory-loop/acceptance/Acceptance.ps1'
            SourcePath = Join-Path $templateRoot 'demo/Invoke-Acceptance.ps1'
        }
    )
}

function Get-FactoryLoopSetupPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-FactoryLoopSetupFiles) {
        $destination = Resolve-FactoryLoopConsumerPath -RepoRoot $root -RelativePath $file.RelativePath
        $desired = [System.IO.File]::ReadAllBytes($file.SourcePath)
        $desiredHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($desired)).ToLowerInvariant()
        $currentHash = $null
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $currentHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        elseif (Test-Path -LiteralPath $destination) {
            throw "Setup target is not a regular file: $($file.RelativePath)"
        }
        $entries.Add([pscustomobject]@{
                path = $file.RelativePath
                action = if ($null -eq $currentHash) { 'create' } else { 'preserve' }
                desiredSha256 = $desiredHash
                currentSha256 = $currentHash
            })
    }
    $ordered = @($entries | Sort-Object -Property path)
    $canonical = $ordered | ConvertTo-Json -Depth 8 -Compress
    $digest = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($canonical))
    ).ToLowerInvariant()
    return [pscustomobject]@{
        repoRoot = $root
        digest = $digest
        files = $ordered
    }
}

function Invoke-FactoryLoopSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('preview', 'apply')][string]$Action,
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ExpectedDigest
    )

    $preview = Get-FactoryLoopSetupPreview -RepoRoot $RepoRoot
    if ($Action -eq 'preview') { return $preview }
    if ([string]::IsNullOrWhiteSpace($ExpectedDigest) -or
        $ExpectedDigest -cne $preview.digest) {
        throw "Setup approval does not match the current preview. Expected digest: $($preview.digest)"
    }

    foreach ($entry in $preview.files) {
        if ($entry.action -eq 'preserve') { continue }
        $file = Get-FactoryLoopSetupFiles | Where-Object RelativePath -CEQ $entry.path
        $destination = Resolve-FactoryLoopConsumerPath -RepoRoot $preview.repoRoot -RelativePath $entry.path
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
        $bytes = [System.IO.File]::ReadAllBytes($file.SourcePath)
        [System.IO.File]::WriteAllBytes($destination, $bytes)
        $actualHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -cne $entry.desiredSha256) {
            throw "Setup verification failed for '$($entry.path)'."
        }
    }
    return Get-FactoryLoopSetupPreview -RepoRoot $preview.repoRoot
}

function ConvertFrom-FactoryLoopAdapterResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][ValidateSet(
            'work-item', 'pull-request', 'deployment', 'version', 'acceptance', 'telemetry', 'evidence'
        )][string]$Domain,
        [Parameter(Mandatory)][ValidateSet(
            'read', 'find', 'create', 'update', 'open', 'checks', 'trigger', 'run', 'query', 'publish', 'close', 'reconcile'
        )][string]$Action,
        [Parameter(Mandatory)][string]$OperationId
    )

    if ($Result -is [string]) {
        if ($Result.Length -gt 65536) { throw 'Adapter output exceeds the 65536-character limit.' }
        try {
            $Result = ConvertFrom-Json -InputObject $Result -AsHashtable -Depth 32 -ErrorAction Stop
        }
        catch {
            throw 'Adapter returned malformed JSON.'
        }
    }
    if ($Result -is [System.Management.Automation.PSCustomObject]) {
        $Result = ConvertFrom-Json -InputObject ($Result | ConvertTo-Json -Depth 32 -Compress) `
            -AsHashtable -Depth 32 -ErrorAction Stop
    }
    if ($Result -isnot [System.Collections.IDictionary]) {
        throw 'Adapter result must be one JSON object.'
    }
    foreach ($name in @('schemaVersion', 'domain', 'action', 'operationId', 'status', 'providerId', 'data')) {
        if (-not $Result.Contains($name)) { throw "Adapter result is missing required field '$name'." }
    }
    if ([int]$Result.schemaVersion -ne 1 -or
        [string]$Result.domain -cne $Domain -or
        [string]$Result.action -cne $Action -or
        [string]$Result.operationId -cne $OperationId) {
        throw 'Adapter result does not match the requested schema, domain, action, and operation ID.'
    }
    if ([string]$Result.status -cnotin @('ok', 'waiting', 'blocked', 'not-found', 'failed')) {
        throw "Adapter returned an unsupported status '$($Result.status)'."
    }
    if ([string]::IsNullOrWhiteSpace([string]$Result.providerId)) {
        throw 'Adapter result must identify its provider object or simulation.'
    }
    if ($Result.status -ceq 'failed') {
        $code = if ($Result.Contains('errorCode')) { [string]$Result['errorCode'] } else { '' }
        if ($code -notmatch '^[A-Za-z0-9._-]{1,64}$') { $code = 'AdapterFailure' }
        throw "Adapter operation failed: $code"
    }
    return [pscustomobject]$Result
}

function Invoke-FactoryLoopAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet(
            'work-item', 'pull-request', 'deployment', 'version', 'acceptance', 'telemetry', 'evidence'
        )][string]$Domain,
        [Parameter(Mandatory)][ValidateSet(
            'read', 'find', 'create', 'update', 'open', 'checks', 'trigger', 'run', 'query', 'publish', 'close', 'reconcile'
        )][string]$Action,
        [Parameter(Mandatory)][string]$OperationId,
        [hashtable]$Payload = @{},
        [Parameter(Mandatory)][scriptblock]$Runner
    )

    if ($OperationId.Length -gt 200 -or $OperationId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$') {
        throw 'Operation ID must be a stable, bounded identifier.'
    }
    $raw = & $Runner $Domain $Action $OperationId $Payload
    return ConvertFrom-FactoryLoopAdapterResult -Result $raw -Domain $Domain -Action $Action `
        -OperationId $OperationId
}

function Get-FactoryLoopApplicationDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationRoot
    )

    $root = [System.IO.Path]::GetFullPath($ApplicationRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Application root does not exist: $root"
    }
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Application root cannot be a link or reparse point: $root"
    }
    $tree = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
    foreach ($item in $tree) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Application contains a link or reparse point: $($item.FullName)"
        }
    }
    $files = @($tree | Where-Object { -not $_.PSIsContainer })
    [Array]::Sort($files, [System.Comparison[System.IO.FileInfo]]{
            param($left, $right)
            [System.StringComparer]::Ordinal.Compare($left.FullName, $right.FullName)
        })
    if ($files.Count -eq 0) { throw 'Application snapshot cannot be empty.' }
    $records = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Application contains a link or reparse point: $($file.FullName)"
        }
        $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $records.Add("$relative`0$hash")
    }
    $canonical = [string]::Join("`n", $records)
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($canonical))
    ).ToLowerInvariant()
}

function New-FactoryLoopArtifactSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApplicationRoot,
        [Parameter(Mandatory)][string]$ArtifactStore,
        [string]$SourceSha,
        [string]$MergeCommit
    )

    $source = [System.IO.Path]::GetFullPath($ApplicationRoot)
    $digest = Get-FactoryLoopApplicationDigest -ApplicationRoot $source
    $store = [System.IO.Path]::GetFullPath($ArtifactStore)
    [void](New-Item -ItemType Directory -Path $store -Force)
    $target = Join-Path $store $digest
    if (Test-Path -LiteralPath $target) {
        $targetItem = Get-Item -LiteralPath $target -Force
        if (-not $targetItem.PSIsContainer -or
            ($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Content-addressed artifact target is not a regular directory.'
        }
    }
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        $staging = Join-Path $store ('.staging-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $staging)
        try {
            foreach ($sourceItem in Get-ChildItem -LiteralPath $source -Force) {
                Copy-Item -LiteralPath $sourceItem.FullName -Destination $staging -Recurse -Force
            }
            $copiedDigest = Get-FactoryLoopApplicationDigest -ApplicationRoot $staging
            if ($copiedDigest -cne $digest) { throw 'Copied artifact does not match its source digest.' }
            foreach ($item in Get-ChildItem -LiteralPath $staging -File -Recurse -Force) {
                $item.IsReadOnly = $true
            }
            Move-Item -LiteralPath $staging -Destination $target
        }
        finally {
            if (Test-Path -LiteralPath $staging) {
                Remove-Item -LiteralPath $staging -Recurse -Force
            }
        }
    }
    $snapshotDigest = Get-FactoryLoopApplicationDigest -ApplicationRoot $target
    if ($snapshotDigest -cne $digest) { throw 'Existing content-addressed artifact failed integrity verification.' }
    return [pscustomobject]@{
        artifactDigest = $digest
        artifactPath = $target
        sourceSha = $SourceSha
        mergeCommit = $MergeCommit
    }
}

function Test-FactoryLoopArtifactAcceptance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][string]$ExpectedDigest,
        [ValidateSet('test', 'preprod', 'prod')][string]$Environment = 'test'
    )

    $actualDigest = Get-FactoryLoopApplicationDigest -ApplicationRoot $ArtifactPath
    if ($actualDigest -cne $ExpectedDigest) {
        return [pscustomobject]@{
            status = 'blocked'
            reason = 'artifact-digest-mismatch'
            expectedDigest = $ExpectedDigest
            actualDigest = $actualDigest
            environment = $Environment
        }
    }
    $acceptance = Join-Path $ArtifactPath 'Invoke-Acceptance.ps1'
    if (-not (Test-Path -LiteralPath $acceptance -PathType Leaf)) {
        throw "Artifact acceptance command is missing: $acceptance"
    }
    $resultText = & $acceptance -ArtifactRoot $ArtifactPath -Environment $Environment
    $result = ConvertFrom-Json -InputObject ($resultText -join "`n") -AsHashtable -Depth 16 -ErrorAction Stop
    if ([int]$result.schemaVersion -ne 1 -or [string]$result.environment -cne $Environment -or
        [string]$result.status -cnotin @('passed', 'failed')) {
        throw 'Artifact acceptance returned a malformed result.'
    }
    return [pscustomobject]@{
        status = if ($result.status -ceq 'passed') { 'passed' } else { 'failed' }
        artifactDigest = $actualDigest
        environment = $Environment
        scenario = [string]$result.scenario
        expected = [string]$result.expected
        actual = [string]$result.actual
    }
}

function New-FactoryLoopDemoProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DemoRoot,
        [string]$ConsumerRoot
    )

    $root = [System.IO.Path]::GetFullPath($DemoRoot)
    if (-not [string]::IsNullOrWhiteSpace($ConsumerRoot)) {
        $consumer = [System.IO.Path]::GetFullPath($ConsumerRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($root.StartsWith($consumer, [System.StringComparison]::OrdinalIgnoreCase) -or
            $consumer.StartsWith($root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'The disposable demo project must be outside the selected consumer repository.'
        }
    }
    if (Test-Path -LiteralPath $root) {
        if (((Get-Item -LiteralPath $root -Force).Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Demo destination cannot be a link or reparse point.'
        }
        $existing = @(Get-ChildItem -LiteralPath $root -Force)
        if ($existing.Count -gt 0) { throw "Demo destination must be empty: $root" }
    }
    else {
        [void](New-Item -ItemType Directory -Path $root -Force)
    }

    $templates = Join-Path (Get-FactoryLoopTemplateRoot) 'demo'
    $application = Join-Path $root 'application'
    [void](New-Item -ItemType Directory -Path $application -Force)
    Copy-Item -LiteralPath (Join-Path $templates 'Invoke-DemoApp.ps1') -Destination $application
    Copy-Item -LiteralPath (Join-Path $templates 'Invoke-Acceptance.ps1') -Destination $application
    git -C $root init --initial-branch=main --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the disposable demo Git repository.' }
    git -C $root -c user.name='Factory Loop Demo' -c user.email='factory-loop-demo@localhost' add --all
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stage the disposable demo application.' }
    git -C $root -c user.name='Factory Loop Demo' -c user.email='factory-loop-demo@localhost' commit --quiet -m 'Seed factory-loop demo with planted defect'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the demo source commit.' }
    return [pscustomobject]@{
        demoRoot = $root
        applicationRoot = $application
        sourceSha = (git -C $root rev-parse HEAD).Trim()
        acceptanceStatus = (Test-FactoryLoopArtifactAcceptance -ArtifactPath $application `
                -ExpectedDigest (Get-FactoryLoopApplicationDigest -ApplicationRoot $application)).status
    }
}

function Merge-FactoryLoopDemoPullRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DemoRoot,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$ExpectedSourceSha,
        [switch]$ConfirmMerge
    )

    if (-not $ConfirmMerge) { throw 'A demo pull-request merge requires explicit -ConfirmMerge approval.' }
    if ($Branch -notmatch '^feature/[A-Za-z0-9][A-Za-z0-9._/-]{0,80}$' -or
        $Branch -match '\.\.') {
        throw 'Demo merge accepts only a bounded feature/* branch name.'
    }
    $root = [System.IO.Path]::GetFullPath($DemoRoot)
    $currentBranch = (git -C $root branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -cne 'main') {
        throw 'Demo pull-request merge must start on the local main branch.'
    }
    $status = @(git -C $root status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $status.Count -gt 0) {
        throw 'Demo pull-request merge requires a clean working tree.'
    }
    $sourceSha = (git -C $root rev-parse $Branch).Trim()
    if ($LASTEXITCODE -ne 0 -or $sourceSha -cne $ExpectedSourceSha) {
        throw 'Demo pull-request source head changed; refresh the reviewed source SHA.'
    }
    $targetSha = (git -C $root rev-parse HEAD).Trim()
    git -C $root merge --no-ff --no-edit $Branch --quiet
    if ($LASTEXITCODE -ne 0) { throw 'The real local Git merge failed.' }
    $mergeCommit = (git -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $mergeCommit -ceq $sourceSha -or $mergeCommit -ceq $targetSha) {
        throw 'The demo merge did not produce a distinct merge commit.'
    }
    $parents = (git -C $root rev-list --parents -n 1 HEAD).Trim() -split '\s+'
    if ($parents.Count -ne 3 -or $parents[1] -cne $targetSha -or $parents[2] -cne $sourceSha) {
        throw 'The demo merge commit does not preserve the reviewed source and target parents.'
    }
    return [pscustomobject]@{
        sourceSha = $sourceSha
        targetBeforeMerge = $targetSha
        mergeCommit = $mergeCommit
    }
}

Export-ModuleMember -Function @(
    'Resolve-FactoryLoopConsumerPath',
    'Get-FactoryLoopSetupPreview',
    'Invoke-FactoryLoopSetup',
    'ConvertFrom-FactoryLoopAdapterResult',
    'Invoke-FactoryLoopAdapter',
    'Get-FactoryLoopApplicationDigest',
    'New-FactoryLoopArtifactSnapshot',
    'Test-FactoryLoopArtifactAcceptance',
    'New-FactoryLoopDemoProject',
    'Merge-FactoryLoopDemoPullRequest'
)

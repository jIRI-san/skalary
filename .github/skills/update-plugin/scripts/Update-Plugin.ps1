#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Name,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$Source,

    [string]$Ref,

    [string]$Repository,

    [switch]$Force,

    [switch]$ApplyRetirements
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Common.ps1')

function Get-ResolvedSourceContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetRepoRoot,

        [string]$SourcePath,

        [string]$SourceRef,

        [string]$RemoteRepository
    )

    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        $sourceRepoRoot = Resolve-RepoRoot -StartPath $SourcePath
        $resolvedRef = if ([string]::IsNullOrWhiteSpace($SourceRef)) { 'HEAD' } else { $SourceRef }
        $resolvedSha = (git -C $sourceRepoRoot rev-parse $resolvedRef).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolvedSha)) {
            throw "Unable to resolve ref '$resolvedRef' in source repository '$sourceRepoRoot'."
        }

        $sourceTempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("skalary-update-" + [System.Guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $sourceTempPath -Force)
        git -C $sourceRepoRoot archive $resolvedSha | tar -xf - -C $sourceTempPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to materialize local source snapshot '$resolvedSha' from '$sourceRepoRoot'."
        }

        return [pscustomobject]@{
            IsRemote = $false
            Ref = $resolvedRef
            Sha = $resolvedSha
            SourceIdentity = New-PluginSourceIdentity -LocalPath $sourceRepoRoot
            SourceRepoRoot = $sourceTempPath
            TempPath = $sourceTempPath
        }
    }

    $remote = $RemoteRepository
    if ([string]::IsNullOrWhiteSpace($remote)) {
        $remote = (git -C $TargetRepoRoot remote get-url origin).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) {
            throw "Unable to resolve git remote 'origin' for '$TargetRepoRoot'."
        }
    }

    $resolvedRef = if ([string]::IsNullOrWhiteSpace($SourceRef)) { 'HEAD' } else { $SourceRef }
    $sourceIdentity = $null
    try {
        $sourceIdentity = New-PluginSourceIdentity -Repository $remote
    }
    catch {
        if (-not (Test-Path -LiteralPath $remote)) {
            throw
        }
        $sourceIdentity = New-PluginSourceIdentity -LocalPath (Resolve-RepoRoot -StartPath $remote)
    }

    $resolvedRefs = @(git ls-remote $remote $resolvedRef 2>$null)
    $resolvedLine = $null
    foreach ($line in $resolvedRefs) {
        if ($line -match '\^\{\}\s*$') {
            $resolvedLine = $line
            break
        }
    }
    if ($null -eq $resolvedLine -and $resolvedRefs.Count -gt 0) {
        $resolvedLine = $resolvedRefs[0]
    }
    $resolvedSha = if ($null -ne $resolvedLine) { ($resolvedLine -split '\s+')[0] } else { $null }
    if ([string]::IsNullOrWhiteSpace($resolvedSha)) {
        throw "Unable to resolve remote ref '$resolvedRef' for source '$([string]$sourceIdentity.identity)'."
    }

    $sourceTempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("skalary-update-" + [System.Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $sourceTempPath -Force)

    if ($resolvedRef -eq 'HEAD') {
        git clone -c core.autocrlf=false -c core.eol=lf --depth 1 $remote $sourceTempPath 2>$null | Out-Null
    }
    else {
        git clone -c core.autocrlf=false -c core.eol=lf --depth 1 --branch $resolvedRef $remote $sourceTempPath 2>$null | Out-Null
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone source '$([string]$sourceIdentity.identity)' (ref '$resolvedRef')."
    }

    $clonedSha = (git -C $sourceTempPath rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($clonedSha)) {
        throw "Unable to resolve cloned SHA in '$sourceTempPath'."
    }
    if ($clonedSha -ne $resolvedSha) {
        throw "Remote ref '$resolvedRef' resolved to '$resolvedSha' but clone checked out '$clonedSha'."
    }

    return [pscustomobject]@{
        IsRemote = $true
        Ref = $resolvedRef
        Sha = $resolvedSha
        SourceIdentity = $sourceIdentity
        SourceRepoRoot = $sourceTempPath
        TempPath = $sourceTempPath
    }
}

$targetRepoRoot = Resolve-RepoRoot -StartPath $RepoRoot
$sourceContext = $null
$mutationLock = $null
$operationRoot = $null
$appliedEntries = [System.Collections.Generic.List[object]]::new()
$receiptPath = $null
$receiptBackupPath = $null
$receiptCommitted = $false

try {
    $mutationLock = Enter-PluginMutationLock -RepoRoot $targetRepoRoot
    $sourceContext = Get-ResolvedSourceContext -TargetRepoRoot $targetRepoRoot -SourcePath $Source -SourceRef $Ref -RemoteRepository $Repository
    $sourceRepoRoot = [string]$sourceContext.SourceRepoRoot
    $resolvedSha = [string]$sourceContext.Sha

    $registryPath = Join-Path $sourceRepoRoot 'registry.json'
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
        throw "registry.json not found at source '$sourceRepoRoot'."
    }
    $registry = Read-JsonFile -Path $registryPath

    $retirementResult = Invoke-PluginRetirementReconciliation -RepoRoot $targetRepoRoot -Registry $registry -SourceIdentity $sourceContext.SourceIdentity -DirectTarget $Name -ApplyRetirements:$ApplyRetirements -LockHeld
    Write-PluginRetirementRecord -Result $retirementResult
    if ($retirementResult.ExitCode -ne 0) {
        exit ([int]$retirementResult.ExitCode)
    }

    $receipt = Read-PluginReceipt -RepoRoot $targetRepoRoot -PluginName $Name
    if ($null -eq $receipt) {
        throw "Plugin '$Name' is not installed (receipt missing)."
    }
    $plugin = @($registry.plugins | Where-Object { [string]$_.name -eq $Name } | Select-Object -First 1)
    if ($plugin.Count -eq 0) {
        throw "Plugin '$Name' is not present in source registry."
    }
    $plugin = $plugin[0]

    $versionComparison = Compare-SemVer -Left ([string]$receipt.version) -Right ([string]$plugin.version)
    if ($versionComparison -gt 0) {
        throw "Installed version '$($receipt.version)' is newer than registry version '$($plugin.version)'. Refusing downgrade."
    }

    $pluginRoot = Join-Path $sourceRepoRoot "plugins/$Name"
    if (-not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
        throw "Plugin '$Name' source directory is missing in '$sourceRepoRoot/plugins/'."
    }

    $registryFiles = @($plugin.files | Where-Object { [string]$_.src -notmatch '^evals(?:/|$)' } | Sort-Object dest, src)
    if ($registryFiles.Count -eq 0) {
        throw "Plugin '$Name' has no installable files in registry."
    }

    $receiptByDest = @{}
    foreach ($receiptFile in @($receipt.files)) {
        $receiptByDest[[string]$receiptFile.dest] = $receiptFile
    }

    $ownerByDest = @{}
    $receiptsRoot = Join-Path $targetRepoRoot '.github/.skalary/receipts'
    if (Test-Path -LiteralPath $receiptsRoot -PathType Container) {
        foreach ($otherReceiptPath in Get-ChildItem -LiteralPath $receiptsRoot -File -Filter '*.json') {
            $otherReceipt = Read-JsonFile -Path $otherReceiptPath.FullName
            foreach ($ownedFile in @($otherReceipt.files)) {
                $ownedPath = Resolve-GithubConstrainedPath -RepoRoot $targetRepoRoot `
                    -RelativePath ([string]$ownedFile.dest)
                Assert-GithubStatePathSafe -RepoRoot $targetRepoRoot -Path $ownedPath
                $ownerKey = [System.IO.Path]::GetFullPath($ownedPath).ToLowerInvariant()
                $owner = [string]$otherReceipt.name
                if ($ownerByDest.ContainsKey($ownerKey) -and $ownerByDest[$ownerKey] -cne $owner) {
                    throw "Existing receipt ownership collision for '$([string]$ownedFile.dest)'."
                }
                $ownerByDest[$ownerKey] = $owner
            }
        }
    }

    $operationRoot = Resolve-GithubConstrainedPath -RepoRoot $targetRepoRoot `
        -RelativePath (".skalary/tmp/update-" + [guid]::NewGuid().ToString('N'))
    Assert-GithubStatePathSafe -RepoRoot $targetRepoRoot -Path $operationRoot
    $stagedRoot = Join-Path $operationRoot 'staged'
    $backupRoot = Join-Path $operationRoot 'backups'
    [void](New-Item -ItemType Directory -Path $stagedRoot -Force)
    [void](New-Item -ItemType Directory -Path $backupRoot -Force)
    Assert-GithubStatePathSafe -RepoRoot $targetRepoRoot -Path $stagedRoot
    Assert-GithubStatePathSafe -RepoRoot $targetRepoRoot -Path $backupRoot

    $updatedCount = 0
    $skippedCount = 0
    $nextReceiptFiles = @()
    $operations = [System.Collections.Generic.List[object]]::new()
    $newDestinations = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $operationIndex = 0

    foreach ($file in $registryFiles) {
        $src = [string]$file.src
        $dest = [string]$file.dest
        [void]$newDestinations.Add($dest)
        $expectedNewSha = [string]$file.sha256
        $targetPath = Resolve-GithubConstrainedPath -RepoRoot $targetRepoRoot -RelativePath $dest
        Assert-GithubStatePathSafe -RepoRoot $targetRepoRoot -Path $targetPath
        $sourcePath = Resolve-PluginConstrainedPath -PluginRoot $pluginRoot -RelativePath $src

        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Plugin '$Name' source '$src' is missing from source snapshot."
        }
        $sourceHash = Get-FileSha256 -Path $sourcePath
        if ($sourceHash -ne $expectedNewSha) {
            throw "Source hash mismatch for '$Name' file '$src': expected '$expectedNewSha', got '$sourceHash'."
        }

        $hasTarget = Test-Path -LiteralPath $targetPath -PathType Leaf
        $actualCurrentSha = if ($hasTarget) { Get-FileSha256 -Path $targetPath } else { $null }
        $hasReceiptEntry = $receiptByDest.ContainsKey($dest)
        $expectedCurrentSha = if ($hasReceiptEntry) { [string]$receiptByDest[$dest].sha256 } else { $null }
        $targetKey = [System.IO.Path]::GetFullPath($targetPath).ToLowerInvariant()
        if ($ownerByDest.ContainsKey($targetKey) -and
            [string]$ownerByDest[$targetKey] -cne $Name) {
            throw "Refusing overwrite of '$dest': owned by installed plugin '$($ownerByDest[$targetKey])'."
        }

        if (-not $Force) {
            if (-not $hasReceiptEntry -and $hasTarget) {
                throw "New destination '$dest' already exists and is not owned by '$Name'. Use -Force to overwrite."
            }
            if ($hasReceiptEntry -and -not $hasTarget) {
                throw "Installed destination '$dest' is missing on disk. Use -Force to recreate it."
            }
            if ($hasReceiptEntry -and $actualCurrentSha -ne $expectedCurrentSha) {
                $nextReceiptFiles += [pscustomobject]@{
                    dest = $dest
                    outcome = 'skipped-modified'
                    sha256 = $expectedCurrentSha
                }
                $skippedCount++
                continue
            }
        }

        $stagePath = Join-Path $stagedRoot ('{0:d5}-{1}' -f $operationIndex, [System.IO.Path]::GetFileName($dest))
        Copy-Item -LiteralPath $sourcePath -Destination $stagePath -Force
        if ((Get-FileSha256 -Path $stagePath) -ne $expectedNewSha) {
            throw "Staged hash mismatch for '$dest'."
        }
        $operations.Add([pscustomobject]@{
                Kind = 'write'
                Dest = $dest
                TargetPath = $targetPath
                StagePath = $stagePath
                BackupPath = Join-Path $backupRoot ('{0:d5}.bak' -f $operationIndex)
            })
        $operationIndex++

        $nextReceiptFiles += [pscustomobject]@{
            dest = $dest
            outcome = 'updated'
            sha256 = $expectedNewSha
        }
        $updatedCount++
    }

    foreach ($retiredEntry in @($receipt.files)) {
        $dest = [string]$retiredEntry.dest
        if ($newDestinations.Contains($dest)) { continue }

        $targetPath = Resolve-GithubConstrainedPath -RepoRoot $targetRepoRoot -RelativePath $dest
        Assert-GithubStatePathSafe -RepoRoot $targetRepoRoot -Path $targetPath
        $targetKey = [System.IO.Path]::GetFullPath($targetPath).ToLowerInvariant()
        if ($ownerByDest.ContainsKey($targetKey) -and
            [string]$ownerByDest[$targetKey] -cne $Name) {
            throw "Refusing removal of retired destination '$dest': owned by installed plugin '$($ownerByDest[$targetKey])'."
        }
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            continue
        }

        $expectedCurrentSha = [string]$retiredEntry.sha256
        $actualCurrentSha = Get-FileSha256 -Path $targetPath
        if (-not $Force -and $actualCurrentSha -ne $expectedCurrentSha) {
            $nextReceiptFiles += [pscustomobject]@{
                dest = $dest
                outcome = 'skipped-modified'
                sha256 = $expectedCurrentSha
            }
            $skippedCount++
            Write-Warning "Retired destination '$dest' is modified; preserving it as managed residue."
            continue
        }

        $operations.Add([pscustomobject]@{
                Kind = 'delete'
                Dest = $dest
                TargetPath = $targetPath
                StagePath = $null
                BackupPath = Join-Path $backupRoot ('{0:d5}.bak' -f $operationIndex)
            })
        $operationIndex++
    }

    $allUpdated = ($skippedCount -eq 0)
    $receiptVersion = if ($allUpdated) { [string]$plugin.version } else { [string]$receipt.version }
    $receiptOutput = [ordered]@{
        evalStatus = if ($receipt.PSObject.Properties.Name -contains 'evalStatus' -and $null -ne $receipt.evalStatus) { [string]$receipt.evalStatus } else { 'none' }
        files = $nextReceiptFiles
        installedAt = (Get-Date).ToUniversalTime().ToString('o')
        name = $Name
        ref = $resolvedSha
        sourceIdentity = $sourceContext.SourceIdentity
        version = $receiptVersion
    }
    if (-not $allUpdated) {
        $receiptOutput.degraded = $true
    }

    $stagedReceiptPath = Join-Path $operationRoot 'receipt.json'
    Write-JsonFileStable -Path $stagedReceiptPath -InputObject ([pscustomobject]$receiptOutput)

    foreach ($operation in $operations) {
        $targetDir = Split-Path -Parent ([string]$operation.TargetPath)
        if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $targetDir -Force)
        }
        Assert-GithubStatePathSafe -RepoRoot $targetRepoRoot -Path $operation.TargetPath
        $entry = [pscustomobject]@{ Operation = $operation; HadTarget = $false; WroteTarget = $false }
        $appliedEntries.Add($entry)
        if (Test-Path -LiteralPath $operation.TargetPath -PathType Leaf) {
            Move-Item -LiteralPath $operation.TargetPath -Destination $operation.BackupPath -Force
            $entry.HadTarget = $true
        }
        if ($operation.Kind -eq 'write') {
            Move-Item -LiteralPath $operation.StagePath -Destination $operation.TargetPath -Force
            $entry.WroteTarget = $true
            if ((Get-FileSha256 -Path $operation.TargetPath) -ne
                [string]$receiptOutput.files.Where({ $_.dest -ceq $operation.Dest }, 'First').sha256) {
                throw "Write verification failed for '$($operation.Dest)'."
            }
        }
    }

    $receiptPath = Get-PluginReceiptPath -RepoRoot $targetRepoRoot -PluginName $Name
    Assert-GithubStatePathSafe -RepoRoot $targetRepoRoot -Path $receiptPath
    $receiptBackupPath = Join-Path $operationRoot 'receipt.backup.json'
    Move-Item -LiteralPath $receiptPath -Destination $receiptBackupPath -Force
    Move-Item -LiteralPath $stagedReceiptPath -Destination $receiptPath -Force
    $receiptCommitted = $true

    if ($allUpdated) {
        Write-Output "Updated plugin '$Name' to version '$($plugin.version)' at '$resolvedSha' ($updatedCount current file(s), $(@($operations | Where-Object Kind -eq 'delete').Count) retired file(s) removed)."
    }
    else {
        Write-Warning "Plugin '$Name' updated partially: $skippedCount file(s) skipped as modified. Receipt marked degraded."
        Write-Output "Plugin '$Name' remains at version '$($receipt.version)' with refreshed ref '$resolvedSha'."
    }
}
catch {
    if ($receiptCommitted -and -not [string]::IsNullOrWhiteSpace($receiptPath) -and
        (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        Remove-Item -LiteralPath $receiptPath -Force
    }
    if (-not [string]::IsNullOrWhiteSpace($receiptBackupPath) -and
        (Test-Path -LiteralPath $receiptBackupPath -PathType Leaf)) {
        Move-Item -LiteralPath $receiptBackupPath -Destination $receiptPath -Force
    }
    foreach ($entry in @($appliedEntries) | Sort-Object { $_.Operation.Dest } -Descending) {
        if ($entry.WroteTarget -and (Test-Path -LiteralPath $entry.Operation.TargetPath -PathType Leaf)) {
            Remove-Item -LiteralPath $entry.Operation.TargetPath -Force
        }
        if ($entry.HadTarget -and (Test-Path -LiteralPath $entry.Operation.BackupPath -PathType Leaf)) {
            $targetDir = Split-Path -Parent ([string]$entry.Operation.TargetPath)
            if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $targetDir -Force)
            }
            Move-Item -LiteralPath $entry.Operation.BackupPath -Destination $entry.Operation.TargetPath -Force
        }
    }
    throw
}
finally {
    if ($null -ne $mutationLock) {
        $mutationLock.Dispose()
    }
    if ($null -ne $sourceContext -and -not [string]::IsNullOrWhiteSpace([string]$sourceContext.TempPath)) {
        Remove-Item -LiteralPath ([string]$sourceContext.TempPath) -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not [string]::IsNullOrWhiteSpace($operationRoot) -and
        (Test-Path -LiteralPath $operationRoot -PathType Container)) {
        Remove-Item -LiteralPath $operationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0

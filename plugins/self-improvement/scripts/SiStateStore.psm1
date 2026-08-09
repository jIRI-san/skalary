#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SiStateContract = [pscustomobject]@{
    ManifestVersion = 2
    RunVersion = 2
    ResolverReceiptVersion = 1
    RepairObservationVersion = 1
    RepairReceiptVersion = 1
    Status = [pscustomobject]@{
        Absent = 0
        Valid = 0
        RepairableOrphans = 2
        RepairableCorrupt = 2
        MigrationRequired = 2
        ForwardReadonly = 3
        ForwardBlocked = 3
        CapacityBlocked = 4
        Invalid = 5
        LockTimeout = 6
        CasConflict = 7
        CasExhausted = 8
        ApplyIncomplete = 9
    }
    Limits = [pscustomobject]@{
        ManifestBytes = 256KB
        PendingDues = 128
        RecentRunReferences = 64
        ActiveCompletedRuns = 32
        ActiveInFlightRuns = 16
        ArchivedRuns = 4096
        RunsPerShard = 256
        RunBytes = 1MB
        RankedCandidates = 5
        LockSeconds = 30
        CasRetries = 3
        AuxiliaryRecordsPerKind = 256
        ResolverReceipts = 512
    }
    Topology = [pscustomobject]@{
        RootSegments = @('docs', 'self-improvement')
        ManifestName = 'state.json'
        ActiveRunsSegments = @('runs')
        ArchiveSegments = @('archive')
        BackupSegments = @('backups')
        QuarantineSegments = @('quarantine')
        ObservationSegments = @('repair-observations')
        ReceiptSegments = @('repair-receipts')
        ResolverReceiptSegments = @('resolver-receipts')
        LockName = '.state.lock'
    }
    TransactionOrder = @(
        'acquire-lock',
        'read-generation',
        'write-random-temp',
        'validate-temp',
        'recheck-generation',
        'replace-run-before-manifest',
        'replace-manifest',
        'release-lock'
    )
}

function Get-SiStateContract {
    [CmdletBinding()]
    param()

    return $script:SiStateContract
}

function Assert-SiStateImplementationAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName
    )

    throw "$CommandName is contract-only until plan 1936cb step 1.2 installs the shared atomic store implementation."
}

Export-ModuleMember -Function Get-SiStateContract, Assert-SiStateImplementationAvailable

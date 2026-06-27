#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'PlanState New-PlanId' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'test:new-planid-format emits 6 crypto-random hex chars' {
        for ($i = 0; $i -lt 25; $i++) {
            $id = New-PlanId -ExistingId @()
            $id | Should -Match '^[0-9a-f]{6}$'
        }
    }

    It 'test:new-planid-format scans the repo inventory when -ExistingId is omitted' {
        $id = New-PlanId -RepoRoot $repoRoot
        $id | Should -Match '^[0-9a-f]{6}$'
        $existing = @(Get-PlanInventory -RepoRoot $repoRoot | ForEach-Object { $_.Id })
        $existing | Should -Not -Contain $id
    }

    It 'test:new-planid-collision regenerates on a full-id collision' {
        $state = [pscustomobject]@{ Calls = 0 }
        $provider = {
            $state.Calls++
            switch ($state.Calls) {
                1 { 'aaaaaa' }
                2 { 'aaaaaa' }
                default { 'bbbbbb' }
            }
        }.GetNewClosure()

        $id = New-PlanId -ExistingId @('aaaaaa') -HexProvider $provider
        $id | Should -Be 'bbbbbb'
        $state.Calls | Should -BeGreaterThan 1
    }

    It 'test:new-planid-collision matches existing ids case-insensitively' {
        $state = [pscustomobject]@{ Calls = 0 }
        $provider = {
            $state.Calls++
            if ($state.Calls -eq 1) { 'ABCDEF' } else { '012345' }
        }.GetNewClosure()

        $id = New-PlanId -ExistingId @('abcdef') -HexProvider $provider
        $id | Should -Be '012345'
    }

    It 'test:new-planid-collision warns when the 4-char prefix is not unique' {
        $provider = { 'aaaa00' }
        $warnings = @()
        $id = New-PlanId -ExistingId @('aaaa99') -HexProvider $provider -WarningVariable warnings -WarningAction SilentlyContinue
        $id | Should -Be 'aaaa00'
        ($warnings -join ' ') | Should -Match 'not uniquely addressable'
    }

    It 'test:new-planid-collision does not warn when the prefix is unique' {
        $provider = { 'abcd00' }
        $warnings = @()
        $id = New-PlanId -ExistingId @('ef0099') -HexProvider $provider -WarningVariable warnings -WarningAction SilentlyContinue
        $id | Should -Be 'abcd00'
        ($warnings -join ' ') | Should -Not -Match 'not uniquely addressable'
    }

    It 'throws when generation cannot find a unique id' {
        { New-PlanId -ExistingId @('aaaaaa') -HexProvider { 'aaaaaa' } -MaxAttempts 5 } | Should -Throw
    }
}

Describe 'PlanState Get-PlanInventory' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'parses legacy and new-scheme folders' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("inv-" + [guid]::NewGuid().ToString('N'))
        $plans = Join-Path $root 'docs/implementation-plans'
        $archived = Join-Path $plans 'archived'
        New-Item -ItemType Directory -Path $archived -Force | Out-Null

        $legacy = Join-Path $archived '003-old-thing'
        New-Item -ItemType Directory -Path $legacy -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $legacy 'plan.md') -Value "# legacy`n" -Encoding utf8NoBOM

        $new = Join-Path $plans '2026-06-27-abc123-shiny'
        New-Item -ItemType Directory -Path $new -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $new 'plan.md') -Value "# new`n<!-- plan-id: abc123 -->`n" -Encoding utf8NoBOM

        try {
            $inv = @(Get-PlanInventory -RepoRoot $root)
            ($inv | Where-Object Scheme -eq 'legacy').Id | Should -Be '003'
            ($inv | Where-Object Scheme -eq 'legacy').IsArchived | Should -BeTrue
            $newEntry = $inv | Where-Object Scheme -eq 'new'
            $newEntry.Id | Should -Be 'abc123'
            $newEntry.Slug | Should -Be 'shiny'
            $newEntry.Date | Should -Be '2026-06-27'
            $newEntry.IsArchived | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'prefers the plan-id anchor over the folder-derived id' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("inv-" + [guid]::NewGuid().ToString('N'))
        $plans = Join-Path $root 'docs/implementation-plans'
        $dir = Join-Path $plans '2026-06-27-ffffff-anchored'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'plan.md') -Value "# x`n<!-- plan-id: 9f9f9f -->`n" -Encoding utf8NoBOM
        try {
            $inv = @(Get-PlanInventory -RepoRoot $root)
            $inv.Count | Should -Be 1
            $inv[0].Id | Should -Be '9f9f9f'
            $inv[0].FolderId | Should -Be 'ffffff'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'PlanState Resolve-Plan' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking

        function New-InvEntry {
            param($Id, $Scheme, $Slug, $Date, $FolderName)
            [pscustomobject]@{
                Id = $Id; FolderId = $Id; AnchorId = $null; Scheme = $Scheme
                Slug = $Slug; Date = $Date; FolderName = $FolderName
                Path = "C:/fake/$FolderName"; IsArchived = $false
            }
        }

        $inv = @(
            New-InvEntry -Id '7645b1' -Scheme 'new' -Slug 'optimize-ci-cip-plugins' -Date '2026-06-27' -FolderName '2026-06-27-7645b1-optimize-ci-cip-plugins'
            New-InvEntry -Id '7645c2' -Scheme 'new' -Slug 'colliding-prefix' -Date '2026-06-28' -FolderName '2026-06-28-7645c2-colliding-prefix'
            New-InvEntry -Id '88ab00' -Scheme 'new' -Slug 'another-thing' -Date '2026-06-30' -FolderName '2026-06-30-88ab00-another-thing'
            New-InvEntry -Id '012345' -Scheme 'new' -Slug 'numeric-hash' -Date '2026-06-29' -FolderName '2026-06-29-012345-numeric-hash'
            New-InvEntry -Id '007' -Scheme 'legacy' -Slug 'workflow-memory-ledger' -Date $null -FolderName '007-workflow-memory-ledger'
        )
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'test:resolve-plan-hash-prefix resolves a unique hash prefix to the canonical id' {
        (Resolve-Plan -Reference '88ab' -RepoRoot 'x' -Inventory $inv).Id | Should -Be '88ab00'
    }

    It 'test:resolve-plan-hash-prefix resolves a full hash id' {
        (Resolve-Plan -Reference '7645b1' -RepoRoot 'x' -Inventory $inv).Id | Should -Be '7645b1'
    }

    It 'test:resolve-plan-hash-prefix is case-insensitive' {
        (Resolve-Plan -Reference '7645B1' -RepoRoot 'x' -Inventory $inv).Id | Should -Be '7645b1'
    }

    It 'test:resolve-plan-legacy-number resolves a 3-digit legacy id' {
        (Resolve-Plan -Reference '007' -RepoRoot 'x' -Inventory $inv).Id | Should -Be '007'
    }

    It 'test:resolve-plan-ambiguous errors git-style on a non-unique prefix' {
        { Resolve-Plan -Reference '7645' -RepoRoot 'x' -Inventory $inv } | Should -Throw -ExpectedMessage '*Ambiguous*'
    }

    It 'test:resolve-plan-alldigit-hash treats a 6-digit reference as a hash, not a legacy number' {
        (Resolve-Plan -Reference '012345' -RepoRoot 'x' -Inventory $inv).Id | Should -Be '012345'
    }

    It 'test:resolve-plan-alldigit-hash does not match a hash plan when querying a 3-digit legacy number' {
        { Resolve-Plan -Reference '012' -RepoRoot 'x' -Inventory $inv } | Should -Throw -ExpectedMessage '*No plan matches*'
    }

    It 'resolves by exact slug' {
        (Resolve-Plan -Reference 'another-thing' -RepoRoot 'x' -Inventory $inv).Id | Should -Be '88ab00'
    }

    It 'resolves by date when unique' {
        (Resolve-Plan -Reference '2026-06-27' -RepoRoot 'x' -Inventory $inv).Id | Should -Be '7645b1'
    }

    It 'errors when nothing matches' {
        { Resolve-Plan -Reference 'zzzz99' -RepoRoot 'x' -Inventory $inv } | Should -Throw -ExpectedMessage '*No plan matches*'
    }
}

Describe 'PlanState Get-PlanHeaderMarkers' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking

        $planContent = @'
# 7645b1: Sample plan

<!-- plan-id: 7645b1 -->
<!-- execution-mode: manual -->
<!-- scope: step -->
<!-- cip-stage: dr-round-2 -->
<!-- depends-on: 006, abc123 -->

## Phase 1
<!-- worktree: agents/sample -->

- [x] 1.1 First step `S`
'@
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'test:get-planheadermarkers parses the named header markers from content' {
        $markers = Get-PlanHeaderMarkers -Content $planContent
        $markers.PlanId | Should -Be '7645b1'
        $markers.ExecutionMode | Should -Be 'manual'
        $markers.Scope | Should -Be 'step'
        $markers.CipStage | Should -Be 'dr-round-2'
    }

    It 'test:get-planheadermarkers splits depends-on into a trimmed array' {
        $markers = Get-PlanHeaderMarkers -Content $planContent
        $markers.DependsOn | Should -Be @('006', 'abc123')
    }

    It 'test:get-planheadermarkers ignores markers below the first heading' {
        $markers = Get-PlanHeaderMarkers -Content $planContent
        $markers.All.Contains('worktree') | Should -BeFalse
    }

    It 'test:get-planheadermarkers returns nulls and an empty array when markers are absent' {
        $markers = Get-PlanHeaderMarkers -Content "# Title`n`n## Phase 1`n"
        $markers.PlanId | Should -BeNullOrEmpty
        $markers.ExecutionMode | Should -BeNullOrEmpty
        @($markers.DependsOn).Count | Should -Be 0
    }
}

Describe 'PlanState Get-PlanProgress' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking

        function New-Step {
            param($Id, $Status, $Phase)
            [pscustomobject]@{ Id = $Id; Status = $Status; Phase = $Phase }
        }

        $metadata = [pscustomobject]@{
            Steps = @(
                New-Step -Id '1.1' -Status 'x' -Phase '## Phase 1: Foundation'
                New-Step -Id '1.2' -Status 'x' -Phase '## Phase 1: Foundation'
                New-Step -Id '2.1' -Status '~' -Phase '## Phase 2: State commands'
                New-Step -Id '2.2' -Status ' ' -Phase '## Phase 2: State commands'
                New-Step -Id '3.1' -Status ' ' -Phase '## Phase 3: Scripts'
            )
        }
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'test:get-planprogress-counts reports completed/in-progress/pending counts' {
        $progress = Get-PlanProgress -Metadata $metadata
        $progress.Total | Should -Be 5
        $progress.Completed | Should -Be 2
        $progress.InProgress | Should -Be 1
        $progress.Pending | Should -Be 2
    }

    It 'test:get-planprogress-counts reports the current phase and last completed step' {
        $progress = Get-PlanProgress -Metadata $metadata
        $progress.CurrentPhase | Should -Be '## Phase 2: State commands'
        $progress.LastCompleted | Should -Be '1.2'
        $progress.IsComplete | Should -BeFalse
    }

    It 'test:get-planprogress-counts marks a fully completed plan and pins the last phase' {
        $allDone = [pscustomobject]@{
            Steps = @(
                New-Step -Id '1.1' -Status 'x' -Phase '## Phase 1: Foundation'
                New-Step -Id '2.1' -Status 'x' -Phase '## Phase 2: Done'
            )
        }
        $progress = Get-PlanProgress -Metadata $allDone
        $progress.IsComplete | Should -BeTrue
        $progress.Percent | Should -Be 100
        $progress.CurrentPhase | Should -Be '## Phase 2: Done'
    }
}

Describe 'PlanState Get-NextStep' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking

        function New-FullStep {
            param($Id, $Status, $Role = 'ai-agent', $After = @(), $Body = 'body')
            [pscustomobject]@{ Id = $Id; Status = $Status; Role = $Role; After = $After; Body = $Body; Phase = '## Phase 1' }
        }
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'test:get-nextstep-after returns the first non-complete step in top-down order' {
        $meta = [pscustomobject]@{ Steps = @(
            New-FullStep -Id '1.1' -Status 'x'
            New-FullStep -Id '1.2' -Status '~'
            New-FullStep -Id '1.3' -Status ' '
        ) }
        $next = Get-NextStep -Metadata $meta
        $next.Id | Should -Be '1.2'
        $next.IsComplete | Should -BeFalse
    }

    It 'test:get-nextstep-after flags blockedByAfter when an [after:] dependency is incomplete' {
        $meta = [pscustomobject]@{ Steps = @(
            New-FullStep -Id '1.1' -Status ' '
            New-FullStep -Id '2.1' -Status 'x'
            New-FullStep -Id '3.1' -Status ' ' -After @('1.1', '2.1')
        ) }
        $next = Get-NextStep -Metadata $meta
        $next.Id | Should -Be '1.1'
        $next.BlockedByAfter | Should -BeFalse

        $meta2 = [pscustomobject]@{ Steps = @(
            New-FullStep -Id '1.1' -Status 'x'
            New-FullStep -Id '3.1' -Status ' ' -After @('1.1', '2.9')
        ) }
        $next2 = Get-NextStep -Metadata $meta2
        $next2.Id | Should -Be '3.1'
        $next2.BlockedByAfter | Should -BeTrue
        $next2.UnmetAfter | Should -Be @('2.9')
    }

    It 'test:get-nextstep-flags surfaces isHuman, isDiscovery, and hasUncommittedChanges' {
        $meta = [pscustomobject]@{ Steps = @(
            New-FullStep -Id '1.1' -Status ' ' -Role 'human' -Body 'Manual review [discovery] of X'
        ) }
        $next = Get-NextStep -Metadata $meta -HasUncommittedChanges
        $next.IsHuman | Should -BeTrue
        $next.IsDiscovery | Should -BeTrue
        $next.HasUncommittedChanges | Should -BeTrue
    }

    It 'test:get-nextstep-flags reports IsComplete when no step remains' {
        $meta = [pscustomobject]@{ Steps = @(
            New-FullStep -Id '1.1' -Status 'x'
            New-FullStep -Id '1.2' -Status 'x'
        ) }
        $next = Get-NextStep -Metadata $meta
        $next.IsComplete | Should -BeTrue
        $next.Step | Should -BeNullOrEmpty
    }
}


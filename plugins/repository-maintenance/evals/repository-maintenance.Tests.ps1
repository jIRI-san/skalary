#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'repository-maintenance structural evals' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/repository-maintenance'
        $script:manifest = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 30
        $script:skill = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/rcs/SKILL.md'
        ) -Raw
        $script:audit = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/rcs/assets/audit-guide.md'
        ) -Raw
        $script:decisions = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/rcs/assets/decision-guide.md'
        ) -Raw
        $script:all = $script:skill + "`n" + $script:audit + "`n" + $script:decisions
        $script:destinations = @($script:manifest.files | ForEach-Object { [string]$_.dest })
    }

    It 'eval:RCS.AlignmentContract requires evidence, counter-evidence, exception, and uncertainty' {
        foreach ($term in @(
                'Defect/drift', 'Alignment question', 'Unfinished work', 'Optional improvement',
                'Coverage gap', 'exceptions\s+and counter-evidence', 'trigger', 'specific lines or symbols',
                'confirmed criterion or locked contract', 'incomplete'
            )) {
            $script:audit | Should -Match $term
        }
        $script:skill | Should -Match 'Do not claim unexamined areas are clean'
    }

    It 'eval:RCS.CodebaseQualityContract applies local standards and Simplicity First' {
        foreach ($term in @(
                'active local standards', 'Simplicity First', 'codebase-wide architecture/design proposals',
                'smallest corrective change', 'benefit', 'tradeoff', 'Effort', 'Complexity'
            )) {
            $script:audit | Should -Match ([regex]::Escape($term))
        }
        $script:audit | Should -Match 'without a claimed requirement violation'
    }

    It 'eval:RCS.DeadCodeContract investigates supported roots and rejects no-reference proof' {
        foreach ($term in @(
                'No-reference alone is insufficient', 'public/exported APIs', 'manual\s+maintenance tools',
                'tests', 'configuration', 'reflection', 'dynamic dispatch', 'generated code',
                'external consumers', 'never deletes code'
            )) {
            $script:audit | Should -Match $term
        }
        $script:audit | Should -Match 'uncertainty and propose investigation'
    }

    It 'eval:RCS.RecommendationContract lists all actionable evidence and sizing fields' {
        foreach ($term in @(
                'category', 'subject and scope', 'specific citations', 'current behavior/reachability',
                'trigger', 'impact', 'exceptions/counter-evidence', 'uncertainty', 'smallest action',
                'benefits and tradeoffs', 'effort and complexity'
            )) {
            $script:audit | Should -Match ([regex]::Escape($term))
        }
    }

    It 'eval:RCS.BoundaryContract keeps review read-only and all corrective/archive actions explicit' {
        foreach ($term in @(
                'read-only', 'at most three artifacts total', 'already-framed result a second time',
                'No silence-based dispositions', 'ConvertTo-UntrustedReviewBlock',
                'Do not change code', 'delete candidates', 'commit, push', 'broad/premium',
                'full documentation/reference sweep', 'network crawl'
            )) {
            $script:all | Should -Match ([regex]::Escape($term))
        }
        $script:skill | Should -Match 'link only after successful creation/update'
        $script:decisions | Should -Match 'No disposition is inferred from silence'
        $script:decisions | Should -Match 'separate explicit operator choice'
        $script:skill | Should -Match 'Delegate only for one concrete unresolved concern'
    }

    It 'test:RCS.InventoryCoverage probes plans before the index and labels every coverage state' {
        foreach ($term in @(
                'Probe for', 'Get-PlanIndex.ps1', 'PlanState.psm1', 'malformed-plan errors',
                'at most three artifacts total'
            )) {
            $script:skill | Should -Match $term
        }
        $script:skill.IndexOf('Probe for', [StringComparison]::Ordinal) |
            Should -BeLessThan $script:skill.IndexOf('Get-PlanIndex.ps1', [StringComparison]::Ordinal)
        $script:audit | Should -Match 'Surveyed,\s*traced,\s*skipped,\s*blocked,\s*and unread'
        $script:audit | Should -Match 'absent corpora'
        $script:audit | Should -Match 'legacy layout'
        $script:skill | Should -Match 'unread sources'
    }

    It 'test:RCS.ArchiveHandoff uses existing gates and distinguishes standalone and epic routes' {
        $script:skill | Should -Match '(?s)installed.*Archive-Epic\.ps1|Archive-Epic\.ps1.*installed'
        $script:skill | Should -Match 'no standalone archive\s+script'
        $script:decisions | Should -Match 'unarchived epic children'
        $script:decisions | Should -Match 'destination\s+collisions'
        $script:decisions | Should -Match 'already archived item is a no-op'
        $script:decisions | Should -Match 'unknown\s+state\s+is\s+not\s+evidence\s+of\s+completion'
        $script:decisions | Should -Match 'route is missing or unclear.*stop pending'
        $script:decisions | Should -Match 'clean maintenance\s+report'
        $script:decisions | Should -Match 'old review does not prove completion'
        $script:decisions | Should -Match 'After a separate explicit operator choice'
        $script:decisions | Should -Match 'Record a successful archive only after verifying'
    }

    It 'test:RCS.CorrectivePlanHandoff checks overlap and records only successful selected outcomes' {
        $script:decisions | Should -Match 'Search current active plans for outcome, scope, and evidence overlap'
        $script:decisions | Should -Match 'reuse/update before new creation'
        $script:decisions | Should -Match 'operator selects the exact plan'
        $script:decisions | Should -Match 'original\s+expectation, current evidence'
        $script:decisions | Should -Match 'changed confirmed criteria must be\s+reconfirmed'
        $script:decisions | Should -Match 'locked-contract changes use the architecture-maintenance approval flow'
        $script:decisions | Should -Match 'cancelled, incomplete, or fails'
        $script:decisions | Should -Match 'Creating a plan is not a delivered fix'
        $script:decisions | Should -Match 'only after its actual outcome is established'
    }

    It 'test:RCS.RecordRoundTrip declares exact identity matching and preserves operator history' {
        $helper = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/rcs/Write-RepositoryMaintenanceRecord.ps1'
        ) -Raw
        $helper | Should -Match 'ambiguous identity'
        $helper | Should -Match 'no content was changed'
        $helper | Should -Match 'RecordDisposition'
        $script:decisions | Should -Match 'older rationale'
        $script:skill | Should -Match 'unseen findings open'
    }

    It 'test:RCS.RecordRefusal fixes the write path and rejects links, secrets, malformed bytes, and overflow' {
        $helper = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/rcs/Write-RepositoryMaintenanceRecord.ps1'
        ) -Raw
        foreach ($term in @(
                "docs/repository-maintenance.md", 'Resolve-PhysicalRepoPath',
                'ReparsePoint', 'Find-HighConfidenceSecret', 'UTF8Encoding', '$script:Limit',
                'File]::Move'
            )) {
            $helper | Should -Match ([regex]::Escape($term))
        }
        @($script:manifest.scaffolds).Count | Should -Be 1
        $script:manifest.scaffolds[0].path | Should -BeExactly 'docs/repository-maintenance.md'
        $script:manifest.scaffolds[0].mode | Should -BeExactly 'literal'
        $script:manifest.scaffolds[0].PSObject.Properties.Name |
            Should -Not -Contain 'confine'
    }

    It 'test:RCS.ConsumerInstall declares a closed payload and bounded skill' {
        foreach ($path in @(
                'skills/rcs/SKILL.md',
                'skills/rcs/assets/audit-guide.md',
                'skills/rcs/assets/decision-guide.md',
                'skills/rcs/assets/record-template.md',
                'skills/rcs/Write-RepositoryMaintenanceRecord.ps1',
                'skills/rcs/scripts/Get-PlanIndex.ps1',
                'skills/rcs/scripts/Get-PlanState.ps1',
                'skills/rcs/scripts/Get-DirectPlanArtifactConsumerContext.ps1',
                'skills/rcs/scripts/Archive-Epic.ps1',
                'skills/rcs/scripts/New-Epic.ps1',
                'skills/rcs/scripts/PlanState.psm1',
                'skills/rcs/scripts/DirectWorkflow.psm1',
                'skills/rcs/scripts/SecretGuard.psm1'
            )) {
            $script:destinations | Should -Contain $path
        }
        [System.Text.Encoding]::UTF8.GetByteCount($script:skill) | Should -BeLessThan 12000
        $script:manifest.dependencies | Should -BeNullOrEmpty
        $script:all | Should -Not -Match '(?m)(?:\./plugins/|scripts/skalary/)'
        $script:manifest.name | Should -BeExactly 'repository-maintenance'
    }

    It 'eval:RCS.ConsumerInstall uses the required installed writer and historical reader closure' {
        $script:skill | Should -Match '\.github/skills/rcs/Write-RepositoryMaintenanceRecord\.ps1'
        $script:skill | Should -Match '\.github/skills/rcs/scripts/Get-DirectPlanArtifactConsumerContext\.ps1'
        $script:skill | Should -Match '\.github/skills/rcs/scripts/Get-PlanIndex\.ps1'
        $script:manifest.scaffolds[0].path | Should -BeExactly 'docs/repository-maintenance.md'
    }
}

#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance scenario trace' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.ScenarioTrace publishes cited drift, an exception, and legacy context without touching implementation' {
        $root = New-RecordRoot
        $codePath = Join-Path $root 'src/service.ps1'
        $apiPath = Join-Path $root 'src/api.ps1'
        $expectationPath = Join-Path $root 'docs/expectations.md'
        $legacyContractPath = Join-Path $root 'docs/legacy-api-contract.md'
        $legacyPlan = Join-Path $root 'docs/implementation-plans/archived/003-legacy'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $codePath) -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force)
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $expectationPath) -Force)
        [void](New-Item -ItemType Directory -Path $legacyPlan -Force)
        [System.IO.File]::WriteAllText($codePath, @(
                'function Get-Account($id) {'
                '    return Get-Item "accounts/$id.json"'
                '}'
                'function Clear-LocalCache {'
                '    Remove-Item cache/* -Force'
                '}'
                'function Get-ObsoleteFormatter($value) {'
                '    return $value.Trim()'
                '}'
                'function Invoke-CacheRefresh {'
                '    Clear-LocalCache'
                '}'
            ) -join "`n")
        [System.IO.File]::WriteAllText($apiPath, @(
                'function Get-AccountById($id) {'
                '    return Get-Item "accounts/$id.json"'
                '}'
            ) -join "`n")
        [System.IO.File]::WriteAllText($expectationPath, @(
                '# Expectations'
                '- Unknown accounts return a not-found result.'
                '- Clear-LocalCache remains a supported manual maintenance command.'
            ) -join "`n")
        [System.IO.File]::WriteAllText($legacyContractPath, @(
                '# Legacy API contract'
                '- Unknown accounts return an empty object with success status.'
            ) -join "`n")
        [System.IO.File]::WriteAllText((Join-Path $root 'config/events.psd1'),
            "@{ CacheRefresh = 'Invoke-CacheRefresh' }")
        [System.IO.File]::WriteAllText((Join-Path $legacyPlan 'plan.md'), '# Legacy plan without saved intent')
        $codeBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($codePath))
        $apiBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($apiPath))
        $lines = [System.IO.File]::ReadAllLines($codePath)
        $findings = @(
            @{
                Id = 'RCS-account-not-found'
                Category = 'drift'
                Subject = 'Unknown account path is not mapped to not-found'
                Scope = 'src/service.ps1::Get-Account'
                Citations = @('docs/expectations.md:2', 'src/service.ps1:2')
                Expectation = 'Unknown accounts return a not-found result.'
                CurrentBehavior = 'The selected path uses Get-Item and has no local not-found mapping.'
                Impact = 'A missing account can surface as a raw filesystem error.'
                CounterEvidence = 'No selected caller-specific exception handler was found.'
                Uncertainty = 'Only this function and its directly observed caller were traced.'
                Action = 'Create a normal corrective plan to map the missing account result.'
                Benefits = 'The behavior matches the local expectation.'
                Tradeoffs = 'Callers may rely on the current error shape.'
                Effort = 2
                Complexity = 2
            }
            @{
                Id = 'RCS-conflicting-api-expectations'
                Category = 'alignment-question'
                Subject = 'Human sources disagree on unknown-account behavior'
                Scope = 'src/service.ps1::Get-Account'
                Citations = @('docs/expectations.md:2', 'docs/legacy-api-contract.md:2')
                Expectation = 'The current expectation and legacy contract prescribe different unknown-account results.'
                CurrentBehavior = 'Get-Account delegates to Get-Item; neither human source establishes the intended current response.'
                Impact = 'Changing behavior before resolving intent could break a consumer that relies on either contract.'
                CounterEvidence = 'The legacy contract may have been superseded, but no source records that decision.'
                Uncertainty = 'Consumer compatibility and the status of the legacy contract are unverified.'
                Action = 'Ask the operator which contract is authoritative before creating a corrective plan.'
                Benefits = 'Resolves the human decision before implementation changes.'
                Tradeoffs = 'The finding remains open until an owner clarifies intent.'
                Effort = 1
                Complexity = 2
            }
            @{
                Id = 'RCS-manual-cache-exception'
                Category = 'coding-standard'
                Subject = 'Manual cache maintenance command is intentionally retained'
                Scope = 'src/service.ps1::Clear-LocalCache'
                Citations = @('docs/expectations.md:3', 'src/service.ps1:4')
                Expectation = 'Local documentation explicitly supports manual cache cleanup.'
                CurrentBehavior = 'The function has no internal caller but remains directly invokable.'
                Impact = 'No defect; removal would break the documented maintenance entry point.'
                CounterEvidence = 'No direct runtime reference exists.'
                Uncertainty = 'External scripts were not searched.'
                Action = 'Retain; do not classify as dead code.'
                Benefits = 'Preserves an explicitly supported operator tool.'
                Tradeoffs = 'The manual entry point has no internal callers.'
                Effort = 1
                Complexity = 1
            }
            @{
                Id = 'RCS-unreferenced-formatter'
                Category = 'dead-code'
                Subject = 'Private formatter has no observed repository-owned reachability'
                Scope = 'src/service.ps1::Get-ObsoleteFormatter'
                Citations = @('src/service.ps1:7')
                Expectation = 'Private helpers should have a supported caller or an explicit retention reason.'
                CurrentBehavior = 'The definition has no other reference in the selected fixture; no export or event registration names it.'
                Impact = 'If owner and external-consumer checks confirm the gap, removal may reduce maintenance surface.'
                CounterEvidence = 'The separately registered Invoke-CacheRefresh handler and documented Clear-LocalCache command are intentionally retained.'
                Uncertainty = 'External callers and unrepresented dynamic mechanisms remain unread; no deletion is justified by this trace alone.'
                Action = 'Search remaining supported roots and ask the owner before creating a normal removal plan.'
                Benefits = 'A confirmed unreachable helper would no longer require maintenance.'
                Tradeoffs = 'Additional root searches and owner confirmation are required.'
                Effort = 3
                Complexity = 2
            }
            @{
                Id = 'RCS-shared-account-storage'
                Category = 'design-architecture'
                Subject = 'Account lookup duplicates file access across service and API subsystems'
                Scope = 'src/service.ps1::Get-Account; src/api.ps1::Get-AccountById'
                Citations = @('src/service.ps1:2', 'src/api.ps1:2')
                Expectation = 'Optional design improvement; no repository contract requires this refactor.'
                CurrentBehavior = 'Both account entry points construct the storage path and call Get-Item directly.'
                Impact = 'Storage and missing-account behavior can diverge between the two boundaries.'
                CounterEvidence = 'The fixture does not establish a production coupling or performance defect.'
                Uncertainty = 'Only these two selected entry points were compared.'
                Action = 'Consider a small shared account-store helper through a corrective plan if broader call sites confirm the duplication.'
                Benefits = 'One boundary can own path construction and not-found mapping.'
                Tradeoffs = 'A shared abstraction adds indirection for a small fixture and should not be generalized without more evidence.'
                Effort = 3
                Complexity = 4
            }
        )
        $payload = New-PublishPayload -Findings $findings `
            -Survey 'Subsystems: account lookup and local maintenance. Plans: one archived legacy plan without intent.' `
            -Coverage 'Traced the account path and manual tool; legacy intent unavailable; external callers unread.'
        (Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ($payload | ConvertTo-Json -Depth 12 -Compress)).status | Should -BeExactly 'written'

        $decision = [ordered]@{
            FindingId = 'RCS-manual-cache-exception'
            Disposition = 'accepted-intentional-drift'
            DecidedOn = '2026-10-03'
            Rationale = 'The operator confirms this is a documented manual tool, not dead code.'
            Scope = 'Only Clear-LocalCache in this repository snapshot.'
            Assumptions = 'The maintenance documentation remains active.'
            RevisitWhen = 'The documented command or its owning contract changes.'
            Citations = @('docs/expectations.md:3', 'src/service.ps1:4')
        }
        (Invoke-RecordWriter -Root $root -Operation 'RecordDisposition' `
                -Json ($decision | ConvertTo-Json -Compress)).status | Should -BeExactly 'written'
        $content = (Invoke-RecordWriter -Root $root -Operation 'Read').content
        $content | Should -Match 'Unknown account path is not mapped'
        $content | Should -Match 'Human sources disagree on unknown-account behavior'
        $content | Should -Match 'alignment-question'
        $content | Should -Match 'Private formatter has no observed repository-owned reachability'
        $content | Should -Match 'Account lookup duplicates file access'
        $content | Should -Match 'External callers and unrepresented dynamic mechanisms remain unread'
        $content | Should -Match 'Complexity:\*\* 4/10'
        $content | Should -Match 'accepted-intentional-drift'
        $content | Should -Match 'Legacy plan without intent'
        $content | Should -Match 'docs/expectations.md:2'
        $content | Should -Match 'docs/legacy-api-contract.md:2'
        (Get-Content -LiteralPath (Join-Path $root 'config/events.psd1') -Raw) |
            Should -Match 'Invoke-CacheRefresh'
        @(Select-String -Path $codePath -Pattern 'Get-ObsoleteFormatter').Count |
            Should -Be 1
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($codePath)) |
            Should -BeExactly $codeBefore
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($apiPath)) |
            Should -BeExactly $apiBefore
        [System.IO.File]::ReadAllLines($codePath) | Should -Be $lines
    }
}

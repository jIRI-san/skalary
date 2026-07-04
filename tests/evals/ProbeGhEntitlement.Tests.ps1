#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Probe-GhEntitlement pure helpers' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        # Dot-source WITHOUT executing the orchestrator (guarded by InvocationName -ne '.').
        . (Join-Path $repoDir 'scripts/skalary/Probe-GhEntitlement.ps1')
    }

    Context 'Get-GhEntitlementOutcome — decision matrix' {
        It 'is entitled when source=gh, models>0, task passed' {
            $o = Get-GhEntitlementOutcome -Source 'gh' -ModelCount 12 -TaskExit 0 -RequireGh $true
            $o.Entitled | Should -BeTrue
        }

        It 'is entitled (models-only) when task skipped ($null exit)' {
            $o = Get-GhEntitlementOutcome -Source 'gh' -ModelCount 3 -TaskExit $null -RequireGh $true
            $o.Entitled | Should -BeTrue
            $o.Reason | Should -Match 'models-only'
        }

        It 'FAILS when the source is not gh (fallback does not prove the gh path)' {
            $o = Get-GhEntitlementOutcome -Source 'credmanager:copilot-eval' -ModelCount 12 -TaskExit 0 -RequireGh $true
            $o.Entitled | Should -BeFalse
            $o.Reason | Should -Match "not 'gh'"
        }

        It 'FAILS when no models are listed (no entitlement) even on the gh source' {
            $o = Get-GhEntitlementOutcome -Source 'gh' -ModelCount 0 -TaskExit $null -RequireGh $true
            $o.Entitled | Should -BeFalse
            $o.Reason | Should -Match 'no models'
        }

        It 'FAILS when the live task exited non-zero despite entitlement' {
            $o = Get-GhEntitlementOutcome -Source 'gh' -ModelCount 12 -TaskExit 1 -RequireGh $true
            $o.Entitled | Should -BeFalse
            $o.Reason | Should -Match 'exited 1'
        }

        It 'accepts a non-gh source only when -RequireGh:$false' {
            $o = Get-GhEntitlementOutcome -Source 'ambient' -ModelCount 5 -TaskExit $null -RequireGh $false
            $o.Entitled | Should -BeTrue
        }
    }

    Context 'Get-WazaModelCount — parses both array and wrapped shapes' {
        It 'counts a bare JSON array' {
            Get-WazaModelCount -JsonText '["a","b","c"]' | Should -Be 3
        }

        It 'counts a {models:[...]} wrapper' {
            Get-WazaModelCount -JsonText '{"models":[{"id":"x"},{"id":"y"}]}' | Should -Be 2
        }

        It 'returns 0 for empty or malformed text (fail-closed)' {
            Get-WazaModelCount -JsonText '' | Should -Be 0
            Get-WazaModelCount -JsonText 'not json' | Should -Be 0
        }
    }

    Context 'Format-GhEntitlementTableRow — renders the design-note row' {
        It 'renders PASS + ENTITLED for a clean gh run' {
            $row = Format-GhEntitlementTableRow -Account 'octocat' -GhHost 'github.com' -Source 'gh' -ModelCount 12 -TaskExit 0 -Entitled $true
            $row | Should -Match 'octocat @ github.com'
            $row | Should -Match '\| gh \|'
            $row | Should -Match 'PASS'
            $row | Should -Match 'ENTITLED'
        }

        It 'renders skipped task + NOT ENTITLED verdict' {
            $row = Format-GhEntitlementTableRow -Account '' -GhHost '' -Source 'credmanager' -ModelCount 0 -TaskExit $null -Entitled $false
            $row | Should -Match 'skipped'
            $row | Should -Match 'NOT ENTITLED'
            $row | Should -Match 'github.com'
        }
    }

    Context 'Find-GhExecutable — locator is side-effect free and honors PATH' {
        It 'returns a path or $null without throwing' {
            { Find-GhExecutable } | Should -Not -Throw
        }
    }
}

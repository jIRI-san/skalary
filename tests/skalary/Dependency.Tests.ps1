#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Plan dependency start-gate' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $scriptPath = Join-Path $repoRoot 'scripts/skalary/Test-DependencyPlan006.ps1'
        $tempRoots = [System.Collections.Generic.List[string]]::new()

        function Invoke-DependencyGate {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [string]$Root,
                [Parameter(Mandatory)]
                [string]$PlanPath,
                [string]$DependencyReference
            )

            $argList = @('-NoProfile', '-File', $scriptPath, '-RepoRoot', $Root, '-PlanPath', $PlanPath)
            if ($PSBoundParameters.ContainsKey('DependencyReference')) {
                $argList += @('-DependencyReference', $DependencyReference)
            }

            $output = @(& pwsh @argList 2>&1)

            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ($output | ForEach-Object { "$_" }) -join "`n"
            }
        }

        function New-DependencyFixture {
            [CmdletBinding()]
            param()

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("dependency-tests-" + [System.Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            New-Item -ItemType Directory -Path (Join-Path $root 'scripts/skalary') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'plugins/create-implementation-plan/skills/cip/assets') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'plugins/continue-implementation/skills/ci/assets') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'plugins/autopilot/agents') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'docs/implementation-plans/007-workflow-memory-ledger') -Force | Out-Null

            Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/skalary/Test-Plan.ps1') -Destination (Join-Path $root 'scripts/skalary/Test-Plan.ps1') -Force
            Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/skalary/PlanEvidence.psm1') -Destination (Join-Path $root 'scripts/skalary/PlanEvidence.psm1') -Force
            Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/skalary/PlanState.psm1') -Destination (Join-Path $root 'scripts/skalary/PlanState.psm1') -Force

            Set-Content -LiteralPath (Join-Path $root 'README.md') -Value "# Fixture`n" -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $root 'plugins/create-implementation-plan/skills/cip/assets/drafting-guide.md') -Value "Use Test-Plan.ps1 for validation.`n" -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $root 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md') -Value "- test:<TestId>`n- file:<path>#<assertion>`n- review:cr|dr`n" -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $root 'plugins/autopilot/agents/autopilot.agent.md') -Value 'In this repo, `test` stays allowlist-clean as `npm test`.' -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $root 'docs/implementation-plans/007-workflow-memory-ledger/plan.md') -Value "# 007`n<!-- depends-on: 006 -->`n" -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $root 'package.json') -Value @'
{
  "scripts": {
    "test": "npm run validate-plan && npm run test:unit",
    "test:unit": "pwsh -NoProfile -File scripts/skalary/Run-UnitTests.ps1"
  }
}
'@ -Encoding utf8NoBOM

            $tempRoots.Add($root)
            return $root
        }
    }

    AfterAll {
        foreach ($root in $tempRoots) {
            if (Test-Path -LiteralPath $root -PathType Container) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It 'Skalary.Dependency.Plan006Present' {
        $planPath = Join-Path $repoRoot 'docs/implementation-plans/archived/007-workflow-memory-ledger/plan.md'
        $result = Invoke-DependencyGate -Root $repoRoot -PlanPath $planPath
        $result.ExitCode | Should -Be 0
    }

    It 'test:validate-all keeps the committed full validation gate explicitly repository-wide' {
        $package = Get-Content -LiteralPath (Join-Path $repoRoot 'package.json') -Raw |
            ConvertFrom-Json -Depth 20
        [string]$package.scripts.test | Should -Match 'npm run validate-plan'
        [string]$package.scripts.test | Should -Match 'npm run test:unit'
        [string]$package.scripts.'test:unit' | Should -Match '(?i)-FullRepository'
    }

    It 'fails when the test:unit gate is missing' {
        $fixture = New-DependencyFixture
        $planPath = Join-Path $fixture 'docs/implementation-plans/007-workflow-memory-ledger/plan.md'
        Set-Content -LiteralPath (Join-Path $fixture 'package.json') -Value @'
{
  "scripts": {
    "test": "npm run validate-plan"
  }
}
'@ -Encoding utf8NoBOM

        $result = Invoke-DependencyGate -Root $fixture -PlanPath $planPath
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match "test:unit"
    }

    It 'test:dep006-legacy triggers the preflight for a legacy 006 dependency' {
        $fixture = New-DependencyFixture
        $planPath = Join-Path $fixture 'docs/implementation-plans/007-workflow-memory-ledger/plan.md'

        $result = Invoke-DependencyGate -Root $fixture -PlanPath $planPath
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'dependency preflight passed'
    }

    It 'test:dep006-hash triggers identical preflight for a hash-style dependency' {
        $fixture = New-DependencyFixture
        # Represent the guarded plan under the new hash scheme so a hash (prefix) reference resolves to it.
        $hashPlanDir = Join-Path $fixture 'docs/implementation-plans/2026-01-01-aaa006-workflow-memory-ledger'
        New-Item -ItemType Directory -Path $hashPlanDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $hashPlanDir 'plan.md') -Value "<!-- plan-id: aaa006 -->`n# 006`n" -Encoding utf8NoBOM

        # Dependent plan declares the dependency by hash prefix; the gate must resolve it to aaa006.
        $planPath = Join-Path $fixture 'docs/implementation-plans/007-workflow-memory-ledger/plan.md'
        Set-Content -LiteralPath $planPath -Value "# 007`n<!-- depends-on: aaa0 -->`n" -Encoding utf8NoBOM

        $result = Invoke-DependencyGate -Root $fixture -PlanPath $planPath -DependencyReference 'aaa006'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'dependency preflight passed'
    }

    It 'test:dep006-gutted fails when a compatibility-anchor token is dropped' {
        $fixture = New-DependencyFixture
        $planPath = Join-Path $fixture 'docs/implementation-plans/007-workflow-memory-ledger/plan.md'
        # Slimming regression: the crosscheck-guide loses the pinned test:<TestId> anchor.
        Set-Content -LiteralPath (Join-Path $fixture 'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md') -Value "- file:<path>#<assertion>`n- review:cr|dr`n" -Encoding utf8NoBOM

        $result = Invoke-DependencyGate -Root $fixture -PlanPath $planPath
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'crosscheck-guide\.md'
    }
}

#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'installed work-hierarchy consumer' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    }

    It 'test:WorkHierarchy.ConsumerInstall runs projection and dry run from the isolated plugin payload' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) (
            'work-hierarchy-consumer-' + [guid]::NewGuid().ToString('N')
        )
        $mappingPath = Join-Path $root 'state/work-hierarchy.json'
        try {
            [void](New-Item -ItemType Directory -Path $root -Force)
            git init -q $root 2>$null | Out-Null
            $LASTEXITCODE | Should -Be 0

            $pluginRoot = Join-Path $script:repoRoot 'plugins/work-hierarchy-sync'
            $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 20
            $installed = Join-Path $root '.github/skills/work-hierarchy-sync/scripts'
            foreach ($mapping in @($manifest.files | Where-Object {
                        [string]$_.dest -like 'skills/work-hierarchy-sync/scripts/*'
                    })) {
                $source = Join-Path $pluginRoot ([string]$mapping.src)
                $destination = Join-Path (Join-Path $root '.github') ([string]$mapping.dest)
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }

            $poisoned = Join-Path $root 'scripts/skalary'
            [void](New-Item -ItemType Directory -Path $poisoned -Force)
            foreach ($name in @('PlanState.psm1', 'WorkHierarchy.psm1')) {
                Set-Content -LiteralPath (Join-Path $poisoned $name) `
                    -Value "throw 'repository $name must not execute from an installed work-hierarchy bundle'" `
                    -Encoding utf8NoBOM
            }

            $epicDir = Join-Path $root 'docs/implementation-plans/epics/2026-01-01-a1b2c3-consumer'
            $planDir = Join-Path $root 'docs/implementation-plans/2026-01-01-111aaa-consumer'
            [void](New-Item -ItemType Directory -Path $epicDir, (Join-Path $planDir 'assets') -Force)
            Set-Content -LiteralPath (Join-Path $epicDir 'epic.md') -Encoding utf8NoBOM -Value @'
# a1b2c3: Consumer epic
<!-- epic-id: a1b2c3 -->

## Goal

Prove the installed work-hierarchy closure.
'@
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') -Encoding utf8NoBOM -Value @'
# 111aaa: Consumer plan
<!-- plan-id: 111aaa -->
<!-- epic: a1b2c3 -->

## Phase 1: Consumer proof

- [x] 1.1 Exercise the installed projection (REQ-1) `S`
'@
            Set-Content -LiteralPath (Join-Path $planDir 'assets/intent.md') -Encoding utf8NoBOM -Value @'
# Intent

## Goal

Exercise the installed projection.

## Desired outcome

The bundled modules run without repository scripts.

## Success signals

- Projection succeeds.

## Non-goals

- No live GitHub writes.

## Definition of done

- The dry run is deterministic and read-only.
'@
            Set-Content -LiteralPath (Join-Path $planDir 'assets/requirements.md') -Encoding utf8NoBOM -Value @'
# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Installed projection works. | The dry run emits the expected create actions. `test:consumer` | 1.1 |
'@

            Remove-Module GitHubWorkHierarchy, WorkHierarchy, PlanState -Force -ErrorAction SilentlyContinue
            Import-Module (Join-Path $installed 'WorkHierarchy.psm1') -Force -DisableNameChecking
            Import-Module (Join-Path $installed 'GitHubWorkHierarchy.psm1') -Force -DisableNameChecking
            foreach ($moduleName in @('GitHubWorkHierarchy', 'WorkHierarchy', 'PlanState')) {
                $loadedModule = @(Get-Module -All | Where-Object Name -EQ $moduleName) |
                    Select-Object -Last 1
                $loadedModule | Should -Not -BeNullOrEmpty
                $loadedModule.Path.StartsWith($installed, [System.StringComparison]::Ordinal) |
                    Should -BeTrue -Because "$moduleName must load from the installed payload"
            }
            foreach ($commandName in @(
                    'New-WorkHierarchyProjection',
                    'Read-WorkHierarchyMappingFile',
                    'New-WorkHierarchyDryRun',
                    'Invoke-WorkHierarchyApply',
                    'New-GitHubWorkHierarchyProvider'
                )) {
                Get-Command $commandName -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }

            $projection = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $root
            $projection.epic.localId | Should -Be 'a1b2c3'
            @($projection.children.localId) | Should -Be @('111aaa')

            $calls = [System.Collections.Generic.List[object]]::new()
            $runner = {
                param([string[]]$Arguments)
                $calls.Add(@($Arguments))
                [pscustomobject]@{
                    ExitCode = 0
                    Output = '[]'
                    Error = ''
                }
            }.GetNewClosure()
            $provider = New-GitHubWorkHierarchyProvider -CommandRunner $runner
            $mapping = Read-WorkHierarchyMappingFile -Path $mappingPath -Repository 'owner/repo'
            $dryRun = New-WorkHierarchyDryRun `
                -Projection $projection `
                -Repository 'owner/repo' `
                -Mapping $mapping.mapping `
                -MappingDigest $mapping.digest `
                -Provider $provider

            @($dryRun.actions | Where-Object kind -EQ 'create') | Should -HaveCount 2
            @($dryRun.actions | Where-Object kind -EQ 'link') | Should -HaveCount 1
            @($dryRun.actions | Where-Object kind -EQ 'refuse') | Should -HaveCount 0
            $calls | Should -HaveCount 2
            @($calls | Where-Object { $_ -contains '--method' }) | Should -HaveCount 0
        }
        finally {
            Remove-Module GitHubWorkHierarchy, WorkHierarchy, PlanState -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

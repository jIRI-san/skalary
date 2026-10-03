#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Workshop skill contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/workshop'
        $script:skill = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'skills/ws/SKILL.md') -Raw
        $script:worktrees = Get-Content -LiteralPath (
            Join-Path $script:pluginRoot 'skills/ws/assets/worktrees.md'
        ) -Raw
    }

    It 'test:Workshop.Payload declares the standalone skill and complete asset closure' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json
        $manifest.name | Should -BeExactly 'workshop'
        @($manifest.dependencies).Count | Should -Be 0
        @($manifest.files).Count | Should -Be 2
        foreach ($file in $manifest.files) {
            $sourcePath = Join-Path $script:pluginRoot $file.src
            $installedPath = Join-Path (Join-Path $script:repoRoot '.github') $file.dest
            Test-Path -LiteralPath $sourcePath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $installedPath -PathType Leaf | Should -BeTrue
            [System.IO.File]::ReadAllText($installedPath) | Should -BeExactly (
                [System.IO.File]::ReadAllText($sourcePath)
            )
            $file.dest | Should -Not -Match '(^/|\\.\\.|^[A-Za-z]:)'
        }
        $script:skill | Should -Match '(?m)^name: ws\r?$'
        $script:skill | Should -Match '(?m)^user-invocable: true\r?$'
        $script:skill | Should -Match '(?m)^disable-model-invocation: true\r?$'
        $script:skill | Should -Match '\./assets/worktrees\.md'
        [System.Text.Encoding]::UTF8.GetByteCount($script:skill) | Should -BeLessOrEqual 12000
    }

    It 'test:Workshop.ConsumerSmoke loads the installed contract without planning dependencies' {
        Import-Module (Join-Path $PSScriptRoot '..' 'ConsumerInstallFixture.psm1') `
            -Force -DisableNameChecking
        $manifest = Get-Content -LiteralPath (Join-Path $script:pluginRoot 'plugin.json') -Raw |
            ConvertFrom-Json
        $root = Join-Path $TestDrive 'workshop-consumer'
        $files = @(
            foreach ($file in $manifest.files) {
                $source = Join-Path $script:pluginRoot $file.src
                $target = Join-Path (Join-Path $root '.github') $file.dest
                New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination $target
                [pscustomobject]@{
                    Install = $true
                    Dest = [string]$file.dest
                    Sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        )
        $fixture = [pscustomobject]@{
            Root = $root
            Catalog = [pscustomobject]@{
                Plugins = @([pscustomobject]@{ Name = 'workshop'; Files = $files })
            }
        }

        $result = @(Invoke-ConsumerInstalledSmokeMatrix -Fixture $fixture)
        $result.Count | Should -Be 1
        $result[0].IsClean | Should -BeTrue -Because $result[0].Output
        $result[0].Output.Trim() | Should -BeExactly 'workshop:handoff'
    }

    It 'test:Workshop.Scope approves a bounded set before execution and counts new directions for life' {
        $script:skill | Should -Match 'Ask one focused question at a time'
        $script:skill | Should -Match 'at most three lifetime-distinct concepts'
        $script:skill | Should -Match 'approval is not winner selection'
        $script:skill | Should -Match 'before any worktree is created or implementer is launched'
        $script:skill | Should -Match 'A correction within an approved concept does not count'
        $script:skill | Should -Match 'including rejected concepts and approved\s+replacement directions'
        $script:skill | Should -Match 'After three concepts,\s+only correct an existing concept, inspect/select, or reject'
    }

    It 'test:Workshop.VerticalSlice requires real central integration and discloses peripheral gaps' {
        $script:skill | Should -Match 'runnable \*\*central vertical slice\*\*'
        $script:skill | Should -Match 'real codebase entrypoints and connection or\s+insertion points'
        $script:skill | Should -Match 'an isolated concept stub is not enough'
        $script:skill | Should -Match 'name them'
        $script:skill | Should -Match 'Run only the smallest existing build/type/smoke check'
        $script:skill | Should -Match 'Show a failure or blocked\s+variant plainly'
    }

    It 'test:Workshop.Isolation fixes one clean common base and stops on host or identity mismatch' {
        $script:worktrees | Should -Match 'exact common base SHA'
        $script:worktrees | Should -Match 'Every\s+approved variant starts from that SHA'
        $script:worktrees | Should -Match 'staged, unstaged, or relevant untracked changes'
        $script:worktrees | Should -Match 'stop for the operator to choose'
        $script:worktrees | Should -Match 'Set `base_branch` explicitly'
        $script:worktrees | Should -Match 'verify that branch still points to the recorded SHA'
        $script:worktrees | Should -Match 'git worktree add -b'
        $script:worktrees | Should -Match 'a tool confined to the\s+source checkout cannot edit another worktree'
        $script:worktrees | Should -Match 'separate ports'
    }

    It 'test:Workshop.IntegrationMap compares real entrypoints, interfaces, touched paths, and demos' {
        foreach ($contract in @(
                'source layout/interfaces and dependencies',
                'entrypoint to central behavior',
                'real connection and insertion points',
                'touched files/codepaths and the path through them',
                'demo and check coverage, including what the check does not establish',
                'distinct ports',
                'executable usage'
            )) {
            $script:skill | Should -Match ([regex]::Escape($contract))
        }
    }

    It 'test:Workshop.Selection leaves the inspected choice and retained alternatives with the operator' {
        $script:skill | Should -Match 'Ask the operator to\s+correct a concept'
        $script:skill | Should -Match 'choose after inspection'
        $script:skill | Should -Match 'Never rank or select a winner from check results'
        $script:skill | Should -Match 'Retain all variant worktrees until explicit cleanup approval'
        $script:skill | Should -Match 'does not authorize merge, cherry-pick, PR publication, cleanup, or invoking CIP'
    }

    It 'test:Workshop.CipHandoff transfers explicit identity-checked draft input to normal CIP' {
        foreach ($contract in @(
                'common base SHA',
                'prototype commit',
                'selection rationale',
                'integration map',
                'known gaps, and open questions',
                'Send it explicitly to the selected app session',
                'paste it alongside `/cip` in the selected VS Code/CLI worktree',
                'CIP must verify the selected identity',
                'reconfirm current intent'
            )) {
            $script:skill | Should -Match ([regex]::Escape($contract))
        }
        $script:skill | Should -Match 'Do not\s+assume a fork or another session inherits this conversation'
        $script:skill | Should -Match 'Only start `/cip` when the operator\s+requests that transition'
        $script:cip = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/create-implementation-plan/skills/cip/SKILL.md'
        ) -Raw
        $script:cip | Should -Match 'verify the current branch, worktree\s+path/session, and HEAD'
        $script:cip | Should -Match 'If any identity\s+differs, stop for the operator'
        $script:cip | Should -Match 'not confirmed criteria or completed plan steps'
        $script:cip | Should -Match 'normal process'
    }
}

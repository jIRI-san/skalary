#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan b0c0d3 REQ-14 (RISK-6, RISK-12): /si opens a same-repo PR, so its write scope cannot be an
# instruction in a guide — a same-repo PR branch runs workflows with repository secrets at PR-open
# time, before the draft-PR and human-review backstops apply. These tests exercise the script
# against real git worktrees, because every hole in this gate (a committed change, an untracked
# file, a symlink) only exists in a real repository.
Describe 'si write-scope guard' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:guard = Join-Path $script:repoRoot 'scripts/skalary/Test-SiWriteScope.ps1'

        function Script:Invoke-Git {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string[]]$Arguments
            )
            $output = & git -C $Root @Arguments 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git $($Arguments -join ' ') failed in '$Root': $output"
            }
            return $output
        }

        function Script:New-ScopeRepo {
            <#
                A throwaway repo with a `main` baseline and a feature branch checked out, which is
                the exact shape /si proposes from.
            #>
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("si-scope-" + [Guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Invoke-Git -Root $root -Arguments @('init', '--initial-branch=main') | Out-Null
            Invoke-Git -Root $root -Arguments @('config', 'user.email', 'si@example.test') | Out-Null
            Invoke-Git -Root $root -Arguments @('config', 'user.name', 'si test') | Out-Null
            Invoke-Git -Root $root -Arguments @('config', 'commit.gpgsign', 'false') | Out-Null

            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'docs/seed.md') -Value "seed`n" -Encoding utf8NoBOM
            Invoke-Git -Root $root -Arguments @('add', 'docs/seed.md') | Out-Null
            Invoke-Git -Root $root -Arguments @('commit', '-m', 'seed') | Out-Null
            Invoke-Git -Root $root -Arguments @('checkout', '-b', 'si/test') | Out-Null

            return $root
        }

        function Script:New-RepoFile {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$RelativePath,
                [string]$Content = "proposal`n"
            )
            $full = Join-Path $Root $RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value $Content -Encoding utf8NoBOM
            return $full
        }

        function Script:Invoke-Guard {
            param([Parameter(Mandatory)][string]$Root)
            # The guard reports through Write-Host (information stream), so `*>&1` is required to
            # capture it; `2>&1` alone yields an empty string and every assertion passes vacuously.
            $output = & $script:guard -RepoRoot $Root -BaseRef main *>&1
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
        }
    }

    BeforeEach {
        $script:root = New-ScopeRepo
    }

    AfterEach {
        if ($script:root -and (Test-Path -LiteralPath $script:root)) {
            Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'test:si-write-scope-denies-workflows' {
        It 'test:si-write-scope-denies-workflows refuses a committed workflow edit' {
            New-RepoFile -Root $script:root -RelativePath '.github/workflows/registry-ci.yml' -Content "on: pull_request`n" | Out-Null
            Invoke-Git -Root $script:root -Arguments @('add', '.github/workflows/registry-ci.yml') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('commit', '-m', 'add workflow') | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'registry-ci\.yml'
            $result.Output | Should -Match '(?i)denied execution-carrying path'
        }

        It 'test:si-write-scope-denies-workflows refuses a composite action edit' {
            New-RepoFile -Root $script:root -RelativePath '.github/actions/setup/action.yml' -Content "runs:`n  using: node20`n" | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match '\.github/actions/setup/action\.yml'
        }

        It 'test:si-write-scope-denies-workflows allows the documentary .github subtrees it does permit' {
            # The denial has to be narrow as well as absolute: denying .github wholesale would stop
            # /si from proposing the dogfood copies it exists to improve.
            New-RepoFile -Root $script:root -RelativePath '.github/skills/si/SKILL.md' | Out-Null
            New-RepoFile -Root $script:root -RelativePath '.github/agents/cr-security.agent.md' | Out-Null
            New-RepoFile -Root $script:root -RelativePath '.github/prompts/si.prompt.md' | Out-Null
            New-RepoFile -Root $script:root -RelativePath 'plugins/self-improvement/skills/si/SKILL.md' | Out-Null
            New-RepoFile -Root $script:root -RelativePath 'docs/design-notes/project/note.design.md' | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Match '(?i)passed'
        }

        It 'test:si-write-scope-denies-workflows refuses paths outside the allowlist entirely' {
            # scripts/ is where the guard itself lives: a proposal that can edit it can disarm it.
            New-RepoFile -Root $script:root -RelativePath 'scripts/skalary/Test-SiWriteScope.ps1' | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match '(?i)outside the /si write allowlist'
        }
    }

    Context 'test:si-write-scope-catches-untracked' {
        It 'test:si-write-scope-catches-untracked refuses an untracked workflow file' {
            # A new file is the most likely shape of a proposal and is invisible to every diff.
            New-RepoFile -Root $script:root -RelativePath '.github/workflows/exfiltrate.yml' -Content "on: pull_request`n" | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'exfiltrate\.yml'
        }

        It 'test:si-write-scope-catches-untracked refuses a staged-but-uncommitted out-of-scope file' {
            New-RepoFile -Root $script:root -RelativePath 'package.json' -Content "{}`n" | Out-Null
            Invoke-Git -Root $script:root -Arguments @('add', 'package.json') | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'package\.json'
        }

        It 'test:si-write-scope-catches-untracked still refuses when the same path is also ignored-adjacent' {
            # .gitignore itself is out of scope; a proposal that could add ignores could hide the
            # rest of its own footprint from the untracked scan.
            New-RepoFile -Root $script:root -RelativePath '.gitignore' -Content "secrets/`n" | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match '\.gitignore'
        }

        It 'test:si-write-scope-catches-untracked refuses a rename that moves a denied file out of its tree' {
            # git reports a detected rename as the destination only, so without --no-renames a
            # single `git mv` deletes a pull_request workflow with nothing to judge.
            Invoke-Git -Root $script:root -Arguments @('checkout', 'main') | Out-Null
            New-RepoFile -Root $script:root -RelativePath '.github/workflows/ci.yml' -Content "on: pull_request`njobs: {}`n" | Out-Null
            Invoke-Git -Root $script:root -Arguments @('add', '.github/workflows/ci.yml') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('commit', '-m', 'baseline workflow') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('checkout', 'si/test') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('merge', '--ff-only', 'main') | Out-Null

            Invoke-Git -Root $script:root -Arguments @('mv', '.github/workflows/ci.yml', 'docs/ci-notes.md') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('commit', '-m', 'move workflow into docs') | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'DENY \.github/workflows/ci\.yml - denied execution-carrying path'
        }

        It 'test:si-write-scope-catches-untracked passes a clean in-scope proposal across all three halves' {
            New-RepoFile -Root $script:root -RelativePath 'docs/design-notes/committed.md' | Out-Null
            Invoke-Git -Root $script:root -Arguments @('add', 'docs/design-notes/committed.md') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('commit', '-m', 'committed half') | Out-Null

            New-RepoFile -Root $script:root -RelativePath 'plugins/self-improvement/skills/si/assets/staged.md' | Out-Null
            Invoke-Git -Root $script:root -Arguments @('add', 'plugins/self-improvement/skills/si/assets/staged.md') | Out-Null

            New-RepoFile -Root $script:root -RelativePath '.github/skills/si/assets/untracked.md' | Out-Null

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 0
        }
    }

    Context 'test:si-write-scope-rejects-symlink-escape' {
        It 'test:si-write-scope-rejects-symlink-escape refuses a link that leaves the repository' {
            $outside = Join-Path ([System.IO.Path]::GetTempPath()) ("si-outside-" + [Guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $outside 'target.md') -Value "outside`n" -Encoding utf8NoBOM

            try {
                $linkParent = Join-Path $script:root 'docs'
                New-Item -ItemType Directory -Path $linkParent -Force | Out-Null
                try {
                    New-Item -ItemType SymbolicLink -Path (Join-Path $linkParent 'escape.md') -Target (Join-Path $outside 'target.md') -ErrorAction Stop | Out-Null
                }
                catch {
                    Set-ItResult -Skipped -Because 'the filesystem or account does not permit symlink creation'
                    return
                }

                $result = Invoke-Guard -Root $script:root
                $result.ExitCode | Should -Be 1
                $result.Output | Should -Match '(?i)resolves outside the repository'
            }
            finally {
                Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'test:si-write-scope-rejects-symlink-escape refuses an in-repo link that lands in a denied tree' {
            # The baseline workflow is committed on `main`, so it is outside main...HEAD: only the
            # symlink can produce a denial, and the assertion names it. With the workflow committed
            # on the branch instead, this test would pass with the destination check deleted.
            Invoke-Git -Root $script:root -Arguments @('checkout', 'main') | Out-Null
            $workflows = Join-Path $script:root '.github/workflows'
            New-Item -ItemType Directory -Path $workflows -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $workflows 'ci.yml') -Value "on: push`n" -Encoding utf8NoBOM
            Invoke-Git -Root $script:root -Arguments @('add', '.github/workflows/ci.yml') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('commit', '-m', 'baseline workflow') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('checkout', 'si/test') | Out-Null
            Invoke-Git -Root $script:root -Arguments @('merge', '--ff-only', 'main') | Out-Null

            $docs = Join-Path $script:root 'docs'
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $docs 'sneaky.yml') -Target (Join-Path $workflows 'ci.yml') -ErrorAction Stop | Out-Null
            }
            catch {
                Set-ItResult -Skipped -Because 'the filesystem or account does not permit symlink creation'
                return
            }

            # An allowlisted *name* is not an allowlisted *destination*: the decision is re-derived
            # from where the path actually resolves.
            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'DENY docs/sneaky\.yml - resolves into a denied execution-carrying path'
        }

        It 'test:si-write-scope-rejects-symlink-escape refuses an out-of-scope path that links into an allowed tree' {
            # Symlink resolution restricts; it never launders. Otherwise any path outside the
            # allowlist — including the guard's own directory — could be written as a link whose
            # target sits in docs/, and the content of that target is fully attacker-controlled.
            New-RepoFile -Root $script:root -RelativePath 'docs/fake-guard.ps1' | Out-Null
            $scripts = Join-Path $script:root 'scripts/skalary'
            New-Item -ItemType Directory -Path $scripts -Force | Out-Null
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $scripts 'guard.ps1') -Target (Join-Path $script:root 'docs/fake-guard.ps1') -ErrorAction Stop | Out-Null
            }
            catch {
                Set-ItResult -Skipped -Because 'the filesystem or account does not permit symlink creation'
                return
            }

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'DENY scripts/skalary/guard\.ps1 - outside the /si write allowlist'
        }

        It 'test:si-write-scope-rejects-symlink-escape refuses a symlinked directory that shadows a denied tree' {
            # git emits the bare directory entry (no trailing slash) when the path is a symlink, so
            # a prefix test alone would never fire on `.github/workflows` itself.
            New-RepoFile -Root $script:root -RelativePath 'docs/wf/evil.yml' -Content "on: pull_request`n" | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:root '.github') -Force | Out-Null
            try {
                New-Item -ItemType SymbolicLink -Path (Join-Path $script:root '.github/workflows') -Target (Join-Path $script:root 'docs/wf') -ErrorAction Stop | Out-Null
            }
            catch {
                Set-ItResult -Skipped -Because 'the filesystem or account does not permit symlink creation'
                return
            }

            $result = Invoke-Guard -Root $script:root
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'DENY \.github/workflows - denied execution-carrying path'
        }

        It 'test:si-write-scope-rejects-symlink-escape refuses rather than passes when the diff base cannot be resolved' {
            # Without a base ref the committed half of the proposal cannot be enumerated. Passing
            # there would approve an unexamined set of commits — the failure has to be closed.
            $result = & $script:guard -RepoRoot $script:root -BaseRef 'no-such-base' *>&1
            $LASTEXITCODE | Should -Be 1
            ($result | Out-String) | Should -Match "(?i)cannot resolve diff base 'no-such-base'"
        }
    }

    Context 'test:si-proposes-never-merges' {
        It 'test:si-proposes-never-merges keeps the PR draft and forbids merging in both skill copies' {
            foreach ($path in @('plugins/self-improvement/skills/si/assets/propose-guide.md',
                    '.github/skills/si/assets/propose-guide.md',
                    'plugins/self-improvement/skills/si/SKILL.md',
                    '.github/skills/si/SKILL.md')) {
                $full = Join-Path $script:repoRoot ($path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                Test-Path -LiteralPath $full -PathType Leaf | Should -BeTrue -Because "$path must ship"
                $text = Get-Content -LiteralPath $full -Raw -Encoding utf8

                $text | Should -Match '(?i)draft' -Because "$path must keep the PR a draft"
                $text | Should -Match '(?i)never (auto-)?merge' -Because "$path must forbid merging"
            }
        }

        It 'test:si-proposes-never-merges runs the guard before the PR, from a worktree' {
            foreach ($path in @('plugins/self-improvement/skills/si/assets/propose-guide.md',
                    '.github/skills/si/assets/propose-guide.md')) {
                $full = Join-Path $script:repoRoot ($path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                $text = Get-Content -LiteralPath $full -Raw -Encoding utf8

                $text | Should -Match 'Test-SiWriteScope\.ps1' -Because "$path must name the guard"
                $text | Should -Match 'gh pr create --draft' -Because "$path must open a draft PR"
                $text | Should -Match 'git worktree add' -Because "$path must isolate the proposal"

                # A refusal that the model may argue with is not a gate.
                $text | Should -Match '(?i)never open the PR on a refusal' -Because "$path must make the guard blocking"
                $text | Should -Match '(?i)never edit the guard' -Because "$path must stop the proposal from disarming its own control"
            }
        }

        It 'test:si-proposes-never-merges ships the guard as an installable payload file' {
            $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'plugins/self-improvement/plugin.json') -Raw | ConvertFrom-Json -Depth 50
            $declared = @($manifest.files | ForEach-Object { ($_.src -replace '\\', '/') })

            foreach ($required in @('skills/si/assets/propose-guide.md', 'skills/si/scripts/Test-SiWriteScope.ps1')) {
                $declared | Should -Contain $required -Because "installation must materialize '$required'"
            }

            # The bundled copy has to be the same script the repo tests, or the consumer runs a
            # different gate than the one under test.
            $source = Get-FileHash -LiteralPath (Join-Path $script:repoRoot 'scripts/skalary/Test-SiWriteScope.ps1') -Algorithm SHA256
            $bundled = Get-FileHash -LiteralPath (Join-Path $script:repoRoot 'plugins/self-improvement/skills/si/scripts/Test-SiWriteScope.ps1') -Algorithm SHA256
            $bundled.Hash | Should -Be $source.Hash
        }
    }
}

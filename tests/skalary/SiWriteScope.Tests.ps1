#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Direct SI write-scope guard' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:guard = Join-Path $script:repoRoot 'scripts/skalary/Test-SiWriteScope.ps1'

        function Script:Invoke-Git {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string[]]$Argument
            )
            $output = & git -C $Root @Argument 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git $($Argument -join ' ') failed in '$Root': $output"
            }
            return $output
        }

        function Script:New-ScopeRepo {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'si-scope-' + [guid]::NewGuid().ToString('n')
            )
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Invoke-Git -Root $root -Argument @('init', '--initial-branch=main', '--quiet') | Out-Null
            Invoke-Git -Root $root -Argument @('config', 'user.email', 'si@example.test') | Out-Null
            Invoke-Git -Root $root -Argument @('config', 'user.name', 'SI Test') | Out-Null
            New-RepoFile -Root $root -RelativePath 'docs/design-notes/seed.md' | Out-Null
            Invoke-Git -Root $root -Argument @('add', '.') | Out-Null
            Invoke-Git -Root $root -Argument @('commit', '--quiet', '-m', 'seed') | Out-Null
            Invoke-Git -Root $root -Argument @('checkout', '--quiet', '-b', 'si/test') | Out-Null
            return $root
        }

        function Script:New-RepoFile {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$RelativePath,
                [string]$Content = "change`n"
            )
            $full = Join-Path $Root $RelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value $Content -Encoding utf8NoBOM
            return $full
        }

        function Script:Invoke-Guard {
            param(
                [Parameter(Mandatory)][string]$Root,
                [string[]]$Path,
                [string]$BaseRef
            )
            $parameters = @{ RepoRoot = $Root; PassThru = $true }
            if ($null -ne $Path) { $parameters.Path = $Path }
            if ($PSBoundParameters.ContainsKey('BaseRef')) { $parameters.BaseRef = $BaseRef }
            $output = & $script:guard @parameters *>&1
            [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ($output | Out-String)
            }
        }
    }

    BeforeEach {
        $script:root = New-ScopeRepo
    }

    AfterEach {
        if ($script:root -and (Test-Path -LiteralPath $script:root)) {
            Remove-Item -LiteralPath $script:root -Recurse -Force
        }
    }

    It 'test:SelfImprovement.WriteScope accepts each canonical Markdown source family explicitly' {
        $paths = @(
            '.github/copilot-instructions.md',
            'plugins/self-improvement/skills/si/SKILL.md',
            'plugins/autopilot/agents/autopilot.agent.md',
            'plugins/self-improvement/prompts/si.prompt.md',
            'docs/design-notes/architecture/self-improvement.design.md',
            'docs/architecture-notes/arch-direct-workflow.md'
        )

        (Invoke-Guard -Root $script:root -Path $paths).ExitCode | Should -Be 0
    }

    It 'test:SelfImprovement.WriteScope refuses generated, executable, state, plan, and traversal targets' {
        foreach ($path in @(
                '.github/skills/si/SKILL.md',
                '.github/agents/autopilot.agent.md',
                '.github/prompts/si.prompt.md',
                '.GITHUB/copilot-instructions.md',
                'Plugins/self-improvement/skills/si/SKILL.md',
                'DOCS/design-notes/architecture/self-improvement.design.md',
                '.github/workflows/ci.yml',
                '.github/actions/setup/action.yml',
                'plugins/self-improvement/scripts/Get-SiHarvest.ps1',
                'plugins/self-improvement/schemas/run.schema.json',
                'docs/feedback/recent-learning.md',
                'docs/implementation-plans/example/plan.md',
                '../outside.md'
            )) {
            $result = Invoke-Guard -Root $script:root -Path @($path)
            $result.ExitCode | Should -Be 1 -Because "$path is not a direct SI target"
            $result.Output | Should -Match 'DENY'
        }
    }

    It 'test:SelfImprovement.WriteScope refuses a blank explicit path list' {
        $result = Invoke-Guard -Root $script:root -Path @('   ')
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'at least one non-blank path'
    }

    It 'test:SelfImprovement.WriteScope scans committed, staged, unstaged, and untracked changes' {
        New-RepoFile -Root $script:root -RelativePath 'docs/design-notes/committed.md' | Out-Null
        Invoke-Git -Root $script:root -Argument @('add', '.') | Out-Null
        Invoke-Git -Root $script:root -Argument @('commit', '--quiet', '-m', 'allowed') | Out-Null
        New-RepoFile -Root $script:root -RelativePath 'plugins/self-improvement/skills/si/staged.md' | Out-Null
        Invoke-Git -Root $script:root -Argument @(
            'add', 'plugins/self-improvement/skills/si/staged.md'
        ) | Out-Null
        New-RepoFile -Root $script:root -RelativePath 'docs/architecture-notes/untracked.md' | Out-Null

        (Invoke-Guard -Root $script:root).ExitCode | Should -Be 0

        New-RepoFile -Root $script:root -RelativePath 'package.json' | Out-Null
        $refused = Invoke-Guard -Root $script:root
        $refused.ExitCode | Should -Be 1
        $refused.Output | Should -Match 'package\.json'
    }

    It 'test:SelfImprovement.WriteScope requires a Git-scanned post-write check before trusted sync' {
        $guide = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/self-improvement/skills/si/assets/propose-guide.md'
        ) -Raw
        $guide | Should -Match '(?s)Before any generator runs.+Git-scan mode.+-BaseRef HEAD'
        $guide | Should -Match 'Never pass a\s+self-reported `-Path` list'
    }

    It 'test:SelfImprovement.WriteScope treats literal HEAD as the worktree baseline' {
        Invoke-Git -Root $script:root -Argument @(
            'update-ref', 'refs/remotes/origin/main', 'refs/heads/main'
        ) | Out-Null
        Invoke-Git -Root $script:root -Argument @(
            'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main'
        ) | Out-Null
        New-RepoFile -Root $script:root -RelativePath 'package.json' | Out-Null
        Invoke-Git -Root $script:root -Argument @('add', 'package.json') | Out-Null
        Invoke-Git -Root $script:root -Argument @('commit', '--quiet', '-m', 'branch history') | Out-Null
        New-RepoFile -Root $script:root -RelativePath 'docs/design-notes/current.md' | Out-Null

        (Invoke-Guard -Root $script:root -BaseRef 'HEAD').ExitCode | Should -Be 0
    }

    It 'test:SelfImprovement.WriteScope refuses a physical path escape' {
        $outside = Join-Path ([System.IO.Path]::GetTempPath()) (
            'si-outside-' + [guid]::NewGuid().ToString('n')
        )
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'escape.md') -Value "outside`n"
        $link = Join-Path $script:root 'docs/design-notes/escape.md'
        try {
            try {
                New-Item -ItemType SymbolicLink -Path $link `
                    -Target (Join-Path $outside 'escape.md') -ErrorAction Stop | Out-Null
            }
            catch {
                Set-ItResult -Skipped -Because 'the filesystem or account does not permit links'
                return
            }

            $result = Invoke-Guard -Root $script:root -Path @('docs/design-notes/escape.md')
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'resolves outside the repository'
        }
        finally {
            Remove-Item -LiteralPath $outside -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:SelfImprovement.Distribution ships identical canonical, plugin, and dogfood guards' {
        $manifest = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/self-improvement/plugin.json'
        ) -Raw | ConvertFrom-Json
        @($manifest.files.dest) | Should -Contain 'skills/si/scripts/Test-SiWriteScope.ps1'

        $source = (Get-FileHash -LiteralPath $script:guard).Hash
        foreach ($path in @(
                'plugins/self-improvement/skills/si/scripts/Test-SiWriteScope.ps1',
                '.github/skills/si/scripts/Test-SiWriteScope.ps1'
            )) {
            (Get-FileHash -LiteralPath (Join-Path $script:repoRoot $path)).Hash | Should -Be $source
        }
    }
}

#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Headless SI due handoff' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        function Script:Install-PluginClosure {
            param(
                [Parameter(Mandatory)][string]$RootPlugin,
                [Parameter(Mandatory)][string]$TargetRoot
            )

            $pending = [System.Collections.Generic.Queue[string]]::new()
            $installed = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )
            $versions = @{}
            $pending.Enqueue($RootPlugin)
            while ($pending.Count -gt 0) {
                $name = $pending.Dequeue()
                if (-not $installed.Add($name)) { continue }
                $pluginRoot = Join-Path $script:repoRoot "plugins/$name"
                $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
                    ConvertFrom-Json -Depth 100
                $versions[$name] = [string]$manifest.version
                foreach ($dependency in @($manifest.dependencies)) {
                    $pending.Enqueue([string]$dependency)
                }
                foreach ($file in @($manifest.files)) {
                    $target = Join-Path $TargetRoot ('.github/' + [string]$file.dest)
                    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
                    Copy-Item -LiteralPath (Join-Path $pluginRoot ([string]$file.src)) `
                        -Destination $target -Force
                }
            }
            return $versions
        }

        function Script:New-InstallRoot {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                'si-due-' + [Guid]::NewGuid().ToString('N')
            )
            [void](New-Item -ItemType Directory -Path $root -Force)
            return $root
        }
    }

    It 'test:SiDue.HeadlessDependencyInvocationAllowlistAndDedup installs independently versioned SI, invokes its writer after source persistence, and deduplicates the exact due' {
        $autopilotManifest = Get-Content -LiteralPath (
            Join-Path $script:repoRoot 'plugins/autopilot/plugin.json'
        ) -Raw | ConvertFrom-Json -Depth 100
        @($autopilotManifest.dependencies) | Should -Contain 'self-improvement'

        $agent = [System.IO.File]::ReadAllText(
            (Join-Path $script:repoRoot 'plugins/autopilot/agents/autopilot.agent.md')
        )
        $installedPath = '.github/skills/si/scripts/Enqueue-SiDue.ps1'
        $agent | Should -Match ([regex]::Escape($installedPath))
        $agent | Should -Match 'bound argument array'
        $agent | Should -Match 'sha256\(repo-id\|plan-id\|source-commit\|si-due-v1\)'
        $agent | Should -Match 'degraded: SI due enqueue failed'
        $agent | Should -Match 'Headless completion does not run `/si`'
        $agent | Should -Match 'Workflow carve-out:.+Enqueue-SiDue\.ps1'
        $sourcePush = $agent.IndexOf('required post-archive `git push origin <current-branch>`')
        $enqueue = $agent.IndexOf('capture complete-source OID -> enqueue')
        $sourcePush | Should -BeGreaterThan -1
        $enqueue | Should -BeGreaterThan $sourcePush

        $autopilotRoot = New-InstallRoot
        $standaloneRoot = New-InstallRoot
        $outside = $null
        $caseVariantOutside = $null
        try {
            $versions = Install-PluginClosure -RootPlugin autopilot -TargetRoot $autopilotRoot
            $versions.Keys | Should -Contain 'self-improvement'
            $versions['autopilot'] | Should -Not -Be $versions['self-improvement']
            Test-Path -LiteralPath (Join-Path $autopilotRoot $installedPath) -PathType Leaf |
                Should -BeTrue

            $standaloneVersions = Install-PluginClosure -RootPlugin self-improvement `
                -TargetRoot $standaloneRoot
            $standaloneVersions.Keys | Should -Contain 'self-improvement'
            $writer = Join-Path $standaloneRoot $installedPath
            Test-Path -LiteralPath $writer -PathType Leaf | Should -BeTrue

            & git -C $standaloneRoot init --quiet
            & git -C $standaloneRoot remote add origin https://github.com/Example/Consumer.git
            $sourceCommit = 'a' * 40
            $repoId = 'origin:github.com/Example/Consumer'
            $expectedBytes = [System.Text.Encoding]::UTF8.GetBytes(
                "$repoId|1936cb|$sourceCommit|si-due-v1"
            )
            $expectedDue = [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData($expectedBytes)
            ).ToLowerInvariant()

            $first = & $writer -RepoRoot $standaloneRoot -PlanId 1936cb `
                -SourceCommit $sourceCommit
            $manifestPath = Join-Path $standaloneRoot 'docs/self-improvement/state.json'
            $firstBytes = [System.IO.File]::ReadAllBytes($manifestPath)
            $second = & $writer -RepoRoot $standaloneRoot -PlanId 1936cb `
                -SourceCommit $sourceCommit
            $first.Status | Should -Be 'complete'
            $first.Written | Should -BeTrue
            $first.DueId | Should -Be $expectedDue
            $second.Status | Should -Be 'complete'
            $second.Written | Should -BeFalse
            $second.DueId | Should -Be $expectedDue
            [Convert]::ToHexString([System.IO.File]::ReadAllBytes($manifestPath)) |
                Should -Be ([Convert]::ToHexString($firstBytes))

            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
            @($manifest.pending).Count | Should -Be 1
            $manifest.pending[0].repoId | Should -Be $repoId
            $manifest.pending[0].sourceCommit | Should -Be $sourceCommit

            $outside = New-InstallRoot
            [void](New-Item -ItemType Directory -Path (Join-Path $standaloneRoot 'docs') -Force)
            Remove-Item -LiteralPath (Join-Path $standaloneRoot 'docs/self-improvement') `
                -Recurse -Force
            try {
                [void](New-Item -ItemType SymbolicLink `
                        -Path (Join-Path $standaloneRoot 'docs/self-improvement') `
                        -Target $outside -ErrorAction Stop)
            }
            catch {
                Set-ItResult -Skipped -Because 'the filesystem or account does not permit symlink creation'
                return
            }
            {
                & $writer -RepoRoot $standaloneRoot -PlanId 1936cb -SourceCommit ('b' * 40)
            } | Should -Throw '*escapes repository root via link*'
            Test-Path -LiteralPath (Join-Path $outside 'state.json') | Should -BeFalse

            Remove-Item -LiteralPath (Join-Path $standaloneRoot 'docs/self-improvement') -Force
            if (-not $IsWindows) {
                $caseVariantOutside = Join-Path (Split-Path -Parent $standaloneRoot) (
                    (Split-Path -Leaf $standaloneRoot).ToUpperInvariant()
                )
                [void](New-Item -ItemType Directory -Path $caseVariantOutside -Force)
                [void](New-Item -ItemType SymbolicLink `
                        -Path (Join-Path $standaloneRoot 'docs/self-improvement') `
                        -Target $caseVariantOutside -ErrorAction Stop)
                {
                    & $writer -RepoRoot $standaloneRoot -PlanId 1936cb -SourceCommit ('c' * 40)
                } | Should -Throw '*escapes repository root via link*'
                Test-Path -LiteralPath (Join-Path $caseVariantOutside 'state.json') |
                    Should -BeFalse
                Remove-Item -LiteralPath (Join-Path $standaloneRoot 'docs/self-improvement') -Force
            }
        }
        finally {
            Remove-Item -LiteralPath $autopilotRoot -Recurse -Force
            Remove-Item -LiteralPath $standaloneRoot -Recurse -Force
            if ($null -ne $outside -and (Test-Path -LiteralPath $outside)) {
                Remove-Item -LiteralPath $outside -Recurse -Force
            }
            if ($null -ne $caseVariantOutside -and
                (Test-Path -LiteralPath $caseVariantOutside)) {
                Remove-Item -LiteralPath $caseVariantOutside -Recurse -Force
            }
        }
    }
}

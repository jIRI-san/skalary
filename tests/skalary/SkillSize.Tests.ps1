#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A SKILL.md is re-read in full on every invocation of its skill, so its size is a recurring
# context cost. The cap is what keeps reference detail in `assets/` (read on demand) instead of
# in the always-loaded body — these tests pin both halves: the gate actually fails an over-cap
# skill, and the repo is currently under the cap.

Describe 'skill size cap' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:validator = Join-Path $script:repoRoot 'scripts/skalary/Test-SkillSize.ps1'

        $script:invoke = {
            param(
                [Parameter(Mandatory)][string]$Root,
                [int]$MaxBytes
            )

            $arguments = @{ RepoRoot = $Root }
            if ($PSBoundParameters.ContainsKey('MaxBytes')) { $arguments['MaxBytes'] = $MaxBytes }

            # The validator reports through Write-Host (information stream), so `*>&1` is
            # required — a bare `2>&1` captures nothing and every message assertion would
            # silently pass against an empty string.
            $output = & $script:validator @arguments *>&1
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output   = ($output | Out-String)
            }
        }

        $script:newSkill = {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$Name,
                [Parameter(Mandatory)][int]$Bytes
            )

            $dir = Join-Path $Root "plugins/sample/skills/$Name"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir 'SKILL.md'
            [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::UTF8.GetBytes('a' * $Bytes))
            return $path
        }
    }

    It 'test:skill-size-cap-enforced fails loud on an over-cap SKILL.md and names the remedy' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('skill-size-' + [System.Guid]::NewGuid().ToString('N'))
        try {
            & $script:newSkill -Root $root -Name 'bloated' -Bytes 2048

            $result = & $script:invoke -Root $root -MaxBytes 1024
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'plugins/sample/skills/bloated/SKILL\.md'
            $result.Output | Should -Match '2048 bytes'
            # The failure has to say what to do about it, or the cap just blocks authoring.
            $result.Output | Should -Match "assets/"
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'test:skill-size-cap-enforced passes a SKILL.md exactly at the cap' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('skill-size-' + [System.Guid]::NewGuid().ToString('N'))
        try {
            & $script:newSkill -Root $root -Name 'exact' -Bytes 1024

            $result = & $script:invoke -Root $root -MaxBytes 1024
            $result.ExitCode | Should -Be 0
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'test:skill-size-cap-enforced measures the hidden .github dogfood mirror too' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('skill-size-' + [System.Guid]::NewGuid().ToString('N'))
        try {
            $dir = Join-Path $root '.github/skills/mirrored'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $dir 'SKILL.md'), [System.Text.Encoding]::UTF8.GetBytes('a' * 2048))

            $result = & $script:invoke -Root $root -MaxBytes 1024
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match '\.github/skills/mirrored/SKILL\.md'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'test:skills-under-cap keeps every SKILL.md in the repo within the cap' {
        $result = & $script:invoke -Root $script:repoRoot
        $result.ExitCode | Should -Be 0
    }

    It 'test:skills-under-cap pushes architecture-notes detail into an installed asset' {
        # The one skill the cap actually forced open: its rare operations moved to an asset, and
        # that asset has to ship with the plugin or the skill reads nothing in a consumer repo.
        $skill = Get-Content -LiteralPath (Join-Path $script:repoRoot 'plugins/architecture-notes/skills/architecture-notes/SKILL.md') -Raw
        $skill | Should -Match 'assets/tier-operations-guide\.md'

        $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'plugins/architecture-notes/plugin.json') -Raw | ConvertFrom-Json
        @($manifest.files.src) | Should -Contain 'skills/architecture-notes/assets/tier-operations-guide.md'

        # plugin.json alone does not ship anything: consumer installs resolve against the
        # registry, so an asset absent there is an asset the skill reads as nothing.
        $registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry.json') -Raw | ConvertFrom-Json
        $entry = @($registry.plugins) | Where-Object { $_.name -eq 'architecture-notes' }
        $entry | Should -Not -BeNullOrEmpty
        @($entry.files.dest) | Should -Contain 'skills/architecture-notes/assets/tier-operations-guide.md'
    }
}

#requires -Version 7.0
<#
.SYNOPSIS
    Covers the file set `validate.ps1` parses (REQ-8, RISK-5).
.DESCRIPTION
    The gate used to enumerate with `Get-ChildItem -Recurse`, which on Unix skips
    dot-prefixed entries because pwsh reports them as hidden, and on Windows does not.
    `.github` was therefore parsed on one platform and skipped on the other while both
    legs reported a pass. These cases pin the three properties that fixes it: dot-prefixed
    payload is enumerated, `.git` is not, and the resulting set is a function of the
    fixture rather than of the host.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'validation payload scope' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/PayloadScope.psm1') -Force -DisableNameChecking
        $script:fixtureRoots = [System.Collections.Generic.List[string]]::new()

        # The fixture declares its own expected file set, so the assertion never asks the
        # filesystem what it should have found — which is what makes it the same assertion
        # on Windows and Linux.
        $script:expectedPayload = @(
            'root.ps1'
            '.github/workflows/ci.ps1'
            '.github/skills/probe/scripts/Probe.psm1'
            'scripts/nested/deep/Deep.ps1'
            'tools/settings.psd1'
        )

        # Present in the fixture, deliberately outside the parsed set: excluded roots and
        # pruned subtrees. `.git` is the one RISK-5 names; `.github/.skalary` is the plugin
        # installer's gitignored runtime state, which would otherwise make the parsed count
        # a function of local install history rather than of the checkout.
        $script:excludedPayload = @(
            '.git/hooks/pre-commit.ps1'
            '.git/config.ps1'
            '.github/.skalary/receipts/keep.ps1'
            '.github/.skalary/tmp/install-1/staged/00001-Third.ps1'
            'node_modules/pkg/index.ps1'
            'scripts/node_modules/pkg/index.ps1'
            'scripts/bin/Built.ps1'
            'scripts/obj/Obj.ps1'
            '.worktrees/wt/Work.ps1'
            'unlisted-root/Stray.ps1'
        )

        function New-PayloadFixture {
            <#
            .SYNOPSIS
                Materialises the declared payload and returns the fixture root.
            #>
            [CmdletBinding()]
            [OutputType([string])]
            param()

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('skalary-payload-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root)
            $script:fixtureRoots.Add($root)

            foreach ($relative in ($script:expectedPayload + $script:excludedPayload)) {
                $path = Join-Path $root $relative
                $parent = Split-Path -Parent $path
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    [void](New-Item -ItemType Directory -Path $parent -Force)
                }
                Set-Content -LiteralPath $path -Value "# $relative" -Encoding utf8NoBOM
            }

            return $root
        }

        function Get-RelativePayload {
            <#
            .SYNOPSIS
                Returns the enumerated files as repo-relative, forward-slashed paths.
            #>
            [CmdletBinding()]
            [OutputType([string[]])]
            param(
                [Parameter(Mandatory)]
                [string]$Root
            )

            $canonicalRoot = [System.IO.Path]::GetFullPath($Root)
            $prefix = $canonicalRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            $found = @(Get-SkalaryPayloadFile -RepoRoot $canonicalRoot -Extension '.ps1', '.psm1', '.psd1')
            return [string[]]@($found | ForEach-Object { $_.Substring($prefix.Length).Replace([System.IO.Path]::DirectorySeparatorChar, '/') })
        }
    }

    AfterAll {
        foreach ($root in $script:fixtureRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:Validate.DotPrefixedPayloadEnumerated parses payload under dot-prefixed roots' {
        $root = New-PayloadFixture
        $found = Get-RelativePayload -Root $root

        foreach ($relative in @($script:expectedPayload | Where-Object { $_.StartsWith('.', [System.StringComparison]::Ordinal) })) {
            $found | Should -Contain $relative -Because 'pwsh treats dot-prefixed entries as hidden on Unix and not on Windows, so an unforced walk parses a different set per platform (REQ-8)'
        }

        # The repo's own `.github` is the root that made this matter.
        $live = @(Get-SkalaryPayloadFile -RepoRoot $script:repoRoot -Extension '.ps1', '.psm1', '.psd1')
        @($live | Where-Object { $_ -match '[\\/]\.github[\\/]' }).Count |
            Should -BeGreaterThan 0 -Because '.github carries the installed skill scripts this gate exists to parse'
    }

    It 'test:Validate.GitDirectoryNotEnumerated keeps .git and vendored trees out of the parsed set' {
        $root = New-PayloadFixture
        $found = Get-RelativePayload -Root $root

        foreach ($relative in $script:excludedPayload) {
            $found | Should -Not -Contain $relative -Because 'enumeration is an allowlist of payload roots, so -Force cannot reach VCS, vendored or generated trees (RISK-5)'
        }

        @($found | Where-Object { $_ -match '(^|/)\.git/' }).Count |
            Should -Be 0 -Because 'RISK-5 names .git specifically: its contents are neither ours nor stable'

        $live = @(Get-SkalaryPayloadFile -RepoRoot $script:repoRoot -Extension '.ps1', '.psm1', '.psd1', '.json')
        @($live | Where-Object { $_ -match '[\\/]\.git[\\/]' }).Count |
            Should -Be 0 -Because 'the same must hold for the repository the gate actually runs against'
    }

    It 'test:Validate.FileCountEqualAcrossPlatforms returns exactly the declared payload, whatever the host' {
        $root = New-PayloadFixture
        $found = Get-RelativePayload -Root $root

        # Compared against the fixture's declaration rather than against a directory
        # listing: a listing would inherit the platform's own idea of what is visible,
        # which is the asymmetry under test. This assertion is therefore literally the
        # same on Windows and Linux, and the count follows from the set.
        $expected = [string[]]@($script:expectedPayload)
        [System.Array]::Sort($expected, [System.StringComparer]::Ordinal)
        $actual = [string[]]@($found)
        [System.Array]::Sort($actual, [System.StringComparer]::Ordinal)

        ($actual -join "`n") | Should -Be ($expected -join "`n") -Because 'the parsed set is a function of the allowlist and the fixture, not of the platform (REQ-8)'
        $actual.Count | Should -Be $expected.Count
    }

    It 'test:Validate.ReparsePointNotFollowed refuses a symlinked payload root' {
        # `Path.GetFullPath` normalises `..` and separators but does not resolve links, so
        # the containment check cannot see through one. Rejecting reparse points is the
        # whole of the RISK-5 mitigation, which is why this case reports skipped rather
        # than passing silently on a host that cannot create a link.
        $root = New-PayloadFixture
        $before = Get-RelativePayload -Root $root

        try {
            [void](New-Item -ItemType SymbolicLink -Path (Join-Path $root 'tools/linked') -Target (Join-Path $root 'scripts/nested') -ErrorAction Stop)
        }
        catch [System.Exception] {
            Set-ItResult -Skipped -Because "this host cannot create a symbolic link unprivileged: $($_.Exception.Message)"
            return
        }

        $after = Get-RelativePayload -Root $root
        ((@($after) | Sort-Object) -join "`n") |
            Should -Be ((@($before) | Sort-Object) -join "`n") -Because 'a symlink inside a payload root must not add or re-add files to the parsed set (RISK-5)'
    }

    It 'test:Validate.PayloadRootsCoverRepository keeps the allowlist abreast of the repository' {
        # The allowlist trades "scans too much" for "scans nothing, quietly". A new
        # top-level directory nobody added here would never be parsed and nothing would say so.
        $allowed = [string[]]@(Get-SkalaryPayloadRoot)
        $pruned = [string[]]@(Get-SkalaryPrunedDirectoryName)

        $unlisted = @(
            [System.IO.Directory]::EnumerateDirectories($script:repoRoot) |
                ForEach-Object { [System.IO.Path]::GetFileName($_) } |
                Where-Object { $pruned -notcontains $_ -and $allowed -notcontains $_ }
        )

        $unlisted.Count | Should -Be 0 -Because "every top-level directory is either an allowlisted payload root or explicitly pruned; unlisted: $($unlisted -join ', ')"

        # And a root that moved must be a loud failure rather than a quiet coverage loss.
        { Get-SkalaryPayloadFile -RepoRoot $script:repoRoot -Extension '.ps1' -Root @('no-such-root') -RequireRoot } |
            Should -Throw -ExpectedMessage '*no-such-root*'
    }
}

#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# `cr` no longer extracts diffs: reviewers read the code themselves, so the only thing the
# orchestrator has to get right is *which files* are in scope. These tests pin that contract —
# every mode resolves to a plain, repo-relative file list and nothing else (REQ-11).

Describe 'Get-ReviewScope' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:scriptPath = Join-Path $script:repoRoot 'plugins/code-review/agents/scripts/Get-ReviewScope.ps1'
        $script:fixtures = [System.Collections.Generic.List[string]]::new()

        function Invoke-Scope {
            param(
                [Parameter(Mandatory)][string]$Root,
                [hashtable]$Arguments = @{}
            )

            $splat = @{ RepoRoot = $Root } + $Arguments
            $output = & $script:scriptPath @splat
            # Comma-wrapped: a one-file scope would otherwise unroll to a bare string and
            # every count/collection assertion below would silently change meaning.
            return , @($output | ForEach-Object { [string]$_ })
        }

        function New-Fixture {
            <#
                Bare origin + clone so origin/HEAD, unpushed commits, and branch-vs-default
                all resolve exactly as they do in a real checkout.
            #>
            param([string]$DefaultBranch = 'main')

            $base = Join-Path ([System.IO.Path]::GetTempPath()) ("review-scope-" + [System.Guid]::NewGuid().ToString('N'))
            $origin = Join-Path $base 'origin.git'
            $work = Join-Path $base 'work'
            [void](New-Item -ItemType Directory -Path $base -Force)

            git init --quiet --bare --initial-branch=$DefaultBranch $origin | Out-Null
            git init --quiet --initial-branch=$DefaultBranch $work | Out-Null
            git -C $work config user.name 'review-scope-tests' | Out-Null
            git -C $work config user.email 'review-scope-tests@example.com' | Out-Null
            git -C $work config commit.gpgsign false | Out-Null

            Set-Content -LiteralPath (Join-Path $work 'base.md') -Value "base`n" -NoNewline
            git -C $work add base.md | Out-Null
            git -C $work commit --quiet -m 'base commit' | Out-Null

            git -C $work remote add origin $origin | Out-Null
            git -C $work push --quiet -u origin $DefaultBranch | Out-Null
            git -C $work remote set-head origin $DefaultBranch | Out-Null

            $script:fixtures.Add($base)
            return $work
        }

        function Add-Commit {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$RelativePath,
                [string]$Content = 'content',
                [string]$Message = 'change'
            )

            $full = Join-Path $Root $RelativePath
            $parent = Split-Path -Parent $full
            if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $parent -Force)
            }
            Set-Content -LiteralPath $full -Value "$Content`n" -NoNewline
            git -C $Root add -- $RelativePath | Out-Null
            git -C $Root commit --quiet -m $Message | Out-Null
        }
    }

    AfterAll {
        foreach ($fixture in $script:fixtures) {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:review-scope-modes lists staged, unstaged, and untracked files in uncommitted mode' {
        $work = New-Fixture
        Add-Commit -Root $work -RelativePath 'tracked.md' -Message 'add tracked'

        Set-Content -LiteralPath (Join-Path $work 'tracked.md') -Value "edited`n" -NoNewline
        Set-Content -LiteralPath (Join-Path $work 'staged.md') -Value "staged`n" -NoNewline
        git -C $work add staged.md | Out-Null
        Set-Content -LiteralPath (Join-Path $work 'untracked.md') -Value "new`n" -NoNewline

        $files = Invoke-Scope -Root $work -Arguments @{ Mode = 'uncommitted' }

        $files | Should -Contain 'tracked.md'
        $files | Should -Contain 'staged.md'
        $files | Should -Contain 'untracked.md'
        $files | Should -Not -Contain 'base.md'
    }

    It 'test:review-scope-modes lists only branch commits in branch mode' {
        $work = New-Fixture
        git -C $work checkout --quiet -b feature/scope | Out-Null
        Add-Commit -Root $work -RelativePath 'src/feature.md' -Message 'feature work'
        Set-Content -LiteralPath (Join-Path $work 'dirty.md') -Value "dirty`n" -NoNewline

        $files = Invoke-Scope -Root $work -Arguments @{ Mode = 'branch' }

        $files | Should -Be @('src/feature.md')
    }

    It 'test:review-scope-modes lists exactly the last N commits in commits mode' {
        $work = New-Fixture
        Add-Commit -Root $work -RelativePath 'one.md' -Message 'one'
        Add-Commit -Root $work -RelativePath 'two.md' -Message 'two'
        Add-Commit -Root $work -RelativePath 'three.md' -Message 'three'

        $files = Invoke-Scope -Root $work -Arguments @{ Mode = 'commits'; N = 2 }

        $files | Should -Be @('three.md', 'two.md')
    }

    It 'test:review-scope-modes expands folders and excludes build output in paths mode' {
        $work = New-Fixture
        Add-Commit -Root $work -RelativePath 'src/app/Main.cs' -Message 'main'
        Add-Commit -Root $work -RelativePath 'src/app/Helper.cs' -Message 'helper'
        Add-Commit -Root $work -RelativePath 'src/other/Skip.cs' -Message 'other'
        [void](New-Item -ItemType Directory -Path (Join-Path $work 'src/app/bin') -Force)
        Set-Content -LiteralPath (Join-Path $work 'src/app/bin/Generated.cs') -Value "gen`n" -NoNewline
        Set-Content -LiteralPath (Join-Path $work 'src/app/image.png') -Value "binary`n" -NoNewline

        $files = Invoke-Scope -Root $work -Arguments @{ Mode = 'paths'; Paths = @('src/app') }

        $files | Should -Be @('src/app/Helper.cs', 'src/app/Main.cs')
    }

    It 'test:review-scope-modes accepts a mix of file and folder arguments in paths mode' {
        $work = New-Fixture
        Add-Commit -Root $work -RelativePath 'src/app/Main.cs' -Message 'main'
        Add-Commit -Root $work -RelativePath 'src/other/Skip.cs' -Message 'other'

        $files = Invoke-Scope -Root $work -Arguments @{ Mode = 'paths'; Paths = @('src/app', 'src/other/Skip.cs') }

        $files | Should -Be @('src/app/Main.cs', 'src/other/Skip.cs')
    }

    It 'test:review-scope-modes combines uncommitted and branch commits on a feature branch by default' {
        $work = New-Fixture
        git -C $work checkout --quiet -b feature/scope | Out-Null
        Add-Commit -Root $work -RelativePath 'committed.md' -Message 'committed'
        Set-Content -LiteralPath (Join-Path $work 'working.md') -Value "working`n" -NoNewline

        $files = Invoke-Scope -Root $work

        $files | Should -Be @('committed.md', 'working.md')
    }

    It 'test:review-scope-modes falls back to unpushed commits when on the default branch' {
        $work = New-Fixture
        Add-Commit -Root $work -RelativePath 'pushed.md' -Message 'pushed'
        git -C $work push --quiet origin main | Out-Null
        Add-Commit -Root $work -RelativePath 'unpushed.md' -Message 'unpushed'
        Set-Content -LiteralPath (Join-Path $work 'working.md') -Value "working`n" -NoNewline

        $files = Invoke-Scope -Root $work

        $files | Should -Be @('unpushed.md', 'working.md')
    }

    It 'test:review-scope-modes drops deleted paths unless they are asked for' {
        $work = New-Fixture
        Add-Commit -Root $work -RelativePath 'gone.md' -Message 'add gone'
        git -C $work rm --quiet gone.md | Out-Null

        $default = Invoke-Scope -Root $work -Arguments @{ Mode = 'uncommitted' }
        $withDeleted = Invoke-Scope -Root $work -Arguments @{ Mode = 'uncommitted'; IncludeDeleted = $true }

        # A reviewer that reads files cannot read a file that no longer exists, so the default
        # list must not send it one; the history question is opt-in.
        $default | Should -Not -Contain 'gone.md'
        $withDeleted | Should -Contain 'gone.md'
    }

    It 'test:review-scope-modes emits only repo-relative paths, never diff content' {
        $work = New-Fixture
        git -C $work checkout --quiet -b feature/scope | Out-Null
        Add-Commit -Root $work -RelativePath 'src/app/Main.cs' -Content 'class Main {}' -Message 'main'
        Set-Content -LiteralPath (Join-Path $work 'src/app/Main.cs') -Value "class Main { int x; }`n" -NoNewline

        $files = Invoke-Scope -Root $work

        $files.Count | Should -BeGreaterThan 0
        foreach ($file in $files) {
            $file | Should -Not -Match '^(diff --git|@@|\+\+\+|---|index )'
            $file | Should -Not -Match '^[A-Za-z]:[\\/]'
            $file | Should -Not -Match '\\'
            Test-Path -LiteralPath (Join-Path $work $file) -PathType Leaf | Should -BeTrue
        }
    }

    It 'test:review-scope-modes fails loud on argument combinations it cannot honour' {
        $work = New-Fixture

        { Invoke-Scope -Root $work -Arguments @{ Mode = 'commits' } } | Should -Throw '*requires -N*'
        { Invoke-Scope -Root $work -Arguments @{ Mode = 'paths' } } | Should -Throw '*requires -Paths*'
        { Invoke-Scope -Root $work -Arguments @{ Mode = 'branch'; N = 2 } } | Should -Throw '*only valid with -Mode commits*'
        { Invoke-Scope -Root $work -Arguments @{ Mode = 'branch'; Paths = @('base.md') } } | Should -Throw '*only valid with -Mode paths*'
        { Invoke-Scope -Root $work -Arguments @{ Mode = 'paths'; Paths = @('does/not/exist.md') } } | Should -Throw '*Path not found*'
        { Invoke-Scope -Root $work -Arguments @{ Mode = 'nonsense' } } | Should -Throw
    }

    It 'test:review-scope-modes keeps paths that git would C-quote' {
        $work = New-Fixture
        # `"` is a legal filename character on POSIX but illegal in NTFS, so the
        # embedded-quote case can only be created off Windows.
        $quoted = if ($IsWindows) { $null } else { 'quo' + [char]34 + 'te.md' }
        $names = @('café.md', 'has space.md') + @($quoted | Where-Object { $_ })
        foreach ($name in $names) {
            Set-Content -LiteralPath (Join-Path $work $name) -Value "content`n" -NoNewline
        }

        $files = Invoke-Scope -Root $work -Arguments @{ Mode = 'uncommitted' }

        # git C-quotes these in its newline-separated output; a quoted path resolves to no file
        # and the emitter would drop it while still exiting 0.
        $files | Should -Contain 'café.md'
        $files | Should -Contain 'has space.md'
        if ($quoted) { $files | Should -Contain $quoted }
    }

    It 'test:review-scope-modes keeps files whose names differ only by case' -Skip:($IsWindows) {
        $work = New-Fixture
        foreach ($name in @('Notes.md', 'notes.md')) {
            Set-Content -LiteralPath (Join-Path $work $name) -Value "content`n" -NoNewline
        }

        $files = Invoke-Scope -Root $work -Arguments @{ Mode = 'uncommitted' }

        # Two distinct files on a case-sensitive filesystem; case-insensitive dedup would
        # discard one of them at random.
        $files | Should -Contain 'Notes.md'
        $files | Should -Contain 'notes.md'
    }

    It 'test:review-scope-modes includes dot-prefixed files in paths mode' {
        $work = New-Fixture
        Add-Commit -Root $work -RelativePath 'src/app/Main.cs' -Message 'main'
        Set-Content -LiteralPath (Join-Path $work 'src/app/.editorconfig') -Value "root = true`n" -NoNewline

        $files = Invoke-Scope -Root $work -Arguments @{ Mode = 'paths'; Paths = @('src/app') }

        # Hidden on Unix, not on Windows — without -Force the same command reviews a different
        # set of files per platform.
        $files | Should -Be @('src/app/.editorconfig', 'src/app/Main.cs')
    }

    It 'test:review-scope-modes refuses a path outside the repository instead of reviewing nothing' {
        $work = New-Fixture
        $outside = New-Fixture

        { Invoke-Scope -Root $work -Arguments @{ Mode = 'paths'; Paths = @((Join-Path $outside 'base.md')) } } |
            Should -Throw '*outside the repository root*'
    }

    It 'test:review-scope-modes still resolves a scope in a repo with no commits' {
        $bare = Join-Path ([System.IO.Path]::GetTempPath()) ("review-scope-empty-" + [System.Guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $bare -Force)
        $script:fixtures.Add($bare)
        git init --quiet --initial-branch=main $bare | Out-Null
        Set-Content -LiteralPath (Join-Path $bare 'first.md') -Value "first`n" -NoNewline

        # No branch ref exists before the first commit; demanding one would fail the default
        # mode exactly when everything is new.
        $files = Invoke-Scope -Root $bare

        $files | Should -Be @('first.md')
    }

    It 'test:review-scope-modes is declared in the code-review plugin manifest' {
        $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'plugins/code-review/plugin.json') -Raw | ConvertFrom-Json -Depth 50
        $declared = @($manifest.files | ForEach-Object { [string]$_.src })

        # Installation only materializes what files[] enumerates; an undeclared helper is a
        # scope emitter that exists here and nowhere a consumer can run it.
        $declared | Should -Contain 'agents/scripts/Get-ReviewScope.ps1'
        Test-Path -LiteralPath $script:scriptPath -PathType Leaf | Should -BeTrue
    }
}

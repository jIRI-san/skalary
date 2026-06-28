Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Run with: Invoke-Pester ./tests/autopilot
# Test ID: Autopilot.PreparePackages

Describe 'Autopilot.PreparePackages' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../../plugins/autopilot/scripts/prepare-packages.ps1')
    }

    Context 'ConvertTo-FeedSegment' {
        It 'collapses path separators so a branch cannot escape the feed root' {
            ConvertTo-FeedSegment 'feature/foo' | Should -Be 'feature-foo'
        }
        It 'rejects traversal segments' {
            { ConvertTo-FeedSegment '..' } | Should -Throw
            { ConvertTo-FeedSegment 'a..b' } | Should -Throw
        }
        It 'rejects empty/whitespace' {
            { ConvertTo-FeedSegment '   ' } | Should -Throw
        }
    }

    Context 'Assert-PathUnder' {
        It 'passes for a path under the base' {
            { Assert-PathUnder -Base $TestDrive -Path (Join-Path $TestDrive 'a/b') } | Should -Not -Throw
        }
        It 'throws when the path escapes the base' {
            $base = Join-Path $TestDrive 'feed'
            $escape = Join-Path $TestDrive 'other'
            { Assert-PathUnder -Base $base -Path $escape } | Should -Throw '*escapes feed root*'
        }
    }

    Context 'Get-DetectedEcosystem' {
        BeforeEach {
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        }
        It 'detects dotnet from a csproj' {
            Set-Content (Join-Path $script:root 'App.csproj') '<Project/>'
            Get-DetectedEcosystem -Root $script:root | Should -Contain 'dotnet'
        }
        It 'detects npm from package.json' {
            Set-Content (Join-Path $script:root 'package.json') '{}'
            Get-DetectedEcosystem -Root $script:root | Should -Contain 'npm'
        }
        It 'honors an explicit override and ignores detection' {
            Set-Content (Join-Path $script:root 'App.csproj') '<Project/>'
            Get-DetectedEcosystem -Root $script:root -Override @('npm') | Should -Be @('npm')
        }
        It 'rejects an unknown ecosystem override' {
            { Get-DetectedEcosystem -Root $script:root -Override @('pypi') } | Should -Throw '*Unknown ecosystem*'
        }
    }

    Context 'Assert-Lockfile' {
        BeforeEach {
            $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        }
        It 'fails loud when the npm lockfile is missing' {
            { Assert-Lockfile -Root $script:root -Ecosystem 'npm' } | Should -Throw '*package-lock.json*'
        }
        It 'fails loud when the dotnet lockfile is missing' {
            { Assert-Lockfile -Root $script:root -Ecosystem 'dotnet' } | Should -Throw '*packages.lock.json*'
        }
        It 'passes when the npm lockfile is present' {
            Set-Content (Join-Path $script:root 'package-lock.json') '{}'
            { Assert-Lockfile -Root $script:root -Ecosystem 'npm' } | Should -Not -Throw
        }
    }

    Context 'Invoke-PreparePackages (initial locked mode)' {
        BeforeEach {
            $global:LASTEXITCODE = 0
            $script:repo = Join-Path $TestDrive ('repo-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:repo -Force | Out-Null
            Set-Content (Join-Path $script:repo 'package.json') '{}'
            Set-Content (Join-Path $script:repo 'package-lock.json') '{}'
            $script:feedRoot = Join-Path $TestDrive ('feed-' + [guid]::NewGuid().ToString('N'))
            Mock git { 'work-branch' }
            Mock Invoke-NpmRestore { }
            Mock Invoke-DotnetRestore { }
        }
        It 'builds the feed under repo-leaf and branch and runs a locked npm restore' {
            $feed = Invoke-PreparePackages -RepoRoot $script:repo -FeedRoot $script:feedRoot
            $expected = Join-Path (Join-Path $script:feedRoot (Split-Path $script:repo -Leaf)) 'work-branch'
            $feed | Should -Be $expected
            Test-Path (Join-Path $feed 'npm') | Should -BeTrue
            Should -Invoke Invoke-NpmRestore -Times 1
        }
        It 'fails loud when an enabled ecosystem has no lockfile' {
            Remove-Item (Join-Path $script:repo 'package-lock.json')
            { Invoke-PreparePackages -RepoRoot $script:repo -FeedRoot $script:feedRoot } | Should -Throw '*package-lock.json*'
        }
        It 'is idempotent across repeated runs' {
            $a = Invoke-PreparePackages -RepoRoot $script:repo -FeedRoot $script:feedRoot
            $b = Invoke-PreparePackages -RepoRoot $script:repo -FeedRoot $script:feedRoot
            $a | Should -Be $b
        }
        It 'detects dotnet and runs a dotnet restore' {
            Remove-Item (Join-Path $script:repo 'package.json')
            Remove-Item (Join-Path $script:repo 'package-lock.json')
            Set-Content (Join-Path $script:repo 'App.csproj') '<Project/>'
            Set-Content (Join-Path $script:repo 'packages.lock.json') '{}'
            $feed = Invoke-PreparePackages -RepoRoot $script:repo -FeedRoot $script:feedRoot
            Test-Path (Join-Path $feed 'nuget') | Should -BeTrue
            Should -Invoke Invoke-DotnetRestore -Times 1
        }
    }

    Context 'Invoke-RebundleMode (-Branch)' {
        BeforeEach {
            $global:LASTEXITCODE = 0
            $script:repo = Join-Path $TestDrive ('repo-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:repo -Force | Out-Null
            $script:feedRoot = Join-Path $TestDrive ('feed-' + [guid]::NewGuid().ToString('N'))
            $script:lockChanged = $true
            $script:pushed = $false
            $script:committed = $false

            Mock Invoke-NpmRestore { }
            Mock Invoke-DotnetRestore { }
            Mock git {
                $a = $args
                if ($a -contains 'ls-remote') {
                    $global:LASTEXITCODE = $script:refExit
                    return
                }
                if ($a -contains 'worktree' -and $a -contains 'add') {
                    # The temp worktree path is the element after '--detach'.
                    $idx = [array]::IndexOf($a, '--detach')
                    $wt = $a[$idx + 1]
                    New-Item -ItemType Directory -Path $wt -Force | Out-Null
                    Set-Content (Join-Path $wt 'package.json') '{}'
                    Set-Content (Join-Path $wt 'package-lock.json') '{}'
                    $global:LASTEXITCODE = 0
                    return
                }
                if ($a -contains 'diff') {
                    $global:LASTEXITCODE = 0
                    if ($script:lockChanged) { return 'package-lock.json' }
                    return
                }
                if ($a -contains 'commit') { $script:committed = $true; $global:LASTEXITCODE = 0; return }
                if ($a -contains 'push') { $script:pushed = $true; $global:LASTEXITCODE = 0; return }
                $global:LASTEXITCODE = 0
            }
        }

        It 'throws when the remote ref is missing' {
            $script:refExit = 1
            { Invoke-RebundleMode -RepoRoot $script:repo -Branch 'feature/x' -FeedRoot $script:feedRoot -RepoLeaf 'repo' } |
                Should -Throw '*not found*'
        }

        It 'regenerates, commits, and pushes the lockfile when it changed' {
            $script:refExit = 0
            $script:lockChanged = $true
            $feed = Invoke-RebundleMode -RepoRoot $script:repo -Branch 'feature/x' -FeedRoot $script:feedRoot -RepoLeaf 'repo'
            $feed | Should -Be (Join-Path (Join-Path $script:feedRoot 'repo') 'feature-x')
            $script:committed | Should -BeTrue
            $script:pushed | Should -BeTrue
        }

        It 'does not commit or push when the lockfile is unchanged' {
            $script:refExit = 0
            $script:lockChanged = $false
            $null = Invoke-RebundleMode -RepoRoot $script:repo -Branch 'feature/x' -FeedRoot $script:feedRoot -RepoLeaf 'repo'
            $script:committed | Should -BeFalse
            $script:pushed | Should -BeFalse
        }
    }
}

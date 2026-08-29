Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Run with: Invoke-Pester ./tests/autopilot
#
# launch-sandbox.ps1 is UTF-16 and shells out to Windows Sandbox, so this
# fixture verifies the offline wiring by reading the script text (Get-Content
# -Raw transparently decodes the BOM) rather than launching a sandbox.

Describe 'Autopilot.SandboxOffline' {
    BeforeAll {
        $script:sandboxPath = Join-Path $PSScriptRoot '../../plugins/autopilot/scripts/launch-sandbox.ps1'
        $script:sandbox = Get-Content -LiteralPath $script:sandboxPath -Raw
    }

    Context 'launcher mount + lifecycle' {
        It 'exposes a -FeedPath parameter' {
            $sandbox.Contains('[string]$FeedPath') | Should -BeTrue
        }
        It 'maps the feed read-only at C:\feed only when a feed is provided' {
            $sandbox.Contains('if ($FeedPath) {') | Should -BeTrue
            $sandbox.Contains('<SandboxFolder>C:\feed</SandboxFolder>') | Should -BeTrue
            $sandbox.Contains('$feedMapping') | Should -BeTrue
        }
        It 'clears stale sentinel + rebundle markers before launch' {
            $sandbox.Contains("Remove-Item -Path `$SentinelPath, `$RebundleMarker") | Should -BeTrue
        }
        It 'blocks on the bootstrap completion sentinel with a timeout' {
            $sandbox.Contains('while (-not (Test-Path $SentinelPath))') | Should -BeTrue
            $sandbox.Contains('$Config.timeout') | Should -BeTrue
        }
        It 'returns exit 43 when the rebundle marker is present after the poll' {
            $sandbox.Contains('if (Test-Path $RebundleMarker) {') | Should -BeTrue
            $sandbox.Contains('$exitCode = 43') | Should -BeTrue
            $sandbox.Contains('exit $exitCode') | Should -BeTrue
        }
    }

    Context 'bootstrap offline restore' {
        It 'detects offline mode from the read-only feed mount' {
            $sandbox.Contains("Test-Path 'C:\feed'") | Should -BeTrue
        }
        It 'copies the feed to a writable cache (no C:\work writes)' {
            $sandbox.Contains("Copy-Item -Path 'C:\feed\*'") | Should -BeTrue
        }
        It 'emits an out-of-tree NuGet config with a cleared source list' {
            $sandbox.Contains('NUGET_CONFIG') | Should -BeTrue
            $sandbox.Contains('<clear />') | Should -BeTrue
            $sandbox.Contains('globalPackagesFolder') | Should -BeTrue
        }
        It 'emits an out-of-tree npm offline config' {
            $sandbox.Contains('npm_config_cache') | Should -BeTrue
            $sandbox.Contains('npm_config_offline') | Should -BeTrue
        }
        It 'on copilot exit 43 pushes the manifest and writes the rebundle marker' {
            $sandbox.Contains('-eq 43') | Should -BeTrue
            ([regex]::Matches($sandbox, [regex]::Escape('.autopilot-rebundle-needed')).Count) |
                Should -BeGreaterThan 0
        }
        It 'writes the completion sentinel from the finally block (always fires)' {
            # Once in the host clear-markers, once in the bootstrap finally.
            ([regex]::Matches($sandbox, [regex]::Escape('.bootstrap-complete')).Count) |
                Should -BeGreaterThan 1
            $finallyStart = $sandbox.IndexOf('} finally {', [System.StringComparison]::Ordinal)
            $bootstrapEnd = $sandbox.IndexOf('"@', $finallyStart, [System.StringComparison]::Ordinal)
            $finallyBlock = $sandbox.Substring($finallyStart, $bootstrapEnd - $finallyStart)
            $exitMarker = $finallyBlock.IndexOf('.autopilot-exit-code', [System.StringComparison]::Ordinal)
            $completionSentinel = $finallyBlock.IndexOf('.bootstrap-complete', [System.StringComparison]::Ordinal)
            $exitMarker | Should -BeGreaterThan -1
            $completionSentinel | Should -BeGreaterThan $exitMarker
        }
        It 'keeps the existing exit-42 @human branch' {
            $sandbox.Contains('-eq 42') | Should -BeTrue
        }
    }
}

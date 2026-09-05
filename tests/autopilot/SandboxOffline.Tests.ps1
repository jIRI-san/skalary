Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Run with: Invoke-Pester ./tests/autopilot
#
# launch-sandbox.ps1 shells out to Windows Sandbox, so this fixture verifies
# the offline wiring by reading the UTF-8 script rather than launching a sandbox.

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
        It 'blocks on the bootstrap completion sentinel without an elapsed kill' {
            $sandbox.Contains('while (-not (Test-Path $SentinelPath))') | Should -BeTrue
            $sandbox.Contains('$sandboxProcess.HasExited') | Should -BeTrue
            $sandbox.Contains('$Config.timeout') | Should -BeFalse
            $sandbox.Contains('$sandboxProcess.Kill') | Should -BeFalse
        }
        It 'returns exit 43 when the rebundle marker is present after the poll' {
            $sandbox.Contains('if (Test-Path $RebundleMarker) {') | Should -BeTrue
            $sandbox.Contains('$exitCode = 43') | Should -BeTrue
            $sandbox.Contains('exit $exitCode') | Should -BeTrue
        }
        It 'reports invalid terminal markers without bypassing diagnostics or rebundle handling' {
            $terminalStart = $sandbox.IndexOf('$exitCode = if', [System.StringComparison]::Ordinal)
            $diagnosticsStart = $sandbox.IndexOf('Write-Host "Session output:', $terminalStart, [System.StringComparison]::Ordinal)
            $terminalBlock = $sandbox.Substring($terminalStart, $diagnosticsStart - $terminalStart)
            $terminalBlock | Should -Match 'Write-Warning "Sandbox returned invalid exit marker'
            $terminalBlock | Should -Match "Write-Warning 'Sandbox completed without a valid exit marker"
            $terminalBlock | Should -Not -Match 'Write-Error'
            $terminalBlock.IndexOf('if (Test-Path $RebundleMarker)', [System.StringComparison]::Ordinal) |
                Should -BeGreaterThan -1
        }
        It 'reports the repository mount as read-only' {
            $sandbox.Contains('C:\repo (read-only)') | Should -BeTrue
            $sandbox.Contains('C:\repo (read-write)') | Should -BeFalse
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
            $finallyBlock | Should -Match 'Complete-Bootstrap -Code'
            $helperStart = $sandbox.IndexOf('function Complete-Bootstrap', [System.StringComparison]::Ordinal)
            $helperEnd = $sandbox.IndexOf("Log 'Bootstrap started'", $helperStart, [System.StringComparison]::Ordinal)
            $helper = $sandbox.Substring($helperStart, $helperEnd - $helperStart)
            $exitMarker = $helper.IndexOf('.autopilot-exit-code', [System.StringComparison]::Ordinal)
            $completionSentinel = $helper.IndexOf('.bootstrap-complete', [System.StringComparison]::Ordinal)
            $exitMarker | Should -BeGreaterThan -1
            $completionSentinel | Should -BeGreaterThan $exitMarker
        }
        It 'publishes terminal markers for setup and plan-resolution failures' {
            ([regex]::Matches($sandbox, 'Complete-Bootstrap -Code 1').Count) |
                Should -BeGreaterOrEqual 2
        }
        It 'keeps the existing exit-42 @human branch' {
            $sandbox.Contains('-eq 42') | Should -BeTrue
        }
    }
}

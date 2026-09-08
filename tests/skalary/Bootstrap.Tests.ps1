#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'bootstrap.ps1' {
    BeforeAll {
        $script:root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:bootstrap = Join-Path $root 'scripts/skalary/bootstrap.ps1'
        $script:text = [System.IO.File]::ReadAllText($bootstrap)
    }

    It 'test:Bootstrap.InstallsPluginManager parses and auto-installs plugin-manager with an approval offer' {
        # Parses without syntax errors.
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($bootstrap, [ref]$null, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0

        # Set-ScriptApproval.ps1 is downloaded alongside the other scripts.
        $text | Should -Match "'Set-ScriptApproval\.ps1'"

        # plugin-manager is auto-installed via Install-Plugin.ps1 (payload copy only).
        $text | Should -Match 'Install-Plugin\.ps1'
        $text | Should -Match "-Name 'plugin-manager'"
        $text | Should -Match '\$installExitCode\s*=\s*\$LASTEXITCODE'
        $text | Should -Match '\$installExitCode\s+-in\s+@\(20,\s*21\)'

        # Read-only auto-approval is offered (opt-in via -AutoApprove).
        $text | Should -Match 'Set-ScriptApproval'
        $text | Should -Match '\$AutoApprove'
    }

    It 'test:Bootstrap.RemoteLifecycleSupportsWindowsLongPaths enables long paths for clone and checkout' {
        foreach ($relative in @(
                'scripts/skalary/Install-Plugin.ps1'
                'scripts/skalary/Update-Plugin.ps1'
                'scripts/skalary/_Common.ps1'
            )) {
            $content = [System.IO.File]::ReadAllText((Join-Path $root $relative))
            $gitMaterializationCommands = @(
                $content -split '\r?\n' |
                    Where-Object { $_ -match '^\s*git\s+.*\b(?:clone|checkout)\b' }
            )
            $gitMaterializationCommands.Count | Should -BeGreaterThan 0 -Because $relative
            foreach ($command in $gitMaterializationCommands) {
                $command | Should -Match '\s-c\s+core\.longpaths=true(?:\s|$)' -Because $relative
            }
        }
    }
}

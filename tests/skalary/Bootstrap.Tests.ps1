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
}

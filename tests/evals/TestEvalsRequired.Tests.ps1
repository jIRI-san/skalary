#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'required structural eval enforcement' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:runner = Join-Path $script:repoRoot 'scripts/skalary/Test-Evals.ps1'

        function Invoke-RequiredEvalFixture {
            param(
                [Parameter(Mandatory)][string]$TestBody,
                [Parameter(Mandatory)][string[]]$RequiredIds
            )

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('required-evals-' + [guid]::NewGuid().ToString('N'))
            $evalDir = Join-Path $root 'plugins/fixture/evals'
            [void](New-Item -ItemType Directory -Path $evalDir -Force)
            Set-Content -LiteralPath (Join-Path $evalDir 'fixture.Tests.ps1') -Value $TestBody -Encoding utf8NoBOM
            $requiredPath = Join-Path $root 'required.json'
            [System.IO.File]::WriteAllText($requiredPath, (([ordered]@{
                            schema = 'skalary/structural-eval-required@1'
                            caseIds = $RequiredIds
                        } | ConvertTo-Json -Depth 4 -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))
            try {
                $output = & pwsh -NoProfile -File $script:runner -RepoRoot $root `
                    -PluginsRoot (Join-Path $root 'plugins') -RequiredContractPath $requiredPath `
                    -OutputRoot (Join-Path $root 'output') -FullRepository 2>&1
                return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'test:ReviewReport.StructuralEvalEnforcement executes required cases and rejects missing skipped or duplicate outcomes' {
        $passing = @'
Describe 'fixture' {
    It 'eval:Fixture.Required passes' { $true | Should -BeTrue }
}
'@
        $pass = Invoke-RequiredEvalFixture -TestBody $passing -RequiredIds @('eval:Fixture.Required')
        $pass.ExitCode | Should -Be 0 -Because $pass.Output
        $pass.Output | Should -Match 'required: 1/1'

        $missing = Invoke-RequiredEvalFixture -TestBody $passing -RequiredIds @('eval:Fixture.Missing')
        $missing.ExitCode | Should -Be 1
        $missing.Output | Should -Match "required structural eval 'eval:Fixture\.Missing' executed 0 times"

        $skipped = @'
Describe 'fixture' {
    It 'eval:Fixture.Required skips' { Set-ItResult -Skipped -Because 'fixture skip' }
}
'@
        $skip = Invoke-RequiredEvalFixture -TestBody $skipped -RequiredIds @('eval:Fixture.Required')
        $skip.ExitCode | Should -Be 1
        $skip.Output | Should -Match "completed as 'skip'"

        $duplicate = @'
Describe 'fixture' {
    It 'eval:Fixture.Required first' { $true | Should -BeTrue }
    It 'eval:Fixture.Required second' { $true | Should -BeTrue }
}
'@
        $twice = Invoke-RequiredEvalFixture -TestBody $duplicate -RequiredIds @('eval:Fixture.Required')
        $twice.ExitCode | Should -Be 1
        $twice.Output | Should -Match "executed 2 times"
    }
}
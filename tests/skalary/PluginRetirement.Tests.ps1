#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'direct plugin lifecycle retirement' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()
        . (Join-Path $script:repoRoot 'scripts/skalary/_Common.ps1')
    }

    AfterAll {
        foreach ($root in $script:tempRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:PluginLifecycle.MinimalReceipt accepts only the installed identity shape' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("plugin-receipt-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $root -Force)
        git init -q $root
        $script:tempRoots.Add($root)
        $receipt = [pscustomobject][ordered]@{
            name = 'example'
            version = '1.2.3'
            sourceIdentity = New-PluginSourceIdentity -LocalPath $script:repoRoot
            ref = (git -C $script:repoRoot rev-parse HEAD).Trim()
        }

        Write-PluginReceipt -RepoRoot $root -Receipt $receipt | Should -Not -BeNullOrEmpty
        (Read-PluginReceipt -RepoRoot $root -PluginName 'example').PSObject.Properties.Name |
            Should -Be @('name', 'ref', 'sourceIdentity', 'version')

        $receipt | Add-Member -NotePropertyName files -NotePropertyValue @()
        { Write-PluginReceipt -RepoRoot $root -Receipt $receipt } |
            Should -Throw '*exactly name, version, sourceIdentity, and ref*'
    }

    It 'test:PluginLifecycle.Retirement retains published metadata and refuses direct installation' {
        $catalog = Get-Content -LiteralPath (Join-Path $script:repoRoot 'registry-retirements.json') -Raw |
            ConvertFrom-Json -Depth 100
        $record = @($catalog.retiredPlugins | Where-Object { [string]$_.name -eq 'architecture-tests' })
        $record.Count | Should -Be 1
        @($record[0].payloadSets).Count | Should -BeGreaterThan 0

        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("plugin-retirement-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $root -Force)
        git init -q $root
        $script:tempRoots.Add($root)
        $output = @(& pwsh -NoProfile -File (Join-Path $script:repoRoot 'scripts/skalary/Install-Plugin.ps1') `
                -Name 'architecture-tests' -RepoRoot $root -Source $script:repoRoot -Ref HEAD 2>&1)
        ($output -join "`n") | Should -Match 'retired.*Remove-Plugin\.ps1'
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'test:PluginLifecycle.RetiredStateResidue has no retired lifecycle machinery in active sources' {
        $activePaths = @(
            Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'scripts/skalary') -Recurse -File -Include '*.ps1', '*.psm1'
            Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'plugins/plugin-manager') -Recurse -File -Include '*.ps1', '*.psm1'
        )
        $retiredPatterns = @(
            'Invoke-PluginRetirement',
            'ApplyRetirements',
            'PluginRemovalJournal',
            'PluginRetirementState',
            'PluginMutationLock',
            'mutation\.lock',
            'removal-journal',
            'retirement-state'
        )
        foreach ($pattern in $retiredPatterns) {
            $matches = @($activePaths | Select-String -Pattern $pattern)
            $matches | Should -BeNullOrEmpty -Because "$pattern is retired lifecycle machinery"
        }
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'schemas/receipt/receipt.schema.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'schemas/retirement') | Should -BeFalse
    }
}

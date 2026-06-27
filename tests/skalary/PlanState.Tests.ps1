#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'PlanState New-PlanId' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'test:new-planid-format emits 6 crypto-random hex chars' {
        for ($i = 0; $i -lt 25; $i++) {
            $id = New-PlanId -ExistingId @()
            $id | Should -Match '^[0-9a-f]{6}$'
        }
    }

    It 'test:new-planid-format scans the repo inventory when -ExistingId is omitted' {
        $id = New-PlanId -RepoRoot $repoRoot
        $id | Should -Match '^[0-9a-f]{6}$'
        $existing = @(Get-PlanInventory -RepoRoot $repoRoot | ForEach-Object { $_.Id })
        $existing | Should -Not -Contain $id
    }

    It 'test:new-planid-collision regenerates on a full-id collision' {
        $state = [pscustomobject]@{ Calls = 0 }
        $provider = {
            $state.Calls++
            switch ($state.Calls) {
                1 { 'aaaaaa' }
                2 { 'aaaaaa' }
                default { 'bbbbbb' }
            }
        }.GetNewClosure()

        $id = New-PlanId -ExistingId @('aaaaaa') -HexProvider $provider
        $id | Should -Be 'bbbbbb'
        $state.Calls | Should -BeGreaterThan 1
    }

    It 'test:new-planid-collision matches existing ids case-insensitively' {
        $state = [pscustomobject]@{ Calls = 0 }
        $provider = {
            $state.Calls++
            if ($state.Calls -eq 1) { 'ABCDEF' } else { '012345' }
        }.GetNewClosure()

        $id = New-PlanId -ExistingId @('abcdef') -HexProvider $provider
        $id | Should -Be '012345'
    }

    It 'test:new-planid-collision warns when the 4-char prefix is not unique' {
        $provider = { 'aaaa00' }
        $warnings = @()
        $id = New-PlanId -ExistingId @('aaaa99') -HexProvider $provider -WarningVariable warnings -WarningAction SilentlyContinue
        $id | Should -Be 'aaaa00'
        ($warnings -join ' ') | Should -Match 'not uniquely addressable'
    }

    It 'test:new-planid-collision does not warn when the prefix is unique' {
        $provider = { 'abcd00' }
        $warnings = @()
        $id = New-PlanId -ExistingId @('ef0099') -HexProvider $provider -WarningVariable warnings -WarningAction SilentlyContinue
        $id | Should -Be 'abcd00'
        ($warnings -join ' ') | Should -Not -Match 'not uniquely addressable'
    }

    It 'throws when generation cannot find a unique id' {
        { New-PlanId -ExistingId @('aaaaaa') -HexProvider { 'aaaaaa' } -MaxAttempts 5 } | Should -Throw
    }
}

Describe 'PlanState Get-PlanInventory' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $modulePath = Join-Path $repoRoot 'scripts/skalary/PlanState.psm1'
        Import-Module $modulePath -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module PlanState -Force -ErrorAction SilentlyContinue
    }

    It 'parses legacy and new-scheme folders' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("inv-" + [guid]::NewGuid().ToString('N'))
        $plans = Join-Path $root 'docs/implementation-plans'
        $archived = Join-Path $plans 'archived'
        New-Item -ItemType Directory -Path $archived -Force | Out-Null

        $legacy = Join-Path $archived '003-old-thing'
        New-Item -ItemType Directory -Path $legacy -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $legacy 'plan.md') -Value "# legacy`n" -Encoding utf8NoBOM

        $new = Join-Path $plans '2026-06-27-abc123-shiny'
        New-Item -ItemType Directory -Path $new -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $new 'plan.md') -Value "# new`n<!-- plan-id: abc123 -->`n" -Encoding utf8NoBOM

        try {
            $inv = Get-PlanInventory -RepoRoot $root
            ($inv | Where-Object Scheme -eq 'legacy').Id | Should -Be '003'
            ($inv | Where-Object Scheme -eq 'legacy').IsArchived | Should -BeTrue
            $newEntry = $inv | Where-Object Scheme -eq 'new'
            $newEntry.Id | Should -Be 'abc123'
            $newEntry.Slug | Should -Be 'shiny'
            $newEntry.Date | Should -Be '2026-06-27'
            $newEntry.IsArchived | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'prefers the plan-id anchor over the folder-derived id' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("inv-" + [guid]::NewGuid().ToString('N'))
        $plans = Join-Path $root 'docs/implementation-plans'
        $dir = Join-Path $plans '2026-06-27-ffffff-anchored'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'plan.md') -Value "# x`n<!-- plan-id: 9f9f9f -->`n" -Encoding utf8NoBOM
        try {
            $inv = Get-PlanInventory -RepoRoot $root
            $inv.Count | Should -Be 1
            $inv[0].Id | Should -Be '9f9f9f'
            $inv[0].FolderId | Should -Be 'ffffff'
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

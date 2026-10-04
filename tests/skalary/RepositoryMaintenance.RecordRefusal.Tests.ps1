#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Repository maintenance record refusal' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'RepositoryMaintenance.Fixture.ps1')
    }

    It 'test:RCS.RecordRefusal rejects malformed, invalid UTF-8, secret, oversized, and linked records without replacing them' {
        $root = New-RecordRoot
        $target = Join-Path $root 'docs/repository-maintenance.md'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
        $payload = New-PublishPayload
        $json = $payload | ConvertTo-Json -Depth 12 -Compress

        $invalidRecords = [System.Collections.Generic.List[byte[]]]::new()
        $invalidRecords.Add([System.Text.Encoding]::UTF8.GetBytes('# wrong title'))
        $invalidRecords.Add([byte[]]@(0xFF, 0xFE, 0xFD))
        $invalidRecords.Add([System.Text.Encoding]::UTF8.GetBytes("ghp_$('A' * 36)"))
        foreach ($bytes in $invalidRecords) {
            [System.IO.File]::WriteAllBytes($target, $bytes)
            $original = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($target))
            { Invoke-RecordWriter -Root $root -Operation 'Publish' -Json $json } |
                Should -Throw
            [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($target)) |
                Should -BeExactly $original
        }

        [System.IO.File]::Delete($target)
        $large = New-PublishPayload -Survey ('x' * 140000)
        { Invoke-RecordWriter -Root $root -Operation 'Publish' `
                -Json ($large | ConvertTo-Json -Depth 12 -Compress) } | Should -Throw '*limit*'
        Test-Path -LiteralPath $target | Should -BeFalse

        $outside = Join-Path $TestDrive ('rcs-outside-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $outside -Force)
        $linkRoot = Join-Path $TestDrive ('rcs-link-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $linkRoot -Force)
        [void](New-Item -ItemType Junction -Path (Join-Path $linkRoot 'docs') -Target $outside -Force)
        {
            Invoke-RecordWriter -Root $linkRoot -Operation 'Publish' -Json $json
        } | Should -Throw '*link or reparse point*'
        @(Get-ChildItem -LiteralPath $outside -Force) | Should -BeNullOrEmpty
    }
}

#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Set-ScriptApproval' {
    BeforeAll {
        $script:projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:approvalScript = Join-Path $projectRoot 'scripts/skalary/Set-ScriptApproval.ps1'
        $script:tempRoots = [System.Collections.Generic.List[string]]::new()

        function New-ApprovalFixture {
            [CmdletBinding()]
            param([string]$SettingsContent)

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('approval-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            git init -q $root 2>$null | Out-Null
            $script:tempRoots.Add($root)

            # Bundled scripts under .github/ — two read-only, one mutating, one lib.
            $lpScripts = Join-Path $root '.github/skills/lp/scripts'
            $ipScripts = Join-Path $root '.github/skills/ip/scripts'
            New-Item -ItemType Directory -Path $lpScripts -Force | Out-Null
            New-Item -ItemType Directory -Path $ipScripts -Force | Out-Null
            foreach ($f in @('Get-Plugin.ps1', 'Find-Plugin.ps1', '_Common.ps1')) {
                Set-Content -LiteralPath (Join-Path $lpScripts $f) -Value '# stub' -Encoding utf8NoBOM
            }
            Set-Content -LiteralPath (Join-Path $ipScripts 'Install-Plugin.ps1') -Value '# stub' -Encoding utf8NoBOM

            $registry = [ordered]@{
                plugins = @(
                    [ordered]@{
                        name  = 'testplug'
                        version = '1.0.0'
                        files = @(
                            @{ src = 'a'; dest = 'skills/lp/scripts/Get-Plugin.ps1' }
                            @{ src = 'b'; dest = 'skills/lp/scripts/Find-Plugin.ps1' }
                            @{ src = 'c'; dest = 'skills/lp/scripts/_Common.ps1' }
                            @{ src = 'd'; dest = 'skills/ip/scripts/Install-Plugin.ps1' }
                            @{ src = 'e'; dest = 'skills/lp/SKILL.md' }
                        )
                    }
                )
            }
            Set-Content -LiteralPath (Join-Path $root 'registry.json') -Value ($registry | ConvertTo-Json -Depth 10) -Encoding utf8NoBOM

            if ($PSBoundParameters.ContainsKey('SettingsContent')) {
                $vscode = Join-Path $root '.vscode'
                New-Item -ItemType Directory -Path $vscode -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $vscode 'settings.json') -Value $SettingsContent -Encoding utf8NoBOM
            }

            return $root
        }

        function Read-Jsonc {
            [CmdletBinding()]
            param([string]$Path)

            $text = [System.IO.File]::ReadAllText($Path)
            $opts = [System.Text.Json.JsonDocumentOptions]::new()
            $opts.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
            $opts.AllowTrailingCommas = $true
            return [System.Text.Json.JsonDocument]::Parse($text, $opts)
        }

        function Get-ApproveKeys {
            [CmdletBinding()]
            param([string]$Path)

            $doc = Read-Jsonc -Path $Path
            try {
                $obj = $doc.RootElement.GetProperty('chat.tools.terminal.autoApprove')
                return @($obj.EnumerateObject() | ForEach-Object { $_.Name })
            }
            finally { $doc.Dispose() }
        }
    }

    AfterAll {
        foreach ($root in $script:tempRoots) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'test:SetScriptApproval.Confinement approves only read-only scripts, never mutating or lib scripts' {
        $root = New-ApprovalFixture -SettingsContent "{`n  `"chat.tools.terminal.autoApprove`": {`n    `"git add`": true`n  }`n}"
        & $approvalScript -Name 'testplug' -RepoRoot $root *> $null

        $keys = Get-ApproveKeys -Path (Join-Path $root '.vscode/settings.json')
        $keys | Should -Contain '.github/skills/lp/scripts/Get-Plugin.ps1'
        $keys | Should -Contain '.github/skills/lp/scripts/Find-Plugin.ps1'
        $keys | Should -Not -Contain '.github/skills/ip/scripts/Install-Plugin.ps1'
        $keys | Should -Not -Contain '.github/skills/lp/scripts/_Common.ps1'
        $keys | Should -Contain 'git add'  # pre-existing key preserved
    }

    It 'test:SetScriptApproval.MergeRemove is idempotent on add and cleanly removes' {
        $root = New-ApprovalFixture -SettingsContent "{`n  `"chat.tools.terminal.autoApprove`": {`n    `"git add`": true`n  }`n}"
        $settings = Join-Path $root '.vscode/settings.json'

        & $approvalScript -Name 'testplug' -RepoRoot $root *> $null
        $afterAdd = [System.IO.File]::ReadAllText($settings)

        # Re-running add must be a no-op (idempotent).
        & $approvalScript -Name 'testplug' -RepoRoot $root *> $null
        [System.IO.File]::ReadAllText($settings) | Should -Be $afterAdd

        # Remove drops exactly the plugin keys, keeps the pre-existing one.
        & $approvalScript -Name 'testplug' -RepoRoot $root -Remove *> $null
        $keys = Get-ApproveKeys -Path $settings
        $keys | Should -Not -Contain '.github/skills/lp/scripts/Get-Plugin.ps1'
        $keys | Should -Not -Contain '.github/skills/lp/scripts/Find-Plugin.ps1'
        $keys | Should -Contain 'git add'
    }

    It 'test:SetScriptApproval.Jsonc preserves comments and trailing commas' {
        $jsonc = @'
{
  // top-level comment
  "chat.tools.terminal.autoApprove": {
    "git add": true,
    /* block comment */
    "dotnet build": true,
  },
  "editor.tabSize": 2
}
'@
        $root = New-ApprovalFixture -SettingsContent $jsonc
        $settings = Join-Path $root '.vscode/settings.json'

        & $approvalScript -Name 'testplug' -RepoRoot $root *> $null
        $text = [System.IO.File]::ReadAllText($settings)

        $text | Should -Match '// top-level comment'
        $text | Should -Match '/\* block comment \*/'
        $text | Should -Match '"editor\.tabSize": 2'

        # Still valid JSONC and carries the new + old keys.
        $keys = Get-ApproveKeys -Path $settings
        $keys | Should -Contain '.github/skills/lp/scripts/Get-Plugin.ps1'
        $keys | Should -Contain 'git add'
        $keys | Should -Contain 'dotnet build'
    }

    It 'test:SetScriptApproval.Jsonc survives braces inside comments' {
        $jsonc = @'
{
  // a brace in a comment: { should not break the scan }
  "chat.tools.terminal.autoApprove": {
    /* another } brace { here */
    "git add": true
  },
  "editor.tabSize": 2
}
'@
        $root = New-ApprovalFixture -SettingsContent $jsonc
        $settings = Join-Path $root '.vscode/settings.json'

        & $approvalScript -Name 'testplug' -RepoRoot $root *> $null
        $keys = Get-ApproveKeys -Path $settings
        $keys | Should -Contain '.github/skills/lp/scripts/Get-Plugin.ps1'
        $keys | Should -Contain 'git add'
        ([System.IO.File]::ReadAllText($settings)) | Should -Match '"editor\.tabSize": 2'
    }

    It 'test:SetScriptApproval.MergeRemove -Remove is a no-op when there is no autoApprove block' {
        $root = New-ApprovalFixture -SettingsContent "{`n  `"editor.tabSize`": 2`n}"
        $settings = Join-Path $root '.vscode/settings.json'
        $before = [System.IO.File]::ReadAllText($settings)

        & $approvalScript -Name 'testplug' -RepoRoot $root -Remove *> $null
        [System.IO.File]::ReadAllText($settings) | Should -Be $before
    }
}


#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'Named', Mandatory)]
    [string]$Name,

    [Parameter(ParameterSetName = 'All', Mandatory)]
    [switch]$All,

    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [string]$RegistryPath,

    [string]$SettingsPath,

    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Common.ps1')

# Read-only script verbs whose scripts are safe to auto-approve. Anything that
# fetches remote payloads or mutates the repo (Install/Uninstall/Update/Remove/
# Set/New/Add/Build/Sync/Repair/bootstrap ...) is deliberately excluded so a
# prompt-injected argument cannot ride an approval into a silent install.
$script:ReadOnlyVerbs = @('Get', 'Find', 'Test', 'Validate')
# Never auto-approve a script whose name suggests it emits secrets, even if its
# verb is read-only (e.g. `get-credential.ps1`) — auto-running it unprompted could
# surface a token into the session.
$script:SensitiveNameFragments = @('credential', 'secret', 'token', 'password', 'passphrase')
$script:SettingKey = 'chat.tools.terminal.autoApprove'

function Test-ReadOnlyScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )

    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    foreach ($fragment in $script:SensitiveNameFragments) {
        if ($base -match [regex]::Escape($fragment)) {
            return $false
        }
    }
    $dashIndex = $base.IndexOf('-')
    if ($dashIndex -lt 1) {
        return $false
    }
    $verb = $base.Substring(0, $dashIndex)
    return $script:ReadOnlyVerbs -contains $verb
}

function Get-PluginApprovalKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Plugin,

        [Parameter(Mandatory)]
        [string]$RepoRootPath
    )

    $keys = @()
    foreach ($file in @($Plugin.files)) {
        $dest = ([string]$file.dest) -replace '\\', '/'
        if (-not $dest.EndsWith('.ps1')) {
            continue
        }
        if ($dest -notmatch '^skills/[^/]+/scripts/') {
            continue
        }
        if (-not (Test-ReadOnlyScript -FileName (Split-Path -Leaf $dest))) {
            continue
        }

        # Confine to .github/ and only approve scripts that are actually present.
        $fullPath = Resolve-GithubConstrainedPath -RepoRoot $RepoRootPath -RelativePath $dest
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            continue
        }

        $keys += ".github/$dest"
    }

    return @($keys | Sort-Object -Unique)
}

function Get-TargetPlugin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Registry,

        [switch]$AllPlugins,

        [string]$PluginName
    )

    $plugins = @($Registry.plugins)
    if ($AllPlugins) {
        return @($plugins | Sort-Object name)
    }

    $match = @($plugins | Where-Object { [string]$_.name -eq $PluginName })
    if ($match.Count -eq 0) {
        throw "Plugin '$PluginName' not found in registry."
    }
    return , $match[0]
}

function Get-SettingsNewline {
    [CmdletBinding()]
    param([string]$Text)

    if ($Text -match "`r`n") {
        return "`r`n"
    }
    return "`n"
}

function Find-AutoApproveInnerSpan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $keyMatch = [regex]::Match($Text, '"chat\.tools\.terminal\.autoApprove"\s*:\s*\{')
    if (-not $keyMatch.Success) {
        return $null
    }

    $openBrace = $Text.IndexOf('{', $keyMatch.Index + $keyMatch.Length - 1)
    $depth = 0
    $inString = $false
    $escaped = $false
    for ($i = $openBrace; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inString) {
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $inString = $false }
            continue
        }
        # Skip JSONC comments so braces inside them never miscount depth.
        if ($ch -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            $nl = $Text.IndexOf("`n", $i)
            if ($nl -lt 0) { break }
            $i = $nl
            continue
        }
        if ($ch -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '*') {
            $end = $Text.IndexOf('*/', $i + 2)
            if ($end -lt 0) { throw 'Malformed .vscode/settings.json: unterminated block comment.' }
            $i = $end + 1
            continue
        }
        if ($ch -eq '"') { $inString = $true; continue }
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return [pscustomobject]@{ InnerStart = $openBrace + 1; InnerEnd = $i }
            }
        }
    }

    throw 'Malformed .vscode/settings.json: unbalanced braces in chat.tools.terminal.autoApprove.'
}

function Get-InnerKeys {
    [CmdletBinding()]
    param([string]$Inner)

    $keys = @()
    foreach ($m in [regex]::Matches($Inner, '(?m)^\s*"(?<key>(?:[^"\\]|\\.)*)"\s*:\s*(?:true|false)')) {
        $keys += $m.Groups['key'].Value
    }
    return @($keys)
}

function Set-ApprovalKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string[]]$Add = @(),
        [string[]]$RemoveKeys = @()
    )

    $newline = Get-SettingsNewline -Text $Text
    $span = Find-AutoApproveInnerSpan -Text $Text

    if ($null -eq $span) {
        # Nothing to remove when there is no block; never fabricate an empty one.
        if ($Add.Count -eq 0) {
            return $Text
        }
        # No autoApprove block yet: create one at the top of the root object.
        $rootBrace = $Text.IndexOf('{')
        if ($rootBrace -lt 0) {
            $Text = "{$newline}"
            $rootBrace = 0
        }
        $entries = ($Add | Sort-Object -Unique | ForEach-Object { "    `"$_`": true," }) -join $newline
        $block = "$newline  `"$($script:SettingKey)`": {$newline$entries$newline  },"
        return $Text.Insert($rootBrace + 1, $block)
    }

    $inner = $Text.Substring($span.InnerStart, $span.InnerEnd - $span.InnerStart)
    $existing = Get-InnerKeys -Inner $inner

    # Rebuild inner line-by-line: drop removed keys, keep comments, drop blank
    # lines (so re-runs stay byte-idempotent).
    $lines = $inner -split "`n"
    $kept = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $keyMatch = [regex]::Match($line, '^\s*"(?<key>(?:[^"\\]|\\.)*)"\s*:\s*(?:true|false)')
        if ($keyMatch.Success -and $RemoveKeys -contains $keyMatch.Groups['key'].Value) {
            continue
        }
        $kept.Add($line) | Out-Null
    }

    # Normalize commas on entry lines so a trailing comma (JSONC-valid) is always safe.
    for ($i = 0; $i -lt $kept.Count; $i++) {
        $entryMatch = [regex]::Match($kept[$i], '^(?<body>\s*"(?:[^"\\]|\\.)*"\s*:\s*(?:true|false))\s*,?\s*$')
        if ($entryMatch.Success) {
            $kept[$i] = "$($entryMatch.Groups['body'].Value),"
        }
    }

    $indent = '    '
    $additions = @($Add | Sort-Object -Unique | Where-Object { $existing -notcontains $_ })
    foreach ($key in $additions) {
        $kept.Add("$indent`"$key`": true,") | Out-Null
    }

    # Reassemble, trimming leading/trailing blank lines inside the block.
    $body = ($kept -join "`n").Trim("`r", "`n")
    if ([string]::IsNullOrWhiteSpace($body)) {
        $rebuilt = ''
    }
    else {
        $rebuilt = "`n$body`n  "
    }
    if ($newline -eq "`r`n") {
        $rebuilt = $rebuilt -replace "`r?`n", "`r`n"
    }

    return $Text.Substring(0, $span.InnerStart) + $rebuilt + $Text.Substring($span.InnerEnd)
}

# --- Main ------------------------------------------------------------------

$repoRootPath = Resolve-RepoRoot -StartPath $RepoRoot
$registryFile = Resolve-RegistryPath -RepoRoot $repoRootPath -RegistryPath $RegistryPath
$registry = Read-JsonFile -Path $registryFile

$settingsFile = if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) {
    [System.IO.Path]::GetFullPath($SettingsPath)
}
else {
    Join-Path $repoRootPath '.vscode/settings.json'
}

$targetPlugins = Get-TargetPlugin -Registry $registry -AllPlugins:$All -PluginName $Name

$approvalKeys = @()
foreach ($plugin in $targetPlugins) {
    $approvalKeys += Get-PluginApprovalKey -Plugin $plugin -RepoRootPath $repoRootPath
}
$approvalKeys = @($approvalKeys | Sort-Object -Unique)

if ($approvalKeys.Count -eq 0) {
    Write-Host 'No read-only plugin scripts to approve (nothing changed).'
    return
}

if (Test-Path -LiteralPath $settingsFile -PathType Leaf) {
    $settingsText = [System.IO.File]::ReadAllText($settingsFile)
}
else {
    $settingsText = "{`n}"
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $settingsFile) -Force)
}

$before = if ($null -ne (Find-AutoApproveInnerSpan -Text $settingsText)) {
    $span = Find-AutoApproveInnerSpan -Text $settingsText
    Get-InnerKeys -Inner $settingsText.Substring($span.InnerStart, $span.InnerEnd - $span.InnerStart)
}
else {
    @()
}

if ($Remove) {
    $updated = Set-ApprovalKeys -Text $settingsText -RemoveKeys $approvalKeys
    $changed = @($approvalKeys | Where-Object { $before -contains $_ })
    $verb = 'Removed'
}
else {
    $updated = Set-ApprovalKeys -Text $settingsText -Add $approvalKeys
    $changed = @($approvalKeys | Where-Object { $before -notcontains $_ })
    $verb = 'Added'
}

if ($updated -eq $settingsText) {
    Write-Host "No changes to '$settingsFile' (already up to date)."
    return
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($settingsFile, $updated, $utf8NoBom)

Write-Host "Updated '$settingsFile'."
if ($changed.Count -gt 0) {
    Write-Host "$verb $($changed.Count) auto-approve key(s):"
    foreach ($key in ($changed | Sort-Object)) {
        Write-Host "  $key"
    }
}
else {
    Write-Host 'No key changes (settings already reflected the request).'
}

#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Get-Location).Path,

    [string]$Repository = 'jIRI-san/skalary',

    [string]$Ref = 'main',

    [switch]$AutoApprove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-TargetRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StartPath
    )

    $resolvedStart = [System.IO.Path]::GetFullPath($StartPath)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $root = git -C $resolvedStart rev-parse --show-toplevel 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previous

    if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($root)) {
        return [System.IO.Path]::GetFullPath($root.Trim())
    }

    return $resolvedStart
}

function New-RawContentUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repo,

        [Parameter(Mandatory)]
        [string]$PinnedRef,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $repoPath = $Repo.Trim()
    if ([string]::IsNullOrWhiteSpace($repoPath)) {
        throw 'Repository cannot be empty.'
    }

    if ($repoPath -notmatch '^[^/\s]+/[^/\s]+$') {
        throw "Repository '$Repo' must be in '<owner>/<repo>' format."
    }

    if ([string]::IsNullOrWhiteSpace($PinnedRef)) {
        throw 'Ref cannot be empty.'
    }

    return "https://raw.githubusercontent.com/$repoPath/$PinnedRef/$RelativePath"
}

function Get-RemoteContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    try {
        $response = Invoke-WebRequest -Uri $Url
    }
    catch {
        throw "Failed to fetch '$Url': $($_.Exception.Message)"
    }

    if ([string]::IsNullOrEmpty($response.Content)) {
        throw "Downloaded empty content from '$Url'."
    }

    return [string]$response.Content
}

$scriptFiles = @(
    '_Common.ps1',
    'Build-Registry.ps1',
    'Find-Plugin.ps1',
    'Get-Plugin.ps1',
    'Install-Plugin.ps1',
    'Remove-Plugin.ps1',
    'Set-ScriptApproval.ps1',
    'Sync-Dogfood.ps1',
    'Test-Registry.ps1',
    'Update-Plugin.ps1'
)

$targetRoot = Resolve-TargetRoot -StartPath $RepoRoot
$scriptsRoot = Join-Path $targetRoot 'scripts/skalary'
$skalaryStateRoot = Join-Path $targetRoot '.github/.skalary'

[void](New-Item -ItemType Directory -Path $scriptsRoot -Force)
[void](New-Item -ItemType Directory -Path $skalaryStateRoot -Force)

foreach ($scriptFile in $scriptFiles) {
    $relativeSourcePath = "scripts/skalary/$scriptFile"
    $url = New-RawContentUrl -Repo $Repository -PinnedRef $Ref -RelativePath $relativeSourcePath
    $content = Get-RemoteContent -Url $url
    $targetPath = Join-Path $scriptsRoot $scriptFile
    Set-Content -LiteralPath $targetPath -Value $content -Encoding utf8
}

$registryRelativePath = 'registry.json'
$registryUrl = New-RawContentUrl -Repo $Repository -PinnedRef $Ref -RelativePath $registryRelativePath
$registryContent = Get-RemoteContent -Url $registryUrl
Set-Content -LiteralPath (Join-Path $scriptsRoot 'registry.json') -Value $registryContent -Encoding utf8

Write-Host "Bootstrapped skalary scripts to '$scriptsRoot' from '$Repository' at ref '$Ref'."
Write-Host "Created skalary state directory '$skalaryStateRoot'."

# Install the plugin-manager plugin so its install/uninstall/list/update skills
# are available immediately. Install clones the pinned source and copies payload
# files into .github/; it does not execute plugin code.
$installScript = Join-Path $scriptsRoot 'Install-Plugin.ps1'
Write-Host ''
Write-Host "Installing the 'plugin-manager' plugin from '$Repository' at ref '$Ref' (payload copy only, no code execution)..."
& $installScript -Name 'plugin-manager' -RepoRoot $targetRoot -Repository $Repository -Ref $Ref
$installExitCode = $LASTEXITCODE
if ($installExitCode -in @(20, 21)) {
    exit $installExitCode
}
if ($installExitCode -ne 0) {
    throw "Plugin-manager installation failed with exit code $installExitCode."
}

# Offer to auto-approve plugin-manager's read-only scripts. Bootstrap is
# non-interactive, so this is opt-in via -AutoApprove; otherwise print the command.
$approvalScript = Join-Path $scriptsRoot 'Set-ScriptApproval.ps1'
if ($AutoApprove) {
    Write-Host ''
    Write-Host "Auto-approving plugin-manager's read-only scripts in .vscode/settings.json..."
    & $approvalScript -Name 'plugin-manager' -RepoRoot $targetRoot
}
else {
    Write-Host ''
    Write-Host 'Optional: auto-approve plugin-manager read-only scripts (list/find/get) so they run without a prompt:'
    Write-Host '  scripts/skalary/Set-ScriptApproval.ps1 -Name plugin-manager -RepoRoot .'
}

Write-Host ''
Write-Host 'Done. Use the plugin-manager skills to manage plugins:'
Write-Host '  /list-plugins             browse available + installed plugins'
Write-Host '  /install-plugin <name>    install a plugin'
Write-Host '  /update-plugin <name>     update a plugin'
Write-Host '  /uninstall-plugin <name>  remove a plugin'

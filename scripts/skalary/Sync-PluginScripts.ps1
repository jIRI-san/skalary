#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Common.ps1')

$repoRootPath = Resolve-RepoRoot -StartPath $RepoRoot
$scriptsSource = $PSScriptRoot
$pluginsRoot = Join-Path $repoRootPath 'plugins'

if (-not (Test-Path -LiteralPath $pluginsRoot -PathType Container)) {
    throw "Plugins directory not found: $pluginsRoot"
}

# Installed-path references to bundled workflow scripts/modules, e.g.
# `.github/skills/ci/scripts/Test-Plan.ps1`. The <skill> segment selects the
# per-plugin bundle destination; the <name> is resolved against scripts/skalary/.
$refRegex = [regex]'\.github/skills/(?<skill>[a-z0-9][a-z0-9-]*)/scripts/(?<name>[A-Za-z0-9][A-Za-z0-9._-]*\.psm?1)'
# PowerShell module imports of the form `Join-Path $PSScriptRoot 'PlanState.psm1'`.
$moduleRegex = [regex]'\$PSScriptRoot\s+''(?<mod>[A-Za-z0-9][A-Za-z0-9._-]*\.psm1)'''
$scannableExtensions = @('.md', '.ps1', '.psm1', '.txt')

function Get-ModuleClosure {
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter(Mandatory)][string]$SourceDir
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $modules = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $work = [System.Collections.Generic.Queue[string]]::new()
    $work.Enqueue($ScriptName)

    while ($work.Count -gt 0) {
        $current = $work.Dequeue()
        if (-not $seen.Add($current)) { continue }

        $currentPath = Join-Path $SourceDir $current
        if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) {
            throw "Bundled script source not found: $currentPath"
        }

        $content = [System.IO.File]::ReadAllText($currentPath)
        foreach ($match in $moduleRegex.Matches($content)) {
            $mod = $match.Groups['mod'].Value
            [void]$modules.Add($mod)
            $work.Enqueue($mod)
        }
    }

    return , @($modules)
}

function Update-PluginPatchVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath
    )

    # Targeted single-line rewrite so the rest of the manifest formatting is untouched.
    $raw = [System.IO.File]::ReadAllText($ManifestPath)
    $match = [regex]::Match($raw, '"version"\s*:\s*"(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)"')
    if (-not $match.Success) {
        throw "Cannot bump version for '$ManifestPath': no semver version field found."
    }

    $patchGroup = $match.Groups['patch']
    $newPatch = [int]$patchGroup.Value + 1
    $updated = $raw.Remove($patchGroup.Index, $patchGroup.Length).Insert($patchGroup.Index, [string]$newPatch)

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($ManifestPath, $updated, $utf8NoBom)
    return $true
}

$manifestPaths = @(Get-ChildItem -LiteralPath $pluginsRoot -Recurse -File -Filter 'plugin.json' | Sort-Object FullName)
if ($manifestPaths.Count -eq 0) {
    throw "No plugin manifests found under '$pluginsRoot'."
}

$expected = @{}        # managedDirKey -> @{ Dir; Files = @{ name -> sourcePath } }
foreach ($manifestPath in $manifestPaths) {
    $manifest = Read-JsonFile -Path $manifestPath.FullName
    $pluginName = [string]$manifest.name
    $pluginRoot = Split-Path -Parent $manifestPath.FullName

    foreach ($file in @($manifest.files)) {
        $src = [string]$file.src
        $ext = [System.IO.Path]::GetExtension($src).ToLowerInvariant()
        if ($scannableExtensions -notcontains $ext) { continue }

        $sourcePath = Resolve-PluginConstrainedPath -PluginRoot $pluginRoot -RelativePath $src
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }

        $content = [System.IO.File]::ReadAllText($sourcePath)
        foreach ($match in $refRegex.Matches($content)) {
            $skill = $match.Groups['skill'].Value
            $name = $match.Groups['name'].Value

            # Only scripts whose canonical source lives in scripts/skalary are managed
            # here. Plugin-local scripts (e.g. the autopilot launchers) are authored and
            # registered directly by their owning plugin, so skip references to them
            # instead of failing — the bundler is the sole writer of scripts/skalary copies.
            if (-not (Test-Path -LiteralPath (Join-Path $scriptsSource $name) -PathType Leaf)) {
                continue
            }

            $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            [void]$names.Add($name)
            if ($name.EndsWith('.ps1')) {
                foreach ($mod in (Get-ModuleClosure -ScriptName $name -SourceDir $scriptsSource)) {
                    [void]$names.Add($mod)
                }
            }

            $managedDir = Join-Path $pluginRoot (Join-Path 'skills' (Join-Path $skill 'scripts'))
            $dirKey = ([System.IO.Path]::GetFullPath($managedDir)).ToLowerInvariant()
            if (-not $expected.ContainsKey($dirKey)) {
                $expected[$dirKey] = [pscustomobject]@{
                    PluginName = $pluginName
                    PluginRoot = $pluginRoot
                    ManifestPath = $manifestPath.FullName
                    Skill = $skill
                    Dir = $managedDir
                    Files = @{}
                }
            }
            foreach ($n in $names) {
                $sourceScript = Join-Path $scriptsSource $n
                if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
                    throw "Plugin '$pluginName' references '$n' but scripts/skalary/$n does not exist."
                }
                $expected[$dirKey].Files[$n] = $sourceScript
            }
        }
    }
}

$changedCount = 0
$staleCount = 0
$changedManifests = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($entry in ($expected.Values | Sort-Object Dir)) {
    if (-not (Test-Path -LiteralPath $entry.Dir -PathType Container) -and -not $WhatIfPreference) {
        [void](New-Item -ItemType Directory -Path $entry.Dir -Force)
    }

    foreach ($name in ($entry.Files.Keys | Sort-Object)) {
        $sourcePath = $entry.Files[$name]
        $targetPath = Join-Path $entry.Dir $name

        $sourceHash = Get-FileSha256 -Path $sourcePath
        $targetHash = if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            Get-FileSha256 -Path $targetPath
        }
        else {
            $null
        }

        if ($sourceHash -eq $targetHash) { continue }

        $changedCount++
        [void]$changedManifests.Add($entry.ManifestPath)
        if ($PSCmdlet.ShouldProcess($targetPath, "Bundle from '$sourcePath' for plugin '$($entry.PluginName)'")) {
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        }
    }

    if (Test-Path -LiteralPath $entry.Dir -PathType Container) {
        $existing = Get-ChildItem -LiteralPath $entry.Dir -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') }
        foreach ($existingFile in $existing) {
            if (-not $entry.Files.ContainsKey($existingFile.Name)) {
                $staleCount++
                [void]$changedManifests.Add($entry.ManifestPath)
                if ($PSCmdlet.ShouldProcess($existingFile.FullName, "Remove stale bundled script for plugin '$($entry.PluginName)'")) {
                    Remove-Item -LiteralPath $existingFile.FullName -Force
                }
            }
        }
    }
}

if ($WhatIfPreference -and ($changedCount + $staleCount) -gt 0) {
    throw "Plugin-script bundle drift detected: $changedCount file(s) differ from scripts/skalary sources, $staleCount stale file(s). Run scripts/skalary/Sync-PluginScripts.ps1 and rebuild the registry."
}

# A bundled copy is part of each plugin's installable payload, so a content change
# is a payload change: bump the patch version of every plugin whose bundle changed,
# keeping the advertised version honest against registry.json hashes. Skipped under
# -WhatIf (the drift gate above already fails CI on stale bundles).
$bumpedCount = 0
if (-not $WhatIfPreference) {
    foreach ($manifestPath in ($changedManifests | Sort-Object)) {
        if (Update-PluginPatchVersion -ManifestPath $manifestPath) {
            $bumpedCount++
        }
    }
}

Write-Host "Plugin-script bundle sync completed. Changed: $changedCount. Removed stale: $staleCount. Version-bumped plugins: $bumpedCount."

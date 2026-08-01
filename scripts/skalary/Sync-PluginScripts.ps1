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
# PowerShell module/script imports of the form `Join-Path $PSScriptRoot 'PlanState.psm1'`
# or `. (Join-Path $PSScriptRoot '_Common.ps1')`. `.psm?1` covers both `.psm1` modules
# and `.ps1` dot-source siblings; the leading `_` allows `_Common.ps1`.
$moduleRegex = [regex]'\$PSScriptRoot\s+''(?<mod>[A-Za-z0-9_][A-Za-z0-9._-]*\.psm?1)'''
$scannableExtensions = @('.md', '.ps1', '.psm1', '.txt')

# --- Asset reference grammar (REQ-19) -------------------------------------------------
# A payload that reads a file installation never materializes fails silently in a consumer
# repo: the agent reads nothing and degrades instead of erroring. The grammar below is
# deliberately *closed* — only these two forms are recognized, and anything else (a
# dynamically composed path, a bare `assets/x.md` that could equally mean a plan folder)
# is out of grammar and must not appear in a payload as a runtime read.
#
#   1. Installed-path literal — `.github/skills/<skill>/assets/<file>`, i.e. the path the
#      payload would open in an installed repo. Required dest: the same path minus `.github/`.
#   2. Skill-relative — `./assets/<file>`, resolved against the *skill root* of the payload
#      that contains it (not the containing directory), so a guide under `assets/` and its
#      `SKILL.md` spell the same asset identically. The leading `./` is what separates a
#      skill's own asset from a plan folder's `assets/` (`assets/intent.md`), which is not a
#      payload file at all.
$assetInstalledRegex = [regex]'\.github/(?<dest>(?:skills|agents|prompts)/[A-Za-z0-9][A-Za-z0-9._/-]*\.[A-Za-z0-9]+)'
$assetRelativeRegex = [regex]'\./assets/(?<rest>[A-Za-z0-9][A-Za-z0-9._/-]*\.[A-Za-z0-9]+)'

function Remove-FencedBlocks {
    <#
    .SYNOPSIS
    Blanks out fenced code blocks so illustrative examples never count as runtime reads.
    .DESCRIPTION
    Line-oriented rather than regex-oriented: a single multiline regex would swallow the rest
    of the file at an unbalanced fence. Returns the stripped text plus an `Unterminated` flag —
    a fence the author never closed blanks every following line, so it can hide a real
    reference from the gate; the caller fails on it rather than scanning a truncated file.
    Blank replacement lines keep line numbers usable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $lines = $Content -split "`r?`n"
    $inFence = $false
    $fenceMarker = $null
    $result = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        $fence = [regex]::Match($line, '^\s*(?<marker>`{3,}|~{3,})')
        if ($fence.Success) {
            $marker = $fence.Groups['marker'].Value
            if (-not $inFence) {
                $inFence = $true
                $fenceMarker = $marker[0]
            }
            elseif ($marker[0] -eq $fenceMarker) {
                $inFence = $false
                $fenceMarker = $null
            }
            $result.Add('')
            continue
        }

        $result.Add($(if ($inFence) { '' } else { $line }))
    }

    return [pscustomobject]@{
        Text         = ($result -join "`n")
        Unterminated = $inFence
    }
}


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

# Every installed destination across *every* plugin: a payload may legitimately reference an
# asset another plugin owns (the autopilot agent reads the cr/dr concern map), so declaration
# is checked repo-wide rather than per-plugin.
$declaredDests = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($manifestPath in $manifestPaths) {
    $manifest = Read-JsonFile -Path $manifestPath.FullName
    foreach ($file in @($manifest.files)) {
        [void]$declaredDests.Add(([string]$file.dest).Replace('\', '/'))
    }
}

$assetViolations = [System.Collections.Generic.List[string]]::new()

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

        $dest = ([string]$file.dest).Replace('\', '/')
        $stripped = Remove-FencedBlocks -Content $content
        $prose = $stripped.Text

        if ($stripped.Unterminated) {
            $assetViolations.Add("plugin '$pluginName': '$dest' has an unterminated code fence. Everything after it is treated as an example, so a runtime asset reference there would slip past this gate — close the fence.")
        }

        foreach ($match in $assetInstalledRegex.Matches($prose)) {
            $referenced = $match.Groups['dest'].Value
            # Bundled scripts whose canonical source is scripts/skalary are materialized by the
            # script-bundler arm below on this same run, so the asset arm would fail a reference
            # the sync is in the middle of satisfying. The condition mirrors the bundler's own:
            # a plugin-local script (no scripts/skalary source) is nobody else's job and stays
            # subject to the files[] check.
            $scriptMatch = [regex]::Match($referenced, '^skills/[^/]+/scripts/(?<name>[^/]+\.psm?1)$')
            if ($scriptMatch.Success -and (Test-Path -LiteralPath (Join-Path $scriptsSource $scriptMatch.Groups['name'].Value) -PathType Leaf)) {
                continue
            }
            if ($declaredDests.Contains($referenced)) { continue }
            $assetViolations.Add("plugin '$pluginName': '$dest' reads '.github/$referenced', which no plugin declares in files[]. Declare it (dest '$referenced') so installation materializes it.")
        }

        $skillMatch = [regex]::Match($dest, '^skills/(?<skill>[^/]+)/')
        foreach ($match in $assetRelativeRegex.Matches($prose)) {
            $rest = $match.Groups['rest'].Value
            if (-not $skillMatch.Success) {
                $assetViolations.Add("plugin '$pluginName': '$dest' uses the skill-relative form './assets/$rest' but is not installed under skills/<skill>/, so the reference has no skill root to resolve against. Use the installed-path literal instead.")
                continue
            }

            $referenced = "skills/$($skillMatch.Groups['skill'].Value)/assets/$rest"
            if ($declaredDests.Contains($referenced)) { continue }
            $assetViolations.Add("plugin '$pluginName': '$dest' reads './assets/$rest', which resolves to '$referenced' and is not declared in files[]. Declare it so installation materializes it.")
        }

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

# An undeclared asset reference is not drift the sync can repair — only the plugin author
# knows whether the file should ship or the reference should go — so it fails in both the
# -WhatIf gate and a real run rather than being silently bundled.
if ($assetViolations.Count -gt 0) {
    $detail = ($assetViolations | Sort-Object) -join "`n  "
    throw "Undeclared runtime asset reference(s) — installation would not materialize these files:`n  $detail"
}

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

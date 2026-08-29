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
$reviewSchemaSource = Join-Path $repoRootPath 'schemas/review'
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
$schemaRegex = [regex]'\$PSScriptRoot\s+''(?<schema>schemas/review/[A-Za-z0-9][A-Za-z0-9._-]*\.schema\.json)'''
$scannableExtensions = @('.md', '.ps1', '.psm1', '.txt')

# --- Asset reference grammar (REQ-19) -------------------------------------------------
# A payload that reads a file installation never materializes fails silently in a consumer
# repo: the agent reads nothing and degrades instead of erroring. The grammar below is
# deliberately *closed*. Supported roots must use literal paths so the scanner can prove
# where each runtime read resolves; dynamic composition of one of these roots fails closed.
#
#   1. Installed-path literal — `.github/` plus one of the three payload roots (`skills/`,
#      `agents/`, `prompts/`), i.e. the path the payload would open in an installed repo.
#      Required dest: the same path minus `.github/`.
#   2. Skill-relative — `./assets/<file>`, resolved against the *skill root* of the payload
#      that contains it (not the containing directory), so a guide under `assets/` and its
#      `SKILL.md` spell the same asset identically. The leading `./` is what separates a
#      skill's own asset from a plan folder's `assets/` (`assets/intent.md`), which is not a
#      payload file at all.
$assetInstalledRegex = [regex]'\.github/(?<dest>(?:skills|agents|prompts)/[A-Za-z0-9][A-Za-z0-9._/-]*\.[A-Za-z0-9]+)'
$assetRelativeRegex = [regex]'\./assets/(?<rest>[A-Za-z0-9][A-Za-z0-9._/-]*\.[A-Za-z0-9]+)'
#   3. Scaffold path — a repo-relative runtime path *outside* `.github/`. The installer is
#      hard-confined to `.github/` (ARCH-Install-Confinement) and there is no post-install
#      hook, so these are materialized on first use by their owning skill or script and are
#      declared in `scaffolds[]` instead of `files[]`. Every docs/, schemas/, and tools/
#      reference is checked; deriving the roots from existing declarations would make a wholly
#      undeclared runtime tree invisible.
$assetScaffoldRegex = [regex]'(?<![A-Za-z0-9._/-])(?<path>(?:docs|schemas|tools)/[A-Za-z0-9<][A-Za-z0-9._/<>-]*)'
#   4. Source-tree path — authoring paths under plugins/ and canonical scripts/skalary/ never
#      exist in a foreign consumer. Payloads must use their installed .github/ destination.
$assetSourceRegex = [regex]'(?<![A-Za-z0-9._/-])(?<path>\./(?:plugins|scripts/skalary)/[A-Za-z0-9_][A-Za-z0-9._/-]*\.[A-Za-z0-9]+)'
# A variable tail prevents the literal inventory from proving closure. This deliberately
# targets the supported roots in the grammar rather than every Join-Path call in executable
# scripts, where dynamic consumer-selected output paths are valid.
$assetDynamicRegex = [regex]'(?i)\bJoin-Path\s+(?:-Path(?:\s*:\s*|\s+))?[''"](?<root>\./assets|\.github/(?:skills|agents|prompts)(?:/[A-Za-z0-9._/-]*)?|(?:docs|schemas|tools)(?:/[A-Za-z0-9._/-]*)?)[''"]\s+(?:-ChildPath(?:\s*:\s*|\s+))?(?<tail>\$[A-Za-z_][A-Za-z0-9_]*|[''"][^''"\r\n]*\$[A-Za-z_][^''"\r\n]*[''"])'
$assetLiteralJoinRegex = [regex]'(?i)\bJoin-Path\s+(?:-Path(?:\s*:\s*|\s+))?(?<q>[''"])(?<root>\./assets|\.github/(?:skills|agents|prompts)(?:/[A-Za-z0-9._/-]*)?|(?:docs|schemas|tools)(?:/[A-Za-z0-9._/-]*)?|\./(?:plugins|scripts/skalary)(?:/[A-Za-z0-9._/-]*)?)\k<q>\s+(?:-ChildPath(?:\s*:\s*|\s+))?(?<cq>[''"])(?<child>[^''"\r\n$]+)\k<cq>'
$repoOwnedOptionalInputs = @{
    'code-review' = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('docs/review-standards.md'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    'design-review' = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('docs/review-standards.md'),
        [System.StringComparer]::OrdinalIgnoreCase
    )
}

function Test-RepoOwnedOptionalInput {
    param(
        [Parameter(Mandatory)][string]$PluginName,
        [Parameter(Mandatory)][string]$Path
    )

    return $repoOwnedOptionalInputs.ContainsKey($PluginName) -and
    $repoOwnedOptionalInputs[$PluginName].Contains($Path.Trim('/'))
}

function Get-ScaffoldRoot {
    <#
    .SYNOPSIS
    First two segments of a repo-relative path, e.g. `docs/review-ledger`. $null when shorter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $segments = $Path.Trim('/') -split '/'
    if ($segments.Count -lt 2) { return $null }
    return "$($segments[0])/$($segments[1])"
}

function Test-ScaffoldMatch {
    <#
    .SYNOPSIS
    Tests a referenced path against one declared scaffold entry.
    .DESCRIPTION
    A literal entry matches on equality. A parameterized entry's template is compiled to a
    regex: `<name>` matches one segment, `**` matches any subtree. When the entry declares a
    closed value domain, a *concrete* segment must be a member of it — a reference that is
    itself the placeholder (`docs/review-ledger/<category>.md`) is the template being quoted,
    not a value, so it is accepted without a domain check.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Scaffold
    )

    $template = ([string]$Scaffold.path).Trim('/')
    $candidate = $Path.Trim('/')

    if ([string]$Scaffold.mode -eq 'literal') {
        return $candidate -eq $template
    }

    # A trailing `/**` names the subtree *and* the folder itself: a payload that mentions the
    # scaffolded folder is naming the same declaration as one that names a file inside it.
    $subtree = $template.EndsWith('/**')
    if ($subtree) { $template = $template.Substring(0, $template.Length - 3) }

    # Placeholders are not always whole segments (`<category>.md`), so the template is
    # tokenized rather than split on '/'.
    $tokens = [regex]::Split($template, '(<[^<>]+>|\*\*)')
    $pattern = [System.Text.StringBuilder]::new('^')
    $groupIndex = 0
    $groupNames = [System.Collections.Generic.List[string]]::new()
    foreach ($token in $tokens) {
        if ([string]::IsNullOrEmpty($token)) { continue }
        if ($token -eq '**') {
            [void]$pattern.Append('.*')
            continue
        }
        if ($token -match '^<[^<>]+>$') {
            $name = "seg$groupIndex"
            $groupNames.Add($name)
            $groupIndex++
            [void]$pattern.Append("(?<$name>[^/]+)")
            continue
        }
        [void]$pattern.Append([regex]::Escape($token))
    }
    [void]$pattern.Append($(if ($subtree) { '(?:/.*)?$' } else { '$' }))

    $match = [regex]::Match($candidate, $pattern.ToString())
    if (-not $match.Success) { return $false }

    $values = @()
    if ($Scaffold.PSObject.Properties.Name -contains 'values' -and $null -ne $Scaffold.values) {
        $values = @($Scaffold.values)
    }
    if ($values.Count -eq 0) { return $true }

    foreach ($name in $groupNames) {
        $value = $match.Groups[$name].Value
        # A quoted placeholder is the template itself, not a value drawn from the domain.
        if ($value -match '^<[^<>]+>') { continue }
        if ($values -notcontains $value) { return $false }
    }

    return $true
}


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
        Text = ($result -join "`n")
        Unterminated = $inFence
    }
}

function Get-PowerShellRuntimeFacts {
    <#
    .SYNOPSIS
    Parses comment-free text, installed-sidecar joins, and dynamic supported-root joins.
    .DESCRIPTION
    Comment examples describe source layouts and hostile fixture paths but execute no reads.
    The AST also distinguishes `$PSScriptRoot`/`$AssetRoot` sidecars from repo-root joins and
    catches positional, named, and interpolated Join-Path arguments without regex ambiguity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Content,
        [ref]$tokens,
        [ref]$parseErrors
    )
    $chars = $Content.ToCharArray()
    foreach ($token in @($tokens | Where-Object { $_.Kind -eq 'Comment' })) {
        for ($index = $token.Extent.StartOffset; $index -lt $token.Extent.EndOffset; $index++) {
            if ($chars[$index] -ne "`r" -and $chars[$index] -ne "`n") {
                $chars[$index] = ' '
            }
        }
    }

    $sidecarRanges = [System.Collections.Generic.List[object]]::new()
    $sidecarReferences = [System.Collections.Generic.List[object]]::new()
    $dynamicJoins = [System.Collections.Generic.List[object]]::new()
    $literalJoins = [System.Collections.Generic.List[object]]::new()
    $sourceTreeJoins = [System.Collections.Generic.List[object]]::new()
    $joinCommands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Join-Path'
            }, $true))
    foreach ($command in $joinCommands) {
        $named = @{}
        $positional = [System.Collections.Generic.List[object]]::new()
        $elements = @($command.CommandElements)
        for ($index = 1; $index -lt $elements.Count; $index++) {
            $element = $elements[$index]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                $parameterName = $element.ParameterName.ToLowerInvariant()
                if ($parameterName -in @('path', 'childpath', 'additionalchildpath') -and $element.Argument) {
                    $named[$parameterName] = $element.Argument
                }
                elseif ($parameterName -in @('path', 'childpath', 'additionalchildpath') -and
                    $index + 1 -lt $elements.Count -and
                    $elements[$index + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    $named[$parameterName] = $elements[$index + 1]
                    $index++
                }
                continue
            }
            $positional.Add($element)
        }

        $pathArgument = if ($named.ContainsKey('path')) {
            $named['path']
        }
        elseif ($positional.Count -gt 0) {
            $positional[0]
        }
        else {
            $null
        }
        if (-not $pathArgument) { continue }

        $pathText = $null
        $pathDynamic = $false
        if ($pathArgument -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $pathText = [string]$pathArgument.Value
        }
        elseif ($pathArgument -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            $pathText = [string]$pathArgument.Value
            $pathDynamic = @($pathArgument.NestedExpressions).Count -gt 0
        }
        $childArguments = [System.Collections.Generic.List[object]]::new()
        foreach ($parameterName in @('childpath', 'additionalchildpath')) {
            if ($named.ContainsKey($parameterName)) {
                $childArguments.Add($named[$parameterName])
            }
        }
        $positionalStart = if ($named.ContainsKey('path')) { 0 } else { 1 }
        for ($index = $positionalStart; $index -lt $positional.Count; $index++) {
            $childArguments.Add($positional[$index])
        }

        $childTexts = [System.Collections.Generic.List[string]]::new()
        $dynamicChild = $null
        foreach ($childArgument in $childArguments) {
            $childText = if ($childArgument -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                [string]$childArgument.Value
            }
            elseif ($childArgument -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and
                @($childArgument.NestedExpressions).Count -eq 0) {
                [string]$childArgument.Value
            }
            else {
                $null
            }
            if ($null -eq $childText) {
                if (-not $dynamicChild) { $dynamicChild = $childArgument }
            }
            else {
                $childTexts.Add($childText)
            }
        }

        if ($pathArgument -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $pathArgument.VariablePath.UserPath -in @('PSScriptRoot', 'AssetRoot')) {
            if (-not $dynamicChild -and $childTexts.Count -eq $childArguments.Count -and
                $childTexts.Count -gt 0) {
                foreach ($childArgument in $childArguments) {
                    $sidecarRanges.Add([pscustomobject]@{
                            Start = $childArgument.Extent.StartOffset
                            End = $childArgument.Extent.EndOffset
                        })
                }
                $sidecarPath = (($childTexts | ForEach-Object { $_.Trim('/', '\') }) -join '/')
                if ($sidecarPath -notmatch '(^|/)\.\.(/|$)' -and
                    $sidecarPath -match '\.[A-Za-z0-9]+$') {
                    $sidecarReferences.Add([pscustomobject]@{
                            Base = [string]$pathArgument.VariablePath.UserPath
                            Path = $sidecarPath
                        })
                }
            }
        }

        if ($pathArgument -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $pathArgument.VariablePath.UserPath -notin @('PSScriptRoot', 'AssetRoot')) {
            foreach ($childText in $childTexts) {
                if ($childText -match '^(?:\./)?(?:plugins/|scripts/skalary/(?!registry\.json$))') {
                    $sourceTreeJoins.Add([pscustomobject]@{
                            Path = $childText
                            Base = [string]$pathArgument.Extent.Text
                        })
                }
            }
        }

        if (-not $pathText -or $pathText -notmatch '^(?:\./assets(?:/|$)|\.github/(?:skills|agents|prompts)(?:/|$)|(?:docs|schemas|tools)(?:/|$)|\./(?:plugins|scripts/skalary)(?:/|$))') {
            continue
        }

        if ($pathDynamic -or $dynamicChild) {
            $dynamicJoins.Add([pscustomobject]@{
                    Root = $pathText
                    Tail = if ($dynamicChild) { [string]$dynamicChild.Extent.Text } else { [string]$pathArgument.Extent.Text }
                })
        }
        elseif ($childTexts.Count -eq $childArguments.Count -and $childTexts.Count -gt 0) {
            $literalJoins.Add([pscustomobject]@{
                    Path = (($pathText.TrimEnd('/', '\')) + '/' +
                        (($childTexts | ForEach-Object { $_.Trim('/', '\') }) -join '/')).Replace('\', '/')
                })
        }
    }

    return [pscustomobject]@{
        Text = -join $chars
        SidecarRanges = @($sidecarRanges)
        SidecarReferences = @($sidecarReferences)
        DynamicJoins = @($dynamicJoins)
        LiteralJoins = @($literalJoins)
        SourceTreeJoins = @($sourceTreeJoins)
    }
}

function Test-IsInstalledSidecarReference {
    param(
        [Parameter(Mandatory)]$PowerShellFacts,
        [Parameter(Mandatory)][int]$MatchIndex
    )

    return @(
        $PowerShellFacts.SidecarRanges |
            Where-Object { $MatchIndex -ge $_.Start -and $MatchIndex -lt $_.End }
    ).Count -gt 0
}


function Get-BundleClosure {
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$ReviewSchemaDir
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $files = [ordered]@{}
    $work = [System.Collections.Generic.Queue[string]]::new()
    $work.Enqueue($ScriptName)

    while ($work.Count -gt 0) {
        $current = $work.Dequeue()
        if (-not $seen.Add($current)) { continue }

        $currentPath = Join-Path $SourceDir $current
        if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) {
            throw "Bundled script source not found: $currentPath"
        }
        $files[$current] = $currentPath

        $content = [System.IO.File]::ReadAllText($currentPath)
        foreach ($match in $moduleRegex.Matches($content)) {
            $mod = $match.Groups['mod'].Value
            $work.Enqueue($mod)
        }
        foreach ($match in $schemaRegex.Matches($content)) {
            $relative = $match.Groups['schema'].Value
            $schemaName = [System.IO.Path]::GetFileName($relative)
            $schemaPath = Join-Path $ReviewSchemaDir $schemaName
            if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
                throw "Bundled review schema source not found in canonical schemas/review/: $schemaPath"
            }
            $files[$relative] = $schemaPath
        }
    }

    return $files
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
$declaredScaffolds = [System.Collections.Generic.List[object]]::new()
$scaffoldRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($manifestPath in $manifestPaths) {
    $manifest = Read-JsonFile -Path $manifestPath.FullName
    foreach ($file in @($manifest.files)) {
        [void]$declaredDests.Add(([string]$file.dest).Replace('\', '/'))
    }

    if ($manifest.PSObject.Properties.Name -notcontains 'scaffolds' -or $null -eq $manifest.scaffolds) { continue }
    foreach ($scaffold in @($manifest.scaffolds)) {
        $declaredScaffolds.Add($scaffold)
        $root = Get-ScaffoldRoot -Path ([string]$scaffold.path)
        if ($root) { [void]$scaffoldRoots.Add($root) }
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

        $dest = ([string]$file.dest).Replace('\', '/')
        $scanSourcePath = $sourcePath
        $bundleClosureDests = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $managedScript = [regex]::Match($dest, '^skills/[^/]+/scripts/(?<name>[^/]+\.psm?1)$')
        if ($managedScript.Success) {
            $canonicalScript = Join-Path $scriptsSource $managedScript.Groups['name'].Value
            if (Test-Path -LiteralPath $canonicalScript -PathType Leaf) {
                $scanSourcePath = $canonicalScript
                $managedDirDest = $dest.Substring(0, $dest.LastIndexOf('/'))
                $managedClosure = Get-BundleClosure -ScriptName $managedScript.Groups['name'].Value `
                    -SourceDir $scriptsSource -ReviewSchemaDir $reviewSchemaSource
                foreach ($relative in $managedClosure.Keys) {
                    [void]$bundleClosureDests.Add("$managedDirDest/$relative")
                }
            }
        }
        $content = [System.IO.File]::ReadAllText($scanSourcePath)

        $stripped = Remove-FencedBlocks -Content $content
        $powerShellFacts = if ($ext -in @('.ps1', '.psm1')) {
            Get-PowerShellRuntimeFacts -Content $stripped.Text
        }
        else {
            $null
        }
        $prose = if ($powerShellFacts) { $powerShellFacts.Text } else { $stripped.Text }

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

        foreach ($match in $assetScaffoldRegex.Matches($prose)) {
            if ($powerShellFacts -and
                (Test-IsInstalledSidecarReference -PowerShellFacts $powerShellFacts -MatchIndex $match.Index)) {
                continue
            }
            $referenced = $match.Groups['path'].Value.TrimEnd('.', ',', ')').Trim('/')
            if (Test-RepoOwnedOptionalInput -PluginName $pluginName -Path $referenced) { continue }
            $root = Get-ScaffoldRoot -Path $referenced
            if (-not $root) { continue }
            # A payload naming a scaffold's own root folder is naming the declaration.
            if ($scaffoldRoots.Contains($referenced)) { continue }
            # A path whose final segment is a bare placeholder names a shape, not a file —
            # `docs/design-notes/<subfolder>/<derived-filename>` is prose describing where
            # notes go. A placeholder with a literal suffix (`<category>.md`) is still a real
            # path template and stays in grammar.
            if ($referenced -match '/<[^<>/]+>$') { continue }

            $matched = $false
            foreach ($scaffold in $declaredScaffolds) {
                if (Test-ScaffoldMatch -Path $referenced -Scaffold $scaffold) { $matched = $true; break }
            }
            if ($matched) { continue }

            $assetViolations.Add("plugin '$pluginName': '$dest' reads '$referenced', a runtime path under the scaffolded root '$root' that no scaffolds[] entry declares. Installation cannot write outside .github/, so declare who scaffolds it on first use (or correct the path).")
        }

        foreach ($sidecar in @($(if ($powerShellFacts) { $powerShellFacts.SidecarReferences } else { @() }))) {
            $sidecarPath = ([string]$sidecar.Path).Trim('/')
            $referenced = if ([string]$sidecar.Base -eq 'PSScriptRoot') {
                $destParent = $dest.Substring(0, $dest.LastIndexOf('/'))
                "$destParent/$sidecarPath"
            }
            elseif ($skillMatch.Success) {
                "skills/$($skillMatch.Groups['skill'].Value)/assets/$sidecarPath"
            }
            else {
                $null
            }
            if ($referenced -and
                ($declaredDests.Contains($referenced) -or $bundleClosureDests.Contains($referenced))) {
                continue
            }
            $assetViolations.Add("plugin '$pluginName': '$dest' reads sidecar '$([string]$sidecar.Base)/$sidecarPath', which does not resolve to a declared files[] destination or verified script bundle.")
        }

        $literalJoins = if ($powerShellFacts) {
            @($powerShellFacts.LiteralJoins)
        }
        else {
            @(
                foreach ($match in $assetLiteralJoinRegex.Matches($prose)) {
                    [pscustomobject]@{
                        Path = "$($match.Groups['root'].Value.TrimEnd('/', '\'))/$($match.Groups['child'].Value.Trim('/', '\'))"
                    }
                }
            )
        }
        foreach ($literalJoin in $literalJoins) {
            $referenced = ([string]$literalJoin.Path).Replace('\', '/')
            if ($referenced -match '^\.github/(?<installed>.+)$') {
                $installed = $Matches['installed']
                $scriptReference = [regex]::Match($installed, '^skills/[^/]+/scripts/(?<name>[^/]+\.psm?1)$')
                if (($scriptReference.Success -and
                        (Test-Path -LiteralPath (Join-Path $scriptsSource $scriptReference.Groups['name'].Value) -PathType Leaf)) -or
                    $declaredDests.Contains($installed)) {
                    continue
                }
                $assetViolations.Add("plugin '$pluginName': '$dest' joins installed path '$referenced', which no plugin declares in files[].")
                continue
            }
            if ($referenced -match '^\./assets/(?<rest>.+)$') {
                $rest = $Matches['rest']
                $installed = if ($skillMatch.Success) {
                    "skills/$($skillMatch.Groups['skill'].Value)/assets/$rest"
                }
                else {
                    $null
                }
                if ($installed -and $declaredDests.Contains($installed)) { continue }
                $assetViolations.Add("plugin '$pluginName': '$dest' joins skill-relative path '$referenced', which does not resolve to a declared files[] destination.")
                continue
            }
            if ($referenced -match '^(?:docs|schemas|tools)/') {
                if (Test-RepoOwnedOptionalInput -PluginName $pluginName -Path $referenced) { continue }
                if ($scaffoldRoots.Contains($referenced)) { continue }
                $matched = $false
                foreach ($scaffold in $declaredScaffolds) {
                    if (Test-ScaffoldMatch -Path $referenced -Scaffold $scaffold) {
                        $matched = $true
                        break
                    }
                }
                if ($matched) { continue }
                $assetViolations.Add("plugin '$pluginName': '$dest' joins scaffold path '$referenced', which no scaffolds[] entry declares.")
                continue
            }
            if ($referenced -match '^\./(?:plugins|scripts/skalary)/') {
                $assetViolations.Add("plugin '$pluginName': '$dest' joins source-tree path '$($referenced.TrimStart('.', '/'))'. Foreign consumers have no skalary source tree.")
            }
        }

        foreach ($match in $assetSourceRegex.Matches($prose)) {
            $referenced = $match.Groups['path'].Value.TrimStart('.', '/')
            $assetViolations.Add("plugin '$pluginName': '$dest' reads source-tree path '$referenced'. Foreign consumers have no skalary plugins/ or scripts/skalary/ tree; use the installed .github/ destination.")
        }

        if ($powerShellFacts) {
            foreach ($sourceTreeJoin in @($powerShellFacts.SourceTreeJoins)) {
                $assetViolations.Add("plugin '$pluginName': '$dest' joins source-tree path '$($sourceTreeJoin.Path)' to '$($sourceTreeJoin.Base)'. Foreign consumers have no skalary plugins/ tree; use the installed .github/ destination.")
            }
            foreach ($dynamicJoin in @($powerShellFacts.DynamicJoins)) {
                $assetViolations.Add("plugin '$pluginName': '$dest' dynamically composes supported runtime root '$($dynamicJoin.Root)' with '$($dynamicJoin.Tail)'. Use a literal installed, skill-relative, or scaffold path so reference closure is checkable.")
            }
        }
        else {
            foreach ($match in $assetDynamicRegex.Matches($prose)) {
                $assetViolations.Add("plugin '$pluginName': '$dest' dynamically composes supported runtime root '$($match.Groups['root'].Value)' with '$($match.Groups['tail'].Value)'. Use a literal installed, skill-relative, or scaffold path so reference closure is checkable.")
            }
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

            $closure = Get-BundleClosure -ScriptName $name -SourceDir $scriptsSource `
                -ReviewSchemaDir $reviewSchemaSource

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
            foreach ($relative in $closure.Keys) {
                $expected[$dirKey].Files[$relative] = $closure[$relative]
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

    foreach ($relative in ($entry.Files.Keys | Sort-Object)) {
        $sourcePath = $entry.Files[$relative]
        $targetPath = Join-Path $entry.Dir $relative
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDir -PathType Container) -and -not $WhatIfPreference) {
            [void](New-Item -ItemType Directory -Path $targetDir -Force)
        }

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
        $existing = @(
            Get-ChildItem -LiteralPath $entry.Dir -File |
                Where-Object { $_.Extension -in @('.ps1', '.psm1') }
            $schemaBundleDir = Join-Path $entry.Dir 'schemas/review'
            if (Test-Path -LiteralPath $schemaBundleDir -PathType Container) {
                Get-ChildItem -LiteralPath $schemaBundleDir -Recurse -File |
                    Where-Object { $_.Name.EndsWith('.schema.json', [System.StringComparison]::OrdinalIgnoreCase) }
            }
        )
        foreach ($existingFile in $existing) {
            $relative = [System.IO.Path]::GetRelativePath($entry.Dir, $existingFile.FullName).Replace('\', '/')
            if (-not $entry.Files.ContainsKey($relative)) {
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

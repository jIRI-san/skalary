#requires -Version 7.0
<#
.SYNOPSIS
Regenerates the human-readable architecture document from the contract sources, embedding the
canonical freshness digest.

.DESCRIPTION
The human-doc generation step of the architecture-notes update flow (`/uan`). The human doc
(`docs/architecture-notes/architecture.human.md`) is a DERIVED artifact: it carries hand-authored
narrative regions (Purpose, Decision Records, Resources) plus a GENERATED region (system diagram +
per-component summary) rebuilt from the contracts on every architecture change. It is excluded
from AI auto-load (not referenced by `.architecture-notes.md`) so it never pollutes agent context.

The generator:

  1. Materializes the doc from the template on first run (never overwriting narrative later).
  2. Rebuilds ONLY the region between the `BEGIN GENERATED: contracts` / `END GENERATED: contracts`
     markers: a Mermaid dependency diagram and a per-contract component summary.
  3. Recomputes the canonical contract-sources digest (via Get-ArchContractsHash.ps1) and embeds
     it in the `arch-contracts-sha256` marker so Test-ArchDocFreshness can detect drift.

Hand-authored regions are preserved verbatim across regenerations. Contract prose is untrusted
input rendered as data (fenced), never executed.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Repository root containing schemas/ and docs/architecture-notes/.
    [Parameter(Mandatory)][string]$RepoRoot,

    # Project name used when the doc is first materialized from the template.
    [string]$ProjectName,

    # Root of the shipped assets (…/architecture-notes/assets). Auto-detected when omitted.
    [string]$AssetRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    throw "RepoRoot not found or not a directory: $RepoRoot"
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$hashScript = Join-Path $PSScriptRoot 'Get-ArchContractsHash.ps1'
if (-not (Test-Path -LiteralPath $hashScript -PathType Leaf)) {
    throw "Required sibling script missing: $hashScript"
}
. $hashScript  # dot-source Get-ArchContractsHash

if (-not $AssetRoot) {
    $candidates = @(
        (Join-Path $PSScriptRoot '..' 'skills' 'architecture-notes' 'assets'),
        (Join-Path $PSScriptRoot '..' 'assets')
    )
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath $candidate -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'templates') -PathType Container)) {
            $AssetRoot = (Resolve-Path -LiteralPath $candidate).Path
            break
        }
    }
    if (-not $AssetRoot) {
        throw "Could not locate architecture-notes assets relative to $PSScriptRoot; pass -AssetRoot explicitly."
    }
}
$humanDocTemplate = Join-Path $AssetRoot 'templates/architecture-human-doc.template.md'
if (-not (Test-Path -LiteralPath $humanDocTemplate -PathType Leaf)) {
    throw "Required template missing: $humanDocTemplate"
}

$schemasDir = Join-Path $RepoRoot 'schemas/architecture'
$notesDir = Join-Path $RepoRoot 'docs/architecture-notes'
$docPath = Join-Path $notesDir 'architecture.human.md'

$beginMarker = '<!-- BEGIN GENERATED: contracts -->'
$endMarker = '<!-- END GENERATED: contracts -->'
$hashMarkerPattern = '<!-- arch-contracts-sha256: [^>]* -->'
$eol = "`n"

function ConvertTo-SafeText {
    param([string]$Text)
    # Contract-derived text is untrusted. Collapse newlines, escape table pipes, and HTML-escape
    # angle brackets so prose can never emit the GENERATED / sha256 marker comments and corrupt the
    # next regeneration (the region splice locates markers by literal string).
    if ($null -eq $Text) { return '' }
    $t = $Text -replace '[\r\n]+', ' '
    $t = $t -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
    $t = $t -replace '\|', '\|'
    return $t.Trim()
}

function ConvertTo-MermaidLabel {
    param([string]$Text)
    # Mermaid node labels break on " [ ] and backticks; neutralize them so an untrusted title
    # cannot escape the label and inject diagram syntax. Applied on top of ConvertTo-SafeText.
    $t = ConvertTo-SafeText $Text
    $t = $t -replace '"', "'" -replace '\[', '(' -replace '\]', ')' -replace '`', "'"
    return $t
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

# --- Load contracts (excluding the schema definition) ------------------------------------------
$contracts = @()
if (Test-Path -LiteralPath $schemasDir -PathType Container) {
    $collectedFiles = @(
        Get-ChildItem -LiteralPath $schemasDir -File -Filter '*.json' -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.json' -and $_.Name -ne 'architecture-contract.schema.json' }
    )
    # Ordinal sort so the doc's component order matches the digest's canonical order exactly.
    $fileList = [System.Collections.Generic.List[object]]::new()
    $fileList.AddRange([object[]]$collectedFiles)
    $fileList.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
    $contracts = @(
        foreach ($f in $fileList) {
            try { Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json }
            catch { throw "Contract JSON is unparseable: $($f.FullName). Fix or remove it before regenerating (a silently dropped contract would leave a stale-but-'fresh' doc)." }
        }
    )
}

# --- Build the GENERATED region ----------------------------------------------------------------
$diagramLines = [System.Collections.Generic.List[string]]::new()
$diagramLines.Add('```mermaid')
$diagramLines.Add('graph TD')
if ($contracts.Count -eq 0) {
    $diagramLines.Add('  empty["(no contracts yet)"]')
}
else {
    foreach ($c in $contracts) {
        $id = [string](Get-Prop $c 'id')
        $title = ConvertTo-MermaidLabel ([string](Get-Prop $c 'title' $id))
        $node = ($id -replace '[^A-Za-z0-9_]', '_')
        $diagramLines.Add("  $node[""$title""]")
    }
}
$diagramLines.Add('```')

$componentLines = [System.Collections.Generic.List[string]]::new()
if ($contracts.Count -eq 0) {
    $componentLines.Add('_No contracts defined yet._')
}
else {
    foreach ($c in $contracts) {
        $id = [string](Get-Prop $c 'id')
        $title = ConvertTo-SafeText ([string](Get-Prop $c 'title' $id))
        $maturity = ConvertTo-SafeText ([string](Get-Prop $c 'maturity' 'draft'))
        $prose = ConvertTo-SafeText ([string](Get-Prop $c 'description' (Get-Prop $c 'prose' '')))
        $componentLines.Add("### $title")
        $componentLines.Add('')
        $componentLines.Add("- **Governing contract:** ``$id`` ($maturity)")
        if ($prose) { $componentLines.Add("- **Boundary:** $prose") }
        $componentLines.Add('')
    }
}

$generated = @(
    $beginMarker
    ''
    '## System Diagram'
    ''
    ($diagramLines -join $eol)
    ''
    '## Components'
    ''
    ($componentLines -join $eol).TrimEnd()
    ''
    $endMarker
) -join $eol

# --- Load or materialize the doc ---------------------------------------------------------------
if (Test-Path -LiteralPath $docPath -PathType Leaf) {
    $doc = (Get-Content -LiteralPath $docPath -Raw) -replace "`r`n", "`n" -replace "`r", "`n"
}
else {
    if (-not $ProjectName) { $ProjectName = Split-Path -Leaf $RepoRoot }
    $doc = ((Get-Content -LiteralPath $humanDocTemplate -Raw) -replace "`r`n", "`n" -replace "`r", "`n").
    Replace('<PROJECT_NAME>', $ProjectName)
}

# Replace the GENERATED region (markers included) with the freshly built content. Ordinal match so
# region location is deterministic regardless of locale / culture-ignorable characters.
$ord = [System.StringComparison]::Ordinal
$beginIdx = $doc.IndexOf($beginMarker, $ord)
$endIdx = $doc.IndexOf($endMarker, $ord)
if ($beginIdx -ge 0 -and $endIdx -gt $beginIdx) {
    $before = $doc.Substring(0, $beginIdx)
    $after = $doc.Substring($endIdx + $endMarker.Length)
    $doc = $before + $generated + $after
}
else {
    throw "Human doc is missing the GENERATED markers; cannot regenerate without clobbering narrative. Restore markers from the template."
}

# --- Embed the canonical freshness digest ------------------------------------------------------
$hashResult = Get-ArchContractsHash -SchemasDir $schemasDir
$hashMarker = "<!-- arch-contracts-sha256: $($hashResult.Digest) -->"
if ($doc -match $hashMarkerPattern) {
    $doc = [regex]::Replace($doc, $hashMarkerPattern, $hashMarker)
}
else {
    throw "Human doc is missing the arch-contracts-sha256 marker; restore it from the template."
}

# --- Write ------------------------------------------------------------------------------------
$action = 'whatif'
if ($PSCmdlet.ShouldProcess($docPath, 'Regenerate human architecture doc')) {
    $destDir = Split-Path -Parent $docPath
    if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($destDir)
    }
    Set-Content -LiteralPath $docPath -Value $doc -NoNewline
    $action = 'created'
}

[pscustomobject]@{
    Path      = $docPath
    Action    = $action
    Digest    = $hashResult.Digest
    Contracts = $hashResult.Count
}

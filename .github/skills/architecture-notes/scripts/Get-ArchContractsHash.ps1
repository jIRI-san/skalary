#requires -Version 7.0
<#
.SYNOPSIS
Computes the canonical content hash of a repository's architecture contract sources.

.DESCRIPTION
Single source of truth for the architecture-doc freshness digest. Both the human-doc generator
(New-ArchHumanDoc.ps1) and the freshness gate (Test-ArchDocFreshness.ps1) call this so the
embedded digest and the recomputed digest can never diverge over an algorithm difference.

Canonicalization (order- and encoding-stable, add/delete-sensitive):

  1. Enumerate contract sources: ``*.json`` under <SchemasDir>.
  2. Address each by its normalized relative path (forward slashes), lower-cased for
     case-insensitive filesystems.
  3. Normalize content: strip a UTF-8 BOM, convert CRLF/CR to LF.
  4. For each record, feed ``UTF8(relPath) + NUL + UTF8(content) + NUL`` into the hash, processing
     records in ordinal-sorted relative-path order.
  5. Return the lower-case hex SHA-256 of the concatenation.

Adding, deleting, renaming, or editing any contract changes the digest; reordering the filesystem
does not. Returns the digest string; also returns the ordered relative paths that fed it.
#>
[CmdletBinding()]
param(
    # Directory holding the contract JSON sources (typically <repoRoot>/schemas). Optional so the
    # script can be dot-sourced (to import Get-ArchContractsHash) without binding a mandatory param.
    [string]$SchemasDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ArchContractsHash {
    param(
        [Parameter(Mandatory)][string]$SchemasDir
    )

    $files = @()
    if (Test-Path -LiteralPath $SchemasDir -PathType Container) {
        $rootFull = (Resolve-Path -LiteralPath $SchemasDir).Path
        $collected = @(
            Get-ChildItem -LiteralPath $rootFull -File -Filter '*.json' -ErrorAction SilentlyContinue |
                # Post-filter the extension: the Windows -Filter '*.json' also matches .jsonc/.json5
                # and 8.3 aliases, which would diverge from the literal glob on Linux/macOS.
                Where-Object { $_.Extension -eq '.json' } |
                ForEach-Object {
                    [pscustomobject]@{
                        Rel      = $_.Name.ToLowerInvariant()
                        FullName = $_.FullName
                    }
                }
        )
        # Sort by ORDINAL codepoint order (not culture-aware collation) so the canonical record
        # order is identical across OSes/ICU versions — the digest is the gate's source of truth.
        $list = [System.Collections.Generic.List[object]]::new()
        $list.AddRange([object[]]$collected)
        $list.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Rel, $b.Rel) })
        $files = @($list)
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $buffer = [System.IO.MemoryStream]::new()
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        foreach ($f in $files) {
            $raw = [System.IO.File]::ReadAllText($f.FullName)
            # ReadAllText already strips a UTF-8 BOM during decoding; normalize line endings to LF.
            $raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"

            $relBytes = $utf8.GetBytes($f.Rel)
            $contentBytes = $utf8.GetBytes($raw)
            $buffer.Write($relBytes, 0, $relBytes.Length)
            $buffer.WriteByte(0)
            $buffer.Write($contentBytes, 0, $contentBytes.Length)
            $buffer.WriteByte(0)
        }
        $buffer.Position = 0
        $hashBytes = $sha.ComputeHash($buffer)
        $buffer.Dispose()
    }
    finally {
        $sha.Dispose()
    }

    $hex = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    return [pscustomobject]@{
        Digest = $hex
        Files  = @($files | ForEach-Object { $_.Rel })
        Count  = $files.Count
    }
}

# When invoked as a script (not dot-sourced), emit the digest for the requested directory.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $SchemasDir) { throw "SchemasDir is required when running this script directly." }
    Get-ArchContractsHash -SchemasDir $SchemasDir
}

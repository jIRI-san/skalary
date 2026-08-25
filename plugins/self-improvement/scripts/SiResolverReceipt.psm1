#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ResolverReceiptProtocol = 'si-resolver-receipt-v1'
$script:ResolverCandidateProtocol = 'si-resolver-candidate-v1'
$script:RankedSetProtocol = 'si-ranked-set-v1'
function ConvertTo-SiJcsString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $builder = [System.Text.StringBuilder]::new($Value.Length + 2)
    [void]$builder.Append('"')
    :nextCharacter for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        switch ([int]$character) {
            8 { [void]$builder.Append('\b'); continue nextCharacter }
            9 { [void]$builder.Append('\t'); continue nextCharacter }
            10 { [void]$builder.Append('\n'); continue nextCharacter }
            12 { [void]$builder.Append('\f'); continue nextCharacter }
            13 { [void]$builder.Append('\r'); continue nextCharacter }
            34 { [void]$builder.Append('\"'); continue nextCharacter }
            92 { [void]$builder.Append('\\'); continue nextCharacter }
        }
        if ([int]$character -lt 0x20) {
            [void]$builder.Append('\u')
            [void]$builder.Append(([int]$character).ToString('x4'))
            continue
        }
        if ([char]::IsHighSurrogate($character)) {
            if ($index + 1 -ge $Value.Length -or -not [char]::IsLowSurrogate($Value[$index + 1])) {
                throw 'JCS string contains an unpaired high surrogate.'
            }
            [void]$builder.Append($character)
            $index++
            [void]$builder.Append($Value[$index])
            continue
        }
        if ([char]::IsLowSurrogate($character)) {
            throw 'JCS string contains an unpaired low surrogate.'
        }
        [void]$builder.Append($character)
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-SiJcsJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $Value
    )

    process {
        if ($null -eq $Value) { return 'null' }
        if ($Value -is [string]) {
            return ConvertTo-SiJcsString -Value ([string]$Value)
        }
        if ($Value -is [bool]) {
            return $(if ($Value) { 'true' } else { 'false' })
        }
        if ($Value -is [byte] -or $Value -is [sbyte] -or
            $Value -is [int16] -or $Value -is [uint16] -or
            $Value -is [int32] -or $Value -is [uint32] -or
            $Value -is [int64] -or $Value -is [uint64]) {
            return [Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        if ($Value -is [System.Collections.IDictionary]) {
            $keys = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
            [Array]::Sort($keys, [System.StringComparer]::Ordinal)
            $properties = foreach ($key in $keys) {
                (ConvertTo-SiJcsJson -Value $key) + ':' + (ConvertTo-SiJcsJson -Value $Value[$key])
            }
            return '{' + ($properties -join ',') + '}'
        }
        if ($Value -is [psobject] -and $Value -isnot [System.Collections.IEnumerable]) {
            $names = [string[]]@($Value.PSObject.Properties.Name)
            [Array]::Sort($names, [System.StringComparer]::Ordinal)
            $properties = foreach ($name in $names) {
                (ConvertTo-SiJcsJson -Value $name) + ':' +
                (ConvertTo-SiJcsJson -Value $Value.PSObject.Properties[$name].Value)
            }
            return '{' + ($properties -join ',') + '}'
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $items = foreach ($item in $Value) { ConvertTo-SiJcsJson -Value $item }
            return '[' + ($items -join ',') + ']'
        }
        throw "JCS canonicalization does not support value type '$($Value.GetType().FullName)'."
    }
}

function Get-SiDomainHash {
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$CanonicalJson
    )

    $domainBytes = [System.Text.Encoding]::UTF8.GetBytes($Domain)
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalJson)
    $framed = [byte[]]::new($domainBytes.Length + $jsonBytes.Length)
    [Array]::Copy($domainBytes, 0, $framed, 0, $domainBytes.Length)
    [Array]::Copy($jsonBytes, 0, $framed, $domainBytes.Length, $jsonBytes.Length)
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($framed)
    ).ToLowerInvariant()
}

function Get-SiResolverReceiptId {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Payload)

    return Get-SiDomainHash -Domain $script:ResolverReceiptProtocol `
        -CanonicalJson (ConvertTo-SiJcsJson -Value $Payload)
}

function New-SiRankedCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Candidate
    )

    if ($Candidate.Count -gt 5) { throw 'Resolver candidate list exceeds five entries.' }
    $ranked = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    for ($index = 0; $index -lt $Candidate.Count; $index++) {
        $item = $Candidate[$index]
        if ($null -eq $item -or
            $item.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') {
            throw "Resolver candidate $($index + 1) must be a JSON object."
        }
        $names = [string[]]@($item.PSObject.Properties.Name)
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
        if ($names.Count -ne 4 -or
            @('rationale', 'sources', 'targets', 'title' | Where-Object { $names -notcontains $_ }).Count -gt 0) {
            throw "Resolver candidate $($index + 1) must contain only title, rationale, sources, and targets."
        }
        if ($item.title -isnot [string] -or $item.rationale -isnot [string] -or
            $item.sources -isnot [System.Array] -or $item.targets -isnot [System.Array] -or
            @($item.sources | Where-Object { $_ -isnot [string] }).Count -gt 0 -or
            @($item.targets | Where-Object { $_ -isnot [string] }).Count -gt 0) {
            throw "Resolver candidate $($index + 1) has invalid JSON field types."
        }
        $title = [string]$item.title
        $rationale = [string]$item.rationale
        $sources = [string[]]$item.sources
        $targets = [string[]]$item.targets
        if ([string]::IsNullOrWhiteSpace($title) -or
            [System.Text.Encoding]::UTF8.GetByteCount($title) -gt 512 -or
            [string]::IsNullOrWhiteSpace($rationale) -or
            [System.Text.Encoding]::UTF8.GetByteCount($rationale) -gt 8KB -or
            $sources.Count -lt 1 -or $sources.Count -gt 32 -or
            $targets.Count -lt 1 -or $targets.Count -gt 32) {
            throw "Resolver candidate $($index + 1) exceeds its closed field limits."
        }
        foreach ($path in @($sources) + @($targets)) {
            if ([string]::IsNullOrWhiteSpace($path) -or
                [System.Text.Encoding]::UTF8.GetByteCount($path) -gt 1KB) {
                throw "Resolver candidate $($index + 1) contains an invalid source or target."
            }
        }
        $body = [ordered]@{
            rank      = $index + 1
            title     = $title
            rationale = $rationale
            sources   = $sources
            targets   = $targets
        }
        $candidateId = Get-SiDomainHash -Domain $script:ResolverCandidateProtocol `
            -CanonicalJson (ConvertTo-SiJcsJson -Value $body)
        if (-not $ids.Add($candidateId)) { throw "Duplicate resolver candidate '$candidateId'." }
        $ranked.Add([pscustomobject][ordered]@{
                candidateId = $candidateId
                rank        = $body.rank
                title       = $body.title
                rationale   = $body.rationale
                sources     = $body.sources
                targets     = $body.targets
            })
    }
    $rankedSetDigest = Get-SiDomainHash -Domain $script:RankedSetProtocol `
        -CanonicalJson (ConvertTo-SiJcsJson -Value $ranked.ToArray())
    return [pscustomobject]@{
        Candidates      = $ranked.ToArray()
        CandidateIds    = [string[]]@($ranked | ForEach-Object { $_.candidateId })
        RankedSetDigest = $rankedSetDigest
    }
}

Export-ModuleMember -Function ConvertTo-SiJcsJson, Get-SiResolverReceiptId, New-SiRankedCandidates

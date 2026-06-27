#requires -Version 7.0

Set-StrictMode -Version Latest

function Remove-FencedCodeBlocks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $output = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            $output.Add('')
            continue
        }

        if ($inFence) {
            $output.Add('')
            continue
        }

        $output.Add($line)
    }

    return , $output.ToArray()
}

function Split-MarkdownTableCells {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Row
    )

    $trimmed = $Row.Trim()
    $withoutPipes = $trimmed.Trim('|')
    $rawCells = $withoutPipes.Split('|')
    $cells = @()
    foreach ($cell in $rawCells) {
        $cells += , $cell.Trim()
    }

    return , $cells
}

function Get-PlanMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $repoRootPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $content = Get-Content -LiteralPath $fullPath -Raw
    $normalized = $content -replace "`r`n", "`n"
    $allLines = $normalized.Split("`n")
    $lines = Remove-FencedCodeBlocks -Lines $allLines

    $inRequirements = $false
    $inRisks = $false
    $currentPhase = ''
    $phaseSteps = @{}
    $requirements = @{}
    $risks = @{}
    $steps = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $lines) {
        if ($line -match '^\s*##\s+Requirements\b') {
            $inRequirements = $true
            $inRisks = $false
            continue
        }

        if ($line -match '^\s*##\s+Risks\b') {
            $inRequirements = $false
            $inRisks = $true
            continue
        }

        if ($line -match '^\s*##\s+') {
            $inRequirements = $false
            $inRisks = $false
            $currentPhase = $line.Trim()
            if ($currentPhase -match '^##\s+Phase\s+\d+:\s+') {
                $phaseSteps[$currentPhase] = [System.Collections.Generic.List[object]]::new()
            }
            continue
        }

        if ($inRequirements -and $line.Trim().StartsWith('|')) {
            $cells = Split-MarkdownTableCells -Row $line
            if ($cells.Count -lt 4 -or $cells[0] -eq 'ID' -or $cells[0] -eq '----') {
                continue
            }

            if ($cells[0] -match '^REQ-(?<id>\d+)$') {
                $requirements[$cells[0]] = [pscustomobject]@{
                    Id = $cells[0]
                    Number = [int]$Matches.id
                    AcceptanceCriteria = $cells[2]
                }
            }
            continue
        }

        if ($inRisks -and $line.Trim().StartsWith('|')) {
            $cells = Split-MarkdownTableCells -Row $line
            if ($cells.Count -lt 2 -or $cells[0] -eq 'ID' -or $cells[0] -eq '----') {
                continue
            }

            if ($cells[0] -match '^RISK-(?<id>\d+)$') {
                $risks[$cells[0]] = [int]$Matches.id
            }
            continue
        }

        if ($line -match '^\s*-\s\[(?<status>[ x~])\]\s+(?<step>\d+\.\d+[a-z]?)\s+(?<body>.+)$') {
            $stepId = $Matches.step
            $body = $Matches.body
            $size = ''
            if ($body -match '`(?<size>[SML])`') {
                $size = [string]$Matches.size
            }

            $role = 'ai-agent'
            if ($body -match '\s@(?<role>human|ai-agent)\b') {
                $role = [string]$Matches.role
            }

            $afterIds = @()
            if ($body -match '\[after:\s*(?<after>[^\]]+)\]') {
                $afterList = $Matches.after.Split(',')
                foreach ($after in $afterList) {
                    $candidate = $after.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        $afterIds += , $candidate
                    }
                }
            }

            $refs = @()
            $parenMatches = [regex]::Matches($body, '\((?<refs>[^)]*)\)')
            foreach ($parenMatch in $parenMatches) {
                $candidateRefs = @($parenMatch.Groups['refs'].Value.Split(',') | ForEach-Object { $_.Trim() })
                if ($candidateRefs -match '^REQ-\d+$' -or $candidateRefs -match '^RISK-\d+$') {
                    $refs = @($candidateRefs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }
            }

            $step = [pscustomobject]@{
                Id = $stepId
                Body = $body
                Role = $role
                Size = $size
                After = $afterIds
                Refs = $refs
                Phase = $currentPhase
            }
            $steps.Add($step)
            if ($phaseSteps.ContainsKey($currentPhase)) {
                $phaseSteps[$currentPhase].Add($step)
            }
            continue
        }
    }

    $sizeBytes = [System.Text.Encoding]::UTF8.GetByteCount($content)
    if ($sizeBytes -ge 20480 -or $allLines.Length -ge 400) {
        $warnings.Add("Plan size warning: ${sizeBytes} bytes / $($allLines.Length) lines (warn threshold 20KB/400).")
    }
    if ($sizeBytes -ge 35840 -or $allLines.Length -ge 700) {
        $warnings.Add("Plan size warning: ${sizeBytes} bytes / $($allLines.Length) lines (block threshold 35KB/700 is advisory in this validator).")
    }

    return [pscustomobject]@{
        PlanPath = $fullPath
        RepoRoot = $repoRootPath
        Content = $content
        Lines = $lines
        AllLines = $allLines
        Requirements = $requirements
        Risks = $risks
        Steps = @($steps)
        PhaseSteps = $phaseSteps
        Warnings = $warnings
    }
}

Export-ModuleMember -Function Get-PlanMetadata

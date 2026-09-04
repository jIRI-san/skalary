#requires -Version 7.0
<#
.SYNOPSIS
    Internal implementation body for the focused route of scripts/validate.ps1. Not an entry point.
.DESCRIPTION
    Holds the whole focused validation operation: path confinement, file enumeration, and the
    PowerShell/JSON parse. scripts/validate.ps1 always supervises this body in a child process
    for a focused run; run as a script it reads one bound request from stdin, so the supervised
    child performs the validated operation without re-entering public dispatch.

    scripts/validate.ps1 stays the documented command; this file is its focused body.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ConfinedValidationPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Label
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $full = if ([System.IO.Path]::IsPathRooted($Candidate)) {
        [System.IO.Path]::GetFullPath($Candidate)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $rootFull $Candidate))
    }
    $relative = [System.IO.Path]::GetRelativePath($rootFull, $full)
    if ([System.IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or
        $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::Ordinal)) {
        throw "$Label must stay inside the repository: '$full'."
    }
    if (-not (Test-Path -LiteralPath $full)) {
        throw "$Label does not exist: '$full'."
    }

    $cursor = $rootFull
    $segments = @(if ($relative -eq '.') { @() } else { $relative.Split(
            [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar),
            [System.StringSplitOptions]::RemoveEmptyEntries) })
    foreach ($segment in $segments) {
        $cursor = Join-Path $cursor $segment
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label must not traverse a link or reparse point: '$cursor'."
        }
    }
    return $full
}

function Get-FocusedValidationFile {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string[]]$SelectedPath = @()
    )

    $pathComparer = if ($IsWindows) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $supported = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('.ps1', '.psm1', '.psd1', '.json'),
        $pathComparer
    )
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($selected in $SelectedPath) {
        if ([string]::IsNullOrWhiteSpace($selected)) {
            throw 'Focused paths must be non-empty.'
        }
        $full = Resolve-ConfinedValidationPath -Root $RepoRoot -Candidate $selected -Label 'Focused validation path'
        $item = Get-Item -LiteralPath $full -Force
        if ($item -is [System.IO.FileInfo]) {
            if (-not $supported.Contains($item.Extension)) {
                throw "Focused validation file has an unsupported extension: '$selected'."
            }
            $files.Add($item.FullName)
            continue
        }

        $pending = [System.Collections.Generic.Stack[string]]::new()
        $pending.Push($item.FullName)
        while ($pending.Count -gt 0) {
            $current = $pending.Pop()
            foreach ($file in [System.IO.Directory]::EnumerateFiles($current)) {
                if (-not $supported.Contains([System.IO.Path]::GetExtension($file))) {
                    continue
                }
                $fileItem = Get-Item -LiteralPath $file -Force
                if (($fileItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Focused validation path must not contain linked files: '$file'."
                }
                $files.Add($fileItem.FullName)
            }
            foreach ($directory in [System.IO.Directory]::EnumerateDirectories($current)) {
                $directoryItem = Get-Item -LiteralPath $directory -Force
                if (($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Focused validation path must not contain linked directories: '$directory'."
                }
                $pending.Push($directoryItem.FullName)
            }
        }
    }
    return @($files | Sort-Object -Unique -CaseSensitive:(-not $IsWindows))
}

function Invoke-SkalaryFocusedValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string[]]$Path = @()
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {
        if (@($Path).Count -eq 0) {
            throw 'Routine validation requires one or more explicit -Path values. Use -FullRepository only for a direct broad run.'
        }
        $focusedFiles = @(Get-FocusedValidationFile -RepoRoot $RepoRoot -SelectedPath $Path)
        if (@($focusedFiles).Count -eq 0) {
            throw 'Focused validation selected no PowerShell or JSON files.'
        }
    }
    catch {
        Write-Host "FocusedScopeRequired: $($_.Exception.Message)" -ForegroundColor Red
        exit 12
    }

    $errors = [System.Collections.Generic.List[string]]::new()
    $psFiles = @($focusedFiles | Where-Object {
            [System.IO.Path]::GetExtension($_) -in @('.ps1', '.psm1', '.psd1')
        })
    $jsonFiles = @($focusedFiles | Where-Object {
            [System.IO.Path]::GetExtension($_) -eq '.json'
        })
    foreach ($file in $psFiles) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) {
            $errors.Add("${file}:$($parseError.Extent.StartLineNumber) $($parseError.Message)")
        }
    }
    foreach ($file in $jsonFiles) {
        try {
            $null = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            $errors.Add("${file}: invalid JSON - $($_.Exception.Message)")
        }
    }
    Write-Host "Focused validation parsed $($psFiles.Count) PowerShell and $($jsonFiles.Count) JSON file(s)."
    if ($errors.Count -gt 0) {
        Write-Host "VALIDATION FAILED ($($errors.Count) error(s)):" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host 'Validation passed.' -ForegroundColor Green
    exit 0
}

# Script mode is the supervised child: one bound request arrives on stdin, and the same body
# the public command names runs it. There is no other input path and no re-dispatch.
if ($MyInvocation.InvocationName -ne '.') {
    $supervision = & ([System.IO.Path]::Combine($PSScriptRoot, 'FocusedSupervision.ps1'))
    $request = & $supervision.ReadBodyRequest
    Invoke-SkalaryFocusedValidation @request
    exit 0
}

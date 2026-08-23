#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'WorkHierarchy.psm1') -DisableNameChecking

function Assert-GitHubWorkHierarchyRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository
    )

    if ($Repository -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]+$') {
        throw "GitHub repository must use the 'owner/name' form."
    }
}

function Get-GitHubWorkHierarchyProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($InputObject.PSObject.Properties.Name -notcontains $Name) {
        throw "GitHub adapter input is missing required property '$Name'."
    }
    return $InputObject.$Name
}

function Invoke-GitHubWorkHierarchyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [scriptblock]$CommandRunner
    )

    $result = if ($CommandRunner) {
        & $CommandRunner $Arguments
    }
    else {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'gh'
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in $Arguments) {
            $startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) {
                throw "GitHub CLI process did not start."
            }
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            [pscustomobject]@{
                ExitCode = $process.ExitCode
                Output = $stdout.GetAwaiter().GetResult()
                Error = $stderr.GetAwaiter().GetResult()
            }
        }
        finally {
            $process.Dispose()
        }
    }

    if (
        $null -eq $result -or
        $result.PSObject.Properties.Name -notcontains 'ExitCode' -or
        $result.PSObject.Properties.Name -notcontains 'Output'
    ) {
        throw 'GitHub command runner must return ExitCode and Output.'
    }
    if ([int]$result.ExitCode -ne 0) {
        $diagnostics = @()
        if ($result.PSObject.Properties.Name -contains 'Error') {
            $diagnostics += ([string]$result.Error).Trim()
        }
        $diagnostics += ([string]$result.Output).Trim()
        $detail = ($diagnostics | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
        throw $(if ($detail) { "GitHub CLI request failed: $detail" } else { 'GitHub CLI request failed with no diagnostic output.' })
    }
    return [string]$result.Output
}

function ConvertFrom-GitHubWorkHierarchyJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Json,

        [Parameter(Mandatory)]
        [string]$Operation
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw "GitHub CLI returned no JSON for $Operation."
    }
    try {
        return $Json | ConvertFrom-Json
    }
    catch {
        throw "GitHub CLI returned invalid JSON for ${Operation}: $($_.Exception.Message)"
    }
}

function ConvertFrom-GitHubWorkHierarchyIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Issue
    )

    $id = Get-GitHubWorkHierarchyProperty -InputObject $Issue -Name id
    $nodeId = [string](Get-GitHubWorkHierarchyProperty -InputObject $Issue -Name node_id)
    $number = [int](Get-GitHubWorkHierarchyProperty -InputObject $Issue -Name number)
    $title = [string](Get-GitHubWorkHierarchyProperty -InputObject $Issue -Name title)
    $body = Get-GitHubWorkHierarchyProperty -InputObject $Issue -Name body
    $state = ([string](Get-GitHubWorkHierarchyProperty -InputObject $Issue -Name state)).ToLowerInvariant()
    $url = [string](Get-GitHubWorkHierarchyProperty -InputObject $Issue -Name html_url)
    $providerId = 0L
    if (
        -not [long]::TryParse([string]$id, [ref]$providerId) -or
        $providerId -le 0 -or
        $number -le 0 -or
        [string]::IsNullOrWhiteSpace($nodeId) -or
        [string]::IsNullOrWhiteSpace($title) -or
        $state -notin @('open', 'closed') -or
        [string]::IsNullOrWhiteSpace($url)
    ) {
        throw 'GitHub CLI returned an invalid issue shape.'
    }

    return [pscustomobject][ordered]@{
        kind = 'issue'
        providerId = [string]$providerId
        nodeId = $nodeId
        number = $number
        title = $title
        body = [string]$body
        state = $state
        url = $url
    }
}

function Invoke-GitHubWorkHierarchyRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Request,

        [scriptblock]$CommandRunner
    )

    $kind = [string](Get-GitHubWorkHierarchyProperty -InputObject $Request -Name kind)
    if ($kind -ne 'issue') {
        throw "GitHub adapter does not support read kind '$kind'."
    }

    $repository = [string](Get-GitHubWorkHierarchyProperty -InputObject $Request -Name repository)
    Assert-GitHubWorkHierarchyRepository -Repository $repository
    $number = [int](Get-GitHubWorkHierarchyProperty -InputObject $Request -Name number)
    if ($number -le 0) {
        throw 'GitHub issue number must be positive.'
    }

    $json = Invoke-GitHubWorkHierarchyCommand `
        -Arguments @('api', "repos/$repository/issues/$number") `
        -CommandRunner $CommandRunner
    $issue = ConvertFrom-GitHubWorkHierarchyJson -Json $json -Operation "issue read '$repository#$number'"
    return ConvertFrom-GitHubWorkHierarchyIssue -Issue $issue
}

function Invoke-GitHubWorkHierarchyWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Operation,

        [scriptblock]$CommandRunner
    )

    $kind = [string](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name kind)
    $repository = [string](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name repository)
    Assert-GitHubWorkHierarchyRepository -Repository $repository

    switch ($kind) {
        'create-issue' {
            $title = [string](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name title)
            $body = [string](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name body)
            $arguments = @(
                'api', '--method', 'POST', "repos/$repository/issues",
                '-f', "title=$title", '-f', "body=$body"
            )
        }
        'update-issue' {
            $number = [int](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name number)
            if ($number -le 0) { throw 'GitHub issue number must be positive.' }
            $title = [string](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name title)
            $body = [string](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name body)
            $arguments = @(
                'api', '--method', 'PATCH', "repos/$repository/issues/$number",
                '-f', "title=$title", '-f', "body=$body"
            )
        }
        'link-child' {
            $parentNumber = [int](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name parentNumber)
            $childProviderId = [long](Get-GitHubWorkHierarchyProperty -InputObject $Operation -Name childProviderId)
            if ($parentNumber -le 0 -or $childProviderId -le 0) {
                throw 'GitHub parent issue number and child provider id must be positive.'
            }
            $arguments = @(
                'api', '--method', 'POST', "repos/$repository/issues/$parentNumber/sub_issues",
                '-F', "sub_issue_id=$childProviderId"
            )
        }
        default {
            throw "GitHub adapter does not support write kind '$kind'."
        }
    }

    $json = Invoke-GitHubWorkHierarchyCommand -Arguments $arguments -CommandRunner $CommandRunner
    $issue = ConvertFrom-GitHubWorkHierarchyJson -Json $json -Operation $kind
    return ConvertFrom-GitHubWorkHierarchyIssue -Issue $issue
}

function New-GitHubWorkHierarchyProvider {
    [CmdletBinding()]
    param(
        [scriptblock]$CommandRunner
    )

    $runner = $CommandRunner
    $read = {
        param($Request)
        GitHubWorkHierarchy\Invoke-GitHubWorkHierarchyRead -Request $Request -CommandRunner $runner
    }.GetNewClosure()
    $write = {
        param($Operation)
        GitHubWorkHierarchy\Invoke-GitHubWorkHierarchyWrite -Operation $Operation -CommandRunner $runner
    }.GetNewClosure()
    return New-WorkHierarchyProvider -Name github -Read $read -Write $write
}

Export-ModuleMember -Function `
    New-GitHubWorkHierarchyProvider, `
    Invoke-GitHubWorkHierarchyRead, Invoke-GitHubWorkHierarchyWrite

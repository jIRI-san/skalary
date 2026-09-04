#requires -Version 7.0
<#
.SYNOPSIS
    Runs one focused command in a bounded child process.
.DESCRIPTION
    Public focused commands pass a private script path and bound request data. The helper starts
    a clean PowerShell child, waits for the configured deadline, and uses the cross-platform
    Process.Kill(true) API to terminate that child and its current descendants on timeout.

    This is intentionally a small best-effort boundary for a single-user skills repository, not
    a sandbox. A descendant that deliberately detaches and is reparented before the timeout may
    escape the process tree; stronger OS containment is disproportionate here.
#>

$readBodyRequest = {
    $raw = [System.Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'No supervised request was supplied on stdin.'
    }
    return ($raw | Microsoft.PowerShell.Utility\ConvertFrom-Json -AsHashtable)
}

$writeOutput = {
    param($StdoutTask, $StderrTask)

    foreach ($entry in @(
            @{ Task = $StdoutTask; Writer = [System.Console]::Out },
            @{ Task = $StderrTask; Writer = [System.Console]::Error }
        )) {
        if ($entry.Task.IsCompletedSuccessfully) {
            $text = $entry.Task.GetAwaiter().GetResult()
            if ($text) { $entry.Writer.Write($text) }
            $entry.Writer.Flush()
        }
    }
}

$invokeSupervisedBody = {
    param(
        [Parameter(Mandatory)][string]$BodyPath,
        [Parameter(Mandatory)][hashtable]$Request,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][double]$WarningSeconds,
        [Parameter(Mandatory)][double]$TimeoutSeconds
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $process = $null
    $stdoutTask = $null
    $stderrTask = $null
    $timedOut = $false
    $exitCode = 14

    try {
        $body = [System.IO.Path]::GetFullPath($BodyPath)
        if (-not [System.IO.File]::Exists($body)) {
            throw "Focused body does not exist: '$body'."
        }

        $hostExecutable = [System.Environment]::ProcessPath
        if ([string]::IsNullOrWhiteSpace($hostExecutable) -or
            -not [System.IO.File]::Exists($hostExecutable)) {
            throw 'The running PowerShell executable could not be resolved.'
        }

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $hostExecutable
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
        $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-File', $body)) {
            [void]$startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $requestJson = $Request |
            Microsoft.PowerShell.Utility\ConvertTo-Json -Depth 10 -Compress
        $process.StandardInput.Write($requestJson)
        $process.StandardInput.Close()

        $remainingMilliseconds = [math]::Max(
            1,
            [int][math]::Ceiling(($TimeoutSeconds - $clock.Elapsed.TotalSeconds) * 1000)
        )
        if (-not $process.WaitForExit($remainingMilliseconds)) {
            $timedOut = $true
            $process.Kill($true)
            [void]$process.WaitForExit(5000)
        }

        foreach ($task in @($stdoutTask, $stderrTask)) {
            if (-not $task.IsCompleted) {
                try { [void]$task.Wait(2000) } catch { }
            }
        }
        & $writeOutput $stdoutTask $stderrTask

        if ($timedOut) {
            [System.Console]::Out.WriteLine(
                "FocusedTimeout: $Label exceeded $TimeoutSeconds seconds; its process tree was terminated.")
            $exitCode = 13
        }
        else {
            $exitCode = $process.ExitCode
        }
    }
    catch {
        if ($null -ne $process -and -not $process.HasExited) {
            try { $process.Kill($true) } catch { }
        }
        [System.Console]::Out.WriteLine("FocusedWorkerStartFailed: $Label could not run: $($_.Exception.Message)")
        $exitCode = 14
    }
    finally {
        $clock.Stop()
        if ($null -ne $process) { $process.Dispose() }
    }

    if (-not $timedOut -and $exitCode -ne 14 -and
        $clock.Elapsed.TotalSeconds -ge $WarningSeconds) {
        [System.Console]::Error.WriteLine(
            "WARNING: FocusedSlow: $Label completed in $([math]::Round($clock.Elapsed.TotalSeconds, 3))s (target <${WarningSeconds}s).")
        [System.Console]::Error.Flush()
    }

    return $exitCode
}.GetNewClosure()

return @{
    InvokeSupervisedBody = $invokeSupervisedBody
    ReadBodyRequest = $readBodyRequest
}

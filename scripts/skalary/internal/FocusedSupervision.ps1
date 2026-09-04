#requires -Version 7.0
<#
.SYNOPSIS
    Internal supervision helper for the focused repository commands. Not an entry point.
.DESCRIPTION
    Invoked by path from scripts/validate.ps1, scripts/skalary/Run-UnitTests.ps1 and
    scripts/skalary/Test-Evals.ps1. Those three scripts remain the only documented commands;
    this file carries the process supervision they share so the same 30/60 second contract
    cannot drift between three near-identical copies.

    Supervision is structural. A public focused invocation calls the supervisor
    unconditionally, and the work runs in a child process executing a private implementation
    body under scripts/skalary/internal/ — never the public script again. Nothing a caller can
    set selects the supervised or the unsupervised path: there is no switch, no script or
    global variable, no environment marker and no parent-process token. The request reaches
    the child on stdin as bound data rather than through an interpolated command line.

    Nothing here is reached by command-name resolution. This file invokes no named command at
    all: every step is a fully qualified .NET call or the invocation of a scriptblock held in
    a variable, and the file returns those scriptblocks as an object whose members the callers
    address directly. An alias or function defined by whoever dot-sources or calls a public
    focused command therefore cannot stand in for the host executable lookup, the request
    encoder, the containment, or the supervisor itself.

    Containment is native and owned. On Linux the child is launched through a physically
    validated absolute `setsid` so it leads its own session and process group, confirmed by a
    native `getpgid`; termination is a native negative-PGID `SIGKILL`. On Windows the child is
    assigned to a Job Object configured kill-on-close, and the assignment completes before the
    child is released by the stdin request handshake. Containment that cannot be established
    fails closed: no work runs that the supervisor could not terminate.

    One monotonic wall-clock deadline spans process start, request handoff, root exit, stdout
    EOF and stderr EOF. A root that exits after spawning a descendant which retains the output
    pipes still hits that deadline, and no completed-task result is read after an incomplete
    timed wait.
#>

# ---------------------------------------------------------------------------
# Request encoding. `ConvertTo-Json` is a command and a command is resolvable by
# the caller, so the request is written here with .NET primitives only. Everything
# outside printable ASCII is escaped: the child reads stdin under whatever console
# encoding it inherits, and a request carrying a non-ASCII path must be identical
# on both sides.
# ---------------------------------------------------------------------------

$writeJsonString = {
    param([string]$Text, [System.Text.StringBuilder]$Builder)

    [void]$Builder.Append('"')
    foreach ($character in $Text.ToCharArray()) {
        $code = [int]$character
        if ($character -eq '"') { [void]$Builder.Append('\"') }
        elseif ($character -eq '\') { [void]$Builder.Append('\\') }
        elseif ($code -lt 32 -or $code -gt 126) {
            [void]$Builder.Append('\u')
            [void]$Builder.Append($code.ToString('x4', [System.Globalization.CultureInfo]::InvariantCulture))
        }
        else { [void]$Builder.Append($character) }
    }
    [void]$Builder.Append('"')
}

$writeJsonValue = {
    param($Value, [System.Text.StringBuilder]$Builder, $Self, $StringWriter)

    if ($null -eq $Value) { [void]$Builder.Append('null'); return }
    if ($Value -is [string]) { & $StringWriter $Value $Builder; return }
    if ($Value -is [bool]) {
        [void]$Builder.Append($(if ($Value) { 'true' } else { 'false' }))
        return
    }
    if ($Value -is [System.Collections.IDictionary]) {
        [void]$Builder.Append('{')
        $isFirst = $true
        foreach ($key in $Value.Keys) {
            if (-not $isFirst) { [void]$Builder.Append(',') }
            $isFirst = $false
            & $StringWriter ([string]$key) $Builder
            [void]$Builder.Append(':')
            & $Self $Value[$key] $Builder $Self $StringWriter
        }
        [void]$Builder.Append('}')
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        [void]$Builder.Append('[')
        $isFirst = $true
        foreach ($item in $Value) {
            if (-not $isFirst) { [void]$Builder.Append(',') }
            $isFirst = $false
            & $Self $item $Builder $Self $StringWriter
        }
        [void]$Builder.Append(']')
        return
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        [void]$Builder.Append([System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture))
        return
    }
    & $StringWriter ([string]$Value) $Builder
}

$convertToRequestJson = {
    param([System.Collections.IDictionary]$Request)

    $builder = [System.Text.StringBuilder]::new()
    & $writeJsonValue $Request $builder $writeJsonValue $writeJsonString
    return $builder.ToString()
}.GetNewClosure()

$convertFromJsonElement = {
    param($Element, $Self)

    $kind = $Element.ValueKind
    if ($kind -eq [System.Text.Json.JsonValueKind]::Object) {
        $map = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            $map[$property.Name] = (& $Self $property.Value $Self)
        }
        return $map
    }
    if ($kind -eq [System.Text.Json.JsonValueKind]::Array) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Element.EnumerateArray()) {
            [void]$items.Add((& $Self $item $Self))
        }
        return , $items.ToArray()
    }
    if ($kind -eq [System.Text.Json.JsonValueKind]::String) { return $Element.GetString() }
    if ($kind -eq [System.Text.Json.JsonValueKind]::True) { return $true }
    if ($kind -eq [System.Text.Json.JsonValueKind]::False) { return $false }
    if ($kind -eq [System.Text.Json.JsonValueKind]::Number) {
        $integer = 0
        if ($Element.TryGetInt32([ref]$integer)) { return $integer }
        return $Element.GetDouble()
    }
    return $null
}

$readBodyRequest = {
    $raw = [System.Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'No supervised request was supplied on stdin.'
    }
    $document = [System.Text.Json.JsonDocument]::Parse($raw)
    try {
        return (& $convertFromJsonElement $document.RootElement $convertFromJsonElement)
    }
    finally {
        $document.Dispose()
    }
}.GetNewClosure()

# ---------------------------------------------------------------------------
# Native containment primitives. `Add-Type` is a command, so the delegate types are
# emitted directly through System.Reflection.Emit and bound to exported entry points
# with NativeLibrary/Marshal. No process-control command name is used anywhere.
# ---------------------------------------------------------------------------

$nativeState = @{}

$defineNativeDelegate = {
    param($ModuleBuilder, [string]$Name, [Type]$ReturnType, [Type[]]$ParameterTypes)

    $typeAttributes = [System.Reflection.TypeAttributes]::Public -bor
        [System.Reflection.TypeAttributes]::Sealed -bor
        [System.Reflection.TypeAttributes]::AnsiClass -bor
        [System.Reflection.TypeAttributes]::AutoClass
    $typeBuilder = $ModuleBuilder.DefineType($Name, $typeAttributes, [System.MulticastDelegate])

    $constructor = $typeBuilder.DefineConstructor(
        ([System.Reflection.MethodAttributes]::RTSpecialName -bor
            [System.Reflection.MethodAttributes]::HideBySig -bor
            [System.Reflection.MethodAttributes]::Public),
        [System.Reflection.CallingConventions]::Standard,
        [Type[]]@([object], [System.IntPtr]))
    $constructor.SetImplementationFlags(
        [System.Reflection.MethodImplAttributes]::Runtime -bor
        [System.Reflection.MethodImplAttributes]::Managed)

    $invoke = $typeBuilder.DefineMethod('Invoke',
        ([System.Reflection.MethodAttributes]::Public -bor
            [System.Reflection.MethodAttributes]::HideBySig -bor
            [System.Reflection.MethodAttributes]::NewSlot -bor
            [System.Reflection.MethodAttributes]::Virtual),
        $ReturnType, $ParameterTypes)
    $invoke.SetImplementationFlags(
        [System.Reflection.MethodImplAttributes]::Runtime -bor
        [System.Reflection.MethodImplAttributes]::Managed)

    return $typeBuilder.CreateType()
}

$bindNativeContainment = {
    if ($nativeState.ContainsKey('Bound')) { return $nativeState['Bound'] }

    $assemblyName = [System.Reflection.AssemblyName]::new('SkalaryFocusedContainment')
    $assembly = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        $assemblyName, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $module = $assembly.DefineDynamicModule('SkalaryFocusedContainmentModule')
    $bound = @{}

    if ([System.OperatingSystem]::IsWindows()) {
        $library = [System.Runtime.InteropServices.NativeLibrary]::Load('kernel32.dll')
        $entries = @(
            @{ Key = 'CreateJobObject'; Export = 'CreateJobObjectW'; Return = [System.IntPtr]; Parameters = [Type[]]@([System.IntPtr], [System.IntPtr]) },
            @{ Key = 'SetInformationJobObject'; Export = 'SetInformationJobObject'; Return = [int]; Parameters = [Type[]]@([System.IntPtr], [int], [System.IntPtr], [uint32]) },
            @{ Key = 'AssignProcessToJobObject'; Export = 'AssignProcessToJobObject'; Return = [int]; Parameters = [Type[]]@([System.IntPtr], [System.IntPtr]) },
            @{ Key = 'TerminateJobObject'; Export = 'TerminateJobObject'; Return = [int]; Parameters = [Type[]]@([System.IntPtr], [uint32]) },
            @{ Key = 'CloseHandle'; Export = 'CloseHandle'; Return = [int]; Parameters = [Type[]]@([System.IntPtr]) }
        )
    }
    else {
        $library = [System.IntPtr]::Zero
        foreach ($candidate in @('libc', 'libc.so.6', 'libSystem.dylib')) {
            $handle = [System.IntPtr]::Zero
            if ([System.Runtime.InteropServices.NativeLibrary]::TryLoad($candidate, [ref]$handle)) {
                $library = $handle
                break
            }
        }
        if ($library -eq [System.IntPtr]::Zero) {
            throw 'FocusedContainmentUnavailable: the C runtime exporting getpgid/kill could not be loaded.'
        }
        $entries = @(
            @{ Key = 'Kill'; Export = 'kill'; Return = [int]; Parameters = [Type[]]@([int], [int]) },
            @{ Key = 'Getpgid'; Export = 'getpgid'; Return = [int]; Parameters = [Type[]]@([int]) }
        )
    }

    foreach ($entry in $entries) {
        $delegateType = & $defineNativeDelegate $module ('SkalaryNative' + $entry.Key) $entry.Return $entry.Parameters
        $export = [System.Runtime.InteropServices.NativeLibrary]::GetExport($library, $entry.Export)
        $bound[$entry.Key] = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($export, $delegateType)
    }

    $nativeState['Bound'] = $bound
    return $bound
}.GetNewClosure()

# ---------------------------------------------------------------------------
# Host executable and session launcher resolution. Both are absolute paths taken from
# the runtime and physically validated as existing leaves; neither is a command name a
# caller could resolve to something else.
# ---------------------------------------------------------------------------

$resolveHostExecutable = {
    $candidate = [System.Environment]::ProcessPath
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        throw 'FocusedContainmentUnavailable: the running PowerShell host reported no executable path.'
    }
    if (-not [System.IO.Path]::IsPathFullyQualified($candidate)) {
        throw "FocusedContainmentUnavailable: the host executable path '$candidate' is not absolute."
    }
    if ($candidate -cne [System.IO.Path]::GetFullPath($candidate)) {
        throw "FocusedContainmentUnavailable: the host executable path '$candidate' is not canonical."
    }
    if (-not [System.IO.File]::Exists($candidate)) {
        throw "FocusedContainmentUnavailable: the host executable path '$candidate' is not an existing file."
    }
    $leaf = [System.IO.Path]::GetFileName($candidate)
    $expected = $(if ([System.OperatingSystem]::IsWindows()) { 'pwsh.exe' } else { 'pwsh' })
    if (-not [string]::Equals($leaf, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "FocusedContainmentUnavailable: the host executable leaf '$leaf' is not the expected '$expected'."
    }
    return $candidate
}

$resolveSessionLauncher = {
    # Absolute literals only. A PATH lookup or a bare command name would be exactly the
    # resolution the caller can poison, and the launcher is what owns the child's session.
    foreach ($candidate in @('/usr/bin/setsid', '/bin/setsid', '/usr/local/bin/setsid')) {
        if ([System.IO.File]::Exists($candidate)) { return $candidate }
    }
    return ''
}

$confirmProcessGroup = {
    param($Native, $Process)

    # setsid() runs in the forked child, so the new group id is observable a moment after
    # Start returns. Poll for it rather than sampling once and mistaking the race for a
    # containment failure — but never release the child until it is observed.
    $observedClock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($observedClock.ElapsedMilliseconds -lt 5000) {
        $groupId = [int]$Native['Getpgid'].DynamicInvoke([int]$Process.Id)
        if ($groupId -eq $Process.Id) { return $groupId }
        if ($Process.HasExited) { break }
        [System.Threading.Thread]::Sleep(10)
    }
    throw ('FocusedContainmentUnavailable: the focused child did not lead its own process ' +
        "group, so its descendants could not be owned (pid $($Process.Id)).")
}

$startContainedProcess = {
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$LauncherPath
    )

    $onWindows = [System.OperatingSystem]::IsWindows()

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

    if ($onWindows) {
        if ([System.IntPtr]::Size -ne 8) {
            throw 'FocusedContainmentUnavailable: a 64-bit host is required to own the focused job object.'
        }
        $startInfo.FileName = $ExecutablePath
        foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
    }
    else {
        $launcher = $LauncherPath
        if ([string]::IsNullOrWhiteSpace($launcher)) { $launcher = & $resolveSessionLauncher }
        if ([string]::IsNullOrWhiteSpace($launcher) -or
            -not [System.IO.Path]::IsPathFullyQualified($launcher) -or
            $launcher -cne [System.IO.Path]::GetFullPath($launcher) -or
            -not [System.IO.File]::Exists($launcher)) {
            throw ('FocusedContainmentUnavailable: no validated absolute session launcher was ' +
                "found ('$launcher'), so the focused child's descendants could not be owned.")
        }
        $startInfo.FileName = $launcher
        [void]$startInfo.ArgumentList.Add($ExecutablePath)
        foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $jobHandle = [System.IntPtr]::Zero
    $processGroupId = 0
    $native = $null
    $stdoutTask = $null
    $stderrTask = $null

    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $native = & $bindNativeContainment
        if ($onWindows) {
            $jobHandle = [System.IntPtr]$native['CreateJobObject'].DynamicInvoke(
                [System.IntPtr]::Zero, [System.IntPtr]::Zero)
            if ($jobHandle -eq [System.IntPtr]::Zero) {
                throw 'FocusedContainmentUnavailable: the focused job object could not be created.'
            }

            # JOBOBJECT_EXTENDED_LIMIT_INFORMATION is 144 bytes on a 64-bit host; LimitFlags
            # sits at offset 16 and JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE is 0x2000, so releasing
            # the handle kills anything still inside the job.
            $information = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(144)
            try {
                for ($offset = 0; $offset -lt 144; $offset += 8) {
                    [System.Runtime.InteropServices.Marshal]::WriteInt64($information, $offset, [long]0)
                }
                [System.Runtime.InteropServices.Marshal]::WriteInt32($information, 16, 0x2000)
                $configured = [int]$native['SetInformationJobObject'].DynamicInvoke(
                    $jobHandle, [int]9, $information, [uint32]144)
                if ($configured -eq 0) {
                    throw 'FocusedContainmentUnavailable: the focused job object could not be set kill-on-close.'
                }
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::FreeHGlobal($information)
            }

            $assigned = [int]$native['AssignProcessToJobObject'].DynamicInvoke($jobHandle, $process.Handle)
            if ($assigned -eq 0) {
                throw 'FocusedContainmentUnavailable: the focused child could not be assigned to its job object.'
            }
        }
        else {
            $processGroupId = & $confirmProcessGroup $native $process
        }
    }
    catch {
        # Fail closed. Nothing may keep running that this supervisor could not terminate, and
        # the child is still blocked on its unwritten stdin request, so it has done no work.
        try { if (-not $process.HasExited) { $process.Kill($true) } } catch { }
        if ($jobHandle -ne [System.IntPtr]::Zero -and $null -ne $native) {
            [void]$native['TerminateJobObject'].DynamicInvoke($jobHandle, [uint32]13)
            [void]$native['CloseHandle'].DynamicInvoke($jobHandle)
        }
        try { $process.Dispose() } catch { }
        throw
    }

    $terminate = {
        if ($onWindows) {
            if ($jobHandle -ne [System.IntPtr]::Zero) {
                [void]$native['TerminateJobObject'].DynamicInvoke($jobHandle, [uint32]13)
            }
        }
        elseif ($processGroupId -gt 1) {
            # Negative pid is the whole process group: the root and every descendant it left
            # behind, and nothing outside the session this supervisor created.
            [void]$native['Kill'].DynamicInvoke([int](-$processGroupId), [int]9)
        }
    }.GetNewClosure()

    $dispose = {
        try { & $terminate } catch { }
        if ($jobHandle -ne [System.IntPtr]::Zero) {
            [void]$native['CloseHandle'].DynamicInvoke($jobHandle)
        }
        try { $process.Dispose() } catch { }
    }.GetNewClosure()

    return @{
        Process = $process
        ProcessGroupId = $processGroupId
        JobHandle = $jobHandle
        StdoutTask = $stdoutTask
        StderrTask = $stderrTask
        Terminate = $terminate
        Dispose = $dispose
    }
}.GetNewClosure()

# ---------------------------------------------------------------------------
# Supervision.
# ---------------------------------------------------------------------------

$waitBounded = {
    param($Task, [int]$Milliseconds)

    # A faulted task counts as finished; IsCompletedSuccessfully is what gates reading it, so
    # a result is never demanded from a wait that did not complete.
    try { return [bool]$Task.Wait($Milliseconds) } catch { return $true }
}

$writeChildOutput = {
    param($StdoutTask, $StderrTask)

    if ($null -ne $StdoutTask -and $StdoutTask.IsCompletedSuccessfully) {
        $text = $StdoutTask.GetAwaiter().GetResult()
        if ($text) { [System.Console]::Out.Write($text) }
    }
    [System.Console]::Out.Flush()
    if ($null -ne $StderrTask -and $StderrTask.IsCompletedSuccessfully) {
        $text = $StderrTask.GetAwaiter().GetResult()
        if ($text) { [System.Console]::Error.Write($text) }
    }
    [System.Console]::Error.Flush()
}

$invokeSupervisedBody = {
    param(
        [Parameter(Mandatory)][string]$BodyPath,
        [Parameter(Mandatory)][hashtable]$Request,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][double]$WarningSeconds,
        [Parameter(Mandatory)][double]$TimeoutSeconds
    )

    $requestJson = & $convertToRequestJson $Request

    # One monotonic clock, started before anything can block, covers every phase below.
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $limitMilliseconds = [long][math]::Ceiling($TimeoutSeconds * 1000)
    $remaining = {
        $left = $limitMilliseconds - $clock.ElapsedMilliseconds
        if ($left -lt 0) { return [int]0 }
        if ($left -gt [int]::MaxValue) { return [int]::MaxValue }
        return [int]$left
    }.GetNewClosure()

    $containment = $null
    try {
        $hostExecutable = & $resolveHostExecutable
        $containment = & $startContainedProcess `
            -ExecutablePath $hostExecutable `
            -Arguments @('-NoProfile', '-NonInteractive', '-OutputFormat', 'Text', '-File', $BodyPath)
    }
    catch {
        [System.Console]::Out.WriteLine(
            "$Label refused to run because its process containment could not be " +
            "established: $($_.Exception.Message)")
        return 14
    }

    $process = $containment.Process
    $stdoutTask = $containment.StdoutTask
    $stderrTask = $containment.StderrTask
    $timedOut = $false
    $exitCode = 0

    try {
        # Request handoff. The child is blocked reading stdin until this completes, so the
        # containment above is already established before any work is released.
        try {
            $writeTask = $process.StandardInput.WriteAsync($requestJson)
            if (-not (& $waitBounded $writeTask (& $remaining))) { $timedOut = $true }
            if (-not $timedOut) {
                $flushTask = $process.StandardInput.FlushAsync()
                if (-not (& $waitBounded $flushTask (& $remaining))) { $timedOut = $true }
            }
        }
        catch {
            # The child exited before reading its request; its own exit code is the verdict.
        }
        finally {
            try { $process.StandardInput.Close() } catch { }
        }

        if (-not $timedOut -and -not $process.WaitForExit((& $remaining))) { $timedOut = $true }
        # Root exit is not completion. A descendant holding the inherited pipes keeps the run
        # alive, and it is measured against the same deadline rather than a fresh one.
        if (-not $timedOut -and -not (& $waitBounded $stdoutTask (& $remaining))) { $timedOut = $true }
        if (-not $timedOut -and -not (& $waitBounded $stderrTask (& $remaining))) { $timedOut = $true }

        if ($timedOut) {
            & $containment.Terminate
            [void]$process.WaitForExit(5000)
            # Bounded drain after termination so whatever the run did produce is still reported.
            [void](& $waitBounded $stdoutTask 2000)
            [void](& $waitBounded $stderrTask 2000)
            & $writeChildOutput $stdoutTask $stderrTask
            [System.Console]::Out.WriteLine(
                "FocusedTimeout: $Label exceeded $TimeoutSeconds seconds; the owned process group was terminated.")
            return 13
        }

        & $writeChildOutput $stdoutTask $stderrTask
        $exitCode = $process.ExitCode
    }
    finally {
        $clock.Stop()
        & $containment.Dispose
    }

    if ($clock.Elapsed.TotalSeconds -ge $WarningSeconds -and
        $clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        [System.Console]::Error.WriteLine(
            "WARNING: FocusedSlow: $Label completed in $([math]::Round($clock.Elapsed.TotalSeconds, 3))s (target <${WarningSeconds}s).")
        [System.Console]::Error.Flush()
    }

    return $exitCode
}.GetNewClosure()

return @{
    InvokeSupervisedBody = $invokeSupervisedBody
    ReadBodyRequest = $readBodyRequest
    ConvertToRequestJson = $convertToRequestJson
    ResolveHostExecutable = $resolveHostExecutable
    ResolveSessionLauncher = $resolveSessionLauncher
    StartContainedProcess = $startContainedProcess
}

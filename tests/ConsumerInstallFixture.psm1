#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SuiteFixture.psm1') -Force -DisableNameChecking

function Get-ConsumerInstallSha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ConsumerInstallCanonicalSha256 {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $Path).Replace('\', '/')
    $output = @(& git -C $RepoRoot hash-object -w "--path=$relative" -- $Path 2>&1)
    $objectId = @($output | ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ -cmatch '^[0-9a-f]{40,64}$' } | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or $objectId.Count -ne 1) {
        throw "Unable to canonicalize fixture source '$relative': $($output -join ' ')"
    }

    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'
    $start.WorkingDirectory = $RepoRoot
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-C', $RepoRoot, 'cat-file', 'blob', [string]$objectId[0])) {
        [void]$start.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::Start($start)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($process.StandardOutput.BaseStream)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw $errorText }
        return [Convert]::ToHexString($hash).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $process.Dispose()
    }
}

function Test-ConsumerInstallDestination {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Destination)

    if ([string]::IsNullOrWhiteSpace($Destination) -or
        $Destination.StartsWith('/') -or
        $Destination.StartsWith('\') -or
        $Destination -match '^[A-Za-z]:' -or
        $Destination -match '\\\\' -or
        $Destination.Contains(':')) {
        return $false
    }

    return -not (($Destination -replace '\\', '/').Split(
            '/',
            [System.StringSplitOptions]::RemoveEmptyEntries
        ) -contains '..')
}

function Get-ConsumerInstallManifestCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceRepoRoot)

    $sourceRoot = [System.IO.Path]::GetFullPath($SourceRepoRoot)
    $pluginsRoot = Join-Path $sourceRoot 'plugins'
    $manifestPaths = @(
        Get-ChildItem -LiteralPath $pluginsRoot -Recurse -File -Filter 'plugin.json' |
            Sort-Object FullName
    )
    if ($manifestPaths.Count -eq 0) {
        throw "No active plugin manifests found under '$pluginsRoot'."
    }

    $plugins = [System.Collections.Generic.List[object]]::new()
    $files = [System.Collections.Generic.List[object]]::new()
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($manifestPath in $manifestPaths) {
        $manifest = Get-Content -LiteralPath $manifestPath.FullName -Raw |
            ConvertFrom-Json -Depth 100
        $pluginName = [string]$manifest.name
        if ([string]::IsNullOrWhiteSpace($pluginName) -or -not $names.Add($pluginName)) {
            throw "Plugin manifest '$($manifestPath.FullName)' has an empty or duplicate name '$pluginName'."
        }
        if ($manifestPath.Directory.Name -cne $pluginName) {
            throw "Plugin manifest name '$pluginName' does not match folder '$($manifestPath.Directory.Name)'."
        }

        $pluginFiles = [System.Collections.Generic.List[object]]::new()
        foreach ($mapping in @($manifest.files)) {
            $src = [string]$mapping.src
            $dest = [string]$mapping.dest
            $sourcePath = Join-Path $manifestPath.Directory.FullName (
                $src -replace '/', [System.IO.Path]::DirectorySeparatorChar
            )
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Manifest source '$pluginName/$src' does not exist."
            }

            $record = [pscustomobject]@{
                Plugin     = $pluginName
                Src        = $src
                Dest       = $dest
                Sha256     = Get-ConsumerInstallCanonicalSha256 -RepoRoot $sourceRoot -Path $sourcePath
                Install    = $src -notmatch '^evals(?:/|$)'
                SourcePath = [System.IO.Path]::GetFullPath($sourcePath)
            }
            $pluginFiles.Add($record)
            $files.Add($record)
        }

        $plugins.Add([pscustomobject]@{
                Name         = $pluginName
                Version      = [string]$manifest.version
                Status       = if ($manifest.PSObject.Properties.Name -contains 'status') {
                    [string]$manifest.status
                }
                else {
                    'stable'
                }
                Dependencies = @($manifest.dependencies | ForEach-Object { [string]$_ })
                Scaffolds    = if ($manifest.PSObject.Properties.Name -contains 'scaffolds') {
                    @($manifest.scaffolds)
                }
                else {
                    @()
                }
                Files        = @($pluginFiles)
                ManifestPath = $manifestPath.FullName
            })
    }

    return [pscustomobject]@{
        SourceRepoRoot = $sourceRoot
        Plugins        = @($plugins)
        Files          = @($files)
        PluginNames    = @($plugins | ForEach-Object { [string]$_.Name })
    }
}

function Get-ConsumerInstallDependencyClosure {
    param(
        [Parameter(Mandatory)]$Catalog,
        [Parameter(Mandatory)][string]$PluginName
    )

    $pluginsByName = @{}
    foreach ($plugin in @($Catalog.Plugins)) {
        $pluginsByName[[string]$plugin.Name] = $plugin
    }
    $closure = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    function Add-ConsumerInstallDependency {
        param([Parameter(Mandatory)][string]$Name)

        if (-not $pluginsByName.ContainsKey($Name)) {
            throw "Active plugin dependency '$Name' has no manifest."
        }
        if (-not $closure.Add($Name)) {
            return
        }
        foreach ($dependency in @($pluginsByName[$Name].Dependencies)) {
            Add-ConsumerInstallDependency -Name ([string]$dependency)
        }
    }

    Add-ConsumerInstallDependency -Name $PluginName
    return [string[]]@($closure | Sort-Object)
}

function Get-ConsumerInstallOrder {
    param([Parameter(Mandatory)]$Catalog)

    $pluginsByName = @{}
    foreach ($plugin in @($Catalog.Plugins)) {
        $pluginsByName[[string]$plugin.Name] = $plugin
    }
    $state = @{}
    $dependencyFirst = [System.Collections.Generic.List[string]]::new()

    function Visit-ConsumerInstallPlugin {
        param([Parameter(Mandatory)][string]$Name)

        if (-not $pluginsByName.ContainsKey($Name)) {
            throw "Active plugin dependency '$Name' has no manifest."
        }
        $current = if ($state.ContainsKey($Name)) { [int]$state[$Name] } else { 0 }
        if ($current -eq 1) {
            throw "Active plugin dependency cycle includes '$Name'."
        }
        if ($current -eq 2) {
            return
        }

        $state[$Name] = 1
        foreach ($dependency in @($pluginsByName[$Name].Dependencies | Sort-Object)) {
            Visit-ConsumerInstallPlugin -Name ([string]$dependency)
        }
        $state[$Name] = 2
        $dependencyFirst.Add($Name)
    }

    foreach ($name in @($Catalog.PluginNames | Sort-Object)) {
        Visit-ConsumerInstallPlugin -Name ([string]$name)
    }
    $installOrder = $dependencyFirst.ToArray()
    [array]::Reverse($installOrder)
    return [string[]]$installOrder
}

function New-ConsumerInstallFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceRepoRoot)

    $sourceRoot = [System.IO.Path]::GetFullPath($SourceRepoRoot)
    $catalog = Get-ConsumerInstallManifestCatalog -SourceRepoRoot $sourceRoot
    $root = New-SkalaryFixtureRoot -Prefix 'skalary-foreign-consumer'
    try {
        & git init -q $root
        if ($LASTEXITCODE -ne 0) {
            throw "git init failed for foreign consumer fixture '$root'."
        }

        $poisonRelativePaths = @(
            'plugins/.skalary-source-path-poison'
            'schemas/.skalary-source-path-poison'
            'scripts/skalary/.skalary-source-path-poison'
        )
        foreach ($relativePath in $poisonRelativePaths) {
            $path = Join-Path $root ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
            Set-Content -LiteralPath $path -Value 'SKALARY_SOURCE_PATH_POISON' -NoNewline -Encoding utf8NoBOM
        }

        $installer = Join-Path $sourceRoot 'scripts/skalary/Install-Plugin.ps1'
        $installResults = [System.Collections.Generic.List[object]]::new()
        foreach ($pluginName in (Get-ConsumerInstallOrder -Catalog $catalog)) {
            $receiptsRoot = Join-Path $root '.github/.skalary/receipts'
            $beforeReceipts = if (Test-Path -LiteralPath $receiptsRoot -PathType Container) {
                @(Get-ChildItem -LiteralPath $receiptsRoot -File -Filter '*.json' |
                        ForEach-Object { $_.BaseName })
            }
            else {
                @()
            }
            $result = Invoke-SuiteFixtureProcess -WorkingDirectory $root -TimeoutSeconds 120 -ArgumentList @(
                '-NoProfile'
                '-File'
                $installer
                '-Name'
                $pluginName
                '-RepoRoot'
                $root
                '-Source'
                $sourceRoot
                '-Ref'
                'HEAD'
            )
            if ($result.ExitCode -ne 0) {
                throw "Production install failed for '$pluginName' (exit $($result.ExitCode)): $($result.Output)"
            }
            $afterReceipts = @(
                Get-ChildItem -LiteralPath $receiptsRoot -File -Filter '*.json' |
                    ForEach-Object { $_.BaseName }
            )
            $expectedReceipts = Get-ConsumerInstallDependencyClosure -Catalog $catalog -PluginName $pluginName
            $missingReceipts = @($expectedReceipts | Where-Object { $_ -notin $afterReceipts })
            if ($missingReceipts.Count -gt 0) {
                throw "Production install for '$pluginName' omitted dependency receipt(s): $($missingReceipts -join ', ')."
            }
            $installResults.Add([pscustomobject]@{
                    Plugin               = $pluginName
                    ExitCode             = $result.ExitCode
                    Output               = $result.Output
                    ExpectedReceiptNames = $expectedReceipts
                    NewReceiptNames      = @($afterReceipts | Where-Object { $_ -notin $beforeReceipts })
                })
        }

        $registry = Get-Content -LiteralPath (Join-Path $sourceRoot 'registry.json') -Raw |
            ConvertFrom-Json -Depth 100
        return [pscustomobject]@{
            Root                = $root
            SourceRepoRoot      = $sourceRoot
            Catalog             = $catalog
            Registry            = $registry
            PoisonRelativePaths = $poisonRelativePaths
            InstallResults      = @($installResults)
        }
    }
    catch {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Test-ConsumerInstallInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Fixture,
        $Catalog = $Fixture.Catalog,
        $Registry = $Fixture.Registry
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    $extra = [System.Collections.Generic.List[string]]::new()
    $hashMismatched = [System.Collections.Generic.List[string]]::new()
    $escaping = [System.Collections.Generic.List[string]]::new()
    $staleMappings = [System.Collections.Generic.List[string]]::new()
    $receiptMismatches = [System.Collections.Generic.List[string]]::new()
    $dependencyMismatches = [System.Collections.Generic.List[string]]::new()
    $outsideWrites = [System.Collections.Generic.List[string]]::new()

    $expectedByDest = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    $expectedDestCase = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($file in @($Catalog.Files)) {
        $dest = [string]$file.Dest
        if (-not (Test-ConsumerInstallDestination -Destination $dest)) {
            $escaping.Add("$([string]$file.Plugin):$dest")
            continue
        }
        if (-not [bool]$file.Install) {
            continue
        }
        if ($expectedDestCase.ContainsKey($dest) -and $expectedDestCase[$dest] -cne $dest) {
            $staleMappings.Add(
                "manifest destinations '$($expectedDestCase[$dest])' and '$dest' differ only by case"
            )
        }
        else {
            $expectedDestCase[$dest] = $dest
        }
        if ($expectedByDest.ContainsKey($dest)) {
            $staleMappings.Add("duplicate manifest destination '$dest'")
            continue
        }
        $expectedByDest[$dest] = $file
    }

    $githubRoot = Join-Path $Fixture.Root '.github'
    $actualByDest = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::Ordinal
    )
    if (Test-Path -LiteralPath $githubRoot -PathType Container) {
        foreach ($actual in Get-ChildItem -LiteralPath $githubRoot -Recurse -File -Force) {
            $relative = [System.IO.Path]::GetRelativePath($githubRoot, $actual.FullName).Replace('\', '/')
            if ($relative -eq '.skalary' -or $relative.StartsWith('.skalary/')) {
                continue
            }
            $actualByDest[$relative] = $actual.FullName
        }
    }

    foreach ($dest in $expectedByDest.Keys) {
        if (-not $actualByDest.ContainsKey($dest)) {
            $missing.Add($dest)
            continue
        }
        $actualHash = Get-ConsumerInstallSha256 -Path $actualByDest[$dest]
        if ($actualHash -cne [string]$expectedByDest[$dest].Sha256) {
            $hashMismatched.Add($dest)
        }
    }
    foreach ($dest in $actualByDest.Keys) {
        if (-not $expectedByDest.ContainsKey($dest)) {
            $extra.Add($dest)
        }
    }

    $expectedOutside = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($relative in @($Fixture.PoisonRelativePaths)) {
        [void]$expectedOutside.Add([string]$relative)
    }
    foreach ($child in Get-ChildItem -LiteralPath $Fixture.Root -Force) {
        if ($child.Name -ceq '.git' -or $child.Name -ceq '.github') {
            continue
        }
        $outsideFiles = if ($child.PSIsContainer) {
            @(Get-ChildItem -LiteralPath $child.FullName -Recurse -File -Force)
        }
        else {
            @($child)
        }
        foreach ($outsideFile in $outsideFiles) {
            $relative = [System.IO.Path]::GetRelativePath($Fixture.Root, $outsideFile.FullName).Replace('\', '/')
            if (-not $expectedOutside.Contains($relative)) {
                $outsideWrites.Add($relative)
            }
        }
    }

    $registryByName = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($plugin in @($Registry.plugins)) {
        $name = [string]$plugin.name
        if ($registryByName.ContainsKey($name)) {
            $staleMappings.Add("registry contains duplicate plugin '$name'")
            continue
        }
        $registryByName[$name] = $plugin
    }
    $catalogByName = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($plugin in @($Catalog.Plugins)) {
        $name = [string]$plugin.Name
        $catalogByName[$name] = $plugin
        if (-not $registryByName.ContainsKey($name)) {
            $staleMappings.Add("$name is missing from registry.json")
            continue
        }

        $registryPlugin = $registryByName[$name]
        if ([string]$registryPlugin.version -cne [string]$plugin.Version) {
            $staleMappings.Add("$name version differs between manifest and registry")
        }
        $manifestDependencies = @($plugin.Dependencies | Sort-Object)
        $registryDependencies = @($registryPlugin.dependencies | ForEach-Object { [string]$_ } | Sort-Object)
        if (($manifestDependencies -join "`n") -cne ($registryDependencies -join "`n")) {
            $staleMappings.Add("$name dependencies differ between manifest and registry")
        }

        $registryFiles = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($file in @($registryPlugin.files)) {
            $key = "$([string]$file.src)|$([string]$file.dest)"
            if ($registryFiles.ContainsKey($key)) {
                $staleMappings.Add("$name registry contains duplicate mapping '$key'")
                continue
            }
            $registryFiles[$key] = $file
        }
        $manifestFiles = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($file in @($plugin.Files)) {
            $key = "$([string]$file.Src)|$([string]$file.Dest)"
            if ($manifestFiles.ContainsKey($key)) {
                $staleMappings.Add("$name manifest contains duplicate mapping '$key'")
                continue
            }
            $manifestFiles[$key] = $file
            if (-not $registryFiles.ContainsKey($key)) {
                $staleMappings.Add("$name registry mapping missing '$key'")
            }
            elseif ([string]$registryFiles[$key].sha256 -cne [string]$file.Sha256) {
                $staleMappings.Add("$name registry hash stale for '$key'")
            }
        }
        foreach ($key in $registryFiles.Keys) {
            if (-not $manifestFiles.ContainsKey($key)) {
                $staleMappings.Add("$name registry has stale mapping '$key'")
            }
        }
    }
    foreach ($name in $registryByName.Keys) {
        if (-not $catalogByName.ContainsKey($name)) {
            $staleMappings.Add("$name exists in registry without an active manifest")
        }
    }

    $receiptsRoot = Join-Path $Fixture.Root '.github/.skalary/receipts'
    $receiptByName = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    if (Test-Path -LiteralPath $receiptsRoot -PathType Container) {
        foreach ($receiptPath in Get-ChildItem -LiteralPath $receiptsRoot -File -Filter '*.json') {
            $receipt = Get-Content -LiteralPath $receiptPath.FullName -Raw | ConvertFrom-Json -Depth 100
            $receiptName = [string]$receipt.name
            if ($receiptPath.BaseName -cne $receiptName) {
                $receiptMismatches.Add(
                    "receipt file '$($receiptPath.Name)' embeds plugin name '$receiptName'"
                )
            }
            if ($receiptByName.ContainsKey($receiptName)) {
                $receiptMismatches.Add("duplicate receipt name '$receiptName'")
                continue
            }
            $receiptByName[$receiptName] = $receipt
        }
    }
    foreach ($plugin in @($Catalog.Plugins)) {
        $name = [string]$plugin.Name
        if (-not $receiptByName.ContainsKey($name)) {
            $receiptMismatches.Add("$name receipt is missing")
            continue
        }
        $receipt = $receiptByName[$name]
        if ([string]$receipt.version -cne [string]$plugin.Version) {
            $receiptMismatches.Add("$name receipt version is stale")
        }
        $receiptFiles = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($file in @($receipt.files)) {
            $dest = [string]$file.dest
            if ($receiptFiles.ContainsKey($dest)) {
                $receiptMismatches.Add("$name receipt contains duplicate mapping '$dest'")
                continue
            }
            $receiptFiles[$dest] = $file
        }
        $installedFiles = @($plugin.Files | Where-Object { [bool]$_.Install })
        $installedDests = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($file in $installedFiles) {
            $dest = [string]$file.Dest
            [void]$installedDests.Add($dest)
            if (-not $receiptFiles.ContainsKey($dest)) {
                $receiptMismatches.Add("$name receipt mapping missing '$dest'")
            }
            elseif ([string]$receiptFiles[$dest].sha256 -cne [string]$file.Sha256) {
                $receiptMismatches.Add("$name receipt hash stale for '$dest'")
            }
        }
        foreach ($dest in $receiptFiles.Keys) {
            if (-not $installedDests.Contains($dest)) {
                $receiptMismatches.Add("$name receipt has extra mapping '$dest'")
            }
        }
        foreach ($dependency in @($plugin.Dependencies)) {
            if (-not $catalogByName.ContainsKey([string]$dependency)) {
                $dependencyMismatches.Add("$name depends on missing active plugin '$dependency'")
            }
            elseif (-not $receiptByName.ContainsKey([string]$dependency)) {
                $dependencyMismatches.Add("$name dependency '$dependency' was not installed")
            }
        }
    }
    foreach ($name in $receiptByName.Keys) {
        if (-not $catalogByName.ContainsKey($name)) {
            $receiptMismatches.Add("$name receipt has no active manifest")
        }
    }

    $issues = @(
        $missing
        $extra
        $hashMismatched
        $escaping
        $staleMappings
        $receiptMismatches
        $dependencyMismatches
        $outsideWrites
    )
    return [pscustomobject]@{
        IsClean              = @($issues | ForEach-Object { @($_) }).Count -eq 0
        Missing              = @($missing | Sort-Object)
        Extra                = @($extra | Sort-Object)
        HashMismatched       = @($hashMismatched | Sort-Object)
        Escaping             = @($escaping | Sort-Object)
        StaleMappings        = @($staleMappings | Sort-Object)
        ReceiptMismatches    = @($receiptMismatches | Sort-Object)
        DependencyMismatches = @($dependencyMismatches | Sort-Object)
        OutsideWrites        = @($outsideWrites | Sort-Object)
    }
}

function Test-ConsumerRuntimeReferenceClosure {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture)

    $syncScript = Join-Path $Fixture.SourceRepoRoot 'scripts/skalary/Sync-PluginScripts.ps1'
    $staticScan = Invoke-SuiteFixtureProcess `
        -WorkingDirectory $Fixture.SourceRepoRoot `
        -TimeoutSeconds 120 `
        -ArgumentList @(
        '-NoProfile'
        '-File'
        $syncScript
        '-RepoRoot'
        $Fixture.SourceRepoRoot
        '-WhatIf'
    )
    $inventory = Test-ConsumerInstallInventory -Fixture $Fixture
    $changedPoison = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in @($Fixture.PoisonRelativePaths)) {
        $path = Join-Path $Fixture.Root (
            $relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
        )
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            [System.IO.File]::ReadAllText($path) -cne 'SKALARY_SOURCE_PATH_POISON') {
            $changedPoison.Add([string]$relativePath)
        }
    }

    return [pscustomobject]@{
        IsClean        = $staticScan.ExitCode -eq 0 -and $inventory.IsClean -and $changedPoison.Count -eq 0
        StaticExitCode = $staticScan.ExitCode
        StaticOutput   = $staticScan.Output
        Inventory      = $inventory
        ChangedPoison  = @($changedPoison)
    }
}

function Invoke-ConsumerInstalledSmokeMatrix {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture)

    $smokeRoot = Join-Path $Fixture.Root '.github/.skalary/consumer-smoke'
    [void](New-Item -ItemType Directory -Path $smokeRoot -Force)
    $results = [System.Collections.Generic.List[object]]::new()

    function Get-InstalledPath {
        param([Parameter(Mandatory)][string]$Destination)

        return Join-Path (Join-Path $Fixture.Root '.github') (
            $Destination -replace '/', [System.IO.Path]::DirectorySeparatorChar
        )
    }

    function Invoke-InstalledProcess {
        param([Parameter(Mandatory)][string[]]$ArgumentList)

        return Invoke-SuiteFixtureProcess `
            -WorkingDirectory $Fixture.Root `
            -TimeoutSeconds 30 `
            -ArgumentList $ArgumentList
    }

    try {
        foreach ($plugin in @($Fixture.Catalog.Plugins | Sort-Object Name)) {
            $name = [string]$plugin.Name
            $payload = @(
                $plugin.Files |
                    Where-Object { [bool]$_.Install } |
                    Sort-Object Dest |
                    Select-Object -First 1
            )
            if ($payload.Count -ne 1) {
                $results.Add([pscustomobject]@{
                        Plugin   = $name
                        Payload  = $null
                        Probe    = 'payload-load'
                        ExitCode = -1
                        Output   = 'no installed runtime payload declared'
                        IsClean  = $false
                    })
                continue
            }

            $payloadPath = Get-InstalledPath -Destination ([string]$payload[0].Dest)
            $payloadLoaded = (Test-Path -LiteralPath $payloadPath -PathType Leaf) -and
            (Get-ConsumerInstallSha256 -Path $payloadPath) -ceq [string]$payload[0].Sha256
            $probe = ''
            $process = $null
            $expectedExitCode = 0
            $expectedOutput = ''

            switch ($name) {
                'architecture-notes' {
                    $probe = 'canonical-contract-hash'
                    $contractPath = Join-Path $smokeRoot 'architecture-contract.json'
                    Set-Content -LiteralPath $contractPath `
                        -Value '{"z":1,"lockedContentSha256":"ignored","a":2}' `
                        -NoNewline -Encoding utf8NoBOM
                    $scriptPath = Get-InstalledPath -Destination (
                        'skills/architecture-notes/scripts/Get-ArchContractContentHash.ps1'
                    )
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-CommandWithArgs',
                        '(& $args[0] -ContractPath $args[1]).CanonicalJson',
                        $scriptPath, $contractPath
                    )
                    $expectedOutput = '{"a":2,"z":1}'
                }
                'autopilot' {
                    $probe = 'typed-file-evidence'
                    $scriptPath = Get-InstalledPath -Destination 'skills/autopilot/scripts/Test-Plan.ps1'
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-File', $scriptPath,
                        '-RepoRoot', $Fixture.Root,
                        '-EvidenceMarker', 'file:.github/skills/autopilot/SKILL.md#exists',
                        '-EvidenceStage', 'PhaseCrosscheck'
                    )
                    $expectedOutput = 'Evidence passed: file:.github/skills/autopilot/SKILL.md#exists'
                }
                'code-review' {
                    $probe = 'literal-review-scope'
                    $scriptPath = Get-InstalledPath -Destination 'agents/scripts/Get-ReviewScope.ps1'
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-File', $scriptPath,
                        '-Mode', 'paths',
                        '-Paths', '.github/skills/cr/SKILL.md',
                        '-RepoRoot', $Fixture.Root
                    )
                    $expectedOutput = '.github/skills/cr/SKILL.md'
                }
                'continue-implementation' {
                    $probe = 'plan-stage-resolution'
                    $modulePath = Get-InstalledPath -Destination 'skills/ci/scripts/PlanState.psm1'
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-CommandWithArgs',
                        'Import-Module $args[0] -Force; (Resolve-PlanStage -Stage $args[1]).Stage',
                        $modulePath, 'drafted'
                    )
                    $expectedOutput = 'drafted'
                }
                'create-implementation-plan' {
                    $probe = 'plan-stage-resolution'
                    $modulePath = Get-InstalledPath -Destination 'skills/cip/scripts/PlanState.psm1'
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-CommandWithArgs',
                        'Import-Module $args[0] -Force; (Resolve-PlanStage -Stage $args[1]).Stage',
                        $modulePath, 'drafted'
                    )
                    $expectedOutput = 'drafted'
                }
                'design-notes' {
                    $probe = 'skill-dispatch-contract'
                    $skillPath = Get-InstalledPath -Destination 'skills/design-notes/SKILL.md'
                    $templatePath = Get-InstalledPath -Destination (
                        'skills/design-notes/assets/templates/design-notes-index.template.md'
                    )
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-CommandWithArgs',
                        '$skill = [IO.File]::ReadAllText($args[0]); $template = [IO.File]::ReadAllText($args[1]); if ($skill -notmatch ''\| `update` \| \*\*Update\*\*'' -or $template -notmatch ''# Design Notes'') { throw ''installed design-notes dispatch contract is incomplete'' }; ''design-notes:update''',
                        $skillPath, $templatePath
                    )
                    $expectedOutput = 'design-notes:update'
                }
                'design-review' {
                    $probe = 'direct-untrusted-framing'
                    $modulePath = Get-InstalledPath -Destination 'skills/dr/scripts/DirectWorkflow.psm1'
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-CommandWithArgs',
                        'Import-Module $args[0] -Force; $value = ConvertTo-UntrustedReviewBlock -Content ''consumer review''; if ($value -notmatch ''^<UNTRUSTED_INPUT_'' -or $value -notmatch ''consumer review'') { throw ''direct framing failed'' }; ''design-review:direct''',
                        $modulePath
                    )
                    $expectedOutput = 'design-review:direct'
                }
                'plugin-manager' {
                    $probe = 'installed-plugin-list'
                    $registryPath = Join-Path $smokeRoot 'registry.json'
                    Set-Content -LiteralPath $registryPath -Value (
                        ($Fixture.Registry | ConvertTo-Json -Depth 100) + "`n"
                    ) -Encoding utf8NoBOM
                    $scriptPath = Get-InstalledPath -Destination (
                        'skills/list-plugins/scripts/Get-Plugin.ps1'
                    )
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-CommandWithArgs',
                        '$items = @(& $args[0] -RepoRoot $args[1] -RegistryPath $args[2] -Installed); @($items.name) -join '',''',
                        $scriptPath, $Fixture.Root, $registryPath
                    )
                    $expectedOutput = @($Fixture.Catalog.PluginNames | Sort-Object) -join ','
                }
                'process-pr-comments' {
                    $probe = 'remote-slug-normalization'
                    $modulePath = Get-InstalledPath -Destination (
                        'skills/process-pr-comments/scripts/GitHubPr.psm1'
                    )
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-CommandWithArgs',
                        'Import-Module $args[0] -Force; (Get-RepoSlug -RemoteUrl $args[1]).FullName',
                        $modulePath, 'https://github.com/skalary/consumer.git'
                    )
                    $expectedOutput = 'skalary/consumer'
                }
                'self-improvement' {
                    $probe = 'missing-base-refusal'
                    $scriptPath = Get-InstalledPath -Destination (
                        'skills/si/scripts/Test-SiWriteScope.ps1'
                    )
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-File', $scriptPath,
                        '-RepoRoot', $Fixture.Root,
                        '-BaseRef', '__consumer_smoke_missing_base__'
                    )
                    $expectedExitCode = 1
                    $expectedOutput = (
                        "Test-SiWriteScope failed: cannot resolve diff base " +
                        "'__consumer_smoke_missing_base__' in '$($Fixture.Root)'."
                    )
                }
                'work-hierarchy-sync' {
                    $probe = 'provider-contract'
                    $modulePath = Get-InstalledPath -Destination (
                        'skills/work-hierarchy-sync/scripts/WorkHierarchy.psm1'
                    )
                    $process = Invoke-InstalledProcess -ArgumentList @(
                        '-NoProfile', '-CommandWithArgs',
                        'Import-Module $args[0] -Force; $provider = New-WorkHierarchyProvider -Name fixture -Read { param($request) $request } -Write { param($operation) $operation }; Assert-WorkHierarchyProvider -Provider $provider; $provider.name',
                        $modulePath
                    )
                    $expectedOutput = 'fixture'
                }
                default {
                    $process = [pscustomobject]@{
                        ExitCode = -1
                        Output   = "no installed smoke is defined for active plugin '$name'"
                    }
                }
            }

            $results.Add([pscustomobject]@{
                    Plugin   = $name
                    Payload  = [string]$payload[0].Dest
                    Probe    = $probe
                    ExitCode = [int]$process.ExitCode
                    Output   = [string]$process.Output
                    IsClean  = $payloadLoaded -and
                    [int]$process.ExitCode -eq $expectedExitCode -and
                    ([string]$process.Output).Trim() -ceq $expectedOutput
                })
        }
    }
    finally {
        if (Test-Path -LiteralPath $smokeRoot -PathType Container) {
            Remove-Item -LiteralPath $smokeRoot -Recurse -Force
        }
    }

    return @($results)
}

function Invoke-ConsumerFirstUseScaffoldLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Fixture,
        [string[]]$ExcludedOwner = @()
    )

    $owners = @(
        $Fixture.Catalog.Plugins |
            ForEach-Object { @($_.Scaffolds) } |
            ForEach-Object { [string]$_.owner } |
            Where-Object { $_ -notin $ExcludedOwner } |
            Sort-Object -Unique
    )
    $results = [System.Collections.Generic.List[object]]::new()

    function Get-InstalledPath {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$Destination
        )

        return Join-Path (Join-Path $Root '.github') (
            $Destination -replace '/', [System.IO.Path]::DirectorySeparatorChar
        )
    }

    function Get-EntryMap {
        param([Parameter(Mandatory)][string]$Root)

        $map = [System.Collections.Generic.Dictionary[string, string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($entry in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
            $relative = [System.IO.Path]::GetRelativePath($Root, $entry.FullName).Replace('\', '/')
            if ($relative -eq '.git' -or $relative.StartsWith('.git/')) {
                continue
            }
            if ($entry.LinkType) {
                $map[$relative] = "L:$($entry.LinkTarget)"
            }
            elseif ($entry.PSIsContainer) {
                $map[$relative] = 'D'
            }
            else {
                $map[$relative] = 'F:' + [Convert]::ToBase64String(
                    [System.IO.File]::ReadAllBytes($entry.FullName)
                )
            }
        }
        return $map
    }

    function Test-OwnerDeclaredEntry {
        param(
            [AllowEmptyString()][string]$Owner,
            [Parameter(Mandatory)][string]$RelativePath,
            [Parameter(Mandatory)][string]$EntryKind
        )

        $declarations = @(
            $Fixture.Catalog.Plugins |
                ForEach-Object { @($_.Scaffolds) } |
                Where-Object {
                    [string]::IsNullOrEmpty($Owner) -or [string]$_.owner -ceq $Owner
                }
        )
        foreach ($declaration in $declarations) {
            $template = [string]$declaration.path
            $planFolders = if ($template.Contains('<plan>')) {
                @('standalone-2026-01-02-a1b2c3-consumer-scaffold', '007-consumer-scaffold')
            }
            else {
                @('')
            }
            foreach ($planFolder in $planFolders) {
                $expanded = $template.Replace('<category>', 'testing')
                $expanded = $expanded.Replace('<plan>', $planFolder)
                $expanded = $expanded.Replace('<epic>', '2026-01-02-d4e5f6-consumer-epic')
                $subtree = $expanded.EndsWith('/**', [System.StringComparison]::Ordinal)
                if ($subtree) { $expanded = $expanded.Substring(0, $expanded.Length - 3) }
                $literalDirectory = $expanded -notmatch '\.(?:json|md|ps1|psm1|txt|ya?ml)$'

                if ($RelativePath -ceq $expanded) { return $true }
                if (($subtree -or $literalDirectory) -and
                    $RelativePath.StartsWith("$expanded/", [System.StringComparison]::Ordinal)) {
                    return $true
                }
                if ($EntryKind -ceq 'D' -and
                    $expanded.StartsWith("$RelativePath/", [System.StringComparison]::Ordinal)) {
                    return $true
                }
            }
        }
        return $false
    }

    function Test-FileMapEqual {
        param(
            [Parameter(Mandatory)]$Left,
            [Parameter(Mandatory)]$Right
        )

        if ($Left.Count -ne $Right.Count) { return $false }
        foreach ($key in $Left.Keys) {
            if (-not $Right.ContainsKey($key) -or $Left[$key] -cne $Right[$key]) { return $false }
        }
        return $true
    }

    function Invoke-OwnerProcess {
        param(
            [Parameter(Mandatory)][string]$Owner,
            [Parameter(Mandatory)][string]$Root,
            [switch]$Hostile,
            [switch]$Repeat
        )

        $missingRoot = Join-Path $Root '.github/.skalary/missing-scaffold-root'
        $argumentList = switch ($Owner) {
            'Copy-ArchScaffold.ps1' {
                $scriptPath = Get-InstalledPath -Root $Root -Destination (
                    'skills/architecture-notes/scripts/Copy-ArchScaffold.ps1'
                )
                @('-NoProfile', '-File', $scriptPath, '-TargetRoot', $(if ($Hostile) { $missingRoot } else { $Root }))
            }
            'Import-ArchHarvest.ps1' {
                $scriptPath = Get-InstalledPath -Root $Root -Destination (
                    'skills/architecture-notes/scripts/Import-ArchHarvest.ps1'
                )
                $arguments = @('-NoProfile', '-File', $scriptPath, '-RepoRoot', $Root)
                if ($Hostile) {
                    $arguments += @(
                        '-StagingRoot',
                        (Join-Path (Split-Path -Parent $Root) (
                            "$(Split-Path -Leaf $Root)-escaped-architecture-harvest"
                        ))
                    )
                }
                $arguments
            }
            'Import-ArchAdr.ps1' {
                $scriptPath = Get-InstalledPath -Root $Root -Destination (
                    'skills/architecture-notes/scripts/Import-ArchAdr.ps1'
                )
                $planDir = Join-Path $Root '.github/.skalary/scaffold-input/plan'
                $arguments = @(
                    '-NoProfile', '-File', $scriptPath,
                    '-PlanDir', $planDir,
                    '-RepoRoot', $Root
                )
                if ($Hostile) {
                    $arguments += @(
                        '-StagingRoot',
                        (Join-Path (Split-Path -Parent $Root) (
                            "$(Split-Path -Leaf $Root)-escaped-architecture-adr"
                        ))
                    )
                }
                $arguments
            }
            'New-ArchHumanDoc.ps1' {
                $scriptPath = Get-InstalledPath -Root $Root -Destination (
                    'skills/architecture-notes/scripts/New-ArchHumanDoc.ps1'
                )
                @('-NoProfile', '-File', $scriptPath, '-RepoRoot', $(if ($Hostile) { $missingRoot } else { $Root }))
            }
            'Add-WorkflowNote.ps1' {
                $scriptPath = Get-InstalledPath -Root $Root -Destination (
                    'skills/ci/scripts/Add-WorkflowNote.ps1'
                )
                $planDir = if ($Hostile) {
                    Join-Path (Split-Path -Parent $Root) (
                        "$(Split-Path -Leaf $Root)-escaped-workflow-note"
                    )
                }
                else {
                    Join-Path $Root 'docs/implementation-plans/standalone-2026-01-02-a1b2c3-consumer-scaffold'
                }
                $legacyPlanDir = if ($Hostile) {
                    $planDir
                }
                else {
                    Join-Path $Root 'docs/implementation-plans/007-consumer-scaffold'
                }
                @(
                    '-NoProfile', '-CommandWithArgs',
                    '$ErrorActionPreference = ''Stop''; $scriptPath, $planDir, $legacyPlanDir, $repoRoot = $args; 1..2 | ForEach-Object { & $scriptPath -Kind Learnings -PlanDir $legacyPlanDir -RepoRoot $repoRoot -Phase 1 -Step "1.$_" -Trigger reusable-pattern -Concern maintainability-consistency -Message "legacy learning $_" -MaxLearnings 1 | Out-Null }; 3..4 | ForEach-Object { & $scriptPath -Kind Learnings -PlanDir $planDir -RepoRoot $repoRoot -Phase 1 -Step "1.$_" -Trigger reusable-pattern -Concern maintainability-consistency -Message "assets learning $_" -MaxLearnings 1 | Out-Null }; ''workflow-note:dual-layout''',
                    $scriptPath, $planDir, $legacyPlanDir, $Root
                )
            }
            'New-Plan.ps1' {
                $scriptPath = Get-InstalledPath -Root $Root -Destination 'skills/cip/scripts/New-Plan.ps1'
                $templatePath = Get-InstalledPath -Root $Root -Destination (
                    'skills/cip/assets/plan-template.md'
                )
                $arguments = @(
                    '-NoProfile', '-File', $scriptPath,
                    '-Title', 'Consumer scaffold',
                    '-Slug', 'consumer-scaffold',
                    '-Date', '2026-01-02',
                    '-PlanId', $(if ($Hostile) { '../bad' } else { 'a1b2c3' }),
                    '-TemplatePath', $templatePath,
                    '-RepoRoot', $Root
                )
                $arguments
            }
            'New-Epic.ps1' {
                $scriptPath = Get-InstalledPath -Root $Root -Destination 'skills/cep/scripts/New-Epic.ps1'
                @(
                    '-NoProfile', '-File', $scriptPath,
                    '-Title', 'Consumer epic',
                    '-Slug', 'consumer-epic',
                    '-Date', '2026-01-02',
                    '-EpicId', $(if ($Hostile) { '../bad' } else { 'd4e5f6' }),
                    '-RepoRoot', $Root
                )
            }
            'Initialize-DesignNotes.ps1' {
                $scriptPath = Get-InstalledPath -Root $Root -Destination (
                    'skills/design-notes/scripts/Initialize-DesignNotes.ps1'
                )
                @(
                    '-NoProfile', '-File', $scriptPath,
                    '-RepoRoot', $(if ($Hostile) {
                            Join-Path $Root '.github/.skalary/not-a-directory'
                        }
                        else { $Root })
                )
            }
            default {
                return [pscustomobject]@{
                    ExitCode = -1
                    Output   = "no lifecycle invocation is defined for owner '$Owner'"
                }
            }
        }

        return Invoke-SuiteFixtureProcess `
            -WorkingDirectory $Root `
            -TimeoutSeconds 60 `
            -ArgumentList $argumentList
    }

    foreach ($owner in $owners) {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) (
            "skalary-scaffold-owner-$([guid]::NewGuid().ToString('N'))"
        )
        Copy-SkalaryFixtureTree -Source $Fixture.Root -Destination $root
        try {
            if ($owner -eq 'Import-ArchAdr.ps1') {
                $decisions = Join-Path $root '.github/.skalary/scaffold-input/plan/assets/decisions'
                [void](New-Item -ItemType Directory -Path $decisions -Force)
                Set-Content -LiteralPath (Join-Path $decisions 'consumer-choice.md') `
                    -Value "# Decision: Consumer Choice`n`nKeep scaffold writes confined.`n" `
                    -NoNewline -Encoding utf8NoBOM
            }
            elseif ($owner -eq 'New-ArchHumanDoc.ps1') {
                $copyScript = Get-InstalledPath -Root $root -Destination (
                    'skills/architecture-notes/scripts/Copy-ArchScaffold.ps1'
                )
                $setup = Invoke-SuiteFixtureProcess -WorkingDirectory $root -TimeoutSeconds 30 `
                    -ArgumentList @('-NoProfile', '-File', $copyScript, '-TargetRoot', $root)
                if ($setup.ExitCode -ne 0) { throw "Human-doc prerequisite failed: $($setup.Output)" }
            }
            elseif ($owner -eq 'Add-WorkflowNote.ps1') {
                $newPlanPath = Get-InstalledPath -Root $root -Destination (
                    'skills/cip/scripts/New-Plan.ps1'
                )
                $templatePath = Get-InstalledPath -Root $root -Destination (
                    'skills/cip/assets/plan-template.md'
                )
                $setup = Invoke-SuiteFixtureProcess -WorkingDirectory $root -TimeoutSeconds 30 `
                    -ArgumentList @(
                        '-NoProfile', '-File', $newPlanPath,
                        '-Title', 'Consumer scaffold',
                        '-Slug', 'consumer-scaffold',
                        '-Date', '2026-01-02',
                        '-PlanId', 'a1b2c3',
                        '-TemplatePath', $templatePath,
                        '-RepoRoot', $root
                    )
                if ($setup.ExitCode -ne 0) { throw "Workflow-note prerequisite failed: $($setup.Output)" }
                $legacyPlanDir = Join-Path $root 'docs/implementation-plans/007-consumer-scaffold'
                [void](New-Item -ItemType Directory -Path $legacyPlanDir -Force)
                Set-Content -LiteralPath (Join-Path $legacyPlanDir 'plan.md') -Encoding utf8NoBOM -Value @(
                    '# 007: Consumer legacy scaffold'
                    ''
                    '## Phase 1: Fixture'
                    ''
                    '- [ ] 1.1 Consumer lifecycle `S`'
                )
            }
            elseif ($owner -eq 'Initialize-DesignNotes.ps1') {
                Set-Content -LiteralPath (Join-Path $root '.github/.skalary/not-a-directory') `
                    -Value 'not a directory' -NoNewline -Encoding utf8NoBOM
            }

            $baseline = Get-EntryMap -Root $root
            $hostile = Invoke-OwnerProcess -Owner $owner -Root $root -Hostile
            $afterHostile = Get-EntryMap -Root $root
            $hostileEscapePath = switch ($owner) {
                'Import-ArchHarvest.ps1' {
                    Join-Path (Split-Path -Parent $root) (
                        "$(Split-Path -Leaf $root)-escaped-architecture-harvest"
                    )
                }
                'Import-ArchAdr.ps1' {
                    Join-Path (Split-Path -Parent $root) (
                        "$(Split-Path -Leaf $root)-escaped-architecture-adr"
                    )
                }
                default { $null }
            }
            $first = Invoke-OwnerProcess -Owner $owner -Root $root
            $afterFirst = Get-EntryMap -Root $root
            $created = @($afterFirst.Keys | Where-Object { -not $baseline.ContainsKey($_) } | Sort-Object)

            $unexpectedBaselineMutation = @(
                $baseline.Keys |
                    Where-Object {
                        (-not $afterFirst.ContainsKey($_) -or $baseline[$_] -cne $afterFirst[$_]) -and
                        -not (Test-OwnerDeclaredEntry `
                        -RelativePath $_ `
                        -EntryKind $baseline[$_])
                    }
            )
            $confined = $created.Count -gt 0 -and $unexpectedBaselineMutation.Count -eq 0 -and @(
                $created |
                    Where-Object {
                        -not (Test-OwnerDeclaredEntry `
                                -RelativePath $_ `
                                -EntryKind $afterFirst[$_])
                    }
            ).Count -eq 0
            $starterContent = $created.Count -gt 0 -and @(
                $created | Where-Object {
                    $afterFirst[$_] -like 'F:*' -and
                    [string]::IsNullOrWhiteSpace(
                        [System.IO.File]::ReadAllText((Join-Path $root ($_ -replace '/', [IO.Path]::DirectorySeparatorChar)))
                    )
                }
            ).Count -eq 0
            $ownerDeclarations = @(
                $Fixture.Catalog.Plugins |
                    ForEach-Object { @($_.Scaffolds) } |
                    Where-Object { [string]$_.owner -ceq $owner } |
                    ForEach-Object {
                        $expanded = [string]$_.path
                        $expanded = $expanded.Replace('<category>', 'testing')
                        $planFolder = 'standalone-2026-01-02-a1b2c3-consumer-scaffold'
                        $expanded = $expanded.Replace('<plan>', $planFolder)
                        $expanded = $expanded.Replace('<epic>', '2026-01-02-d4e5f6-consumer-epic')
                        if ($expanded.EndsWith('/**', [System.StringComparison]::Ordinal)) {
                            $expanded = $expanded.Substring(0, $expanded.Length - 3)
                        }
                        $expanded
                    } |
                    Sort-Object -Unique
            )
            $declaredScaffoldsPresent = @(
                $ownerDeclarations |
                    Where-Object {
                        $declaredPath = Join-Path $root (
                            $_ -replace '/', [IO.Path]::DirectorySeparatorChar
                        )
                        if ($_ -match '\.(?:json|md|ps1|psm1|txt|ya?ml)$') {
                            -not (Test-Path -LiteralPath $declaredPath -PathType Leaf)
                        }
                        else {
                            -not (Test-Path -LiteralPath $declaredPath -PathType Container)
                        }
                    }
            ).Count -eq 0

            $beforeRepeat = Get-EntryMap -Root $root
            $repeat = Invoke-OwnerProcess -Owner $owner -Root $root -Repeat
            $afterRepeat = Get-EntryMap -Root $root
            $idempotent = Test-FileMapEqual -Left $beforeRepeat -Right $afterRepeat
            $repeatChanges = @(
                @($beforeRepeat.Keys) + @($afterRepeat.Keys) |
                    Sort-Object -Unique |
                    Where-Object {
                        -not $beforeRepeat.ContainsKey($_) -or
                        -not $afterRepeat.ContainsKey($_) -or
                        $beforeRepeat[$_] -cne $afterRepeat[$_]
                    }
            )

            $partialRetrySucceeded = $true
            if ($owner -ceq 'Initialize-DesignNotes.ps1') {
                $partialPath = Join-Path $root (
                    'docs/design-notes/project/design-note-writing-style.design.md' -replace '/',
                    [IO.Path]::DirectorySeparatorChar
                )
                Remove-Item -LiteralPath $partialPath -Force
                $partialRetry = Invoke-OwnerProcess -Owner $owner -Root $root -Repeat
                $partialRetrySucceeded = [int]$partialRetry.ExitCode -eq 0 -and
                (Test-Path -LiteralPath $partialPath -PathType Leaf) -and
                -not [string]::IsNullOrWhiteSpace([System.IO.File]::ReadAllText($partialPath))
            }

            $sentinel = 'CONSUMER_MODIFIED_TARGET'
            $modifiedPath = switch ($owner) {
                'Copy-ArchScaffold.ps1' { 'docs/architecture-notes/.architecture-notes.md' }
                'Import-ArchHarvest.ps1' { 'docs/architecture-notes/.staging/HARVEST.md' }
                'Import-ArchAdr.ps1' { 'docs/architecture-notes/.staging/adr/ADR-consumer-choice.md' }
                'New-ArchHumanDoc.ps1' { 'docs/architecture-notes/architecture.human.md' }
                'Add-WorkflowNote.ps1' {
                    'docs/implementation-plans/standalone-2026-01-02-a1b2c3-consumer-scaffold/assets/logs/learnings.md'
                }
                'New-Plan.ps1' {
                    'docs/implementation-plans/standalone-2026-01-02-a1b2c3-consumer-scaffold/assets/intent.md'
                }
                'New-Epic.ps1' {
                    'docs/implementation-plans/epics/2026-01-02-d4e5f6-consumer-epic/epic.md'
                }
                'Initialize-DesignNotes.ps1' { 'docs/design-notes/.design-notes.md' }
                default { $null }
            }
            if ($modifiedPath) {
                $fullModifiedPath = Join-Path $root (
                    $modifiedPath -replace '/', [IO.Path]::DirectorySeparatorChar
                )
                $modifiedText = [System.IO.File]::ReadAllText($fullModifiedPath)
                [System.IO.File]::WriteAllText(
                    $fullModifiedPath,
                    $sentinel + "`n" + $modifiedText,
                    [Text.UTF8Encoding]::new($false)
                )
            }
            $beforeModifiedRetry = Get-EntryMap -Root $root
            $modifiedRetry = if ($modifiedPath) {
                Invoke-OwnerProcess -Owner $owner -Root $root -Repeat
            }
            else {
                $null
            }
            $afterModifiedRetry = Get-EntryMap -Root $root
            $modifiedPreserved = if ($modifiedPath) {
                (Test-FileMapEqual -Left $beforeModifiedRetry -Right $afterModifiedRetry) -and
                [System.IO.File]::ReadAllText((Join-Path $root (
                            $modifiedPath -replace '/', [IO.Path]::DirectorySeparatorChar
                        ))).Contains($sentinel)
            }
            else {
                $true
            }
            $safeRefusalPattern = switch ($owner) {
                'New-Plan.ps1' { 'Plan folder already exists' }
                'New-Epic.ps1' { 'Epic id .* is already taken' }
                default { $null }
            }
            $repeatOutcomeExpected = if ($safeRefusalPattern) {
                [int]$repeat.ExitCode -ne 0 -and [string]$repeat.Output -match $safeRefusalPattern
            }
            else {
                [int]$repeat.ExitCode -eq 0
            }
            $modifiedRetryOutcomeExpected = if (-not $modifiedPath) {
                $true
            }
            elseif ($safeRefusalPattern) {
                [int]$modifiedRetry.ExitCode -ne 0 -and
                [string]$modifiedRetry.Output -match $safeRefusalPattern
            }
            else {
                [int]$modifiedRetry.ExitCode -eq 0
            }

            $results.Add([pscustomobject]@{
                    Owner                        = $owner
                    Created                      = $created
                    Declared                     = @(
                        $Fixture.Catalog.Plugins |
                            ForEach-Object { @($_.Scaffolds) } |
                            Where-Object { [string]$_.owner -ceq $owner } |
                            ForEach-Object { [string]$_.path }
                    )
                    FirstExitCode                = [int]$first.ExitCode
                    HostileExitCode              = [int]$hostile.ExitCode
                    RepeatExitCode               = [int]$repeat.ExitCode
                    StarterContent               = $starterContent
                    Confined                     = $confined
                    HostileRefused               = [int]$hostile.ExitCode -ne 0 -and
                    (Test-FileMapEqual -Left $baseline -Right $afterHostile) -and
                    (-not $hostileEscapePath -or -not (Test-Path -LiteralPath $hostileEscapePath))
                    RetrySucceeded               = [int]$first.ExitCode -eq 0
                    DeclaredScaffoldsPresent     = $declaredScaffoldsPresent
                    Idempotent                   = $idempotent
                    RepeatChanges                = $repeatChanges
                    RepeatOutcomeExpected        = $repeatOutcomeExpected
                    PartialRetrySucceeded        = $partialRetrySucceeded
                    ModifiedTargetPreserved      = $modifiedPreserved
                    ModifiedRetryOutcomeExpected = $modifiedRetryOutcomeExpected
                    Output                       = [string]$first.Output
                })
        }
        finally {
            if (Test-Path -LiteralPath $root -PathType Container) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    return @($results)
}

function Test-ConsumerDistributionDrift {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceRepoRoot)

    $sourceRoot = [System.IO.Path]::GetFullPath($SourceRepoRoot)

    function Get-DistributionSnapshot {
        $entries = [System.Collections.Generic.List[string]]::new()
        foreach ($relativeRoot in @('plugins', '.github')) {
            $root = Join-Path $sourceRoot $relativeRoot
            if (-not (Test-Path -LiteralPath $root -PathType Container)) {
                $entries.Add("M:$relativeRoot")
                continue
            }

            $entries.Add("D:$relativeRoot")
            foreach ($entry in Get-ChildItem -LiteralPath $root -Recurse -Force) {
                $relative = [System.IO.Path]::GetRelativePath($sourceRoot, $entry.FullName).Replace('\', '/')
                if ($entry.LinkType) {
                    $entries.Add("L:$relative=$($entry.LinkTarget)")
                }
                elseif ($entry.PSIsContainer) {
                    $entries.Add("D:$relative")
                }
                else {
                    $entries.Add("F:$relative=$(Get-ConsumerInstallSha256 -Path $entry.FullName)")
                }
            }
        }

        foreach ($relativePath in @('registry.json', 'README.md')) {
            $path = Join-Path $sourceRoot $relativePath
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $entries.Add("F:$relativePath=$(Get-ConsumerInstallSha256 -Path $path)")
            }
            else {
                $entries.Add("M:$relativePath")
            }
        }

        return [string[]]@($entries | Sort-Object)
    }

    $before = @(Get-DistributionSnapshot)
    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in @(
            [pscustomobject]@{
                Name      = 'plugin-script-bundles'
                Script    = 'Sync-PluginScripts.ps1'
                Arguments = @('-WhatIf')
            },
            [pscustomobject]@{
                Name      = 'registry'
                Script    = 'Test-Registry.ps1'
                Arguments = @()
            },
            [pscustomobject]@{
                Name      = 'marketplace'
                Script    = 'Build-Marketplace.ps1'
                Arguments = @('-WhatIf')
            },
            [pscustomobject]@{
                Name      = 'dogfood'
                Script    = 'Sync-Dogfood.ps1'
                Arguments = @('-WhatIf')
            }
        )) {
        $scriptPath = Join-Path $sourceRoot "scripts/skalary/$($definition.Script)"
        $result = Invoke-SuiteFixtureProcess `
            -WorkingDirectory $sourceRoot `
            -TimeoutSeconds 120 `
            -ArgumentList (@(
                '-NoProfile'
                '-File'
                $scriptPath
                '-RepoRoot'
                $sourceRoot
            ) + @($definition.Arguments))
        $checks.Add([pscustomobject]@{
                Name     = [string]$definition.Name
                ExitCode = [int]$result.ExitCode
                Output   = [string]$result.Output
            })
    }
    $after = @(Get-DistributionSnapshot)
    $changes = @(Compare-Object -ReferenceObject $before -DifferenceObject $after -SyncWindow 0 |
            ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })

    return [pscustomobject]@{
        Checks    = @($checks)
        Unchanged = $changes.Count -eq 0
        Changes   = $changes
    }
}

function Remove-ConsumerInstallFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Fixture)

    if ($Fixture.Root -and (Test-Path -LiteralPath $Fixture.Root -PathType Container)) {
        Remove-Item -LiteralPath $Fixture.Root -Recurse -Force
    }
}

Export-ModuleMember -Function Get-ConsumerInstallManifestCatalog, New-ConsumerInstallFixture,
Test-ConsumerInstallInventory, Test-ConsumerRuntimeReferenceClosure, Invoke-ConsumerInstalledSmokeMatrix,
Invoke-ConsumerFirstUseScaffoldLifecycle, Test-ConsumerDistributionDrift, Remove-ConsumerInstallFixture

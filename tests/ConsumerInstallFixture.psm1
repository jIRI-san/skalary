#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SuiteFixture.psm1') -Force -DisableNameChecking

function Get-ConsumerInstallSha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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
                Plugin = $pluginName
                Src = $src
                Dest = $dest
                Sha256 = Get-ConsumerInstallSha256 -Path $sourcePath
                Install = $src -notmatch '^evals(?:/|$)'
                SourcePath = [System.IO.Path]::GetFullPath($sourcePath)
            }
            $pluginFiles.Add($record)
            $files.Add($record)
        }

        $plugins.Add([pscustomobject]@{
                Name = $pluginName
                Version = [string]$manifest.version
                Status = if ($manifest.PSObject.Properties.Name -contains 'status') {
                    [string]$manifest.status
                }
                else {
                    'stable'
                }
                Dependencies = @($manifest.dependencies | ForEach-Object { [string]$_ })
                Scaffolds = if ($manifest.PSObject.Properties.Name -contains 'scaffolds') {
                    @($manifest.scaffolds)
                }
                else {
                    @()
                }
                Files = @($pluginFiles)
                ManifestPath = $manifestPath.FullName
            })
    }

    return [pscustomobject]@{
        SourceRepoRoot = $sourceRoot
        Plugins = @($plugins)
        Files = @($files)
        PluginNames = @($plugins | ForEach-Object { [string]$_.Name })
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
                    Plugin = $pluginName
                    ExitCode = $result.ExitCode
                    Output = $result.Output
                    ExpectedReceiptNames = $expectedReceipts
                    NewReceiptNames = @($afterReceipts | Where-Object { $_ -notin $beforeReceipts })
                })
        }

        $registry = Get-Content -LiteralPath (Join-Path $sourceRoot 'registry.json') -Raw |
            ConvertFrom-Json -Depth 100
        return [pscustomobject]@{
            Root = $root
            SourceRepoRoot = $sourceRoot
            Catalog = $catalog
            Registry = $registry
            PoisonRelativePaths = $poisonRelativePaths
            InstallResults = @($installResults)
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
        IsClean = @($issues | ForEach-Object { @($_) }).Count -eq 0
        Missing = @($missing | Sort-Object)
        Extra = @($extra | Sort-Object)
        HashMismatched = @($hashMismatched | Sort-Object)
        Escaping = @($escaping | Sort-Object)
        StaleMappings = @($staleMappings | Sort-Object)
        ReceiptMismatches = @($receiptMismatches | Sort-Object)
        DependencyMismatches = @($dependencyMismatches | Sort-Object)
        OutsideWrites = @($outsideWrites | Sort-Object)
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
        IsClean = $staticScan.ExitCode -eq 0 -and $inventory.IsClean -and $changedPoison.Count -eq 0
        StaticExitCode = $staticScan.ExitCode
        StaticOutput = $staticScan.Output
        Inventory = $inventory
        ChangedPoison = @($changedPoison)
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
    Test-ConsumerInstallInventory, Test-ConsumerRuntimeReferenceClosure, Remove-ConsumerInstallFixture

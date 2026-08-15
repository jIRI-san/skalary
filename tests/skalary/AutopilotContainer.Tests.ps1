#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot container toolchain' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:pluginRoot = Join-Path $script:repoRoot 'plugins/autopilot'
        $script:installedRoot = Join-Path $script:repoRoot '.github/skills/autopilot'
        $script:manifestPath = Join-Path $script:pluginRoot 'devcontainer/toolchain.tsv'
        $script:dockerfilePath = Join-Path $script:pluginRoot 'devcontainer/Dockerfile'
        $script:smokePath = Join-Path $script:pluginRoot 'devcontainer/container-toolchain-smoke.sh'
        $script:contractPath = Join-Path $script:repoRoot 'docs/design-notes/architecture/autopilot-container-toolchain.design.md'

        function Read-ToolchainRows {
            param([Parameter(Mandatory)][string]$Content)

            $rows = [System.Collections.Generic.List[object]]::new()
            $lineNumber = 0
            foreach ($line in ($Content -split "\r?\n")) {
                $lineNumber++
                if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
                    continue
                }
                $fields = $line.Split("`t")
                if ($fields.Count -ne 3) {
                    throw "Invalid toolchain row at line ${lineNumber}: expected three tab-separated fields."
                }
                $rows.Add([pscustomobject]@{
                        Id      = $fields[0]
                        Package = $fields[1]
                        Command = $fields[2]
                    })
            }
            return @($rows)
        }

        function Read-ApprovedRows {
            param([Parameter(Mandatory)][string]$Content)

            $pattern = '(?m)^\|\s*`(?<id>[a-z0-9]+(?:-[a-z0-9]+)*)`\s*\|[^|\r\n]*\|\s*`(?<package>[a-z0-9][a-z0-9+.-]*)`\s*\|\s*`(?<command>[a-z0-9][a-z0-9+.-]*)`\s*\|'
            return @([regex]::Matches($Content, $pattern) | ForEach-Object {
                    [pscustomobject]@{
                        Id      = $_.Groups['id'].Value
                        Package = $_.Groups['package'].Value
                        Command = $_.Groups['command'].Value
                    }
                })
        }

        function Compare-OrdinalSet {
            param(
                [Parameter(Mandatory)][string]$Label,
                [Parameter(Mandatory)][string[]]$Actual,
                [Parameter(Mandatory)][string[]]$Expected
            )

            $actualSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $expectedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($value in $Actual) { [void]$actualSet.Add($value) }
            foreach ($value in $Expected) { [void]$expectedSet.Add($value) }

            $errors = [System.Collections.Generic.List[string]]::new()
            foreach ($value in $actualSet) {
                if (-not $expectedSet.Contains($value)) {
                    $errors.Add("$Label has unexpected '$value'.")
                }
            }
            foreach ($value in $expectedSet) {
                if (-not $actualSet.Contains($value)) {
                    $errors.Add("$Label is missing '$value'.")
                }
            }
            return @($errors)
        }

        function Get-AptHostPolicy {
            param([Parameter(Mandatory)][string]$Dockerfile)

            $caseMatch = [regex]::Match($Dockerfile, '(?s)case "\$host" in(?<body>.*?)esac;')
            if (-not $caseMatch.Success) {
                return $null
            }
            $body = $caseMatch.Groups['body'].Value
            $allowedMatch = [regex]::Match(
                $body,
                '(?<allowed>[a-z][a-z0-9.-]*(?:\|[a-z][a-z0-9.-]*)*)\)\s*;;')
            $fallbackMatch = [regex]::Match($body, '(?s)\*\)(?<fallback>.*?) ;;')
            if (-not $allowedMatch.Success -or -not $fallbackMatch.Success) {
                return $null
            }
            return [pscustomobject]@{
                AllowedHosts  = @($allowedMatch.Groups['allowed'].Value -split '\|')
                RejectsUnknown = $fallbackMatch.Groups['fallback'].Value -match '(?:^|[;\s])exit\s+1(?:[;\s]|$)'
            }
        }

        function Get-ToolchainContractErrors {
            param(
                [Parameter(Mandatory)][string]$Manifest,
                [Parameter(Mandatory)][string]$Dockerfile,
                [Parameter(Mandatory)][string]$Smoke,
                [Parameter(Mandatory)][string]$Contract
            )

            $errors = [System.Collections.Generic.List[string]]::new()
            $manifestRows = @(Read-ToolchainRows -Content $Manifest)
            $approvedRows = @(Read-ApprovedRows -Content $Contract)
            $smokeIds = @([regex]::Matches($Smoke, '(?m)^\s*# CASE:(?<id>[a-z0-9]+(?:-[a-z0-9]+)*)\s*$') |
                    ForEach-Object { $_.Groups['id'].Value })

            foreach ($duplicate in @($manifestRows | Group-Object Id | Where-Object Count -gt 1)) {
                $errors.Add("Manifest case ID '$($duplicate.Name)' is duplicated.")
            }
            foreach ($duplicate in @($smokeIds | Group-Object | Where-Object Count -gt 1)) {
                $errors.Add("Smoke CASE ID '$($duplicate.Name)' is duplicated.")
            }

            $manifestTuples = @($manifestRows | ForEach-Object { "$($_.Id)`t$($_.Package)`t$($_.Command)" })
            $approvedTuples = @($approvedRows | ForEach-Object { "$($_.Id)`t$($_.Package)`t$($_.Command)" })
            foreach ($errorText in @(Compare-OrdinalSet -Label 'Manifest approved row set' -Actual $manifestTuples -Expected $approvedTuples)) {
                $errors.Add($errorText)
            }
            foreach ($errorText in @(Compare-OrdinalSet -Label 'Smoke CASE ID set' -Actual $smokeIds -Expected @($manifestRows.Id))) {
                $errors.Add($errorText)
            }

            $bootstrapMatch = [regex]::Match($Dockerfile, 'bootstrap_packages=\((?<packages>[^)]+)\)')
            if (-not $bootstrapMatch.Success) {
                $errors.Add('Dockerfile has no separately named bootstrap_packages array.')
            }
            else {
                $bootstrapPackages = @($bootstrapMatch.Groups['packages'].Value -split '\s+' | Where-Object { $_ })
                $expectedBootstrap = @('git', 'curl', 'jq', 'ca-certificates', 'gnupg', 'nodejs', 'npm')
                foreach ($errorText in @(Compare-OrdinalSet -Label 'Bootstrap package set' -Actual $bootstrapPackages -Expected $expectedBootstrap)) {
                    $errors.Add($errorText)
                }
                $manifestPackageSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($manifestRows.Package), [System.StringComparer]::Ordinal)
                foreach ($package in $bootstrapPackages) {
                    if ($manifestPackageSet.Contains($package)) {
                        $errors.Add("Bootstrap package '$package' must not appear in the manifest baseline.")
                    }
                }
            }

            $toolchainPackageReferences = @([regex]::Matches($Dockerfile, '\btoolchain_packages\b'))
            if ($toolchainPackageReferences.Count -ne 3) {
                $errors.Add('Dockerfile toolchain_packages must be referenced exactly by manifest loading, installation, and provenance capture.')
            }
            $bootstrapPackageReferences = @([regex]::Matches($Dockerfile, '\bbootstrap_packages\b'))
            if ($bootstrapPackageReferences.Count -ne 3) {
                $errors.Add('Dockerfile bootstrap_packages must be referenced exactly by declaration, installation, and provenance capture.')
            }

            $requiredDockerTokens = @(
                'COPY devcontainer/toolchain.tsv /usr/local/share/autopilot/toolchain.tsv',
                "' /usr/local/share/autopilot/toolchain.tsv > /tmp/autopilot-toolchain-packages;",
                '{ count++; print $2 }',
                'mapfile -t toolchain_packages < /tmp/autopilot-toolchain-packages;',
                'apt-get install -y --no-install-recommends "${bootstrap_packages[@]}" "${toolchain_packages[@]}";',
                "apt-config dump | grep -Eiq '^[[:space:]]*Binary::apt-get::Dir([[:space:]]|::)'",
                'apt-config shell apt_root Dir',
                'apt-config shell apt_etc Dir::Etc',
                'apt-config shell apt_source_list Dir::Etc::sourcelist',
                'apt-config shell apt_source_parts Dir::Etc::sourceparts',
                'APT sourceparts must not contain symlinked source files',
                'deb.debian.org|security.debian.org',
                '*) echo "Disallowed active apt source host: $host" >&2;',
                '[Ee][Nn][Aa][Bb][Ll][Ee][Dd]:',
                '[Ff][Aa][Ll][Ss][Ee]|0',
                '/usr/local/share/autopilot/provenance/os-release',
                '/usr/local/share/autopilot/provenance/apt-sources.txt',
                '/usr/local/share/autopilot/provenance/requested-packages.tsv',
                '/usr/local/share/autopilot/provenance/dependency-closure.tsv',
                '/usr/local/share/autopilot/provenance/selected-origins.txt',
                '/usr/local/share/autopilot/provenance/final-apt-sources.txt',
                '/usr/local/share/autopilot/provenance/final-packages.tsv',
                '/usr/local/share/autopilot/provenance/final-npm-globals.json',
                'sha256sum -c -',
                'd0c2f69250c6ce0d4c6220b142f999d039a3c560af7f980b943687d106ca8e38',
                '14720066647ceac6138e4134c5d0c31790e81e5cbc4719611323ea0e4ed231ba',
                '9DC858229FC7DD38854AE2D88D81803C0EBFCD88'
            )
            foreach ($token in $requiredDockerTokens) {
                if (-not $Dockerfile.Contains($token)) {
                    $errors.Add("Dockerfile is missing contract token '$token'.")
                }
            }

            # Every network fetch that is later installed with root trust must be bound to a digest
            # or key fingerprint in this file; an unverified root install is the hole these tokens
            # exist to close, and counting them keeps a new fetch from slipping in unpinned.
            $curlFetches = @([regex]::Matches($Dockerfile, '(?m)curl\s+(?<flags>-[A-Za-z]+)\s'))
            foreach ($fetch in $curlFetches) {
                if ($fetch.Groups['flags'].Value -notmatch 'f') {
                    $errors.Add('Dockerfile curl fetches must fail on HTTP error status.')
                    break
                }
            }
            $rootInstallFetches = @([regex]::Matches($Dockerfile, '-o\s+/tmp/[^\s]+\.(?:deb|asc)'))
            $verifications = @([regex]::Matches($Dockerfile, 'sha256sum -c -')).Count +
                @([regex]::Matches($Dockerfile, '(?m)grep -qx [0-9A-F]{40}')).Count
            if ($rootInstallFetches.Count -ne $verifications) {
                $errors.Add("Dockerfile has $($rootInstallFetches.Count) root-trusted network fetches but $verifications digest or fingerprint verifications.")
            }

            $hostPolicy = Get-AptHostPolicy -Dockerfile $Dockerfile
            if ($null -eq $hostPolicy) {
                $errors.Add('Dockerfile apt host policy cannot be parsed.')
            }
            else {
                foreach ($errorText in @(Compare-OrdinalSet `
                            -Label 'APT allowed host set' `
                            -Actual @($hostPolicy.AllowedHosts) `
                            -Expected @('deb.debian.org', 'security.debian.org'))) {
                    $errors.Add($errorText)
                }
                if (-not $hostPolicy.RejectsUnknown) {
                    $errors.Add('Dockerfile apt host policy does not exit nonzero for an unknown host.')
                }
            }

            $copyIndex = $Dockerfile.IndexOf('COPY devcontainer/toolchain.tsv', [System.StringComparison]::Ordinal)
            $sourceDiscoveryIndex = $Dockerfile.IndexOf('apt_source_files=();', [System.StringComparison]::Ordinal)
            $validationIndex = $Dockerfile.IndexOf('if apt-config dump', [System.StringComparison]::Ordinal)
            $hostValidationIndex = $Dockerfile.IndexOf('while IFS= read -r uri;', [System.StringComparison]::Ordinal)
            $firstAptUpdate = $Dockerfile.IndexOf('apt-get update;', [System.StringComparison]::Ordinal)
            $installIndex = $Dockerfile.IndexOf('apt-get install -y --no-install-recommends', [System.StringComparison]::Ordinal)
            $provenanceIndex = $Dockerfile.IndexOf('install -d -m 0755 /usr/local/share/autopilot/provenance;', [System.StringComparison]::Ordinal)
            $originCaptureIndex = $Dockerfile.IndexOf('> /usr/local/share/autopilot/provenance/selected-origins.txt;', [System.StringComparison]::Ordinal)
            $firstCleanup = $Dockerfile.IndexOf('rm -rf /var/lib/apt/lists/*', [System.StringComparison]::Ordinal)
            $powerShellLayer = $Dockerfile.IndexOf('# PowerShell', [System.StringComparison]::Ordinal)
            $orderedIndices = @(
                $copyIndex,
                $validationIndex,
                $sourceDiscoveryIndex,
                $hostValidationIndex,
                $firstAptUpdate,
                $installIndex,
                $provenanceIndex,
                $originCaptureIndex,
                $firstCleanup,
                $powerShellLayer
            )
            if (@($orderedIndices | Where-Object { $_ -lt 0 }).Count -gt 0) {
                $errors.Add('Dockerfile is missing a Debian validation, install, provenance, cleanup, or third-party-layer anchor.')
            }
            else {
                for ($index = 1; $index -lt $orderedIndices.Count; $index++) {
                    if ($orderedIndices[$index - 1] -ge $orderedIndices[$index]) {
                        $errors.Add('Dockerfile Debian validation, update, install, provenance, cleanup, and third-party layers are out of order.')
                        break
                    }
                }
            }
            if ($powerShellLayer -gt $copyIndex) {
                $debianLayer = $Dockerfile.Substring($copyIndex, $powerShellLayer - $copyIndex)
                if (@([regex]::Matches($debianLayer, 'apt-get install')).Count -ne 1) {
                    $errors.Add('First Debian layer must contain exactly one manifest-driven apt-get install command.')
                }
                foreach ($uriMatch in [regex]::Matches($debianLayer, 'https?://(?<host>[A-Za-z0-9.-]+)')) {
                    if ($uriMatch.Groups['host'].Value -notin @('deb.debian.org', 'security.debian.org')) {
                        $errors.Add("First Debian layer contains non-allowlisted source host '$($uriMatch.Groups['host'].Value)'.")
                    }
                }
            }

            $finalProvenanceIndex = $Dockerfile.IndexOf('> /usr/local/share/autopilot/provenance/final-apt-sources.txt;', [System.StringComparison]::Ordinal)
            $dockerCliIndex = $Dockerfile.IndexOf('docker-ce-cli;', [System.StringComparison]::Ordinal)
            $nonRootIndex = $Dockerfile.IndexOf('USER autopilot', [System.StringComparison]::Ordinal)
            if ($finalProvenanceIndex -lt 0 -or $dockerCliIndex -lt 0 -or $nonRootIndex -lt 0) {
                $errors.Add('Dockerfile is missing the final root-layer provenance, Docker CLI, or non-root anchor.')
            }
            elseif ($finalProvenanceIndex -lt $dockerCliIndex -or $finalProvenanceIndex -gt $nonRootIndex) {
                # Provenance captured before the last root install describes an image that is never
                # shipped, which is exactly the gap the final capture exists to close.
                $errors.Add('Final provenance capture must run after the last root install and before the non-root user.')
            }

            if (-not $Smoke.Contains('"$provenance_dir/final-apt-sources.txt"')) {
                $errors.Add('Smoke must report origins from the final root-layer apt source capture.')
            }
            foreach ($provenanceFile in @('final-apt-sources.txt', 'final-packages.tsv', 'final-npm-globals.json')) {
                if (-not [regex]::IsMatch($Smoke, "(?m)^\s+$([regex]::Escape($provenanceFile))\s*$")) {
                    $errors.Add("Smoke provenance digest set is missing '$provenanceFile'.")
                }
            }

            return @($errors)
        }

        $script:manifestContent = Get-Content -LiteralPath $script:manifestPath -Raw
        $script:dockerfileContent = Get-Content -LiteralPath $script:dockerfilePath -Raw
        $script:smokeContent = Get-Content -LiteralPath $script:smokePath -Raw
        $script:contractContent = Get-Content -LiteralPath $script:contractPath -Raw
    }

    It 'test:AutopilotContainer.ToolchainContract enforces the manifest, image, smoke, and distribution contract' {
        # The contract must live outside the plan folder: plan folders are moved to archived/ on
        # completion, which would leave this test reading a path that no longer exists.
        $contractPath | Should -Not -Match 'implementation-plans'
        Test-Path -LiteralPath $contractPath -PathType Leaf | Should -BeTrue

        $errors = @(Get-ToolchainContractErrors `
                -Manifest $manifestContent `
                -Dockerfile $dockerfileContent `
                -Smoke $smokeContent `
                -Contract $contractContent)
        $errors | Should -BeNullOrEmpty -Because ($errors -join "`n")

        $firstManifestRow = @(Read-ToolchainRows -Content $manifestContent)[0]
        $originalManifestLine = "$($firstManifestRow.Id)`t$($firstManifestRow.Package)`t$($firstManifestRow.Command)"
        $mutatedManifestLine = "$($firstManifestRow.Id)`t$($firstManifestRow.Package)-mutated`t$($firstManifestRow.Command)"
        $mutatedManifest = $manifestContent.Replace(
            $originalManifestLine,
            $mutatedManifestLine,
            [System.StringComparison]::Ordinal)
        $mutatedManifest | Should -Not -Be $manifestContent
        $packageMutationErrors = @(Get-ToolchainContractErrors `
                -Manifest $mutatedManifest `
                -Dockerfile $dockerfileContent `
                -Smoke $smokeContent `
                -Contract $contractContent)
        ($packageMutationErrors -join "`n") | Should -Match 'Manifest approved row set'

        $mutatedSmoke = $smokeContent.Replace(
            "# CASE:$($firstManifestRow.Id)",
            "# CASE:$($firstManifestRow.Id)-mutated",
            [System.StringComparison]::Ordinal)
        $mutatedSmoke | Should -Not -Be $smokeContent
        $caseMutationErrors = @(Get-ToolchainContractErrors `
                -Manifest $manifestContent `
                -Dockerfile $dockerfileContent `
                -Smoke $mutatedSmoke `
                -Contract $contractContent)
        ($caseMutationErrors -join "`n") | Should -Match 'Smoke CASE ID set'

        $mutatedPackageInstall = $dockerfileContent.Replace(
            'mapfile -t toolchain_packages < /tmp/autopilot-toolchain-packages;',
            'mapfile -t toolchain_packages < /tmp/autopilot-toolchain-packages; toolchain_packages+=(vim);',
            [System.StringComparison]::Ordinal)
        $installMutationErrors = @(Get-ToolchainContractErrors `
                -Manifest $manifestContent `
                -Dockerfile $mutatedPackageInstall `
                -Smoke $smokeContent `
                -Contract $contractContent)
        ($installMutationErrors -join "`n") | Should -Match 'toolchain_packages must be referenced exactly'

        $aptPolicy = Get-AptHostPolicy -Dockerfile $dockerfileContent
        $aptPolicy | Should -Not -BeNullOrEmpty
        $injectedSourceUri = [uri]'https://packages.example.invalid/debian'
        $aptPolicy.AllowedHosts | Should -Not -Contain $injectedSourceUri.Host
        $aptPolicy.RejectsUnknown | Should -BeTrue

        $nonRejectingDockerfile = $dockerfileContent.Replace(
            'exit 1 ;;',
            'exit 0 ;;',
            [System.StringComparison]::Ordinal)
        $originMutationErrors = @(Get-ToolchainContractErrors `
                -Manifest $manifestContent `
                -Dockerfile $nonRejectingDockerfile `
                -Smoke $smokeContent `
                -Contract $contractContent)
        ($originMutationErrors -join "`n") | Should -Match 'does not exit nonzero'

        $userIndex = $dockerfileContent.IndexOf("USER autopilot`n", [System.StringComparison]::Ordinal)
        $smokeCopyIndex = $dockerfileContent.IndexOf('COPY devcontainer/container-toolchain-smoke.sh /usr/local/bin/container-toolchain-smoke', [System.StringComparison]::Ordinal)
        $aliasIndex = $dockerfileContent.IndexOf('ln -s /usr/bin/fdfind /usr/local/bin/fd', [System.StringComparison]::Ordinal)
        $extensionAnchors = @([regex]::Matches($dockerfileContent, [regex]::Escape('# Non-root user')))
        $extensionAnchorIndex = $dockerfileContent.IndexOf('# Non-root user', [System.StringComparison]::Ordinal)
        $userIndex | Should -BeGreaterThan 0
        $smokeCopyIndex | Should -BeGreaterOrEqual 0
        $aliasIndex | Should -BeGreaterOrEqual 0
        $extensionAnchors.Count | Should -Be 1
        $extensionAnchorIndex | Should -BeGreaterThan $aliasIndex
        $extensionAnchorIndex | Should -BeLessThan $userIndex
        $smokeCopyIndex | Should -BeLessThan $userIndex
        $aliasIndex | Should -BeLessThan $userIndex
        $dockerfileContent | Should -Match 'ln -s /usr/bin/fdfind /usr/local/bin/fd'
        $dockerfileContent | Should -Match 'ln -s /usr/bin/batcat /usr/local/bin/bat'
        $dockerfileContent | Should -Match "stat -c '%u:%g' /usr/local/bin/fd"
        $dockerfileContent | Should -Match "stat -c '%u:%g' /usr/local/bin/bat"
        $smokeContent | Should -Match '\[\[ "\$\(id -un\)" != autopilot \|\| -w /usr/local/bin \]\]'
        $smokeContent | Should -Match 'readlink /usr/local/bin/fd\)" == /usr/bin/fdfind'
        $smokeContent | Should -Match 'readlink /usr/local/bin/bat\)" == /usr/bin/batcat'

        $smokeContent | Should -Match 'skalary/container-toolchain-smoke@1'
        $smokeContent | Should -Match '\$\{package_version:0:128\}'
        $smokeContent | Should -Match 'head -c 64'
        $smokeContent | Should -Match '\.\[0:253\]'
        $smokeContent | Should -Match '\$\{#json\} > 65535'
        $smokeContent | Should -Match 'printf ''%s\\n'' "\$json"'
        $smokeContent | Should -Match '\$cases \+ \[\{id:\$id,state:\$state,version:\$version\}\]'
        $smokeContent | Should -Match '(?s)if \[\[ ! -f "\$provenance_dir/\$provenance_file" \|\| ! -r "\$provenance_dir/\$provenance_file" \|\| ! -s "\$provenance_dir/\$provenance_file" \]\]; then\s+provenance_ready=false\s+overall_state=fail'
        $smokeContent | Should -Match '\[\[ -f "\$manifest_path" && -r "\$manifest_path" && -s "\$manifest_path" \]\]'
        $smokeContent | Should -Match '(?s)if file_digest="\$\(sha256sum "\$provenance_dir/\$provenance_file".*?\)" &&\s+\[\[ "\$file_digest" =~ \^\[a-f0-9\]\{64\}\$ \]\]; then.*?else\s+provenance_ready=false\s+overall_state=fail'
        $smokeContent | Should -Match '!\s+"\$manifest_digest"\s+=~ \^\[a-f0-9\]\{64\}\$'
        $smokeContent | Should -Match '!\s+"\$provenance_digest"\s+=~ \^\[a-f0-9\]\{64\}\$'
        $smokeContent | Should -Match '(?s)if next_cases_json="\$\(.*?jq -cn.*?\)"; then\s+cases_json="\$next_cases_json"\s+else\s+cases_json=''\[\]''\s+encoder_failed=true\s+overall_state=fail'
        $smokeContent | Should -Match '(?s)if ! apt_hosts_json="\$\(.*?jq -Rsc.*?\)"; then\s+apt_hosts_json=''\[\]''\s+encoder_failed=true\s+overall_state=fail'
        $smokeContent | Should -Match '(?s)if ! json="\$\(.*?jq -cn.*?\)"; then\s+encoder_failed=true\s+overall_state=fail\s+json="\$fallback_json"'
        $smokeContent | Should -Match '\[\[ "\$encoder_failed" == true \]\] \|\| \(\( \$\{#json\} > 65535 \)\)'
        $smokeContent | Should -Match '(?s)if ! printf ''%s\\n'' "\$json"; then\s+exit 1\s+fi\s+\[\[ "\$overall_state" == pass \]\]'

        $primarySchemaMatch = [regex]::Match(
            $smokeContent,
            '(?s)--argjson cases "\$cases_json"\s*\\\s*''(?<filter>\{.*?\})''\s*\)"')
        $primarySchemaMatch.Success | Should -BeTrue
        ($primarySchemaMatch.Groups['filter'].Value -replace '\s+', '') |
            Should -Be '{schema:$schema,state:$state,origin:{os:$os,aptHosts:$aptHosts},digests:{manifestSha256:$manifestSha256,provenanceSha256:$provenanceSha256},cases:$cases}'

        $fallbackMatch = [regex]::Match(
            $smokeContent,
            "(?m)^\s*fallback_json='(?<json>\{`"schema`":`"skalary/container-toolchain-smoke@1`".+\})'\s*$")
        $fallbackMatch.Success | Should -BeTrue
        $fallback = $fallbackMatch.Groups['json'].Value | ConvertFrom-Json
        (@($fallback.PSObject.Properties.Name) -join ',') | Should -Be 'schema,state,origin,digests,cases'
        (@($fallback.origin.PSObject.Properties.Name) -join ',') | Should -Be 'os,aptHosts'
        (@($fallback.digests.PSObject.Properties.Name) -join ',') | Should -Be 'manifestSha256,provenanceSha256'

        foreach ($relativePath in @(
                'devcontainer/Dockerfile',
                'devcontainer/toolchain.tsv',
                'devcontainer/container-toolchain-smoke.sh'
            )) {
            $canonical = Join-Path $pluginRoot $relativePath
            $installed = Join-Path $installedRoot $relativePath
            (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
        }

        $pluginManifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw | ConvertFrom-Json -Depth 100
        $expectedMappings = @{
            'devcontainer/Dockerfile'                    = 'skills/autopilot/devcontainer/Dockerfile'
            'devcontainer/toolchain.tsv'                 = 'skills/autopilot/devcontainer/toolchain.tsv'
            'devcontainer/container-toolchain-smoke.sh'  = 'skills/autopilot/devcontainer/container-toolchain-smoke.sh'
        }
        foreach ($source in $expectedMappings.Keys) {
            $mapping = @($pluginManifest.files | Where-Object src -EQ $source)
            $mapping.Count | Should -Be 1
            $mapping[0].dest | Should -Be $expectedMappings[$source]
        }

        $registry = Get-Content -LiteralPath (Join-Path $repoRoot 'registry.json') -Raw | ConvertFrom-Json -Depth 100
        $registryPlugin = @($registry.plugins | Where-Object name -EQ 'autopilot')
        $registryPlugin.Count | Should -Be 1
        $registryPlugin[0].version | Should -Be $pluginManifest.version
        foreach ($source in $expectedMappings.Keys) {
            $entry = @($registryPlugin[0].files | Where-Object src -EQ $source)
            $entry.Count | Should -Be 1
            $entry[0].dest | Should -Be $expectedMappings[$source]
            $entry[0].sha256 | Should -Be (
                Get-FileHash -LiteralPath (Join-Path $pluginRoot $source) -Algorithm SHA256
            ).Hash.ToLowerInvariant()
        }

        $marketplace = Get-Content -LiteralPath (Join-Path $repoRoot '.github/plugin/marketplace.json') -Raw | ConvertFrom-Json -Depth 100
        @($marketplace.plugins | Where-Object name -EQ 'autopilot')[0].version |
            Should -Be $pluginManifest.version

        $launcher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch-container.ps1') -Raw
        $launcher | Should -Match "\`$bundleRoot = Join-Path \`$PSScriptRoot '\.\.'"
        $launcher | Should -Match "\`$dockerfilePath = Join-Path \`$bundleRoot 'devcontainer/Dockerfile'"
        $launcher | Should -Match '\$buildContext = \$bundleRoot'
        $launcher | Should -Match 'docker build @buildArgs -t \$ImageName -f \$actualDockerfile \$buildContext'
    }
}

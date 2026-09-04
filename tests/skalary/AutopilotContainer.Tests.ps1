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
                "apt-config dump | grep -Eiq '^[[:space:]]*(Binary::[^[:space:]]+::(Root)?Dir|RootDir)([[:space:]]|::)'",
                'apt-config shell apt_root Dir',
                'apt-config shell apt_etc Dir::Etc',
                'apt-config shell apt_source_list Dir::Etc::sourcelist',
                'apt-config shell apt_source_parts Dir::Etc::sourceparts',
                # The unscoped values above are what `apt-config` reports for itself. A
                # `Binary::apt-get::`-scoped override leaves them untouched, and `RootDir` moves
                # the resolved path without changing the relative one, so the policy also asserts
                # where the source list *resolves* — the one reading neither evasion survives.
                "apt-config shell apt_source_list_path Dir::Etc::sourcelist/f",
                "apt-config shell apt_source_parts_path Dir::Etc::sourceparts/d",
                # A tree the gate reads is worth nothing while `APT_CONFIG` names another one, a
                # proxy answers for an allowlisted host, or a trust setting accepts what it
                # returns unsigned. The build refuses all three at the layer that installs, and
                # again at the layer that records what was installed, so the host-side gate is
                # confirming a policy the image already enforced rather than being its only
                # holder.
                'echo "APT_CONFIG must not be set" >&2; exit 1;',
                'for proxy_var in http_proxy https_proxy ftp_proxy all_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY; do',
                "if apt-config dump | grep -Eiq '^[[:space:]]*[^[:space:]]*proxy'; then",
                'echo "APT proxy configuration is not allowed" >&2; exit 1;',
                'trust_value="$(apt-config shell apt_trust "$trust_key/b")";',
                'echo "APT trust-weakening setting is not allowed: $trust_key" >&2; exit 1;',
                'verify_value="$(apt-config shell apt_verify "$verify_key/b")";',
                'echo "APT verification must not be disabled: $verify_key" >&2; exit 1;',
                'print "Trust-bypassing apt source option in " FILENAME ": " $0 > "/dev/stderr"; exit 1',
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

            # The install layer and the final root layer are separate claims: the first refuses a
            # configuration that would fetch the manifest's packages from somewhere else, and the
            # last refuses one introduced by any layer after it — including whatever a maintainer
            # adds at the documented extension anchor. A policy present once is a policy one of
            # those two layers is running without, so each token is required in both.
            foreach ($token in @(
                    'echo "APT_CONFIG must not be set" >&2; exit 1;',
                    'for proxy_var in http_proxy https_proxy ftp_proxy all_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY; do',
                    'echo "APT proxy configuration is not allowed" >&2; exit 1;',
                    'echo "APT trust-weakening setting is not allowed: $trust_key" >&2; exit 1;',
                    'echo "APT verification must not be disabled: $verify_key" >&2; exit 1;',
                    'print "Trust-bypassing apt source option in " FILENAME ": " $0 > "/dev/stderr"; exit 1'
                )) {
                $occurrences = @([regex]::Matches($Dockerfile, [regex]::Escape($token))).Count
                if ($occurrences -ne 2) {
                    $errors.Add("Dockerfile must enforce '$token' in both the install layer and the final root layer (found $occurrences).")
                }
            }

            # Every network fetch that is later installed with root trust must be bound to a digest
            # or key fingerprint in this file; an unverified root install is the hole these tokens
            # exist to close. Counting fetches against verifications repo-wide cannot tell which
            # verification belongs to which fetch — three fetches and three unrelated `sha256sum -c -`
            # calls satisfy a count while leaving each fetch unverified — so the check is per `RUN`
            # block, and a floor keeps it from passing vacuously if the blocks are ever restructured
            # away.
            $curlFetches = @([regex]::Matches($Dockerfile, '(?m)curl\s+(?<flags>-[A-Za-z]+)\s'))
            foreach ($fetch in $curlFetches) {
                if ($fetch.Groups['flags'].Value -notmatch 'f') {
                    $errors.Add('Dockerfile curl fetches must fail on HTTP error status.')
                    break
                }
            }
            $runBlocks = @([regex]::Matches(
                    $Dockerfile,
                    '(?ms)^RUN\s.*?(?=^(?:RUN|COPY|ADD|USER|WORKDIR|ENV|ARG|FROM|SHELL|ENTRYPOINT|CMD|#)\s|\z)'))
            # An *invocation*, not the word: `bootstrap_packages=(git curl jq ...)` names curl as a
            # package to install, and treating that as a fetch would demand a digest check in a
            # layer that fetches nothing.
            $fetchPattern = '(?:^|[\s;&|(])(?:curl|wget)\s+(?:-|["'']?https?://)'
            $fetchingBlocks = @($runBlocks | Where-Object { $_.Value -match $fetchPattern })
            if ($fetchingBlocks.Count -lt 3) {
                $errors.Add("Dockerfile has $($fetchingBlocks.Count) root-trusted fetch blocks; the pinning check needs at least 3 to be meaningful.")
            }
            foreach ($block in $fetchingBlocks) {
                $blockText = $block.Value
                $hasDigestCheck = $blockText -match 'sha256sum -c -'
                $hasPinnedKeyExport = $blockText -match 'gpg --batch --export [0-9A-F]{40}' -and
                    $blockText -match '(?m)grep -qx [0-9A-F]{40}'
                if (-not ($hasDigestCheck -or $hasPinnedKeyExport)) {
                    $firstLine = @($blockText -split "`n")[0].Trim()
                    $errors.Add("Dockerfile fetch block '$firstLine' installs with root trust but verifies no digest or pinned key fingerprint.")
                }
            }

            # A fetched key file may carry more than one key. Dearmoring the whole file into the
            # keyring named by `signed-by=` would trust every key in it, and a check that the
            # pinned fingerprint is merely present cannot tell that case from the honest one, so
            # the keyring must be built by exporting exactly the pinned key.
            if ($Dockerfile -match '(?m)--dearmor[^\n]*/usr/share/keyrings') {
                $errors.Add('Dockerfile must not dearmor a fetched key file straight into a signed-by keyring.')
            }
            if ($Dockerfile -notmatch '(?m)gpg --batch --export 9DC858229FC7DD38854AE2D88D81803C0EBFCD88') {
                $errors.Add('Dockerfile must export only the pinned Docker key into its keyring.')
            }
            if ($Dockerfile -notmatch '(?m)test "\$\(wc -l < /tmp/docker-primaries\.txt\)" -eq 1') {
                $errors.Add('Dockerfile must assert the Docker keyring holds exactly one primary key.')
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
            # A source that waives its own signature check must be refused before the host
            # allowlist reads it, not after: the waiver names no new host, so every later check
            # passes on it, and an install between the two would already have happened unsigned.
            $sourceTrustIndex = $Dockerfile.IndexOf('print "Trust-bypassing apt source option in "', [System.StringComparison]::Ordinal)
            if ($sourceTrustIndex -lt 0 -or $sourceDiscoveryIndex -lt 0 -or $hostValidationIndex -lt 0) {
                $errors.Add('Dockerfile is missing the source discovery, trust-option, or host validation anchor.')
            }
            elseif ($sourceTrustIndex -lt $sourceDiscoveryIndex -or $sourceTrustIndex -gt $hostValidationIndex) {
                $errors.Add('Dockerfile must reject trust-bypassing source options after discovering the source files and before validating their hosts.')
            }
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
            $extensionAnchor = $Dockerfile.IndexOf('# Non-root user', [System.StringComparison]::Ordinal)
            if ($finalProvenanceIndex -lt 0 -or $dockerCliIndex -lt 0 -or $nonRootIndex -lt 0 -or $extensionAnchor -lt 0) {
                $errors.Add('Dockerfile is missing the final root-layer provenance, Docker CLI, extension, or non-root anchor.')
            }
            elseif ($finalProvenanceIndex -lt $dockerCliIndex -or $finalProvenanceIndex -gt $nonRootIndex) {
                # Provenance captured before the last root install describes an image that is never
                # shipped, which is exactly the gap the final capture exists to close.
                $errors.Add('Final provenance capture must run after the last root install and before the non-root user.')
            }
            elseif ($finalProvenanceIndex -lt $extensionAnchor) {
                # `# Non-root user` is the documented extension anchor. A capture above it omits
                # whatever is added there, which reproduces the gap at the one place maintainers are
                # told to edit.
                $errors.Add('Final provenance capture must run after the documented extension anchor, not before it.')
            }
            else {
                # "Last root layer" is the claim; a RUN between the capture and USER would falsify it
                # while every index above still ordered correctly.
                $tail = $Dockerfile.Substring($finalProvenanceIndex, $nonRootIndex - $finalProvenanceIndex)
                if ($tail -match '(?m)^RUN\s') {
                    $errors.Add('Final provenance capture must be the last root layer; a RUN follows it before USER autopilot.')
                }
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
        $smokeContent | Should -Match '\[\[ "\$\(id -un\)" != autopilot \]\]'
        $smokeContent | Should -Match '\[\[ -w /usr/local/bin \]\]'
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
        $smokeContent | Should -Match '\[\[ "\$encoder_failed" == true \]\]'
        $smokeContent | Should -Match 'elif \(\( \$\{#json\} > 65535 \)\); then'
        $smokeContent | Should -Match '(?s)if ! printf ''%s\\n'' "\$json"; then\s+exit 1\s+fi\s+\[\[ "\$overall_state" == pass \]\]'

        $primarySchemaMatch = [regex]::Match(
            $smokeContent,
            '(?s)--argjson cases "\$cases_json"\s*\\\s*''(?<filter>\{.*?\})''\s*\)"')
        $primarySchemaMatch.Success | Should -BeTrue
        ($primarySchemaMatch.Groups['filter'].Value -replace '\s+', '') |
            Should -Be '{schema:$schema,state:$state,reasons:$reasons,origin:{os:$os,aptHosts:$aptHosts},digests:{manifestSha256:$manifestSha256,provenanceSha256:$provenanceSha256},cases:$cases}'

        # A whole-run failure with no case to blame used to emit a bare `state=fail`. The reasons
        # vocabulary must stay closed and must match the host's allow-list exactly, because the host
        # rejects any value outside it — a drift here turns every affected failure into
        # `candidate-output-invalid` instead of the diagnosis it was meant to carry.
        $expectedReasons = @(
            'case-count-mismatch',
            'encoder-failed',
            'manifest-digest-unavailable',
            'manifest-duplicate-case',
            'manifest-unreadable',
            'not-autopilot-user',
            'output-oversize',
            'provenance-digest-unavailable',
            'provenance-incomplete',
            'usr-local-bin-writable')
        $emittedReasons = @([regex]::Matches($smokeContent, '(?m)^\s*add_reason\s+(?<reason>[a-z][a-z0-9-]*)\s*$') |
                ForEach-Object { $_.Groups['reason'].Value } |
                Sort-Object -Unique)
        $literalReasons = @([regex]::Matches($smokeContent, '(?m)^\s*(?:reasons_json|fallback_json|oversize_json)=.*?"reasons":\[(?<body>[^\]]*)\]') |
                ForEach-Object { [regex]::Matches($_.Groups['body'].Value, '"(?<reason>[^"]+)"') } |
                ForEach-Object { $_.Groups['reason'].Value })
        $literalReasons += @([regex]::Matches($smokeContent, "(?m)^\s*reasons_json='\[(?<body>[^\]]*)\]'") |
                ForEach-Object { [regex]::Matches($_.Groups['body'].Value, '"(?<reason>[^"]+)"') } |
                ForEach-Object { $_.Groups['reason'].Value })
        $allReasons = @(@($emittedReasons) + @($literalReasons) | Sort-Object -Unique)
        foreach ($errorText in @(Compare-OrdinalSet `
                    -Label 'Smoke failure reason vocabulary' `
                    -Actual $allReasons `
                    -Expected $expectedReasons)) {
            throw $errorText
        }
        $fallbackMatch = [regex]::Match(
            $smokeContent,
            "(?m)^\s*fallback_json='(?<json>\{`"schema`":`"skalary/container-toolchain-smoke@1`".+\})'\s*$")
        $fallbackMatch.Success | Should -BeTrue
        $fallback = $fallbackMatch.Groups['json'].Value | ConvertFrom-Json
        (@($fallback.PSObject.Properties.Name) -join ',') | Should -Be 'schema,state,reasons,origin,digests,cases'
        (@($fallback.origin.PSObject.Properties.Name) -join ',') | Should -Be 'os,aptHosts'
        (@($fallback.digests.PSObject.Properties.Name) -join ',') | Should -Be 'manifestSha256,provenanceSha256'
        # The fallback is emitted precisely when the encoder failed, so it must say so rather than
        # falling back to a shape that reports failure without a reason.
        (@($fallback.reasons) -join ',') | Should -Be 'encoder-failed'

        $oversizeMatch = [regex]::Match(
            $smokeContent,
            "(?m)^\s*oversize_json='(?<json>\{`"schema`":`"skalary/container-toolchain-smoke@1`".+\})'\s*$")
        $oversizeMatch.Success | Should -BeTrue
        $oversize = $oversizeMatch.Groups['json'].Value | ConvertFrom-Json
        (@($oversize.PSObject.Properties.Name) -join ',') | Should -Be 'schema,state,reasons,origin,digests,cases'
        (@($oversize.reasons) -join ',') | Should -Be 'output-oversize'

        # The image records apt origins twice — a Debian-baseline capture and a final capture — and
        # the gate holds each to a different allowlist. The two recorders read `Enabled:` differently,
        # and the direction of that difference is the whole safety argument, so it is pinned here
        # rather than left to whoever edits the awk next.
        #
        # The final capture is the enforcement set: it must stay over-inclusive, recording the URIs
        # of a disabled stanza too. If it learned to honour `Enabled: no`, a hostile source could be
        # parked in the image disabled — invisible to the gate, one `sed` away from being live.
        $finalRecorder = [regex]::Match(
            $dockerfileContent,
            '(?s)(?<block>: > /tmp/autopilot-final-apt-uris;.*?>> /tmp/autopilot-final-apt-uris;)')
        $finalRecorder.Success | Should -BeTrue
        $finalRecorder.Groups['block'].Value |
            Should -Not -Match '(?i)\[Ee\]\[Nn\]\[Aa\]\[Bb\]\[Ll\]\[Ee\]\[Dd\]' -Because 'the enforced capture must record disabled sources too'
        # And it must reject anything that is not a plain http(s) URI, so an origin form the host-side
        # scan reports as a pseudo-host cannot reach the enforced file unnoticed.
        $dockerfileContent | Should -Match '(?s)Unsupported final apt source URI.*?final-apt-sources\.txt'

        # The baseline capture is the narrower claim — "what the Debian layer actually resolves from",
        # held to Debian hosts only — so it honours `Enabled:` deliberately. A disabled non-Debian
        # source omitted here is still caught by the final capture above, which is why the asymmetry
        # is safe in this direction and only in this direction. The block is anchored on the write
        # that produces the file rather than on the first loop over the source files, so a check
        # added ahead of the recorder cannot be mistaken for the recorder itself.
        $baselineRecorder = [regex]::Match(
            $dockerfileContent,
            '(?s)(?<block>: > /tmp/autopilot-apt-source-uris;.*?done \| LC_ALL=C sort -u > /tmp/autopilot-apt-source-uris;)')
        $baselineRecorder.Success | Should -BeTrue
        $baselineRecorder.Groups['block'].Value |
            Should -Match '\[Ee\]\[Nn\]\[Aa\]\[Bb\]\[Ll\]\[Ee\]\[Dd\]' -Because 'the baseline capture states the effective Debian source set'

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

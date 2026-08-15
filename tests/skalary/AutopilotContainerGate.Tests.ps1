#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot container gate runner' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:runnerPath = Join-Path $script:repoRoot 'scripts/skalary/Invoke-ContainerToolchainGate.ps1'
        . $script:runnerPath
        $script:headSha = (& git -C $script:repoRoot rev-parse HEAD).Trim()
    }

    It 'test:AutopilotContainer.GateRunnerContract enforces gate runner invariants' {
        $modeAttribute = (Get-Command Invoke-ContainerToolchainGate).Parameters.Mode.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        @($modeAttribute.ValidValues) | Should -Be @('Detect', 'Measure', 'VerifyResult')

        $context = Get-ContainerGateContext -CheckoutRoot $repoRoot
        $context.Payload.Count | Should -BeGreaterOrEqual 5
        $parity = Test-ContainerPayloadParity -CheckoutRoot $repoRoot
        $parity.Valid | Should -BeTrue
        (Test-GateDockerfileBase -Path $context.InstalledDockerfilePath) | Should -BeTrue
        (Test-GateConcreteVersion '1.2.3') | Should -BeTrue
        (Test-GateConcreteVersion '1.2.3-beta.1+build.7') | Should -BeTrue
        foreach ($floatingVersion in @('latest', 'beta', '1', '1.2', '*')) {
            (Test-GateConcreteVersion $floatingVersion) | Should -BeFalse
        }
        @($parity.Entries | Where-Object {
                $_['canonicalSha256'] -ne $_['installedSha256']
            }) | Should -BeNullOrEmpty

        $pathSet = @(Get-ContainerGatePathSet -CheckoutRoot $repoRoot)
        foreach ($path in @(
                'plugins/autopilot/plugin.json',
                'plugins/autopilot/devcontainer/Dockerfile',
                'plugins/autopilot/devcontainer/toolchain.tsv',
                'plugins/autopilot/devcontainer/container-toolchain-smoke.sh',
                'plugins/autopilot/.dockerignore',
                'plugins/autopilot/devcontainer/Dockerfile.dockerignore',
                'plugins/autopilot/scripts/container-entrypoint.sh',
                'plugins/autopilot/scripts/launch-container.ps1',
                '.github/skills/autopilot/devcontainer/Dockerfile',
                '.github/skills/autopilot/.dockerignore',
                '.github/skills/autopilot/devcontainer/Dockerfile.dockerignore',
                'scripts/skalary/Invoke-ContainerToolchainGate.ps1',
                '.github/workflows/autopilot-container-ci.yml',
                'tests/skalary/AutopilotContainer.Tests.ps1',
                'tests/skalary/AutopilotContainerGate.Tests.ps1'
            )) {
            $pathSet | Should -Contain $path
        }

        foreach ($identityCase in @('pull-request-merge', 'main-push')) {
            $identity = Get-ContainerGateDetection -BaseSha $headSha -CandidateSha $headSha `
                -BaseRoot $repoRoot -CandidateRoot $repoRoot
            $identity.Relevant | Should -BeFalse -Because $identityCase
        }
        {
            Get-ContainerGateDetection -BaseSha $headSha -CandidateSha ('e' * 40) `
                -BaseRoot $repoRoot -CandidateRoot $repoRoot
        } | Should -Throw '*Candidate checkout HEAD*'

        $zero = Get-ContainerGateDetection -BaseSha ('0' * 40) -CandidateSha $headSha `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot
        $zero.Relevant | Should -BeTrue
        $zero.CandidateOnlyReason | Should -Be 'zero-base'

        $unreachable = Get-ContainerGateDetection -BaseSha ('f' * 40) -CandidateSha $headSha `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot
        $unreachable.Relevant | Should -BeTrue
        $unreachable.CandidateOnlyReason | Should -Be 'base-unreachable'
        $missingBase = Get-ContainerGateDetection -BaseSha $headSha -CandidateSha $headSha `
            -BaseRoot (Join-Path $TestDrive 'absent-base') -CandidateRoot $repoRoot
        $missingBase.Relevant | Should -BeTrue
        $missingBase.CandidateOnlyReason | Should -Be 'base-unreachable'

        $expectedTruth = @{
            'success|false|skipped' = $true
            'success|true|success' = $true
        }
        foreach ($detector in @('success', 'failure', 'cancelled', 'skipped', 'timed_out')) {
            foreach ($relevanceValue in @('true', 'false', 'invalid')) {
                foreach ($image in @('success', 'failure', 'cancelled', 'skipped', 'timed_out')) {
                    $key = "$detector|$relevanceValue|$image"
                    (Test-ContainerGateResult $detector $relevanceValue $image) |
                        Should -Be $expectedTruth.ContainsKey($key) -Because $key
                }
            }
        }

        foreach ($reason in @(
                'zero-base', 'base-unreachable', 'base-context-absent',
                'base-payload-drift', 'base-build-failed', 'base-timeout'
            )) {
            $candidateOnly = New-ContainerGateReceipt -Outcome success -Relevant $true `
                -Comparison candidate-only -CandidateOnlyReason $reason -CandidateBytes 123
            $candidateOnly.candidateOnlyReason | Should -Be $reason
            $candidateOnly.measurement.deltaBytes | Should -BeNullOrEmpty
        }

        foreach ($outcome in @(
                'success', 'irrelevant', 'candidate-build-failed', 'candidate-smoke-failed',
                'candidate-output-invalid', 'candidate-timeout', 'base-build-failed',
                'base-timeout', 'unexpected-error'
            )) {
            $terminal = New-ContainerGateReceipt -Outcome $outcome -Relevant $true
            $terminal.schema | Should -Be 'skalary/container-toolchain-receipt@1'
            $terminal.outcome | Should -Be $outcome
        }

        $advisory = New-ContainerGateReceipt -Outcome success -Relevant $true -Comparison comparable `
            -CandidateBytes (501MB) -BaseBytes (200MB) -DeltaBytes (301MB) -AdvisoryGrowthMiB 250
        $advisory.advisory | Should -BeTrue
        $advisory.blocking | Should -BeFalse
        $largeImage = New-ContainerGateReceipt -Outcome success -Relevant $true `
            -CandidateBytes ([int64]3GB)
        $largeImage.measurement.candidateBytes | Should -Be ([int64]3GB)

        $encoded = ConvertTo-GateMarkdown "x|y`n<script>`${{ hostile }}"
        $encoded | Should -Not -Match '[\r\n]'
        $encoded | Should -Not -Match '<script>'
        $encoded | Should -Match '\\\|'

        $receiptA = Join-Path $TestDrive 'receipt-a.json'
        $receiptB = Join-Path $TestDrive 'receipt-b.json'
        $deterministic = New-ContainerGateReceipt -Outcome success -Relevant $true `
            -BaseSha ('a' * 40) -CandidateSha ('b' * 40) -CandidateBytes 2 -BaseBytes 1 -DeltaBytes 1
        $jsonA = Write-ContainerGateReceipt -Receipt $deterministic -Path $receiptA
        $jsonB = Write-ContainerGateReceipt -Receipt $deterministic -Path $receiptB
        $jsonA | Should -BeExactly $jsonB
        (Get-Item -LiteralPath $receiptA).Length | Should -BeLessOrEqual 65535
        (Get-Content -LiteralPath $receiptA -Raw | ConvertFrom-Json).schema |
            Should -Be 'skalary/container-toolchain-receipt@1'

        $directReceiptPath = Join-Path $TestDrive 'direct-receipt.json'
        & pwsh -NoProfile -File $runnerPath `
            -BaseSha ('0' * 40) -CandidateSha $headSha `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot -ReceiptPath $directReceiptPath | Out-Null
        $LASTEXITCODE | Should -Be 0
        $directReceipt = Get-Content -LiteralPath $directReceiptPath -Raw | ConvertFrom-Json
        $directReceipt.identities.architecture | Should -Not -BeNullOrEmpty
        $invalidResultReceiptPath = Join-Path $TestDrive 'invalid-result-receipt.json'
        $invalidResult = Invoke-ContainerToolchainGate -Mode VerifyResult `
            -DetectorConclusion success -Relevance invalid -ImageConclusion skipped `
            -ReceiptPath $invalidResultReceiptPath
        $invalidResult.ExitCode | Should -Be 1
        (Get-Content -LiteralPath $invalidResultReceiptPath -Raw | ConvertFrom-Json).outcome |
            Should -Be 'unexpected-error'

        $fallbackPath = Join-Path $TestDrive 'fallback.json'
        $oversized = [ordered]@{ diagnostic = 'x' * 70000 }
        [void](Write-ContainerGateReceipt -Receipt $oversized -Path $fallbackPath)
        $fallback = Get-Content -LiteralPath $fallbackPath -Raw | ConvertFrom-Json
        $fallback.schema | Should -Be 'skalary/container-toolchain-receipt@1'
        $fallback.outcome | Should -Be 'unexpected-error'

        $provenancePath = Join-Path $TestDrive 'provenance.json'
        $provenanceSha = Write-ContainerGateProvenance -Provenance ([ordered]@{
                schema = 'skalary/container-toolchain-provenance@1'
                payload = @([ordered]@{ source = 'a'; sha256 = ('1' * 64) })
            }) -Path $provenancePath
        $provenanceSha | Should -BeExactly (
            Get-FileHash -LiteralPath $provenancePath -Algorithm SHA256).Hash.ToLowerInvariant()

        $manifestPath = Join-Path $repoRoot 'plugins/autopilot/devcontainer/toolchain.tsv'
        $caseIds = @(Get-Content -LiteralPath $manifestPath | Where-Object {
                $_ -and -not $_.TrimStart().StartsWith('#')
            } | ForEach-Object { ($_ -split "`t", 3)[0] })
        $smokeValue = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'pass'
            origin = [ordered]@{ os = 'debian:13'; aptHosts = @('deb.debian.org') }
            digests = [ordered]@{ manifestSha256 = ('a' * 64); provenanceSha256 = ('b' * 64) }
            cases = @($caseIds | ForEach-Object {
                    [ordered]@{ id = $_; state = 'pass'; version = '1.0' }
                })
        }
        $validSmoke = Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
            -ManifestPath $manifestPath
        $validSmoke.Valid | Should -BeTrue
        $smokeValue.cases[0].state = 'fail'
        $invalidSmoke = Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
            -ManifestPath $manifestPath
        $invalidSmoke.Valid | Should -BeFalse
        $invalidSmoke.Summary | Should -Be 'Passing smoke output contains a failed case.'
        $smokeValue.cases[0].state = 'pass'
        $smokeValue.cases[0].version = $null
        (Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
                -ManifestPath $manifestPath).Valid | Should -BeFalse
        $smokeValue.cases[0].version = '1.0'
        $smokeValue.origin.os = $null
        (Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
                -ManifestPath $manifestPath).Valid | Should -BeFalse
        $smokeValue.origin.os = 'debian:13'
        $smokeValue.state = 'fail'
        $smokeValue.cases[0].state = 'fail'
        $validFailureSmoke = Test-GateSmokeOutput -Output (
            $smokeValue | ConvertTo-Json -Depth 8 -Compress) -ManifestPath $manifestPath
        $validFailureSmoke.Valid | Should -BeTrue
        $validFailureSmoke.Summary | Should -Match 'state=fail'

        $savedCulture = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            @(Sort-GateOrdinal @('b', 'A', 'a', 'B')) | Should -BeExactly @('A', 'B', 'a', 'b')
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $savedCulture
        }

        $payloadFixture = Join-Path $TestDrive 'payload'
        $fixturePaths = @('plugins/autopilot/plugin.json') + @(
            $context.Payload | ForEach-Object { $_.CanonicalRelative; $_.InstalledRelative }
        )
        foreach ($relativePath in @($fixturePaths | Sort-Object -Unique)) {
            $destination = Join-Path $payloadFixture $relativePath
            [void](New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force)
            Copy-Item -LiteralPath (Join-Path $repoRoot $relativePath) -Destination $destination
        }
        (Test-ContainerPayloadParity -CheckoutRoot $payloadFixture).Valid | Should -BeTrue
        Set-Content -LiteralPath (Join-Path $payloadFixture 'plugins/autopilot/.dockerignore') `
            -Value 'artifacts/' -Encoding utf8NoBOM
        (Test-ContainerPayloadParity -CheckoutRoot $payloadFixture).Reason | Should -Be 'context-absent'
        Remove-Item -LiteralPath (Join-Path $payloadFixture 'plugins/autopilot/.dockerignore') -Force
        $fixturePluginPath = Join-Path $payloadFixture 'plugins/autopilot/plugin.json'
        $fixturePluginText = Get-Content -LiteralPath $fixturePluginPath -Raw
        $fixturePluginText.Replace(
            '"dest": "skills/autopilot/devcontainer/toolchain.tsv"',
            '"dest": "skills/autopilot/devcontainer/relocated-toolchain.tsv"'
        ) | Set-Content -LiteralPath $fixturePluginPath -Encoding utf8NoBOM -NoNewline
        { Get-ContainerGateContext -CheckoutRoot $payloadFixture } |
            Should -Throw '*must preserve its path beneath the installed Docker build context*'
        Set-Content -LiteralPath $fixturePluginPath -Value $fixturePluginText -Encoding utf8NoBOM -NoNewline
        if (-not $IsWindows) {
            $installedManifest = Join-Path $payloadFixture '.github/skills/autopilot/devcontainer/toolchain.tsv'
            Remove-Item -LiteralPath $installedManifest -Force
            [void](New-Item -ItemType SymbolicLink -Path $installedManifest `
                    -Target (Join-Path $payloadFixture 'plugins/autopilot/devcontainer/toolchain.tsv'))
            (Test-ContainerPayloadParity -CheckoutRoot $payloadFixture).Reason | Should -Be 'context-absent'
            Remove-Item -LiteralPath $installedManifest -Force
            Copy-Item -LiteralPath (Join-Path $payloadFixture 'plugins/autopilot/devcontainer/toolchain.tsv') `
                -Destination $installedManifest
        }
        Add-Content -LiteralPath (
            Join-Path $payloadFixture '.github/skills/autopilot/devcontainer/toolchain.tsv') -Value '# drift'
        (Test-ContainerPayloadParity -CheckoutRoot $payloadFixture).Reason | Should -Be 'payload-drift'
        $installedDockerfile = Join-Path $payloadFixture '.github/skills/autopilot/devcontainer/Dockerfile'
        (Get-Content -LiteralPath $installedDockerfile -Raw).Replace(
            'FROM debian:trixie-slim',
            'FROM docker.io/library/debian:stable'
        ) | Set-Content -LiteralPath $installedDockerfile -Encoding utf8NoBOM -NoNewline
        (Test-GateDockerfileBase -Path $installedDockerfile) | Should -BeFalse
        (Get-Content -LiteralPath (
                Join-Path $repoRoot 'plugins/autopilot/devcontainer/Dockerfile') -Raw).Replace(
                'FROM debian:trixie-slim',
                'FROM --platform=linux/arm64 debian:trixie-slim'
        ) | Set-Content -LiteralPath $installedDockerfile -Encoding utf8NoBOM -NoNewline
        (Test-GateDockerfileBase -Path $installedDockerfile) | Should -BeFalse
        $canonicalDockerfile = Join-Path $payloadFixture 'plugins/autopilot/devcontainer/Dockerfile'
        $canonicalDockerfileText = Get-Content -LiteralPath $canonicalDockerfile -Raw
        Add-Content -LiteralPath $canonicalDockerfile -Value 'copy scripts/unmapped.sh /tmp/unmapped.sh'
        { Get-ContainerGateContext -CheckoutRoot $payloadFixture } |
            Should -Throw "*plugin.json must map Docker input 'scripts/unmapped.sh'*"
        Set-Content -LiteralPath $canonicalDockerfile -Value $canonicalDockerfileText -Encoding utf8NoBOM -NoNewline
        Add-Content -LiteralPath $canonicalDockerfile -Value 'add scripts/container-entrypoint.sh /tmp/entrypoint.sh'
        { Get-ContainerGateContext -CheckoutRoot $payloadFixture } |
            Should -Throw '*Dockerfile ADD instructions are unsupported*'
        Set-Content -LiteralPath $canonicalDockerfile -Value $canonicalDockerfileText -Encoding utf8NoBOM -NoNewline
        Add-Content -LiteralPath $canonicalDockerfile -Value "COPY \"
        { Get-ContainerGateContext -CheckoutRoot $payloadFixture } |
            Should -Throw '*Continued Dockerfile COPY instructions are unsupported*'
        Remove-Item -LiteralPath (
            Join-Path $payloadFixture '.github/skills/autopilot/devcontainer/Dockerfile') -Force
        (Test-ContainerPayloadParity -CheckoutRoot $payloadFixture).Reason | Should -Be 'context-absent'
    }

    It 'fails closed when bounded process capture overflows or contains controls' {
        $oversized = Invoke-GateProcess -FilePath 'pwsh' -ArgumentList @(
            '-NoProfile', '-Command', '[Console]::Out.Write("x" * 70000); [Console]::Out.Write("TAILMARK")'
        ) -TimeoutSeconds 10
        $oversized.ExitCode | Should -Be 0
        $oversized.StdoutOverflow | Should -BeTrue
        $oversized.Stdout.Length | Should -BeLessOrEqual 65535
        # Head-only capture discards the end of the stream, which is exactly where a build states
        # why it failed, so the retained text must keep both ends and say what it dropped.
        $oversized.Stdout | Should -BeLike '*characters truncated*'
        $oversized.Stdout.StartsWith('xxxx') | Should -BeTrue
        $oversized.Stdout.EndsWith('TAILMARK') | Should -BeTrue

        $controlled = Invoke-GateProcess -FilePath 'pwsh' -ArgumentList @(
            '-NoProfile', '-Command', '[Console]::Out.Write([char]0); [Console]::Out.Write("{}")'
        ) -TimeoutSeconds 10
        $controlled.StdoutInvalidControl | Should -BeTrue

        Mock Invoke-GateProcess {
            [pscustomobject]@{
                ExitCode = 0
                Stderr = ''
                Stdout = "M`0scripts/skalary/Invoke-ContainerToolchainGate.ps1`0"
                StdoutOverflow = $true
            }
        }
        {
            Get-GateChangedPaths -CandidateRoot $TestDrive -BaseSha ('a' * 40) -CandidateSha ('b' * 40)
        } | Should -Throw '*exceeded the capture bound*'
    }

    It 'forces unusable bases relevant before deriving the path set' {
        Mock Test-GateCheckoutHead { $true }
        Mock Get-ContainerGatePathSet { throw 'candidate-controlled context must not run' }
        $zero = Get-ContainerGateDetection -BaseSha ('0' * 40) -CandidateSha $headSha `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot
        $zero.Relevant | Should -BeTrue
        $zero.CandidateOnlyReason | Should -Be 'zero-base'
        Assert-MockCalled Get-ContainerGatePathSet -Times 0 -Exactly
    }

    It 'preserves hostile NUL-delimited Git paths with ordinal literal matching' {
        $hostileNames = @(
            ' leading-dash',
            '-option',
            'quote''"file',
            '$(substitution)',
            "line`nbreak",
            "tab`tpath"
        )
        if ($IsWindows) {
            $records = [System.Collections.Generic.List[string]]::new()
            foreach ($name in $hostileNames) {
                $records.Add('A')
                $records.Add($name)
            }
            $records.Add('D')
            $records.Add('delete me')
            $records.Add('R100')
            $records.Add("rename`nsource")
            $records.Add("renamed`ntarget")
            Mock Invoke-GateProcess {
                [pscustomobject]@{
                    ExitCode = 0
                    Stderr = ''
                    Stdout = (($records -join "`0") + "`0")
                    StdoutOverflow = $false
                }
            }
            $changed = @(Get-GateChangedPaths -CandidateRoot $TestDrive `
                    -BaseSha ('a' * 40) -CandidateSha ('b' * 40))
        }
        else {
            $fixture = Join-Path $TestDrive 'hostile-repo'
            [void](New-Item -ItemType Directory -Path $fixture)
            & git -C $fixture init --quiet
            & git -C $fixture config user.email test@example.invalid
            & git -C $fixture config user.name Test
            Set-Content -LiteralPath (Join-Path $fixture 'seed') -Value seed -NoNewline
            Set-Content -LiteralPath (Join-Path $fixture 'delete me') -Value delete -NoNewline
            Set-Content -LiteralPath (Join-Path $fixture "rename`nsource") -Value rename -NoNewline
            & git -C $fixture add -- .
            & git -C $fixture commit --quiet -m base
            $base = (& git -C $fixture rev-parse HEAD).Trim()

            foreach ($name in $hostileNames) {
                Set-Content -LiteralPath (Join-Path $fixture $name) -Value $name -NoNewline
            }
            Remove-Item -LiteralPath (Join-Path $fixture 'delete me')
            & git -C $fixture mv -- "rename`nsource" "renamed`ntarget"
            & git -C $fixture add -- .
            & git -C $fixture commit --quiet -m candidate
            $candidate = (& git -C $fixture rev-parse HEAD).Trim()
            $changed = @(Get-GateChangedPaths -CandidateRoot $fixture -BaseSha $base -CandidateSha $candidate)
        }
        foreach ($name in $hostileNames) { $changed | Should -Contain $name }
        $changed | Should -Contain 'delete me'
        $changed | Should -Contain "rename`nsource"
        $changed | Should -Contain "renamed`ntarget"
        $changed | Should -Not -Contain 'Leading-dash'
    }

    It 'kills a timed-out process tree and returns bounded diagnostics' {
        # Fixed sleeps make this test a race. The child announces itself, then heartbeats, so the
        # assertion is the invariant that matters: the child really started, and it stopped
        # producing work once the tree was killed.
        $startedMarker = Join-Path $TestDrive 'child-started'
        $heartbeatMarker = Join-Path $TestDrive 'child-heartbeat'
        $childScript = Join-Path $TestDrive 'child.ps1'
        $parentScript = Join-Path $TestDrive 'parent.ps1'
        Set-Content -LiteralPath $childScript -Encoding utf8NoBOM -Value @(
            "Set-Content -LiteralPath '$($startedMarker.Replace("'", "''"))' -Value started",
            'for ($beat = 0; $beat -lt 600; $beat++) {',
            "  Add-Content -LiteralPath '$($heartbeatMarker.Replace("'", "''"))' -Value `$beat",
            '  Start-Sleep -Milliseconds 100',
            '}'
        )
        Set-Content -LiteralPath $parentScript -Encoding utf8NoBOM -Value @(
            "Start-Process -FilePath pwsh -ArgumentList @('-NoProfile','-File','$($childScript.Replace("'", "''"))')",
            'Start-Sleep -Seconds 60'
        )
        # The timeout must outlast two cold pwsh starts, or the tree is killed before the grandchild
        # can announce itself and the test asserts nothing about tree kill.
        $process = Invoke-GateProcess -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-File', $parentScript) -TimeoutSeconds 12
        $process.TimedOut | Should -BeTrue
        $process.ExitCode | Should -Be -1

        $deadline = [datetime]::UtcNow.AddSeconds(10)
        while ([datetime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $startedMarker)) {
            Start-Sleep -Milliseconds 100
        }
        Test-Path -LiteralPath $startedMarker | Should -BeTrue -Because 'the child must really have run'

        $beatsAfterKill = @()
        $stableReadings = 0
        $settleDeadline = [datetime]::UtcNow.AddSeconds(15)
        while ([datetime]::UtcNow -lt $settleDeadline -and $stableReadings -lt 4) {
            Start-Sleep -Milliseconds 250
            $current = @(if (Test-Path -LiteralPath $heartbeatMarker) {
                    Get-Content -LiteralPath $heartbeatMarker
                })
            if ($current.Count -eq $beatsAfterKill.Count) { $stableReadings++ } else { $stableReadings = 0 }
            $beatsAfterKill = $current
        }
        $stableReadings | Should -BeGreaterOrEqual 4 -Because 'the killed child must stop heartbeating'

        $process.Stdout.Length | Should -BeLessOrEqual 65535
        $process.Stderr.Length | Should -BeLessOrEqual 65535
    }

    It 'names failing smoke cases and attests image claims against the trusted host' {
        $manifestPath = Join-Path $repoRoot 'plugins/autopilot/devcontainer/toolchain.tsv'
        $caseIds = @(Get-Content -LiteralPath $manifestPath | Where-Object {
                $_ -and -not $_.TrimStart().StartsWith('#')
            } | ForEach-Object { ($_ -split "`t", 3)[0] })
        $failing = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'fail'
            origin = [ordered]@{ os = 'debian:13'; aptHosts = @('deb.debian.org') }
            digests = [ordered]@{ manifestSha256 = ('a' * 64); provenanceSha256 = ('b' * 64) }
            cases = @($caseIds | ForEach-Object {
                    [ordered]@{
                        id = $_
                        state = if ($_ -in @($caseIds[0], $caseIds[1])) { 'fail' } else { 'pass' }
                        version = '1.0'
                    }
                })
        }
        $validation = Test-GateSmokeOutput -Output ($failing | ConvertTo-Json -Depth 8 -Compress) `
            -ManifestPath $manifestPath
        $validation.Valid | Should -BeTrue
        # A bare count sends a reader to the artifact for the one fact they need.
        @($validation.FailedCases) | Should -Be @(Sort-GateOrdinal @($caseIds[0], $caseIds[1]))
        $validation.Summary | Should -Match "failed=2: "
        foreach ($id in @($caseIds[0], $caseIds[1])) { $validation.Summary | Should -Match ([regex]::Escape($id)) }

        $receipt = New-ContainerGateReceipt -Outcome 'candidate-smoke-failed' -Relevant $true `
            -SmokeSummary $validation.Summary -SmokeFailedCases $validation.FailedCases
        @($receipt.smoke.failedCases) | Should -Be @(Sort-GateOrdinal @($caseIds[0], $caseIds[1]))
        $manyCases = @(1..64 | ForEach-Object { "case-$_" })
        $bounded = New-ContainerGateReceipt -Outcome 'candidate-smoke-failed' -Relevant $true `
            -SmokeFailedCases $manyCases
        @($bounded.smoke.failedCases).Count | Should -Be 32

        @(Get-GateAptHost -SourceText "https://deb.debian.org/debian`nhttp://Security.Debian.org/x") |
            Should -Be @('deb.debian.org', 'security.debian.org')
        Get-GateAptHost -SourceText "deb.debian.org" | Should -BeNullOrEmpty
        Get-GateAptHost -SourceText '' | Should -BeNullOrEmpty
        (Test-GateAllowedAptHost -Value @('deb.debian.org') -Allowed $script:DebianAptHosts) | Should -BeTrue
        (Test-GateAllowedAptHost -Value @('evil.invalid') -Allowed $script:DebianAptHosts) | Should -BeFalse
        (Test-GateAllowedAptHost -Value @() -Allowed $script:DebianAptHosts) | Should -BeFalse
        (Test-GateAllowedAptHost -Value $null -Allowed $script:DebianAptHosts) | Should -BeFalse

        $attestation = [pscustomobject]@{
            Valid = $true
            Reason = ''
            ManifestSha256 = ('c' * 64)
            AptHosts = @('deb.debian.org', 'packages.microsoft.com')
            DebianAptHosts = @('deb.debian.org')
        }
        $forged = [pscustomobject]@{
            digests = [pscustomobject]@{ manifestSha256 = ('d' * 64) }
            origin = [pscustomobject]@{ aptHosts = @('deb.debian.org', 'packages.microsoft.com') }
        }
        Test-GateSmokeAttestationAgreement -Smoke $forged -Attestation $attestation |
            Should -Be 'smoke-manifest-digest-forged'
        $lying = [pscustomobject]@{
            digests = [pscustomobject]@{ manifestSha256 = ('c' * 64) }
            origin = [pscustomobject]@{ aptHosts = @('deb.debian.org') }
        }
        Test-GateSmokeAttestationAgreement -Smoke $lying -Attestation $attestation |
            Should -Match '^smoke-origin-mismatch:'
        $truthful = [pscustomobject]@{
            digests = [pscustomobject]@{ manifestSha256 = ('c' * 64) }
            origin = [pscustomobject]@{ aptHosts = @('PACKAGES.microsoft.com', 'deb.debian.org') }
        }
        Test-GateSmokeAttestationAgreement -Smoke $truthful -Attestation $attestation | Should -BeNullOrEmpty
    }

    It 'reads image attestation from the host without granting the candidate trust' {
        $runnerText = Get-Content -LiteralPath $runnerPath -Raw
        $attestationBody = [regex]::Match(
            $runnerText,
            '(?s)function Test-GateImageAttestation \{.*?\n\}\n').Value
        $attestationBody | Should -Not -BeNullOrEmpty
        # The whole point of reading the image from the host is that no candidate code runs and no
        # host resource is handed to it.
        $attestationBody | Should -Match "'create', '--network', 'none'"
        $attestationBody | Should -Match "'cp',"
        $attestationBody | Should -Not -Match '--volume|--mount|(?<!\w)-v(?!\w)|--privileged'
        $attestationBody | Should -Match "'rm', '-f'"

        Mock Invoke-GateProcess {
            switch ($ArgumentList[0]) {
                'create' { [pscustomobject]@{ ExitCode = 1; Stdout = ''; Stderr = 'no such image'; TimedOut = $false; ElapsedMs = 1; StdoutOverflow = $false; StderrOverflow = $false; StdoutInvalidControl = $false } }
                default { [pscustomobject]@{ ExitCode = 0; Stdout = ''; Stderr = ''; TimedOut = $false; ElapsedMs = 1; StdoutOverflow = $false; StderrOverflow = $false; StdoutInvalidControl = $false } }
            }
        }
        $unavailable = Test-GateImageAttestation -ImageTag 'missing:tag' `
            -ExpectedManifestSha256 ('a' * 64) -TimeoutSeconds 5
        $unavailable.Valid | Should -BeFalse
        $unavailable.Reason | Should -Be 'attestation-container-unavailable'
    }

    It 'refuses an empty manifest and reads the live apt configuration from the image' {
        # `0 cases; state=pass` is the one verdict this gate must never report: a green run that
        # exercised nothing. A manifest emptied to comments produces exactly that unless rejected.
        $emptyManifest = Join-Path $TestDrive 'empty-toolchain.tsv'
        Set-Content -LiteralPath $emptyManifest -Value @('# id	kind	value', '') -Encoding utf8NoBOM
        $emptySmoke = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'pass'
            origin = [ordered]@{ os = 'debian:13'; aptHosts = @('deb.debian.org') }
            digests = [ordered]@{ manifestSha256 = ('a' * 64); provenanceSha256 = ('b' * 64) }
            cases = @()
        }
        $emptyResult = Test-GateSmokeOutput -Output ($emptySmoke | ConvertTo-Json -Depth 8 -Compress) `
            -ManifestPath $emptyManifest
        $emptyResult.Valid | Should -BeFalse
        $emptyResult.Summary | Should -Match 'no cases'

        # The recorded provenance file is written by the candidate's own Dockerfile, so the
        # attestation also reads the configuration apt actually carries. Comments are skipped
        # because Debian's own sources file names snapshot.debian.org in one, and keyrings are not
        # read at all so their bytes cannot invent a host.
        $aptRoot = Join-Path $TestDrive 'etc-apt'
        [void](New-Item -ItemType Directory -Path (Join-Path $aptRoot 'sources.list.d') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $aptRoot 'trusted.gpg.d') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $aptRoot 'apt.conf.d') -Force)
        Set-Content -LiteralPath (Join-Path $aptRoot 'sources.list.d/debian.sources') -Encoding utf8NoBOM -Value @(
            '# Mirrors are archived at https://snapshot.debian.org/'
            'Types: deb'
            'URIs: http://deb.debian.org/debian'
            'Suites: trixie'
        )
        Set-Content -LiteralPath (Join-Path $aptRoot 'sources.list.d/docker.list') -Encoding utf8NoBOM -Value @(
            'deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian trixie stable'
        )
        Set-Content -LiteralPath (Join-Path $aptRoot 'trusted.gpg.d/vendor.gpg') -Encoding utf8NoBOM -Value 'binary blob http://evil.invalid/x'
        Set-Content -LiteralPath (Join-Path $aptRoot 'apt.conf.d/00notes') -Encoding utf8NoBOM -Value 'http://evil.invalid/x' -Force
        @(Get-GateAptConfigHost -Root $aptRoot) |
            Should -Be @('deb.debian.org', 'download.docker.com')

        Add-Content -LiteralPath (Join-Path $aptRoot 'sources.list.d/extra.list') -Encoding utf8NoBOM `
            -Value 'deb https://evil.invalid/debian trixie main'
        $withEvil = @(Get-GateAptConfigHost -Root $aptRoot)
        $withEvil | Should -Contain 'evil.invalid'
        (Test-GateAllowedAptHost -Value $withEvil -Allowed $script:AllowedAptHosts) | Should -BeFalse
        Get-GateAptConfigHost -Root (Join-Path $TestDrive 'absent-apt') | Should -BeNullOrEmpty

        # apt resolves a URI with userinfo against the part after the '@'. Reading only up to the
        # delimiter would report the allowed name and pass, so the whole authority is the token —
        # the same one `Get-GateAptHost` produces from the recorded file.
        $userinfoRoot = Join-Path $TestDrive 'etc-apt-userinfo'
        [void](New-Item -ItemType Directory -Path (Join-Path $userinfoRoot 'sources.list.d') -Force)
        Set-Content -LiteralPath (Join-Path $userinfoRoot 'sources.list.d/docker.list') -Encoding utf8NoBOM `
            -Value 'deb [arch=amd64] https://download.docker.com@evil.example.com/linux/debian trixie stable'
        $userinfoHosts = @(Get-GateAptConfigHost -Root $userinfoRoot)
        $userinfoHosts | Should -Be @('download.docker.com@evil.example.com')
        (Test-GateAllowedAptHost -Value $userinfoHosts -Allowed $script:AllowedAptHosts) | Should -BeFalse
        @(Get-GateAptHost -SourceText 'https://download.docker.com@evil.example.com/linux/debian') |
            Should -Be $userinfoHosts -Because 'both readers must agree on what a host is'

        # A port is not a different host, and both readers drop it.
        $portRoot = Join-Path $TestDrive 'etc-apt-port'
        [void](New-Item -ItemType Directory -Path $portRoot -Force)
        Set-Content -LiteralPath (Join-Path $portRoot 'sources.list') -Encoding utf8NoBOM `
            -Value 'deb http://deb.debian.org:8080/debian trixie main'
        @(Get-GateAptConfigHost -Root $portRoot) | Should -Be @('deb.debian.org')
    }

    It 'reaches every terminal Measure outcome without a Docker daemon' {
        # Until now no test drove Measure at all: the orchestration that decides pass/fail was
        # covered only by its helpers. These cases pin the outcome, blocking flag, and diagnostic
        # of each terminal path.
        $manifestPath = Join-Path $repoRoot '.github/skills/autopilot/devcontainer/toolchain.tsv'
        $caseIds = @(Get-Content -LiteralPath $manifestPath | Where-Object {
                $_ -and -not $_.TrimStart().StartsWith('#')
            } | ForEach-Object { ($_ -split "`t", 3)[0] })
        $manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

        function New-SmokeJson {
            param([string]$State = 'pass', [string[]]$FailedIds = @(), [string]$ManifestDigest, [string[]]$AptHosts = @('deb.debian.org'))

            return ([ordered]@{
                    schema = 'skalary/container-toolchain-smoke@1'
                    state = $State
                    origin = [ordered]@{ os = 'debian:13'; aptHosts = @($AptHosts) }
                    digests = [ordered]@{ manifestSha256 = $ManifestDigest; provenanceSha256 = ('b' * 64) }
                    cases = @($caseIds | ForEach-Object {
                            [ordered]@{
                                id = $_
                                state = if ($_ -in $FailedIds) { 'fail' } else { 'pass' }
                                version = '1.0'
                            }
                        })
                } | ConvertTo-Json -Depth 8 -Compress)
        }
        function New-ProcessResult {
            param([int]$ExitCode = 0, [string]$Stdout = '', [string]$Stderr = '', [bool]$TimedOut = $false)

            return [pscustomobject]@{
                ExitCode = $ExitCode
                Stdout = $Stdout
                Stderr = $Stderr
                TimedOut = $TimedOut
                ElapsedMs = [int64]10
                StdoutOverflow = $false
                StderrOverflow = $false
                StdoutInvalidControl = $false
                StderrInvalidControl = $false
            }
        }

        $script:gateScenario = @{}
        Mock Get-ContainerGateDetection {
            [pscustomobject]@{
                Relevant = $true
                CandidateOnlyReason = [string]$script:gateScenario.CandidateOnlyReason
                RelevantPaths = @('plugins/autopilot/devcontainer/Dockerfile')
            }
        }
        Mock Test-GateImageAttestation {
            [pscustomobject]@{
                Valid = [bool]$script:gateScenario.AttestationValid
                Reason = [string]$script:gateScenario.AttestationReason
                ManifestSha256 = [string]$script:gateScenario.AttestedManifestSha
                AptHosts = @($script:gateScenario.AttestedHosts)
                DebianAptHosts = @('deb.debian.org')
            }
        }
        Mock Invoke-GateProcess {
            $joined = ($ArgumentList -join ' ')
            switch -Regex ($joined) {
                '^pull ' { return (New-ProcessResult) }
                '^image inspect --format \{\{\.Os\}\}' {
                    return (New-ProcessResult -Stdout "linux/amd64 sha256:$('c' * 64) debian@sha256:$('d' * 64)")
                }
                '^version --format' { return (New-ProcessResult -Stdout '27.0.0') }
                '^build .*candidate' {
                    return (New-ProcessResult -ExitCode ([int]$script:gateScenario.CandidateBuildExit) `
                            -Stderr ([string]$script:gateScenario.CandidateBuildStderr) `
                            -TimedOut ([bool]$script:gateScenario.CandidateBuildTimedOut))
                }
                '^build .*base' {
                    return (New-ProcessResult -ExitCode ([int]$script:gateScenario.BaseBuildExit) `
                            -Stderr 'base build failed at layer 3')
                }
                '^run --rm --network none' {
                    return (New-ProcessResult -ExitCode ([int]$script:gateScenario.SmokeExit) `
                            -Stdout ([string]$script:gateScenario.SmokeStdout))
                }
                '^image inspect --format \{\{\.Size\}\}.*candidate' { return (New-ProcessResult -Stdout '450000000') }
                '^image inspect --format \{\{\.Size\}\}.*base' { return (New-ProcessResult -Stdout '400000000') }
                default { return (New-ProcessResult) }
            }
        }

        $scenarios = @(
            @{
                Name = 'comparable success'
                State = @{ SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha); AttestationValid = $true; AttestedManifestSha = $manifestSha; AttestedHosts = @('deb.debian.org') }
                Outcome = 'success'
                ExitCode = 0
                Comparison = 'comparable'
            },
            @{
                Name = 'candidate build failure'
                State = @{ CandidateBuildExit = 1; CandidateBuildStderr = 'ERROR: failed to solve: process did not complete' }
                Outcome = 'candidate-build-failed'
                ExitCode = 1
                Diagnostic = 'failed to solve'
            },
            @{
                Name = 'candidate build timeout'
                State = @{ CandidateBuildTimedOut = $true }
                Outcome = 'candidate-timeout'
                ExitCode = 1
                Diagnostic = 'timed out'
            },
            @{
                Name = 'named smoke failures'
                State = @{
                    SmokeExit = 1
                    SmokeStdout = (New-SmokeJson -State 'fail' -FailedIds @($caseIds[0]) -ManifestDigest $manifestSha)
                }
                Outcome = 'candidate-smoke-failed'
                ExitCode = 1
                Diagnostic = $caseIds[0]
            },
            @{
                Name = 'unparsable smoke output'
                State = @{ SmokeStdout = 'not json' }
                Outcome = 'candidate-output-invalid'
                ExitCode = 1
                Diagnostic = 'not valid JSON'
            },
            @{
                Name = 'attestation rejects the image'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    AttestationValid = $false
                    AttestationReason = 'attestation-origin-disallowed:evil.invalid'
                }
                Outcome = 'candidate-output-invalid'
                ExitCode = 1
                Diagnostic = 'attestation-origin-disallowed'
            },
            @{
                Name = 'smoke forges its manifest digest'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest ('e' * 64))
                    AttestationValid = $true
                    AttestedManifestSha = $manifestSha
                    AttestedHosts = @('deb.debian.org')
                }
                Outcome = 'candidate-output-invalid'
                ExitCode = 1
                Diagnostic = 'smoke-manifest-digest-forged'
            },
            @{
                Name = 'smoke understates its origins'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha -AptHosts @('deb.debian.org'))
                    AttestationValid = $true
                    AttestedManifestSha = $manifestSha
                    AttestedHosts = @('deb.debian.org', 'packages.microsoft.com')
                }
                Outcome = 'candidate-output-invalid'
                ExitCode = 1
                Diagnostic = 'smoke-origin-mismatch'
            },
            @{
                Name = 'base build failure degrades to candidate-only'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    AttestationValid = $true
                    AttestedManifestSha = $manifestSha
                    AttestedHosts = @('deb.debian.org')
                    BaseBuildExit = 1
                }
                Outcome = 'base-build-failed'
                ExitCode = 0
                Comparison = 'candidate-only'
            },
            @{
                Name = 'detector candidate-only reason skips the base build'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    AttestationValid = $true
                    AttestedManifestSha = $manifestSha
                    AttestedHosts = @('deb.debian.org')
                    CandidateOnlyReason = 'zero-base'
                }
                Outcome = 'success'
                ExitCode = 0
                Comparison = 'candidate-only'
            }
        )

        foreach ($scenario in $scenarios) {
            $script:gateScenario = @{
                CandidateBuildExit = 0
                CandidateBuildStderr = ''
                CandidateBuildTimedOut = $false
                BaseBuildExit = 0
                SmokeExit = 0
                SmokeStdout = ''
                AttestationValid = $true
                AttestationReason = ''
                AttestedManifestSha = $manifestSha
                AttestedHosts = @('deb.debian.org')
                CandidateOnlyReason = ''
            }
            foreach ($key in $scenario.State.Keys) { $script:gateScenario[$key] = $scenario.State[$key] }

            $safeName = ($scenario.Name -replace '[^a-z0-9]+', '-')
            $receiptPath = Join-Path $TestDrive "measure-$safeName.json"
            $summaryPath = Join-Path $TestDrive "measure-$safeName.md"
            $diagnosticPath = Join-Path $TestDrive "measure-$safeName.log"
            $result = Invoke-ContainerToolchainGate -Mode Measure `
                -BaseSha ('a' * 40) -CandidateSha ('b' * 40) `
                -BaseRoot $repoRoot -CandidateRoot $repoRoot `
                -ReceiptPath $receiptPath -SummaryPath $summaryPath -DiagnosticLogPath $diagnosticPath `
                -ProvenancePath (Join-Path $TestDrive "measure-$safeName-provenance.json") `
                -CopilotVersion '1.2.3' 6>$null

            $result.ExitCode | Should -Be $scenario.ExitCode -Because $scenario.Name
            $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
            $receipt.outcome | Should -Be $scenario.Outcome -Because $scenario.Name
            $receipt.blocking | Should -Be ($scenario.ExitCode -ne 0) -Because $scenario.Name
            if ($scenario.ContainsKey('Comparison')) {
                $receipt.comparison | Should -Be $scenario.Comparison -Because $scenario.Name
            }
            if ($scenario.ContainsKey('Diagnostic')) {
                $receipt.diagnostic | Should -Match ([regex]::Escape($scenario.Diagnostic)) -Because $scenario.Name
            }
            $summary = Get-Content -LiteralPath $summaryPath -Raw
            $summary | Should -Match 'Outcome' -Because $scenario.Name
            $summary | Should -Not -Match '[\r\n]\s*<script' -Because $scenario.Name
        }

        # A build or smoke failure writes its bounded capture where a reader can retrieve it.
        Test-Path -LiteralPath (Join-Path $TestDrive 'measure-candidate-build-failure.log') |
            Should -BeTrue
    }

    It 'reports sizes, delta, and advisory status in the job summary' {
        $summaryPath = Join-Path $TestDrive 'rendered-summary.md'
        $receipt = New-ContainerGateReceipt -Outcome success -Relevant $true -Comparison comparable `
            -BaseSha ('a' * 40) -CandidateSha ('b' * 40) -CandidateBytes (600MB) -BaseBytes (300MB) `
            -DeltaBytes (300MB) -AdvisoryGrowthMiB 250 -SmokeSummary '21 cases; state=pass' `
            -SmokeFailedCases @() -ProvenanceSha256 ('c' * 64)
        Write-ContainerGateSummary -Receipt $receipt -Path $summaryPath
        $summary = Get-Content -LiteralPath $summaryPath -Raw
        # The number the summary exists to communicate must be in the summary, not only the artifact.
        $summary | Should -Match '600'
        $summary | Should -Match '300'
        $summary | Should -Match '250'
        $summary | Should -Match '(?i)advisory'
        $summary | Should -Match '21 cases'

        $failedReceipt = New-ContainerGateReceipt -Outcome 'candidate-smoke-failed' -Relevant $true `
            -SmokeSummary '21 cases; state=fail; failed=1: rg-search' -SmokeFailedCases @('rg-search') `
            -Diagnostic 'Failed smoke cases: rg-search.'
        $failedSummaryPath = Join-Path $TestDrive 'rendered-failed-summary.md'
        Write-ContainerGateSummary -Receipt $failedReceipt -Path $failedSummaryPath
        # The summary escapes markdown metacharacters, so the reader-visible name is compared after
        # unescaping rather than by asserting the escaped spelling, which is an encoding detail.
        $failedSummary = (Get-Content -LiteralPath $failedSummaryPath -Raw).Replace('\', '')
        $failedSummary | Should -Match 'Failed smoke cases: rg-search'
        $failedSummary | Should -Match 'failed=1: rg-search'
    }

    It 'derives relevance from real changed paths in both directions' {
        $fixture = Join-Path $TestDrive 'relevance-repo'
        [void](New-Item -ItemType Directory -Path $fixture)
        foreach ($relativePath in @(Get-ContainerGatePathSet -CheckoutRoot $repoRoot)) {
            $source = Join-Path $repoRoot $relativePath
            # The owned set names paths the dogfood mirror may not have materialised; only real
            # files can seed the fixture, and the assertions below use a path that always exists.
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            $destination = Join-Path $fixture $relativePath
            [void](New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force)
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        Set-Content -LiteralPath (Join-Path $fixture 'README.md') -Value 'unrelated' -Encoding utf8NoBOM
        & git -C $fixture init --quiet
        & git -C $fixture config user.email test@example.invalid
        & git -C $fixture config user.name Test
        & git -C $fixture add -- .
        & git -C $fixture commit --quiet -m base
        $baseSha = (& git -C $fixture rev-parse HEAD).Trim()
        # The detector requires the base root to be a checkout standing at BaseSha; sharing one
        # working tree would only ever exercise the base-unreachable escape hatch.
        $baseCheckout = Join-Path $TestDrive 'relevance-base'
        & git -C $fixture worktree add --quiet --detach $baseCheckout $baseSha

        Add-Content -LiteralPath (Join-Path $fixture 'README.md') -Value 'still unrelated'
        & git -C $fixture add -- .
        & git -C $fixture commit --quiet -m unrelated
        $unrelatedSha = (& git -C $fixture rev-parse HEAD).Trim()
        $unrelated = Get-ContainerGateDetection -BaseSha $baseSha -CandidateSha $unrelatedSha `
            -BaseRoot $baseCheckout -CandidateRoot $fixture
        $unrelated.Relevant | Should -BeFalse
        $unrelated.CandidateOnlyReason | Should -Be ''

        Add-Content -LiteralPath (Join-Path $fixture 'plugins/autopilot/devcontainer/toolchain.tsv') `
            -Value "# owned-path change"
        & git -C $fixture add -- .
        & git -C $fixture commit --quiet -m owned
        $ownedSha = (& git -C $fixture rev-parse HEAD).Trim()
        $owned = Get-ContainerGateDetection -BaseSha $baseSha -CandidateSha $ownedSha `
            -BaseRoot $baseCheckout -CandidateRoot $fixture
        $owned.Relevant | Should -BeTrue
        @($owned.RelevantPaths) | Should -Contain 'plugins/autopilot/devcontainer/toolchain.tsv'
    }

    It 'rejects a measurement re-detection that contradicts the detector' {
        Mock Get-ContainerGateDetection {
            [pscustomobject]@{ Relevant = $false; CandidateOnlyReason = ''; RelevantPaths = @() }
        }
        Mock Test-ContainerPayloadParity { throw 'candidate work must not start on a stale verdict' }
        $receiptPath = Join-Path $TestDrive 'contradiction-receipt.json'
        # Detector said the change is relevant; measurement disagreeing must not silently skip the
        # blocking work while the truth table still reads detector=true.
        $result = Invoke-ContainerToolchainGate -Mode Measure -DetectionRelevance 'true' `
            -BaseSha ('a' * 40) -CandidateSha ('b' * 40) `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot -ReceiptPath $receiptPath 6>$null
        $result.ExitCode | Should -Be 1
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        $receipt.relevant | Should -BeTrue
        # Reaching the parity canary is the assertion: the blocking measurement path ran instead of
        # being skipped by the re-detection, and the receipt still reports relevant=true.
        $receipt.diagnostic | Should -Match 'candidate work must not start on a stale verdict'
        # The rejection is also reportable on the paths that survive to a non-error receipt.
        (Get-Content -LiteralPath $runnerPath -Raw) |
            Should -Match 'measurement re-detection disagreed and was rejected'

        $agreeingPath = Join-Path $TestDrive 'agreeing-receipt.json'
        $agreeing = Invoke-ContainerToolchainGate -Mode Measure -DetectionRelevance 'false' `
            -BaseSha ('a' * 40) -CandidateSha ('b' * 40) `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot -ReceiptPath $agreeingPath 6>$null
        $agreeing.ExitCode | Should -Be 0
        (Get-Content -LiteralPath $agreeingPath -Raw | ConvertFrom-Json).outcome | Should -Be 'irrelevant'
    }
}

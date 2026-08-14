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
        & pwsh -NoProfile -File $runnerPath -Mode VerifyResult `
            -DetectorConclusion success -Relevance invalid -ImageConclusion skipped `
            -ReceiptPath $invalidResultReceiptPath | Out-Null
        $LASTEXITCODE | Should -Be 1
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
        [void](New-Item -ItemType Directory -Path (Join-Path $payloadFixture 'plugins') -Force)
        [void](New-Item -ItemType Directory -Path (Join-Path $payloadFixture '.github/skills') -Force)
        Copy-Item -LiteralPath (Join-Path $repoRoot 'plugins/autopilot') `
            -Destination (Join-Path $payloadFixture 'plugins/autopilot') -Recurse
        Copy-Item -LiteralPath (Join-Path $repoRoot '.github/skills/autopilot') `
            -Destination (Join-Path $payloadFixture '.github/skills/autopilot') -Recurse
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
            'FROM mcr.microsoft.com/dotnet/sdk:10.0',
            'FROM docker.io/library/debian:stable'
        ) | Set-Content -LiteralPath $installedDockerfile -Encoding utf8NoBOM -NoNewline
        (Test-GateDockerfileBase -Path $installedDockerfile) | Should -BeFalse
        (Get-Content -LiteralPath (
                Join-Path $repoRoot 'plugins/autopilot/devcontainer/Dockerfile') -Raw).Replace(
            'FROM mcr.microsoft.com/dotnet/sdk:10.0',
            'FROM --platform=linux/arm64 mcr.microsoft.com/dotnet/sdk:10.0'
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
            '-NoProfile', '-Command', '[Console]::Out.Write("x" * 70000)'
        ) -TimeoutSeconds 10
        $oversized.ExitCode | Should -Be 0
        $oversized.StdoutOverflow | Should -BeTrue
        $oversized.Stdout.Length | Should -Be 65535

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

        $hostileNames = @(
            ' leading-dash',
            '-option',
            'quote''"file',
            '$(substitution)',
            "line`nbreak",
            "tab`tpath"
        )
        foreach ($name in $hostileNames) {
            Set-Content -LiteralPath (Join-Path $fixture $name) -Value $name -NoNewline
        }
        Remove-Item -LiteralPath (Join-Path $fixture 'delete me')
        & git -C $fixture mv -- "rename`nsource" "renamed`ntarget"
        & git -C $fixture add -- .
        & git -C $fixture commit --quiet -m candidate
        $candidate = (& git -C $fixture rev-parse HEAD).Trim()
        $changed = @(Get-GateChangedPaths -CandidateRoot $fixture -BaseSha $base -CandidateSha $candidate)
        foreach ($name in $hostileNames) { $changed | Should -Contain $name }
        $changed | Should -Contain 'delete me'
        $changed | Should -Contain "rename`nsource"
        $changed | Should -Contain "renamed`ntarget"
        $changed | Should -Not -Contain 'Leading-dash'
    }

    It 'kills a timed-out process tree and returns bounded diagnostics' {
        $marker = Join-Path $TestDrive 'child-survived'
        $childScript = Join-Path $TestDrive 'child.ps1'
        $parentScript = Join-Path $TestDrive 'parent.ps1'
        Set-Content -LiteralPath $childScript -Encoding utf8NoBOM -Value @(
            'Start-Sleep -Seconds 2',
            "Set-Content -LiteralPath '$($marker.Replace("'", "''"))' -Value survived"
        )
        Set-Content -LiteralPath $parentScript -Encoding utf8NoBOM -Value @(
            "Start-Process -FilePath pwsh -ArgumentList @('-NoProfile','-File','$($childScript.Replace("'", "''"))')",
            'Start-Sleep -Seconds 20'
        )
        $process = Invoke-GateProcess -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-File', $parentScript) -TimeoutSeconds 1
        $process.TimedOut | Should -BeTrue
        $process.ExitCode | Should -Be -1
        Start-Sleep -Seconds 3
        Test-Path -LiteralPath $marker | Should -BeFalse
        $process.Stdout.Length | Should -BeLessOrEqual 65535
        $process.Stderr.Length | Should -BeLessOrEqual 65535
    }
}

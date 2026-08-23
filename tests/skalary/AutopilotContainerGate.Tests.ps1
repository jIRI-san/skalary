#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot container gate runner' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:runnerPath = Join-Path $script:repoRoot 'scripts/skalary/Invoke-ContainerToolchainGate.ps1'
        . $script:runnerPath
        $script:headSha = (& git -C $script:repoRoot rev-parse HEAD).Trim()

        # Three tests each re-derived the manifest's case IDs with their own copy of the TSV
        # parsing rules. A manifest format change had to be found in three places, and a copy that
        # drifted would silently test a different case set than the gate reads.
        function script:Get-TestManifestCaseId {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Path)
            return @(Get-Content -LiteralPath $Path | Where-Object {
                    $_ -and -not $_.TrimStart().StartsWith('#')
                } | ForEach-Object { ($_ -split "`t", 3)[0] })
        }
    }

    It 'test:AutopilotContainer.GateRunnerContract enforces gate runner invariants' {
        $modeAttribute = (Get-Command Invoke-ContainerToolchainGate).Parameters.Mode.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        # `Initialize` writes a starting receipt; it is setup, not a verdict mode, and the truth
        # table in `Test-ContainerGateResult` never sees it.
        @($modeAttribute.ValidValues) | Should -Be @('Detect', 'Measure', 'VerifyResult', 'Initialize')

        # The script has two param blocks: the file's own, used when the script is invoked, and the
        # function's, used when a caller dot-sources it. They drifted before — a parameter added to
        # one and not the other is silently ignored on the other path. Compare them by reflection
        # rather than by reading both and hoping.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:runnerPath, [ref]$null, [ref]$null)
        $scriptParams = $ast.ParamBlock.Parameters
        $functionAst = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Invoke-ContainerToolchainGate'
            }, $true)[0]
        $functionParams = $functionAst.Body.ParamBlock.Parameters
        $describe = {
            param($parameter, $ignoredAttributes)
            $attributes = @($parameter.Attributes |
                    ForEach-Object { $_.Extent.Text.Trim() } |
                    Where-Object { $_ -notin $ignoredAttributes } |
                    Sort-Object)
            '{0}|{1}' -f $parameter.Name.VariablePath.UserPath, ($attributes -join ';')
        }
        # One difference is deliberate: the script block cannot mark `ReceiptPath` Mandatory,
        # because dot-sourcing this file for tests would then prompt. It is named here rather than
        # allowed by a loose comparison, and the compensating explicit check is asserted below.
        $mandatoryExemptions = @{ ReceiptPath = @('[Parameter(Mandatory)]') }
        $shapeOf = {
            param($parameters)
            @($parameters | ForEach-Object {
                    & $describe $_ ($mandatoryExemptions[$_.Name.VariablePath.UserPath])
                })
        }
        (& $shapeOf $functionParams) | Should -Be (& $shapeOf $scriptParams) -Because (
            'the script and function parameter blocks must stay identical, or a caller gets ' +
            'different validation depending on how it reached the runner')
        # The exemption is only safe because the file-invocation path refuses a missing receipt
        # itself. Assert that by running the file, not by matching its source: a comment or a
        # renamed variable would satisfy a text match while the guard was gone.
        $scriptReceipt = @($scriptParams | Where-Object { $_.Name.VariablePath.UserPath -eq 'ReceiptPath' })[0]
        @($scriptReceipt.Attributes.Extent.Text) | Should -Not -Contain '[Parameter(Mandatory)]'
        $functionReceipt = @($functionParams | Where-Object { $_.Name.VariablePath.UserPath -eq 'ReceiptPath' })[0]
        @($functionReceipt.Attributes.Extent.Text) | Should -Contain '[Parameter(Mandatory)]'
        $guard = & pwsh -NoProfile -NonInteractive -File $script:runnerPath `
            -Mode VerifyResult -DetectorConclusion success -Relevance false -ImageConclusion skipped 2>&1
        $LASTEXITCODE | Should -Not -Be 0 -Because 'invoking the file without a receipt path must fail'
        ($guard | Out-String) | Should -Match 'ReceiptPath' -Because 'the failure must name what is missing'

        $context = Get-ContainerGateContext -CheckoutRoot $repoRoot
        $context.Payload.Count | Should -BeGreaterOrEqual 5
        $parity = Test-ContainerPayloadParity -CheckoutRoot $repoRoot
        $parity.Valid | Should -BeTrue
        (Test-GateDockerfileBase -Path $context.InstalledDockerfilePath) | Should -BeTrue
        $runnerSource = Get-Content -LiteralPath $script:runnerPath -Raw
        $runnerSource | Should -Match ([regex]::Escape('{{json .RepoDigests}}'))
        $runnerSource | Should -Not -Match ([regex]::Escape('{{join .RepoDigests'))
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

        # There is one event that reaches this gate: a push to `main`. An earlier loop iterated
        # `pull-request-merge` and `main-push` over the *same* call with the same arguments, so
        # the second iteration asserted nothing and the name claimed a code path that does not
        # exist — the workflow has no `pull_request` trigger and cannot have one.
        $identity = Get-ContainerGateDetection -BaseSha $headSha -CandidateSha $headSha `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot
        $identity.Relevant | Should -BeFalse -Because 'a push whose base and candidate are one commit changes nothing'
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
        $caseIds = @(Get-TestManifestCaseId -Path $manifestPath)
        $smokeValue = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'pass'
            reasons = @()
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

        # A whole-run failure has no case to blame. Before `reasons`, the runner could only report
        # "reported failure without naming a case", so these cases pin the closed vocabulary the
        # host will accept and the rejections that keep it closed.
        $smokeValue.cases[0].state = 'pass'
        $smokeValue.reasons = @('not-autopilot-user', 'usr-local-bin-writable')
        $wholeRun = Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
            -ManifestPath $manifestPath
        $wholeRun.Valid | Should -BeTrue
        @($wholeRun.Reasons) | Should -Be @('not-autopilot-user', 'usr-local-bin-writable')
        $smokeValue.reasons = @('not-a-real-reason')
        (Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
                -ManifestPath $manifestPath).Valid |
            Should -BeFalse -Because 'an open reason field would be a free-text channel into the job summary'
        $smokeValue.reasons = @('not-autopilot-user', 'not-autopilot-user')
        (Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
                -ManifestPath $manifestPath).Valid | Should -BeFalse
        $smokeValue.reasons = @()
        $noVerdict = Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
            -ManifestPath $manifestPath
        $noVerdict.Valid |
            Should -BeFalse -Because 'a failure with neither a failed case nor a reason diagnoses nothing'
        $smokeValue.state = 'pass'
        $smokeValue.reasons = @('not-autopilot-user')
        (Test-GateSmokeOutput -Output ($smokeValue | ConvertTo-Json -Depth 8 -Compress) `
                -ManifestPath $manifestPath).Valid |
            Should -BeFalse -Because 'a passing run that also reports why it failed is self-contradictory'
        $smokeValue.reasons = @()

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
        $drift = Test-ContainerPayloadParity -CheckoutRoot $payloadFixture
        $drift.Reason | Should -Be 'payload-drift'
        # A reason without a name is a red gate nobody can act on: the detail must identify the
        # mapped source and show the two hashes that disagree.
        $drift.Detail | Should -Match ([regex]::Escape('devcontainer/toolchain.tsv'))
        $drift.Detail | Should -Match 'canonical=[0-9a-f]{16} installed=[0-9a-f]{16}'
        @($drift.Entries).Count | Should -BeGreaterThan 0 -Because 'hashes taken before the drift are the evidence'
        @($drift.Entries | Where-Object { $_.canonicalSha256 -ne $_.installedSha256 }).Count | Should -Be 1
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
        Set-Content -LiteralPath $canonicalDockerfile -Value $canonicalDockerfileText -Encoding utf8NoBOM -NoNewline
        Remove-Item -LiteralPath (
            Join-Path $payloadFixture '.github/skills/autopilot/devcontainer/Dockerfile') -Force
        $absent = Test-ContainerPayloadParity -CheckoutRoot $payloadFixture
        $absent.Reason | Should -Be 'context-absent'
        $absent.Detail | Should -Match ([regex]::Escape('devcontainer/Dockerfile'))
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
        # The timeout must outlast two cold pwsh starts (parent, then grandchild) or the tree is
        # killed before the child announces itself and the test asserts nothing about tree kill.
        # A hardcoded number buys that margin by making every run pay the slowest machine's price,
        # so measure this machine instead: start a pwsh that does nothing and scale from it.
        $coldStart = @(1, 2 | ForEach-Object {
                (Measure-Command { & pwsh -NoProfile -NonInteractive -Command 'exit 0' }).TotalSeconds
            } | Sort-Object -Descending)[0]
        $timeoutSeconds = [math]::Max(4, [int][math]::Ceiling(3 * $coldStart))

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
        $process = Invoke-GateProcess -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-File', $parentScript) -TimeoutSeconds $timeoutSeconds
        $process.TimedOut | Should -BeTrue
        $process.ExitCode | Should -Be -1

        $deadline = [datetime]::UtcNow.AddSeconds([math]::Max(3, 4 * $coldStart))
        while ([datetime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $startedMarker)) {
            Start-Sleep -Milliseconds 100
        }
        Test-Path -LiteralPath $startedMarker | Should -BeTrue `
            -Because "the child must really have run (timeout ${timeoutSeconds}s, cold start ${coldStart}s)"

        # The child heartbeats every 100ms, so a reading taken 200ms after the previous one would
        # have caught a survivor. Three of those after a grace period is the invariant: output
        # stopped and stayed stopped. Waiting longer only re-observes the same dead process.
        Start-Sleep -Milliseconds 400
        $beatsAfterKill = @(if (Test-Path -LiteralPath $heartbeatMarker) {
                Get-Content -LiteralPath $heartbeatMarker
            })
        for ($reading = 0; $reading -lt 3; $reading++) {
            Start-Sleep -Milliseconds 200
            $current = @(if (Test-Path -LiteralPath $heartbeatMarker) {
                    Get-Content -LiteralPath $heartbeatMarker
                })
            $current.Count | Should -Be $beatsAfterKill.Count `
                -Because 'the killed child must stop heartbeating, not merely slow down'
            $beatsAfterKill = $current
        }
        # The child wrote something before it died, or the kill proved nothing about a live tree.
        $beatsAfterKill.Count | Should -BeGreaterThan 0

        $process.Stdout.Length | Should -BeLessOrEqual 65535
        $process.Stderr.Length | Should -BeLessOrEqual 65535
    }

    It 'names failing smoke cases and attests image claims against the trusted host' {
        $manifestPath = Join-Path $repoRoot 'plugins/autopilot/devcontainer/toolchain.tsv'
        $caseIds = @(Get-TestManifestCaseId -Path $manifestPath)
        $failing = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'fail'
            reasons = @()
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
        # Asserting the *text* of Test-GateImageAttestation proves only that the function is spelled
        # a certain way. This drives it: `docker cp` is mocked to materialise real files, every
        # docker invocation is recorded, and the assertions are on the verdicts it returns and the
        # arguments it actually passed.
        $script:attestCalls = [System.Collections.Generic.List[object]]::new()
        $script:attestFiles = @{}
        $script:attestCreateExit = 0
        $script:attestCpFailures = @{}
        $script:attestCreateDelayMs = 0
        $script:attestEnvJson = '["PATH=/usr/local/bin:/usr/bin"]'
        $script:attestEnvExit = 0

        Mock Invoke-GateProcess {
            $script:attestCalls.Add([pscustomobject]@{
                    FilePath = $FilePath
                    ArgumentList = @($ArgumentList)
                    TimeoutSeconds = $TimeoutSeconds
                })
            $ok = {
                param([string]$Out = '')
                [pscustomobject]@{
                    ExitCode = 0; Stdout = $Out; Stderr = ''; TimedOut = $false; ElapsedMs = [int64]1
                    StdoutOverflow = $false; StderrOverflow = $false
                    StdoutInvalidControl = $false; StderrInvalidControl = $false
                }
            }
            $failed = {
                param([string]$Err = 'boom')
                [pscustomobject]@{
                    ExitCode = 1; Stdout = ''; Stderr = $Err; TimedOut = $false; ElapsedMs = [int64]1
                    StdoutOverflow = $false; StderrOverflow = $false
                    StdoutInvalidControl = $false; StderrInvalidControl = $false
                }
            }
            switch ($ArgumentList[0]) {
                'create' {
                    if ($script:attestCreateDelayMs -gt 0) {
                        Start-Sleep -Milliseconds $script:attestCreateDelayMs
                    }
                    if ($script:attestCreateExit -ne 0) { return (& $failed 'no such image') }
                    return (& $ok ('a' * 64))
                }
                'inspect' {
                    if ($script:attestEnvExit -ne 0) { return (& $failed 'no such object') }
                    return (& $ok $script:attestEnvJson)
                }
                'cp' {
                    # ArgumentList = @('cp', "<id>:<source>", "<destination>")
                    $spec = [string]$ArgumentList[1]
                    $source = $spec.Substring($spec.IndexOf(':') + 1)
                    $destination = [string]$ArgumentList[2]
                    if ($script:attestCpFailures.ContainsKey($source)) {
                        return (& $failed 'cp refused')
                    }
                    if (-not $script:attestFiles.ContainsKey($source)) { return (& $ok) }
                    $payload = $script:attestFiles[$source]
                    if ($payload -is [hashtable]) {
                        # A directory copy, e.g. /etc/apt: keys are relative paths under it.
                        foreach ($relative in $payload.Keys) {
                            $target = Join-Path $destination $relative
                            [void](New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force)
                            Set-Content -LiteralPath $target -Value $payload[$relative] -Encoding utf8NoBOM
                        }
                    }
                    else {
                        [void](New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force)
                        Set-Content -LiteralPath $destination -Value $payload -Encoding utf8NoBOM -NoNewline
                    }
                    return (& $ok)
                }
                default { return (& $ok) }
            }
        }

        $manifestPath = Join-Path $repoRoot 'plugins/autopilot/devcontainer/toolchain.tsv'
        $manifestText = [System.IO.File]::ReadAllText($manifestPath)
        $manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifestSource = '/usr/local/share/autopilot/toolchain.tsv'
        $debianSource = '/usr/local/share/autopilot/provenance/apt-sources.txt'
        $finalSource = '/usr/local/share/autopilot/provenance/final-apt-sources.txt'
        $goodDebian = "http://deb.debian.org/debian`nhttp://security.debian.org/debian-security"
        $goodFinal = "$goodDebian`nhttps://download.docker.com/linux/debian`nhttps://packages.microsoft.com/debian/13/prod"
        $goodLive = @{
            'sources.list.d/debian.sources' = "Types: deb`nURIs: http://deb.debian.org/debian`nSuites: trixie"
            'sources.list.d/docker.list' = 'deb [arch=amd64] https://download.docker.com/linux/debian trixie stable'
            'sources.list.d/microsoft.list' = 'deb [arch=amd64] https://packages.microsoft.com/debian/13/prod trixie main'
        }
        $baseline = @{
            $manifestSource = $manifestText
            $debianSource = $goodDebian
            $finalSource = $goodFinal
            '/etc/apt' = $goodLive
        }
        function Reset-AttestFixture {
            $script:attestCalls.Clear()
            $script:attestCreateExit = 0
            $script:attestCreateDelayMs = 0
            $script:attestCpFailures = @{}
            $script:attestFiles = @{}
            $script:attestEnvJson = '["PATH=/usr/local/bin:/usr/bin"]'
            $script:attestEnvExit = 0
            foreach ($key in $baseline.Keys) { $script:attestFiles[$key] = $baseline[$key] }
        }

        # Happy path: the image agrees with the trusted checkout and every origin is allowlisted.
        Reset-AttestFixture
        $good = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $good.Valid | Should -BeTrue -Because ($good.Reason)
        $good.ManifestSha256 | Should -BeExactly $manifestSha
        @($good.AptHosts) | Should -Contain 'download.docker.com'
        @($good.DebianAptHosts) | Should -Be @('deb.debian.org', 'security.debian.org')

        # No mount, socket, device, privilege, or host network is ever handed to the candidate
        # image. This reads the recorded arguments, so a future edit that adds one fails here even
        # if the function's source is reworded.
        $createCalls = @($attestCalls | Where-Object { $_.ArgumentList[0] -eq 'create' })
        $createCalls.Count | Should -Be 1
        @($createCalls[0].ArgumentList) | Should -Contain '--network'
        @($createCalls[0].ArgumentList) | Should -Contain 'none'
        foreach ($call in $attestCalls) {
            $call.FilePath | Should -Be 'docker'
            foreach ($argument in @($call.ArgumentList)) {
                $argument | Should -Not -Match '^(?:-v|--volume|--mount|--privileged|--device|--cap-add|--network=host|--pid|--userns|--security-opt)$'
            }
            ($call.ArgumentList -join ' ') | Should -Not -Match '(?:^|\s)--network\s+host(?:\s|$)'
        }
        # The container is removed on every path, including the successful one.
        @($attestCalls | Where-Object { $_.ArgumentList[0] -eq 'rm' -and $_.ArgumentList[1] -eq '-f' }).Count |
            Should -Be 1

        # A manifest that differs from the trusted checkout is the case smoke output cannot be
        # trusted to report, because smoke runs inside the image being questioned.
        Reset-AttestFixture
        $script:attestFiles[$manifestSource] = $manifestText + "`n# tampered"
        $mismatch = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $mismatch.Valid | Should -BeFalse
        $mismatch.Reason | Should -Match '^attestation-manifest-mismatch:'
        $mismatch.ManifestSha256 | Should -Not -Be $manifestSha
        @($attestCalls | Where-Object { $_.ArgumentList[0] -eq 'rm' }).Count | Should -Be 1

        # A recorded origin outside the final allowlist.
        Reset-AttestFixture
        $script:attestFiles[$finalSource] = "$goodFinal`nhttps://packages.evil.invalid/debian"
        $recordedEvil = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $recordedEvil.Valid | Should -BeFalse
        $recordedEvil.Reason | Should -Match '^attestation-origin-disallowed:.*packages\.evil\.invalid'

        # The Debian baseline record is held to the tighter two-host allowlist.
        Reset-AttestFixture
        $script:attestFiles[$debianSource] = "$goodDebian`nhttps://download.docker.com/linux/debian"
        $baselineEvil = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $baselineEvil.Valid | Should -BeFalse
        $baselineEvil.Reason | Should -Match '^attestation-debian-origin-disallowed:'

        # The image's live /etc/apt disagreeing with its own record is the case the second read
        # exists to catch: the record says Debian and Docker, apt is actually pointed elsewhere.
        Reset-AttestFixture
        $liveEvilFiles = @{}
        foreach ($key in $goodLive.Keys) { $liveEvilFiles[$key] = $goodLive[$key] }
        $liveEvilFiles['sources.list.d/extra.list'] = 'deb https://mirror.evil.invalid/debian trixie main'
        $script:attestFiles['/etc/apt'] = $liveEvilFiles
        $liveEvil = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $liveEvil.Valid | Should -BeFalse
        $liveEvil.Reason | Should -Match '^attestation-live-origin-disallowed:.*mirror\.evil\.invalid'

        # An /etc/apt that cannot be read is not evidence of a clean image, and the reason says
        # which read failed: a copy that never ran and a configuration that relocates itself out
        # of view are different repairs, and a post-merge job has only the receipt to say so.
        Reset-AttestFixture
        $script:attestCpFailures['/etc/apt'] = $true
        $configUnreadable = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $configUnreadable.Valid | Should -BeFalse
        $configUnreadable.Reason | Should -Be 'attestation-apt-config-unreadable:copy-failed'

        # A binary-scoped relocation is the shape the Dockerfile's initial policy already refuses
        # and the live read used to miss, and it is the live read that runs after every later
        # layer. The failure must name the directive class and the file carrying it.
        Reset-AttestFixture
        $relocatedFiles = @{}
        foreach ($key in $goodLive.Keys) { $relocatedFiles[$key] = $goodLive[$key] }
        $relocatedFiles['apt.conf.d/99relocate'] = 'Binary::apt-get::Dir::Etc::sourcelist "/opt/hidden/sources.list";'
        $script:attestFiles['/etc/apt'] = $relocatedFiles
        $relocated = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $relocated.Valid | Should -BeFalse
        $relocated.Reason | Should -Be 'attestation-apt-config-unreadable:config-dir-override:apt.conf.d/99relocate'

        # An include pulls in a file this scan never sees, which is free to relocate the source
        # lists after every check above has passed.
        Reset-AttestFixture
        $includeFiles = @{}
        foreach ($key in $goodLive.Keys) { $includeFiles[$key] = $goodLive[$key] }
        $includeFiles['apt.conf.d/99include'] = '#include "/opt/hidden/apt.conf";'
        $script:attestFiles['/etc/apt'] = $includeFiles
        $included = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $included.Valid | Should -BeFalse
        $included.Reason | Should -Be 'attestation-apt-config-unreadable:config-include:apt.conf.d/99include'

        # A file the copy never produced fails closed and names which one.
        Reset-AttestFixture
        $script:attestFiles.Remove($finalSource)
        $missingFile = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $missingFile.Valid | Should -BeFalse
        $missingFile.Reason | Should -Be "attestation-file-unreadable:$finalSource"

        # The tree above is only the tree apt reads while nothing points it elsewhere. `APT_CONFIG`
        # in the image's own environment is read before `/etc/apt/apt.conf` and can relocate,
        # unauthenticate or proxy the lot from a path no copy here enumerates — so the environment
        # is read from the host first, and a rejection stops the attestation before the copies
        # rather than reporting on a tree that was never the effective one.
        foreach ($case in @(
                @{ Json = '["PATH=/usr/bin","APT_CONFIG=/opt/hidden/apt.conf"]'; Reason = 'attestation-image-env:apt-config' },
                @{ Json = '["PATH=/usr/bin","http_proxy=http://proxy.invalid:3128"]'; Reason = 'attestation-image-env:proxy:http_proxy' },
                @{ Json = ''; Reason = 'attestation-image-env:unreadable' }
            )) {
            Reset-AttestFixture
            $script:attestEnvJson = $case.Json
            $envVerdict = Test-GateImageAttestation -ImageTag 'candidate:test' `
                -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
            $envVerdict.Valid | Should -BeFalse
            $envVerdict.Reason | Should -Be $case.Reason
            @($attestCalls | Where-Object { $_.ArgumentList[0] -eq 'cp' }).Count |
                Should -Be 0 -Because 'a tree apt may never read is not worth copying out'
            @($attestCalls | Where-Object { $_.ArgumentList[0] -eq 'rm' }).Count |
                Should -Be 1 -Because 'the container is still removed on the way out'
        }

        # An environment the host could not read is not an environment known to be empty.
        Reset-AttestFixture
        $script:attestEnvExit = 1
        $envFailed = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $envFailed.Valid | Should -BeFalse
        $envFailed.Reason | Should -Be 'attestation-image-env:inspect-failed'

        # The read is of the container the gate just created, not of the tag it was asked about: a
        # `docker create` that ever gains an `--env` would otherwise be invisible to it.
        Reset-AttestFixture
        [void](Test-GateImageAttestation -ImageTag 'candidate:test' `
                -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60)
        $inspectCalls = @($attestCalls | Where-Object { $_.ArgumentList[0] -eq 'inspect' })
        $inspectCalls.Count | Should -Be 1
        @($inspectCalls[0].ArgumentList) | Should -Contain ('a' * 64)
        @($inspectCalls[0].ArgumentList) | Should -Not -Contain 'candidate:test'

        # No container, no attestation — and nothing to remove.
        Reset-AttestFixture
        $script:attestCreateExit = 1
        $unavailable = Test-GateImageAttestation -ImageTag 'missing:tag' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 60
        $unavailable.Valid | Should -BeFalse
        $unavailable.Reason | Should -Be 'attestation-container-unavailable'
        @($attestCalls | Where-Object { $_.ArgumentList[0] -eq 'rm' }).Count | Should -Be 0

        # TimeoutSeconds is the budget for the whole attestation. Burning it inside the first call
        # must stop the remaining copies rather than funding each of them separately.
        Reset-AttestFixture
        $script:attestCreateDelayMs = 1400
        $timedOut = Test-GateImageAttestation -ImageTag 'candidate:test' `
            -ExpectedManifestSha256 $manifestSha -TimeoutSeconds 1
        $timedOut.Valid | Should -BeFalse
        $timedOut.Reason | Should -Be 'attestation-timeout'
        @($attestCalls | Where-Object { $_.ArgumentList[0] -eq 'cp' }).Count |
            Should -Be 0 -Because 'an exhausted budget must stop before the first copy, not after each one'
    }

    It 'refuses an empty manifest and reads the live apt configuration from the image' {
        # `0 cases; state=pass` is the one verdict this gate must never report: a green run that
        # exercised nothing. A manifest emptied to comments produces exactly that unless rejected.
        $emptyManifest = Join-Path $TestDrive 'empty-toolchain.tsv'
        Set-Content -LiteralPath $emptyManifest -Value @('# id	kind	value', '') -Encoding utf8NoBOM
        $emptySmoke = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'pass'
            reasons = @()
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

        # An `apt.conf` that relocates the source-list tree makes the allowlisted files this
        # function reads irrelevant to what apt fetches, so the read fails closed rather than
        # reporting the hosts of a configuration that is not in effect.
        foreach ($directive in @(
                'Dir::Etc::sourcelist "/opt/hidden/sources.list";',
                'Dir::Etc "/opt/hidden";',
                'Dir "/opt/hidden/";'
            )) {
            $relocatedRoot = Join-Path $TestDrive ("etc-apt-reloc-" + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path (Join-Path $relocatedRoot 'apt.conf.d') -Force)
            Set-Content -LiteralPath (Join-Path $relocatedRoot 'sources.list') -Encoding utf8NoBOM `
                -Value 'deb http://deb.debian.org/debian trixie main'
            Set-Content -LiteralPath (Join-Path $relocatedRoot 'apt.conf.d/99relocate') -Encoding utf8NoBOM `
                -Value $directive
            Get-GateAptConfigHost -Root $relocatedRoot |
                Should -BeNullOrEmpty -Because "'$directive' relocates the tree this scan enumerates"
        }
        # Debian's own base images ship this, and it relocates no source list, so it must not fail.
        $cacheRoot = Join-Path $TestDrive 'etc-apt-cache'
        [void](New-Item -ItemType Directory -Path (Join-Path $cacheRoot 'apt.conf.d') -Force)
        Set-Content -LiteralPath (Join-Path $cacheRoot 'sources.list') -Encoding utf8NoBOM `
            -Value 'deb http://deb.debian.org/debian trixie main'
        Set-Content -LiteralPath (Join-Path $cacheRoot 'apt.conf.d/docker-clean') -Encoding utf8NoBOM `
            -Value 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";'
        @(Get-GateAptConfigHost -Root $cacheRoot) | Should -Be @('deb.debian.org')

        # A scheme outside http(s) is an origin the allowlist was never written against, so it is
        # reported rather than skipped by a pattern that only knows how to see http.
        $schemeRoot = Join-Path $TestDrive 'etc-apt-scheme'
        [void](New-Item -ItemType Directory -Path $schemeRoot -Force)
        Set-Content -LiteralPath (Join-Path $schemeRoot 'sources.list') -Encoding utf8NoBOM `
            -Value 'deb ftp://mirror.evil.invalid/debian trixie main'
        $schemeHosts = @(Get-GateAptConfigHost -Root $schemeRoot)
        $schemeHosts | Should -Be @('ftp://mirror.evil.invalid')
        (Test-GateAllowedAptHost -Value $schemeHosts -Allowed $script:AllowedAptHosts) | Should -BeFalse
    }

    It 'reaches every terminal Measure outcome without a Docker daemon' {
        # Until now no test drove Measure at all: the orchestration that decides pass/fail was
        # covered only by its helpers. These cases pin the outcome, blocking flag, and diagnostic
        # of each terminal path.
        $manifestPath = Join-Path $repoRoot '.github/skills/autopilot/devcontainer/toolchain.tsv'
        $caseIds = @(Get-TestManifestCaseId -Path $manifestPath)
        $manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

        function New-SmokeJson {
            param([string]$State = 'pass', [string[]]$FailedIds = @(), [string]$ManifestDigest, [string[]]$AptHosts = @('deb.debian.org'), [string[]]$Reasons = @())

            return ([ordered]@{
                    schema = 'skalary/container-toolchain-smoke@1'
                    state = $State
                    reasons = @($Reasons)
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
            if ([int]$script:gateScenario.AttestationDelayMs -gt 0) {
                Start-Sleep -Milliseconds ([int]$script:gateScenario.AttestationDelayMs)
            }
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
                    return (New-ProcessResult -ExitCode ([int]$script:gateScenario.BaseIdentityExit) `
                            -Stdout ([string]$script:gateScenario.BaseIdentityStdout) `
                            -Stderr 'Error response from daemon: manifest unknown')
                }
                '^version --format' { return (New-ProcessResult -Stdout '27.0.0') }
                '^build .*candidate' {
                    return (New-ProcessResult -ExitCode ([int]$script:gateScenario.CandidateBuildExit) `
                            -Stderr ([string]$script:gateScenario.CandidateBuildStderr) `
                            -TimedOut ([bool]$script:gateScenario.CandidateBuildTimedOut))
                }
                '^build .*base' {
                    return (New-ProcessResult -ExitCode ([int]$script:gateScenario.BaseBuildExit) `
                            -Stderr 'base build failed at layer 3' `
                            -TimedOut ([bool]$script:gateScenario.BaseBuildTimedOut))
                }
                '^run --rm --network none' {
                    if ([int]$script:gateScenario.SmokeDelayMs -gt 0) {
                        Start-Sleep -Milliseconds ([int]$script:gateScenario.SmokeDelayMs)
                    }
                    return (New-ProcessResult -ExitCode ([int]$script:gateScenario.SmokeExit) `
                            -Stdout ([string]$script:gateScenario.SmokeStdout))
                }
                '^image inspect --format \{\{\.Size\}\}.*candidate' {
                    if ([int]$script:gateScenario.CandidateSizeDelayMs -gt 0) {
                        Start-Sleep -Milliseconds ([int]$script:gateScenario.CandidateSizeDelayMs)
                    }
                    return (New-ProcessResult -Stdout '450000000')
                }
                '^image inspect --format \{\{\.Size\}\}.*base' {
                    return (New-ProcessResult -ExitCode ([int]$script:gateScenario.BaseSizeExit) `
                            -Stdout ([string]$script:gateScenario.BaseSizeStdout) `
                            -Stderr 'Error response from daemon: no such image' `
                            -TimedOut ([bool]$script:gateScenario.BaseSizeTimedOut))
                }
                default { return (New-ProcessResult) }
            }
        }

        # Finding: the parity failure path is what tells a reader *which* file drifted, and nothing
        # exercised it end-to-end. These two roots are real drifted checkouts, not mocks, so the
        # assertions below observe the diagnostic and provenance the gate actually writes.
        $driftRoot = Join-Path $TestDrive 'measure-drifted-root'
        $absentRoot = Join-Path $TestDrive 'measure-absent-root'
        foreach ($fixtureRoot in @($driftRoot, $absentRoot)) {
            foreach ($relativePath in @('plugins/autopilot/plugin.json') + @(
                    (Get-ContainerGateContext -CheckoutRoot $repoRoot).Payload |
                        ForEach-Object { $_.CanonicalRelative; $_.InstalledRelative }
                ) | Sort-Object -Unique) {
                $destination = Join-Path $fixtureRoot $relativePath
                [void](New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force)
                Copy-Item -LiteralPath (Join-Path $repoRoot $relativePath) -Destination $destination -Force
            }
        }
        $driftedRelative = '.github/skills/autopilot/devcontainer/container-toolchain-smoke.sh'
        Add-Content -LiteralPath (Join-Path $driftRoot $driftedRelative) -Value '# injected drift'
        $absentRelative = '.github/skills/autopilot/devcontainer/toolchain.tsv'
        Remove-Item -LiteralPath (Join-Path $absentRoot $absentRelative) -Force

        $scenarios = @(
            @{
                Name = 'comparable success'
                State = @{ SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha); AttestationValid = $true; AttestedManifestSha = $manifestSha; AttestedHosts = @('deb.debian.org') }
                Outcome = 'success'
                ExitCode = 0
                Comparison = 'comparable'
            },
            @{
                # A drifted mirror must be reported by name. "payload-drift" alone sends the reader
                # back to the repository to diff every mapped file by hand.
                Name = 'payload drift names the offending file'
                State = @{}
                Parameters = @{ CandidateRoot = $driftRoot }
                Outcome = 'candidate-output-invalid'
                ExitCode = 1
                Diagnostic = 'payload-drift'
                ParityDetailContains = 'devcontainer/container-toolchain-smoke.sh'
                ParityProvenanceReason = 'payload-drift'
                ParityPartialEntries = $true
            },
            @{
                # An absent mapped file fails before any hash is taken for it, but the entries
                # already hashed still narrow where the checkout stopped being usable.
                Name = 'absent payload names the missing file'
                State = @{}
                Parameters = @{ CandidateRoot = $absentRoot }
                Outcome = 'candidate-output-invalid'
                ExitCode = 1
                Diagnostic = 'context-absent'
                ParityDetailContains = 'devcontainer/toolchain.tsv'
                ParityProvenanceReason = 'context-absent'
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
                # A whole-run smoke failure names no case. The receipt has to carry the reason, or
                # the reader is told only that something failed.
                Name = 'whole-run smoke failure names its reasons'
                State = @{
                    SmokeExit = 1
                    SmokeStdout = (New-SmokeJson -State 'fail' -ManifestDigest $manifestSha `
                            -Reasons @('not-autopilot-user', 'usr-local-bin-writable'))
                }
                Outcome = 'candidate-smoke-failed'
                ExitCode = 1
                Diagnostic = 'not-autopilot-user'
                SmokeReasons = @('not-autopilot-user', 'usr-local-bin-writable')
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
            },
            # `base-timeout` was in the receipt's outcome set and its candidate-only reason set, and
            # nothing reached it. All three ways of reaching it are driven here, because the whole
            # value of the outcome is that a slow base degrades to a reported candidate-only
            # measurement instead of failing a change that is not at fault.
            @{
                Name = 'base build timeout degrades to candidate-only'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    AttestationValid = $true
                    AttestedManifestSha = $manifestSha
                    AttestedHosts = @('deb.debian.org')
                    BaseBuildTimedOut = $true
                }
                Outcome = 'base-timeout'
                ExitCode = 0
                Comparison = 'candidate-only'
                CandidateOnlyReason = 'base-timeout'
                Diagnostic = 'Base build timed out'
            },
            @{
                Name = 'base size inspection timeout degrades to candidate-only'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    AttestationValid = $true
                    AttestedManifestSha = $manifestSha
                    AttestedHosts = @('deb.debian.org')
                    BaseSizeTimedOut = $true
                }
                Outcome = 'base-timeout'
                ExitCode = 0
                Comparison = 'candidate-only'
                CandidateOnlyReason = 'base-timeout'
                Diagnostic = 'Base size inspection timed out'
            },
            @{
                # An advisory step must not be able to fail a candidate. A base size inspection
                # that exits non-zero — a daemon that dropped the image between build and inspect —
                # used to throw into the global catch and reappear as a blocking `unexpected-error`
                # on a candidate that had already passed every blocking check.
                Name = 'base size inspection failure degrades to candidate-only'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    AttestationValid = $true
                    AttestedManifestSha = $manifestSha
                    AttestedHosts = @('deb.debian.org')
                    BaseSizeExit = 1
                    BaseSizeStdout = ''
                }
                Outcome = 'base-build-failed'
                ExitCode = 0
                Comparison = 'candidate-only'
                CandidateOnlyReason = 'base-build-failed'
                Diagnostic = 'Base image size is invalid'
                DiagnosticLogContains = 'stage: base-size-inspect'
            },
            @{
                # Same failure class, different malformation: a daemon that answers but not with a
                # number. Both close to the advisory path rather than to a blocking outcome.
                Name = 'base size garbage degrades to candidate-only'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    AttestationValid = $true
                    AttestedManifestSha = $manifestSha
                    AttestedHosts = @('deb.debian.org')
                    BaseSizeStdout = '<html>gateway timeout</html>'
                }
                Outcome = 'base-build-failed'
                ExitCode = 0
                Comparison = 'candidate-only'
                CandidateOnlyReason = 'base-build-failed'
                Diagnostic = 'Base image size is invalid'
            },
            @{
                # A blocking throw used to reach the artifact as a one-sentence receipt diagnostic
                # and an empty diagnostics log, so the reader of a red gate had the verdict and
                # none of the evidence. Both the failing stage and the unexpected-error path must
                # leave the process output behind.
                Name = 'an unresolvable base image identity is diagnosable'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    BaseIdentityExit = 1
                    BaseIdentityStdout = ''
                }
                Outcome = 'unexpected-error'
                ExitCode = 1
                Diagnostic = 'Could not resolve the pulled base-image identity'
                DiagnosticLogContains = 'stage: base-image-inspect'
                DiagnosticLogAlsoContains = @(
                    'Error response from daemon: manifest unknown',
                    'stage: unexpected-error'
                )
            },
            @{
                # A base image that resolves to the wrong platform is the same class of failure and
                # was equally silent in the artifact.
                Name = 'a platform mismatch is diagnosable'
                State = @{
                    SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
                    BaseIdentityStdout = "linux/arm64 sha256:$('c' * 64) debian@sha256:$('d' * 64)"
                }
                Outcome = 'unexpected-error'
                ExitCode = 1
                Diagnostic = 'does not resolve to linux/amd64'
                DiagnosticLogContains = 'stage: base-image-inspect'
            }
        )

        foreach ($scenario in $scenarios) {
            $script:gateScenario = @{
                CandidateBuildExit = 0
                CandidateBuildStderr = ''
                CandidateBuildTimedOut = $false
                BaseBuildExit = 0
                BaseBuildTimedOut = $false
                BaseSizeTimedOut = $false
                BaseSizeExit = 0
                BaseSizeStdout = '400000000'
                BaseIdentityExit = 0
                BaseIdentityStdout = "linux/amd64 sha256:$('c' * 64) debian@sha256:$('d' * 64)"
                SmokeExit = 0
                SmokeStdout = ''
                SmokeDelayMs = 0
                AttestationDelayMs = 0
                CandidateSizeDelayMs = 0
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
            $invocation = @{
                Mode = 'Measure'
                BaseSha = ('a' * 40)
                CandidateSha = ('b' * 40)
                BaseRoot = $repoRoot
                CandidateRoot = $repoRoot
                ReceiptPath = $receiptPath
                SummaryPath = $summaryPath
                DiagnosticLogPath = $diagnosticPath
                ProvenancePath = (Join-Path $TestDrive "measure-$safeName-provenance.json")
                CopilotVersion = '1.2.3'
            }
            if ($scenario.ContainsKey('Parameters')) {
                foreach ($key in $scenario.Parameters.Keys) { $invocation[$key] = $scenario.Parameters[$key] }
            }
            $result = Invoke-ContainerToolchainGate @invocation 6>$null

            $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
            # The diagnostic is the one thing that explains an unexpected outcome, so a failing
            # assertion here reports it instead of a bare exit code.
            $why = "$($scenario.Name): $($receipt.outcome): $($receipt.diagnostic)"
            $result.ExitCode | Should -Be $scenario.ExitCode -Because $why
            $receipt.outcome | Should -Be $scenario.Outcome -Because $why
            $receipt.blocking | Should -Be ($scenario.ExitCode -ne 0) -Because $why
            if ($scenario.ContainsKey('Comparison')) {
                $receipt.comparison | Should -Be $scenario.Comparison -Because $scenario.Name
            }
            if ($scenario.ContainsKey('CandidateOnlyReason')) {
                $receipt.candidateOnlyReason | Should -Be $scenario.CandidateOnlyReason -Because $scenario.Name
                # A degraded comparison must still report the candidate it did measure, or the
                # outcome is indistinguishable from having measured nothing.
                $receipt.measurement.candidateBytes | Should -Be 450000000 -Because $scenario.Name
                $receipt.measurement.deltaBytes | Should -BeNullOrEmpty -Because $scenario.Name
            }
            if ($scenario.ContainsKey('Diagnostic')) {
                $receipt.diagnostic | Should -Match ([regex]::Escape($scenario.Diagnostic)) -Because $scenario.Name
            }
            if ($scenario.ContainsKey('DiagnosticLogContains')) {
                # The receipt's diagnostic is bounded to 1024 characters; the log is where the
                # process output that named the failure survives. An empty log beside a blocking
                # receipt is a verdict a reader cannot act on.
                $log = Get-Content -LiteralPath $diagnosticPath -Raw
                $log | Should -Match ([regex]::Escape($scenario.DiagnosticLogContains)) -Because $why
                if ($scenario.ContainsKey('DiagnosticLogAlsoContains')) {
                    foreach ($fragment in @($scenario.DiagnosticLogAlsoContains)) {
                        $log | Should -Match ([regex]::Escape($fragment)) -Because $why
                    }
                }
            }
            if ($scenario.ContainsKey('ParityDetailContains')) {
                # The receipt a reviewer opens must name the path, not just the failure class.
                $receipt.diagnostic |
                    Should -Match ([regex]::Escape($scenario.ParityDetailContains)) `
                        -Because "$why (the parity diagnostic must name the offending file)"
                $provenance = Get-Content -LiteralPath $invocation.ProvenancePath -Raw | ConvertFrom-Json
                $provenance.parity.valid | Should -BeFalse -Because $why
                $provenance.parity.reason | Should -Be $scenario.ParityProvenanceReason -Because $why
                $provenance.parity.detail |
                    Should -Match ([regex]::Escape($scenario.ParityDetailContains)) -Because $why
                $receipt.provenance.sha256 | Should -Match '^[0-9a-f]{64}$' -Because $why
                if ($scenario.ContainsKey('ParityPartialEntries')) {
                    # Provenance is written *before* the failure return precisely so the hashes
                    # taken up to the drift survive; an empty payload would prove nothing.
                    @($provenance.payload).Count |
                        Should -BeGreaterThan 0 -Because "$why (partial hash entries are the evidence)"
                    foreach ($entry in $provenance.payload) {
                        $entry.canonicalSha256 | Should -Match '^[0-9a-f]{64}$' -Because $why
                        $entry.installedSha256 | Should -Match '^[0-9a-f]{64}$' -Because $why
                    }
                    # The drifted file is the one whose two sides disagree.
                    $drifted = @($provenance.payload | Where-Object {
                            $_.canonicalSha256 -ne $_.installedSha256
                        })
                    $drifted.Count | Should -Be 1 -Because $why
                    $drifted[0].source | Should -Match ([regex]::Escape($scenario.ParityDetailContains)) -Because $why
                }
            }
            $summary = Get-Content -LiteralPath $summaryPath -Raw
            if ($scenario.ContainsKey('SmokeReasons')) {
                @($receipt.smoke.reasons) | Should -Be $scenario.SmokeReasons -Because $why
                foreach ($reason in $scenario.SmokeReasons) {
                    $summary.Replace('\', '') |
                        Should -Match ([regex]::Escape($reason)) -Because "$why (the summary must name the reason too)"
                }
            }
            $summary | Should -Match 'Outcome' -Because $scenario.Name
            $summary | Should -Not -Match '[\r\n]\s*<script' -Because $scenario.Name
        }

        # A build or smoke failure writes its bounded capture where a reader can retrieve it.
        Test-Path -LiteralPath (Join-Path $TestDrive 'measure-candidate-build-failure.log') |
            Should -BeTrue

        # The runner budget is measured against a Stopwatch the runner owns, so the only honest way
        # to exhaust it is to spend real time. The previous form guessed: a 2.3 s mocked delay
        # against a 3 s budget, whose two guards need `elapsed <= budget - 1` before the delay and
        # `elapsed > budget - 1` after it — leaving under a second for everything the runner does
        # before the delay, on a shared CI runner. It could fail either way for reasons having
        # nothing to do with the behaviour under test. The cost of reaching the guard is measured
        # first and the budget is derived from that measurement, so both directions keep seconds of
        # margin however slow the host is.
        $script:gateScenario = @{
            CandidateBuildExit = 0
            CandidateBuildStderr = ''
            CandidateBuildTimedOut = $false
            BaseBuildExit = 0
            BaseBuildTimedOut = $false
            BaseSizeTimedOut = $false
            BaseSizeExit = 0
            BaseSizeStdout = '400000000'
            BaseIdentityExit = 0
            BaseIdentityStdout = "linux/amd64 sha256:$('c' * 64) debian@sha256:$('d' * 64)"
            SmokeExit = 0
            SmokeStdout = (New-SmokeJson -ManifestDigest $manifestSha)
            SmokeDelayMs = 0
            AttestationDelayMs = 0
            CandidateSizeDelayMs = 0
            AttestationValid = $true
            AttestationReason = ''
            AttestedManifestSha = $manifestSha
            AttestedHosts = @('deb.debian.org')
            CandidateOnlyReason = 'zero-base'
        }
        $warmupPath = Join-Path $TestDrive 'measure-budget-warmup.json'
        [void](Invoke-ContainerToolchainGate -Mode Measure -BaseSha ('a' * 40) -CandidateSha ('b' * 40) `
                -BaseRoot $repoRoot -CandidateRoot $repoRoot -ReceiptPath $warmupPath `
                -SummaryPath (Join-Path $TestDrive 'measure-budget-warmup.md') `
                -ProvenancePath (Join-Path $TestDrive 'measure-budget-warmup-provenance.json') 6>$null)
        # `zero-base` returns immediately after the candidate size inspection, which is exactly the
        # guard the delay has to sit behind, so this is the cost of reaching it.
        $reachGuardMs = [int64](Get-Content -LiteralPath $warmupPath -Raw | ConvertFrom-Json).timing.totalMs
        $budgetSeconds = [int][math]::Ceiling($reachGuardMs / 1000.0) + 4
        $delayMs = 5000
        $script:gateScenario.CandidateOnlyReason = ''
        $script:gateScenario.CandidateSizeDelayMs = $delayMs
        $budgetPath = Join-Path $TestDrive 'measure-budget-exhausted.json'
        $budgetResult = Invoke-ContainerToolchainGate -Mode Measure -BaseSha ('a' * 40) -CandidateSha ('b' * 40) `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot -ReceiptPath $budgetPath `
            -SummaryPath (Join-Path $TestDrive 'measure-budget-exhausted.md') `
            -ProvenancePath (Join-Path $TestDrive 'measure-budget-exhausted-provenance.json') `
            -RunnerBudgetSeconds $budgetSeconds 6>$null
        $budgetReceipt = Get-Content -LiteralPath $budgetPath -Raw | ConvertFrom-Json
        $budgetWhy = "budget=$budgetSeconds s, reach=$reachGuardMs ms: $($budgetReceipt.outcome): $($budgetReceipt.diagnostic)"
        $budgetResult.ExitCode | Should -Be 0 -Because $budgetWhy
        $budgetReceipt.outcome | Should -Be 'base-timeout' -Because $budgetWhy
        $budgetReceipt.blocking | Should -BeFalse -Because $budgetWhy
        $budgetReceipt.comparison | Should -Be 'candidate-only' -Because $budgetWhy
        $budgetReceipt.candidateOnlyReason | Should -Be 'base-timeout' -Because $budgetWhy
        $budgetReceipt.diagnostic | Should -Match 'Runner budget elapsed before base build' -Because $budgetWhy
        # The candidate it did measure still has to be reported, or a degraded comparison is
        # indistinguishable from having measured nothing.
        $budgetReceipt.measurement.candidateBytes | Should -Be 450000000 -Because $budgetWhy
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

    It 'writes the detector verdict to the step-output file the workflow named' {
        # The detector's whole contract with the workflow is three lines in a file. Nothing drove
        # `-StepOutputPath` at all: the runner's own tests called Detect without it, so the format
        # of what CI reads — the exact names, the closed values, the append semantics — was pinned
        # only by a YAML assertion that the flag is passed.
        $outputPath = Join-Path $TestDrive 'detect-step-output.txt'
        $zero = Invoke-ContainerToolchainGate -Mode Detect -BaseSha ('0' * 40) -CandidateSha $headSha `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot -StepOutputPath $outputPath `
            -ReceiptPath (Join-Path $TestDrive 'detect-step-output-zero.json') 6>$null
        $zero.ExitCode | Should -Be 0
        $zeroLines = @(Get-Content -LiteralPath $outputPath)
        $zeroLines[0] | Should -BeExactly 'relevance=true'
        $zeroLines[1] | Should -BeExactly 'candidate_only_reason=zero-base'
        $zeroLines[2] | Should -Match '^relevant_path_count=\d+$'

        # `$GITHUB_OUTPUT` is one file shared by every step in a job, so the runner must append.
        # Truncating it would delete outputs steps before it had already published.
        $irrelevant = Invoke-ContainerToolchainGate -Mode Detect -BaseSha $headSha -CandidateSha $headSha `
            -BaseRoot $repoRoot -CandidateRoot $repoRoot -StepOutputPath $outputPath `
            -ReceiptPath (Join-Path $TestDrive 'detect-step-output-same.json') 6>$null
        $irrelevant.ExitCode | Should -Be 0
        $lines = @(Get-Content -LiteralPath $outputPath)
        $lines.Count | Should -Be 6 -Because 'the step-output file is appended to, never rewritten'
        $lines[0] | Should -BeExactly 'relevance=true'
        $lines[3] | Should -BeExactly 'relevance=false'
        $lines[4] | Should -BeExactly 'candidate_only_reason='
        $lines[5] | Should -BeExactly 'relevant_path_count=0'

        # A commit that really does touch the toolchain reports how many paths made it relevant.
        # The names cannot travel here — the alphabet below has no `/` — so the count is what the
        # final receipt can carry, and the detector receipt artifact keeps the names.
        $countPath = Join-Path $TestDrive 'detect-step-output-count.txt'
        Mock Get-ContainerGateDetection {
            [pscustomobject]@{
                Relevant = $true
                CandidateOnlyReason = ''
                RelevantPaths = @(
                    'plugins/autopilot/devcontainer/Dockerfile',
                    'plugins/autopilot/devcontainer/toolchain.tsv'
                )
            }
        }
        [void](Invoke-ContainerToolchainGate -Mode Detect -BaseSha ('a' * 40) -CandidateSha ('b' * 40) `
                -BaseRoot $repoRoot -CandidateRoot $repoRoot -StepOutputPath $countPath `
                -ReceiptPath (Join-Path $TestDrive 'detect-step-output-count.json') 6>$null)
        @(Get-Content -LiteralPath $countPath) | Should -Contain 'relevant_path_count=2'

        # The alphabet is a security control, not formatting: `$GITHUB_OUTPUT` is line-oriented, so
        # a value carrying a newline publishes an output the runner never set.
        $refusalPath = Join-Path $TestDrive 'detect-step-output-refusal.txt'
        {
            Write-GateStepOutput -Path $refusalPath -Value ([ordered]@{ relevance = "true`nrelevance=false" })
        } | Should -Throw '*unsafe value*'
        {
            Write-GateStepOutput -Path $refusalPath -Value ([ordered]@{ relevance = ('x' * 129) })
        } | Should -Throw '*unsafe value*'
        {
            Write-GateStepOutput -Path $refusalPath -Value ([ordered]@{ 'Relevance Flag' = 'true' })
        } | Should -Throw "*Refusing to write step output*"
    }

    It 'keeps a failing smoke run reasons when its digests and cases are unavailable' {
        # The smoke program's whole-run fallbacks report `state=fail` with a named reason and
        # nothing else — no digests, no cases — because whatever produced them is the reason the
        # run failed. Rejecting the object for that turned `encoder-failed` and `output-oversize`
        # into the generic `candidate-output-invalid`, discarding the one thing the failing run
        # managed to say. These are the literal fallbacks the shipped script emits.
        $manifestPath = Join-Path $repoRoot '.github/skills/autopilot/devcontainer/toolchain.tsv'
        foreach ($case in @(
                @{ Reason = 'encoder-failed' },
                @{ Reason = 'output-oversize' }
            )) {
            $degraded = [ordered]@{
                schema = 'skalary/container-toolchain-smoke@1'
                state = 'fail'
                reasons = @($case.Reason)
                origin = [ordered]@{ os = ''; aptHosts = @() }
                digests = [ordered]@{ manifestSha256 = ''; provenanceSha256 = '' }
                cases = @()
            }
            $result = Test-GateSmokeOutput -ManifestPath $manifestPath `
                -Output ($degraded | ConvertTo-Json -Depth 8 -Compress)
            $result.Valid | Should -BeTrue -Because "'$($case.Reason)' is a diagnosis, not a malformed object"
            @($result.Reasons) | Should -Be @($case.Reason)
            $result.Summary | Should -Match ([regex]::Escape($case.Reason))
            $result.Value.state | Should -Be 'fail'
        }

        # The relaxation is bounded by the reason set staying closed: an unrecognised reason is
        # still a free-text channel into the summary and is still refused.
        $invented = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'fail'
            reasons = @('whatever-i-want')
            origin = [ordered]@{ os = ''; aptHosts = @() }
            digests = [ordered]@{ manifestSha256 = ''; provenanceSha256 = '' }
            cases = @()
        }
        $inventedResult = Test-GateSmokeOutput -ManifestPath $manifestPath `
            -Output ($invented | ConvertTo-Json -Depth 8 -Compress)
        $inventedResult.Valid | Should -BeFalse
        $inventedResult.Summary | Should -Match 'closed set'

        # And a `state=fail` with no reason at all still names nothing, so it stays invalid.
        $silent = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'fail'
            reasons = @()
            origin = [ordered]@{ os = ''; aptHosts = @() }
            digests = [ordered]@{ manifestSha256 = ''; provenanceSha256 = '' }
            cases = @()
        }
        $silentResult = Test-GateSmokeOutput -ManifestPath $manifestPath `
            -Output ($silent | ConvertTo-Json -Depth 8 -Compress)
        $silentResult.Valid | Should -BeFalse

        # Nothing is relaxed for a passing claim: attestation agreement is checked against exactly
        # these fields, so a `state=pass` with an empty digest must still be rejected.
        $caseIds = @(Get-TestManifestCaseId -Path $manifestPath)
        $passing = [ordered]@{
            schema = 'skalary/container-toolchain-smoke@1'
            state = 'pass'
            reasons = @()
            origin = [ordered]@{ os = 'debian:13'; aptHosts = @('deb.debian.org') }
            digests = [ordered]@{ manifestSha256 = ''; provenanceSha256 = ('b' * 64) }
            cases = @($caseIds | ForEach-Object { [ordered]@{ id = $_; state = 'pass'; version = '1.0' } })
        }
        $passingResult = Test-GateSmokeOutput -ManifestPath $manifestPath `
            -Output ($passing | ConvertTo-Json -Depth 8 -Compress)
        $passingResult.Valid | Should -BeFalse
        $passingResult.Summary | Should -Match 'digest is invalid'
    }

    It 'fails closed on a redirected or unsupported apt source tree' {
        # A `-File` enumeration returns nothing for a symlinked directory and reports no error, so
        # a tree whose `sources.list.d` points elsewhere used to be read as the empty set and the
        # scan reported only the part it could see. Any link under the root now fails the read.
        if (-not $IsWindows) {
            $linkRoot = Join-Path $TestDrive 'etc-apt-linked'
            $hidden = Join-Path $TestDrive 'hidden-sources'
            [void](New-Item -ItemType Directory -Path $linkRoot -Force)
            [void](New-Item -ItemType Directory -Path $hidden -Force)
            Set-Content -LiteralPath (Join-Path $linkRoot 'sources.list') -Encoding utf8NoBOM `
                -Value 'deb http://deb.debian.org/debian trixie main'
            Set-Content -LiteralPath (Join-Path $hidden 'evil.list') -Encoding utf8NoBOM `
                -Value 'deb https://evil.invalid/debian trixie main'
            [void](New-Item -ItemType SymbolicLink -Path (Join-Path $linkRoot 'sources.list.d') -Target $hidden)
            Get-GateAptConfigHost -Root $linkRoot |
                Should -BeNullOrEmpty -Because 'a redirected source directory is not a tree this scan can vouch for'

            $fileLinkRoot = Join-Path $TestDrive 'etc-apt-file-linked'
            [void](New-Item -ItemType Directory -Path (Join-Path $fileLinkRoot 'sources.list.d') -Force)
            [void](New-Item -ItemType SymbolicLink `
                    -Path (Join-Path $fileLinkRoot 'sources.list.d/evil.list') `
                    -Target (Join-Path $hidden 'evil.list'))
            Get-GateAptConfigHost -Root $fileLinkRoot |
                Should -BeNullOrEmpty -Because 'a linked source file is not read in place'
        }

        # A source with no authority is still an origin. `scheme://authority` cannot match any of
        # these, so they were invisible to a scan that only knew how to see a host, and an image
        # sourcing packages from a local tree passed the allowlist by naming nothing.
        foreach ($case in @(
                @{ Line = 'deb file:/srv/local-repo trixie main'; Host = 'file:opaque' },
                @{ Line = 'deb cdrom:[Debian trixie]/ trixie main'; Host = 'cdrom:opaque' },
                @{ Line = 'deb mirror+file:///etc/apt/mirrors/debian.list trixie main'; Host = 'mirror+file:opaque' },
                @{ Line = 'deb copy:/var/cache/local trixie main'; Host = 'copy:opaque' },
                @{ Line = 'deb tor+http://example.onion/debian trixie main'; Host = 'tor+http://example.onion' }
            )) {
            $root = Join-Path $TestDrive ('etc-apt-uri-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $root -Force)
            Set-Content -LiteralPath (Join-Path $root 'sources.list') -Encoding utf8NoBOM -Value $case.Line
            $found = @(Get-GateAptConfigHost -Root $root)
            $found | Should -Contain $case.Host -Because "'$($case.Line)' names an origin"
            (Test-GateAllowedAptHost -Value $found -Allowed $script:AllowedAptHosts) |
                Should -BeFalse -Because "'$($case.Host)' is not on the allowlist and must not pass as no host at all"
        }

        # deb822 permits `URIs:https://...` with no space after the colon, and apt honours it. A
        # single `<scheme>:<rest>` pattern binds `scheme=URIs`, swallows the real URL into `rest`,
        # discards it as a non-transport scheme, and never looks at the embedded `https://` again,
        # because matching resumes past the end of the match. The origin is then simply absent from
        # the scan, and the subset check passes on whatever else the tree contained.
        $glued = Join-Path $TestDrive 'etc-apt-glued'
        [void](New-Item -ItemType Directory -Path (Join-Path $glued 'sources.list.d') -Force)
        Set-Content -LiteralPath (Join-Path $glued 'sources.list.d/debian.sources') -Encoding utf8NoBOM -Value @(
            'Types: deb'
            'URIs: http://deb.debian.org/debian'
            'Suites: trixie'
            'Components: main'
        )
        Set-Content -LiteralPath (Join-Path $glued 'sources.list.d/evil.sources') -Encoding utf8NoBOM -Value @(
            'Types: deb'
            'URIs:https://evil.invalid/repo'
            'Suites: trixie'
            'Components: main'
        )
        $gluedHosts = @(Get-GateAptConfigHost -Root $glued)
        $gluedHosts | Should -Contain 'evil.invalid' -Because 'apt fetches from it, so the scan must see it'
        (Test-GateAllowedAptHost -Value $gluedHosts -Allowed $script:AllowedAptHosts) | Should -BeFalse
        # The allowed source in the same tree must not be what rescues the check: an unreported
        # origin plus one legitimate one is exactly how a subset test passes while lying.
        $gluedHosts | Should -Contain 'deb.debian.org'

        # Failing closed must not mean failing on everything: a real deb822 stanza has fields whose
        # values follow a colon, and none of them is a source. Reporting them would block the image
        # the gate is supposed to pass.
        $deb822Root = Join-Path $TestDrive 'etc-apt-deb822'
        [void](New-Item -ItemType Directory -Path (Join-Path $deb822Root 'sources.list.d') -Force)
        Set-Content -LiteralPath (Join-Path $deb822Root 'sources.list.d/debian.sources') -Encoding utf8NoBOM -Value @(
            'Types: deb'
            'URIs: http://deb.debian.org/debian'
            'Suites: trixie trixie-updates'
            'Components: main'
            'Enabled: yes'
            'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg'
        )
        @(Get-GateAptConfigHost -Root $deb822Root) | Should -Be @('deb.debian.org')
    }

    It 'fails closed on an apt configuration that relocates or extends itself out of view' {
        # The live read exists because every check before it runs on a file the candidate's own
        # Dockerfile wrote. It is worth nothing if the configuration can point apt at a tree the
        # scan never enumerates, so each directive that does so must fail the read and say so.
        function New-ConfigRoot {
            param([string]$Directive, [string]$File = 'apt.conf.d/99local')
            $root = Join-Path $TestDrive ('etc-apt-cfg-' + [guid]::NewGuid().ToString('N'))
            $target = Join-Path $root $File
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
            Set-Content -LiteralPath (Join-Path $root 'sources.list') -Encoding utf8NoBOM `
                -Value 'deb http://deb.debian.org/debian trixie main'
            Set-Content -LiteralPath $target -Encoding utf8NoBOM -Value $Directive
            return $root
        }

        # apt scopes configuration per binary. `Binary::apt-get::Dir::Etc::sourcelist` relocates the
        # source list for apt-get alone and leaves the unscoped value untouched, so a scan that
        # required a non-colon before `Dir` read an allowlisted `/etc/apt` that apt-get never
        # consults and reported its hosts as the image's origins. `RootDir` is worse: apt prefixes
        # it onto every resolved path, moving `/etc/apt` itself out of view. `#include` is the same
        # hole by a third route — apt treats it as a directive rather than a comment, and the file
        # it pulls in is not in the tree this scan can vouch for. And none of these is bounded by a
        # line: apt accumulates statements across lines and splices `/* */` out of a token, so the
        # last four cases are the same relocations written so that no single line carries them.
        foreach ($case in @(
                @{ Directive = 'Binary::apt-get::Dir::Etc::sourcelist "/opt/hidden/sources.list";'; Reason = 'config-dir-override' },
                @{ Directive = 'Binary::apt::Dir::Etc::sourceparts "/opt/hidden/sources.list.d";'; Reason = 'config-dir-override' },
                @{ Directive = 'Binary::apt::Dir::Etc "/opt/hidden";'; Reason = 'config-dir-override' },
                @{ Directive = 'Binary::apt-cache::Dir "/opt/hidden/";'; Reason = 'config-dir-override' },
                @{ Directive = 'Binary::apt { Dir::Etc::sourcelist "/opt/hidden/sources.list"; };'; Reason = 'config-dir-override' },
                @{ Directive = 'Binary { apt-get { Dir { Etc { sourcelist "/opt/hidden/x"; }; }; }; };'; Reason = 'config-dir-override' },
                @{ Directive = 'Dir::Etc::sourcelist "/opt/hidden/sources.list";'; Reason = 'config-dir-override' },
                @{ Directive = 'RootDir "/opt/hidden";'; Reason = 'config-dir-override' },
                @{ Directive = 'Binary::apt-get::RootDir "/opt/hidden";'; Reason = 'config-dir-override' },
                @{ Directive = 'Dir::Bin::methods "/opt/hidden/methods";'; Reason = 'config-dir-override' },
                @{ Directive = '#include "/opt/hidden/apt.conf";'; Reason = 'config-include' },
                @{ Directive = '#include /opt/hidden/apt.conf;'; Reason = 'config-include' },
                @{ Directive = '#INCLUDE "/opt/hidden/apt.conf";'; Reason = 'config-include' },
                @{ Directive = '#clear Binary::apt-get::Dir::Etc;'; Reason = 'config-dir-clear' },
                @{ Directive = "Dir`n{`n  Etc { sourcelist `"/opt/hidden/sources.list`"; };`n};"; Reason = 'config-dir-override' },
                @{ Directive = 'APT::Get::Show-Versions "0"; #include "/opt/hidden/apt.conf";'; Reason = 'config-include' },
                @{ Directive = 'D/*x*/ir::Etc::sourcelist "/opt/hidden/sources.list";'; Reason = 'config-dir-override' },
                @{ Directive = "Dir::Etc::sourcelist /*`n*/ `"/opt/hidden/sources.list`";"; Reason = 'config-dir-override' },
                # A `//` inside the quoted proxy URL must not swallow the directive after it. The
                # verdict distinguishes the two readings on its own: swallowed, the only token left
                # is the proxy and the reason is `config-proxy`; read as apt reads it, the
                # relocation is found first and names itself.
                @{ Directive = 'Acquire::http::Proxy "http://proxy.invalid:3128"; Dir::Etc::sourcelist "/opt/hidden/x";'; Reason = 'config-dir-override' },
                # apt parses a *word*, not a span of characters: `ParseQuoteWord` strips embedded
                # quotes and decodes `%XX` escapes in the tag as well as the value. Every line below
                # was run against apt in `debian:trixie-slim` and moves `Dir::Etc::sourcelist` to
                # `/opt/hidden` or honours the include, while a reader that only modelled comments
                # and statements saw `D""r::…`, `""::…` or `%44ir::…` and found no token at all.
                @{ Directive = 'D"i"r::Etc::sourcelist "/opt/hidden/sources.list";'; Reason = 'config-dir-override' },
                @{ Directive = '"Dir"::Etc::sourcelist "/opt/hidden/sources.list";'; Reason = 'config-dir-override' },
                @{ Directive = '"Dir::Etc::sourcelist" "/opt/hidden/sources.list";'; Reason = 'config-dir-override' },
                @{ Directive = '%44ir::Etc::sourcelist "/opt/hidden/sources.list";'; Reason = 'config-dir-override' },
                @{ Directive = '%52ootDir "/opt/hidden";'; Reason = 'config-dir-override' },
                @{ Directive = 'Binary::apt-get::%44ir::Etc::sourceparts "/opt/hidden/parts";'; Reason = 'config-dir-override' },
                @{ Directive = '"#include" "/opt/hidden/apt.conf";'; Reason = 'config-include' },
                @{ Directive = '%23include "/opt/hidden/apt.conf";'; Reason = 'config-include' },
                # A proxy changes no hostname: apt still asks for `deb.debian.org`, the proxy
                # answers, and every origin comparison in this gate passes on a tree that is
                # fetched from somewhere else entirely. Each line below was accepted before this
                # test existed. The forms are not a closed set — per-transport, per-host, and two
                # spellings of auto-detection — so the test is on the segment, not on a list.
                @{ Directive = 'Acquire::http::Proxy "http://proxy.invalid:3128";'; Reason = 'config-proxy' },
                @{ Directive = 'Acquire::https::Proxy "socks5h://127.0.0.1:9050";'; Reason = 'config-proxy' },
                @{ Directive = 'Acquire::http::Proxy::deb.debian.org "http://proxy.invalid:3128";'; Reason = 'config-proxy' },
                @{ Directive = 'Acquire::http::Proxy-Auto-Detect "/opt/hidden/detect.sh";'; Reason = 'config-proxy' },
                @{ Directive = 'Acquire::http::ProxyAutoDetect "/opt/hidden/detect.sh";'; Reason = 'config-proxy' },
                @{ Directive = 'Binary::apt-get::Acquire::http::Proxy "http://proxy.invalid:3128";'; Reason = 'config-proxy' },
                @{ Directive = 'Acquire { http { Proxy "http://proxy.invalid:3128"; }; };'; Reason = 'config-proxy' },
                @{ Directive = 'Acquire::http::P%72oxy "http://proxy.invalid:3128";'; Reason = 'config-proxy' },
                # The proxy substitutes the bytes; these accept them unsigned, and either half is
                # enough on its own. They are refused by segment in any scope and at any value,
                # because agreeing with apt's `StringToBool` on every spelling of true is a
                # comparison that fails silently when it is wrong.
                @{ Directive = 'APT::Get::AllowUnauthenticated "true";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::AllowInsecureRepositories "1";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::AllowDowngradeToInsecureRepositories "yes";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::AllowWeakRepositories "true";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::AllowReleaseInfoChange::Origin "true";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::Check-Valid-Until "false";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::Check-Date "false";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::https::Verify-Peer "false";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::https::Verify-Host "false";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::https::CaInfo "/opt/hidden/ca.pem";'; Reason = 'config-trust' },
                @{ Directive = 'APT::Authentication::TrustCDROM "true";'; Reason = 'config-trust' },
                @{ Directive = 'APT::Hashes::SHA1::Untrusted "false";'; Reason = 'config-trust' },
                @{ Directive = 'Acquire::gpgv::Options { "--ignore-time-conflict"; };'; Reason = 'config-trust' },
                @{ Directive = 'Binary::apt-get::APT::Get::AllowUnauthenticated "true";'; Reason = 'config-trust' },
                @{ Directive = "APT::Get`n{`n  AllowUnauthenticated `"true`";`n};"; Reason = 'config-trust' },
                @{ Directive = 'APT::Get::Allow%55nauthenticated "true";'; Reason = 'config-trust' }
            )) {
            $reason = ''
            $root = New-ConfigRoot -Directive $case.Directive
            Get-GateAptConfigHost -Root $root -Reason ([ref]$reason) |
                Should -BeNullOrEmpty -Because "'$($case.Directive)' moves the tree this scan enumerates out of view"
            $reason | Should -Be "$($case.Reason):apt.conf.d/99local"
        }

        # The same directive in `apt.conf` itself is the same relocation, and the file that carried
        # it is named because "unreadable" alone is not a repair instruction.
        $reason = ''
        $rootConf = New-ConfigRoot -Directive 'Binary::apt::Dir "/opt/hidden/";' -File 'apt.conf'
        Get-GateAptConfigHost -Root $rootConf -Reason ([ref]$reason) | Should -BeNullOrEmpty
        $reason | Should -Be 'config-dir-override:apt.conf'

        # Failing closed must not mean failing on everything. Every block below is shipped verbatim
        # by `debian:trixie-slim` or by the image's own Microsoft and Docker layers, and the gate
        # that rejects one of them blocks `main` over an honest image. `# include …` with a space is
        # prose apt ignores too, and a `Dir::Etc` named inside a real block comment is not a
        # directive at all.
        foreach ($directive in @(
                "# Ideally, these would just be invoking `"apt-get clean`" …`nDPkg::Post-Invoke { `"rm -f /var/cache/apt/archives/*.deb /var/cache/apt/*.bin || true`"; };`nAPT::Update::Post-Invoke { `"rm -f /var/cache/apt/archives/*.deb || true`"; };`n`nDir::Cache::pkgcache `"`";`nDir::Cache::srcpkgcache `"`";",
                "// Pre-configure all packages with debconf before they are installed.`n// If you don't like it, comment it out.`nDPkg::Pre-Install-Pkgs {`"/usr/sbin/dpkg-preconfigure --apt || true`";};",
                "APT`n{`n  NeverAutoRemove`n  {`n`t`"^firmware-linux.*`";`n  };`n  VersionedKernelPackages`n  {`n`t# kernels`n`t`"linux-.*`";`n  };`n};",
                "#   RUN apt-get update \`n#       && apt-get install -y <packages>`nApt::AutoRemove::SuggestsImportant `"false`";",
                'Acquire::Languages "none";',
                'Acquire::GzipIndexes "true";',
                'Dir::State::status "/var/lib/dpkg/status";',
                'Dir::Log::Terminal "/var/log/apt/term.log";',
                'DPkg::Chrootdir "/";',
                '#clear APT::NeverAutoRemove;',
                '# include the docker source in this note',
                '// Dir::Etc::sourcelist is only described here',
                "/* Dir::Etc::sourcelist `"/opt/hidden/x`"; */`nAPT::Install-Suggests `"0`";"
            )) {
            $reason = ''
            $root = New-ConfigRoot -Directive $directive
            @(Get-GateAptConfigHost -Root $root -Reason ([ref]$reason)) |
                Should -Be @('deb.debian.org') -Because "'$directive' relocates no source list"
            $reason | Should -BeNullOrEmpty
        }

        # The failing file's name comes out of the candidate image, so it is untrusted text headed
        # for a diagnostics log, a receipt, and a job summary. It travels as a bounded token on a
        # fixed alphabet rather than as whatever the image chose to call the file.
        $reason = ''
        $hostileName = 'apt.conf.d/99' + ('z' * 90) + '#$ evil'
        $hostileRoot = New-ConfigRoot -Directive 'Dir::Etc "/opt/hidden";' -File $hostileName
        Get-GateAptConfigHost -Root $hostileRoot -Reason ([ref]$reason) | Should -BeNullOrEmpty
        $reason | Should -Match '^config-dir-override:[A-Za-z0-9._/-]+$'
        $reason.Length | Should -BeLessOrEqual 84

        # Every other fail-closed path names itself too, so a red gate is diagnosable without
        # re-running it against the image by hand.
        $reason = ''
        Get-GateAptConfigHost -Root (Join-Path $TestDrive 'absent-config-root') -Reason ([ref]$reason) |
            Should -BeNullOrEmpty
        $reason | Should -Be 'root-absent'

        # The configuration scan is character work on the host, so an image can spend the gate's
        # time by shipping a configuration file large enough to be worth minutes to read. Over the
        # cap the read fails closed and names the file, rather than being skipped — a file this
        # scan did not read is a file it cannot vouch for.
        $reason = ''
        $hugeRoot = New-ConfigRoot -Directive (('# padding for a configuration nobody writes' * 8) + "`n") `
            -File 'apt.conf.d/99huge'
        $hugePath = Join-Path $hugeRoot 'apt.conf.d/99huge'
        [System.IO.File]::WriteAllText($hugePath, ('# padding for a configuration nobody writes' + "`n") * 8192)
        (Get-Item -LiteralPath $hugePath).Length | Should -BeGreaterThan 256KB
        Get-GateAptConfigHost -Root $hugeRoot -Reason ([ref]$reason) | Should -BeNullOrEmpty
        $reason | Should -Be 'config-oversize:apt.conf.d/99huge'

        $reason = ''
        $emptyRoot = Join-Path $TestDrive 'etc-apt-empty'
        [void](New-Item -ItemType Directory -Path $emptyRoot -Force)
        @(Get-GateAptConfigHost -Root $emptyRoot -Reason ([ref]$reason)).Count | Should -Be 0
        $reason | Should -BeNullOrEmpty -Because 'an empty tree is a caller-side verdict, not a read failure'

        if (-not $IsWindows) {
            $reason = ''
            $linkedRoot = Join-Path $TestDrive 'etc-apt-cfg-linked'
            $hiddenDir = Join-Path $TestDrive 'hidden-cfg-sources'
            [void](New-Item -ItemType Directory -Path $linkedRoot -Force)
            [void](New-Item -ItemType Directory -Path $hiddenDir -Force)
            Set-Content -LiteralPath (Join-Path $linkedRoot 'sources.list') -Encoding utf8NoBOM `
                -Value 'deb http://deb.debian.org/debian trixie main'
            [void](New-Item -ItemType SymbolicLink -Path (Join-Path $linkedRoot 'sources.list.d') -Target $hiddenDir)
            Get-GateAptConfigHost -Root $linkedRoot -Reason ([ref]$reason) | Should -BeNullOrEmpty
            $reason | Should -Be 'tree-link:sources.list.d'
        }
    }

    It 'fails closed on a source that waives its own authentication' {
        # A source may waive the signature check in its own syntax, and the waiver names no new
        # host: every origin comparison in this gate — the recorded file, the live tree, the smoke
        # claim — still sees `deb.debian.org` and passes, while apt installs whatever answers for
        # it unsigned. Paired with a proxy or a resolver, that is package substitution with a
        # green gate, so the waiver fails the read where it is written.
        function New-SourceRoot {
            param([Parameter(Mandatory)][string]$Content, [string]$File = 'sources.list.d/vendor.list')
            $root = Join-Path $TestDrive ('etc-apt-src-' + [guid]::NewGuid().ToString('N'))
            $target = Join-Path $root $File
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
            Set-Content -LiteralPath $target -Encoding utf8NoBOM -Value $Content
            return $root
        }

        foreach ($case in @(
                @{ Content = 'deb [trusted=yes] http://deb.debian.org/debian trixie main' },
                @{ Content = 'deb [arch=amd64 trusted=yes] http://deb.debian.org/debian trixie main' },
                @{ Content = 'deb [ trusted = yes ] http://deb.debian.org/debian trixie main' },
                @{ Content = 'deb [trusted=true] http://deb.debian.org/debian trixie main' },
                @{ Content = 'deb [allow-insecure=yes] http://deb.debian.org/debian trixie main' },
                @{ Content = 'deb [allow-weak=yes] http://deb.debian.org/debian trixie main' },
                @{ Content = 'deb [allow-downgrade-to-insecure=yes] http://deb.debian.org/debian trixie main' },
                @{ Content = 'deb [TRUSTED=YES] http://deb.debian.org/debian trixie main' },
                @{ Content = "Types: deb`nURIs: http://deb.debian.org/debian`nSuites: trixie`nTrusted: yes"; File = 'sources.list.d/vendor.sources' },
                @{ Content = "Types: deb`nURIs: http://deb.debian.org/debian`nSuites: trixie`ntrusted:  TRUE"; File = 'sources.list.d/vendor.sources' },
                @{ Content = "Types: deb`nURIs: http://deb.debian.org/debian`nSuites: trixie`nAllow-Weak: yes"; File = 'sources.list.d/vendor.sources' },
                # An empty field is not proof of a safe value: apt reads the waiver's value from
                # the continuation line this reader never joins, so the shape it cannot evaluate
                # fails rather than passing on the half of it that is visible.
                @{ Content = "Types: deb`nURIs: http://deb.debian.org/debian`nSuites: trixie`nTrusted:"; File = 'sources.list.d/vendor.sources' }
            )) {
            $file = if ($case.ContainsKey('File')) { $case.File } else { 'sources.list.d/vendor.list' }
            $reason = ''
            $root = New-SourceRoot -Content $case.Content -File $file
            Get-GateAptConfigHost -Root $root -Reason ([ref]$reason) |
                Should -BeNullOrEmpty -Because "'$($case.Content)' installs from that origin unsigned"
            $reason | Should -Be "source-trusted:$file"
        }

        # The sources this image legitimately carries are the ones the gate exists to let through,
        # and two of them name a keyring under `trusted.gpg.d`. A reader that matched the word
        # rather than the option would fail `main` on Debian's own file. These are the Docker,
        # Microsoft and Debian entries from the built image, verbatim.
        foreach ($case in @(
                @{ File = 'sources.list.d/docker.list'; Content = 'deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian trixie stable'; Hosts = @('download.docker.com') },
                @{ File = 'sources.list.d/microsoft-prod.list'; Content = 'deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/13/prod trixie main'; Hosts = @('packages.microsoft.com') },
                @{ File = 'sources.list.d/debian.sources'; Content = "Types: deb`n# http://snapshot.debian.org/archive/debian/20260803T000000Z`nURIs: http://deb.debian.org/debian`nSuites: trixie trixie-updates`nComponents: main`nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp"; Hosts = @('deb.debian.org') },
                @{ File = 'sources.list.d/legacy.sources'; Content = "Types: deb`nURIs: http://deb.debian.org/debian`nSuites: trixie`nSigned-By: /etc/apt/trusted.gpg.d/debian-archive-trixie-stable.asc"; Hosts = @('deb.debian.org') },
                @{ File = 'sources.list.d/explicit.list'; Content = 'deb [trusted=no] http://deb.debian.org/debian trixie main'; Hosts = @('deb.debian.org') },
                @{ File = 'sources.list'; Content = "# trusted=yes was removed from this file`ndeb http://deb.debian.org/debian trixie main"; Hosts = @('deb.debian.org') }
            )) {
            $reason = ''
            $root = New-SourceRoot -Content $case.Content -File $case.File
            @(Get-GateAptConfigHost -Root $root -Reason ([ref]$reason)) |
                Should -Be $case.Hosts -Because "'$($case.File)' waives nothing"
            $reason | Should -BeNullOrEmpty
        }
    }

    It 'refuses an image environment that points apt at a configuration this gate never reads' {
        # `APT_CONFIG` is read before `/etc/apt/apt.conf` and may relocate, unauthenticate or proxy
        # every path the tree scan enumerates — from a file outside the tree. The whole
        # configuration read is worth nothing while it is set, so it is refused on apt's own
        # condition: non-empty. Proxy variables are refused for the reason the directives are.
        foreach ($case in @(
                @{ Json = '["PATH=/usr/local/bin:/usr/bin"]'; Reason = '' },
                @{ Json = '[]'; Reason = '' },
                @{ Json = 'null'; Reason = '' },
                @{ Json = '["PATH=/usr/bin","APT_CONFIG="]'; Reason = '' },
                @{ Json = '["PATH=/usr/bin","LANG=C.UTF-8","NO_COLOR="]'; Reason = '' },
                @{ Json = '["APT_CONFIG=/opt/hidden/apt.conf"]'; Reason = 'apt-config' },
                @{ Json = '["PATH=/usr/bin","APT_CONFIG=/opt/hidden/apt.conf"]'; Reason = 'apt-config' },
                @{ Json = '["apt_config=/opt/hidden/apt.conf"]'; Reason = 'apt-config' },
                @{ Json = '["http_proxy=http://proxy.invalid:3128"]'; Reason = 'proxy:http_proxy' },
                @{ Json = '["HTTPS_PROXY=http://proxy.invalid:3128"]'; Reason = 'proxy:HTTPS_PROXY' },
                @{ Json = '["all_proxy=socks5h://127.0.0.1:9050"]'; Reason = 'proxy:all_proxy' },
                # A read this function did not understand is not evidence of a clean image.
                @{ Json = ''; Reason = 'unreadable' },
                @{ Json = 'not json at all'; Reason = 'unreadable' },
                @{ Json = '{"APT_CONFIG":"/opt/hidden/apt.conf"}'; Reason = 'unreadable' },
                @{ Json = '[{"name":"APT_CONFIG"}]'; Reason = 'unreadable' },
                # A single-element array comes back from `ConvertFrom-Json` as its element, so a
                # bare JSON string would be indistinguishable from `["APT_CONFIG=…"]` if the shape
                # were decided on the parse rather than on the text.
                @{ Json = '"APT_CONFIG=/opt/hidden/apt.conf"'; Reason = 'unreadable' }
            )) {
            Get-GateImageEnvRejection -Json $case.Json |
                Should -Be $case.Reason -Because "'$($case.Json)' must read as '$($case.Reason)'"
        }

        # The name travels into a diagnostics log, a receipt and a job summary, so it is bounded on
        # a fixed alphabet rather than carried as whatever the image called the variable.
        $hostileName = ('X' * 90) + '_proxy# $(evil)'
        $hostile = Get-GateImageEnvRejection -Json ('["' + $hostileName + '=http://proxy.invalid:3128"]')
        $hostile | Should -Match '^proxy:[A-Za-z0-9_]{1,32}$'

        # Bounded twice — total bytes and entry count — because the input describes a candidate
        # image and a host-side scan an image can make arbitrarily expensive is a denial of the
        # gate rather than a check on it.
        $manyEntries = '[' + (((1..300) | ForEach-Object { "`"VAR$_=x`"" }) -join ',') + ']'
        Get-GateImageEnvRejection -Json $manyEntries | Should -Be 'oversize'
        Get-GateImageEnvRejection -Json ('["PATH=' + ('x' * 70000) + '"]') | Should -Be 'oversize'
    }

    It 'writes a blocking placeholder when a relevant commit job never started' {
        # A placeholder receipt exists because a job can die before writing its own. Hardcoding
        # `irrelevant` made that placeholder claim the commit did not touch the toolchain, which
        # is the one reading under which a lost measurement job disappears instead of being seen.
        $relevantPath = Join-Path $TestDrive 'placeholder-relevant.json'
        $relevant = Invoke-ContainerToolchainGate -Mode Initialize -DetectionRelevance 'true' `
            -BaseSha ('a' * 40) -CandidateSha ('b' * 40) -ReceiptPath $relevantPath `
            -Diagnostic 'measurement did not start' 6>$null
        $relevant.ExitCode | Should -Be 0 -Because 'the placeholder is written, not enforced; the gate job reads it'
        $relevantReceipt = Get-Content -LiteralPath $relevantPath -Raw | ConvertFrom-Json
        $relevantReceipt.outcome | Should -Be 'unexpected-error'
        $relevantReceipt.relevant | Should -BeTrue
        $relevantReceipt.blocking | Should -BeTrue
        $relevantReceipt.identities.candidateSha | Should -Be ('b' * 40)
        $relevantReceipt.diagnostic | Should -Match 'measurement did not start'

        # For a commit that genuinely changed nothing, `irrelevant` is the truth and stays.
        $irrelevantPath = Join-Path $TestDrive 'placeholder-irrelevant.json'
        [void](Invoke-ContainerToolchainGate -Mode Initialize -DetectionRelevance 'false' `
                -BaseSha ('a' * 40) -CandidateSha ('b' * 40) -ReceiptPath $irrelevantPath `
                -Diagnostic 'final verification did not start' 6>$null)
        $irrelevantReceipt = Get-Content -LiteralPath $irrelevantPath -Raw | ConvertFrom-Json
        $irrelevantReceipt.outcome | Should -Be 'irrelevant'
        $irrelevantReceipt.relevant | Should -BeFalse
        $irrelevantReceipt.blocking | Should -BeFalse
    }

    It 'names the commit and the detector evidence in the final receipt' {
        # The final receipt is the only artifact that always exists, and when the measurement job
        # is skipped it is the only one there is. It used to name no commit at all, so the verdict
        # that decides whether main is green could not be attributed to the change it judged.
        $receiptPath = Join-Path $TestDrive 'final-identities.json'
        $result = Invoke-ContainerToolchainGate -Mode VerifyResult `
            -DetectorConclusion success -Relevance true -ImageConclusion success `
            -MeasurementComparison comparable `
            -BaseSha ('a' * 40) -CandidateSha ('b' * 40) -RelevantPathCount '3' `
            -ReceiptPath $receiptPath 6>$null
        $result.ExitCode | Should -Be 0
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        $receipt.identities.baseSha | Should -Be ('a' * 40)
        $receipt.identities.candidateSha | Should -Be ('b' * 40)
        $receipt.identities.architecture | Should -Not -BeNullOrEmpty
        $receipt.comparison | Should -Be 'comparable'
        $receipt.diagnostic | Should -Match 'relevantPaths=3'
        $receipt.diagnostic | Should -Match 'candidateOnlyReason=none'

        # A degraded run must carry *why* the base was unusable, not just that the gate passed.
        $degradedPath = Join-Path $TestDrive 'final-identities-degraded.json'
        [void](Invoke-ContainerToolchainGate -Mode VerifyResult `
                -DetectorConclusion success -Relevance true -ImageConclusion success `
                -MeasurementComparison candidate-only -MeasurementCandidateOnlyReason base-build-failed `
                -BaseSha ('0' * 40) -CandidateSha ('b' * 40) -RelevantPathCount '2' `
                -ReceiptPath $degradedPath 6>$null)
        $degraded = Get-Content -LiteralPath $degradedPath -Raw | ConvertFrom-Json
        $degraded.candidateOnlyReason | Should -Be 'base-build-failed'
        $degraded.comparison | Should -Be 'candidate-only'
        $degraded.diagnostic | Should -Match 'candidateOnlyReason=base-build-failed'

        # An absent count is reported as absent rather than as zero relevant paths, which would be
        # a different claim entirely.
        $unreportedPath = Join-Path $TestDrive 'final-identities-unreported.json'
        [void](Invoke-ContainerToolchainGate -Mode VerifyResult `
                -DetectorConclusion success -Relevance false -ImageConclusion skipped `
                -BaseSha ('a' * 40) -CandidateSha ('b' * 40) -ReceiptPath $unreportedPath 6>$null)
        (Get-Content -LiteralPath $unreportedPath -Raw | ConvertFrom-Json).diagnostic |
            Should -Match 'relevantPaths=unreported'

        # `comparison` is a fact about a measurement, and this job performs none. Claiming
        # `comparable` because the commit was *relevant* puts a comparison next to a null delta in
        # the same receipt, for runs where nothing was ever built.
        foreach ($case in @(
                @{ Image = 'failure'; Expected = 'not-run' },
                @{ Image = 'skipped'; Expected = 'not-run' },
                @{ Image = 'cancelled'; Expected = 'not-run' },
                @{ Image = 'success'; Expected = 'comparable' }
            )) {
            $path = Join-Path $TestDrive "final-comparison-$($case.Image).json"
            [void](Invoke-ContainerToolchainGate -Mode VerifyResult `
                    -DetectorConclusion success -Relevance true -ImageConclusion $case.Image `
                    -MeasurementComparison $(if ($case.Image -eq 'success') { 'comparable' } else { '' }) `
                    -BaseSha ('a' * 40) -CandidateSha ('b' * 40) -ReceiptPath $path 6>$null)
            $written = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $written.comparison | Should -Be $case.Expected -Because "image=$($case.Image) measured $(if ($case.Image -eq 'success') { 'something' } else { 'nothing' })"
            if ($case.Expected -eq 'not-run') {
                $written.measurement.deltaBytes | Should -BeNullOrEmpty -Because 'the receipt must not contradict itself'
            }
        }
    }
}

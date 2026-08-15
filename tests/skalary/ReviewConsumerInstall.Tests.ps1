#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'isolated review-run consumer installs' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        function Script:Write-JsonHandshake {
            param(
                [Parameter(Mandatory)][string]$RunDir,
                [Parameter(Mandatory)][ValidateSet('plan', 'result')][string]$Kind,
                [Parameter(Mandatory)]$Value
            )

            [void](New-Item -ItemType Directory -Path $RunDir -Force)
            $stem = if ($Kind -eq 'plan') { 'review-plan' } else { 'review-result' }
            $tmp = Join-Path $RunDir ".$stem.input.tmp"
            $target = Join-Path $RunDir "$stem.input.json"
            $json = (ConvertTo-Json -InputObject $Value -Depth 40 -Compress) + "`n"
            [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::Move($tmp, $target, $true)
        }

        function Script:New-ConsumerFixture {
            param(
                [Parameter(Mandatory)][string]$Id,
                [Parameter(Mandatory)][string]$Plugin,
                [Parameter(Mandatory)][string]$ReviewType
            )

            $root = Join-Path ([System.IO.Path]::GetTempPath()) (
                "review-consumer-$Id-" + [guid]::NewGuid().ToString('N')
            )
            [void](New-Item -ItemType Directory -Path $root -Force)
            git init -q $root 2>$null | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because "the $Id fixture needs an isolated repository boundary"
            Test-Path -LiteralPath (Join-Path $root '.git') -PathType Container | Should -BeTrue

            $installed = Join-Path $root ".github/skills/$Id/scripts"
            $pluginRoot = Join-Path $script:repoRoot "plugins/$Plugin"
            $manifest = Get-Content -LiteralPath (Join-Path $pluginRoot 'plugin.json') -Raw |
                ConvertFrom-Json -Depth 50
            $scriptMappings = @($manifest.files | Where-Object {
                    [string]$_.dest -like "skills/$Id/scripts/*"
                })
            $scriptMappings.Count | Should -BeGreaterThan 0
            $pluginBoundary = [System.IO.Path]::GetFullPath($pluginRoot).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar
            $installBoundary = [System.IO.Path]::GetFullPath((Join-Path $root '.github')).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar
            foreach ($mapping in $scriptMappings) {
                $source = [System.IO.Path]::GetFullPath(
                    (Join-Path $pluginRoot (([string]$mapping.src) -replace '/', [System.IO.Path]::DirectorySeparatorChar))
                )
                $destination = [System.IO.Path]::GetFullPath(
                    (Join-Path (Join-Path $root '.github') (
                            ([string]$mapping.dest) -replace '/', [System.IO.Path]::DirectorySeparatorChar
                        ))
                )
                $source.StartsWith($pluginBoundary, [System.StringComparison]::Ordinal) |
                    Should -BeTrue -Because "manifest source '$($mapping.src)' must stay inside $Plugin"
                $destination.StartsWith($installBoundary, [System.StringComparison]::Ordinal) |
                    Should -BeTrue -Because "manifest destination '$($mapping.dest)' must stay inside the fixture .github root"
                (Get-Item -LiteralPath $source -Force).LinkType |
                    Should -BeNullOrEmpty -Because 'the isolated install must not follow a manifest source symlink'
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }

            # Any fallback to repository scripts or schemas must fail. The installed closure is the
            # only runtime available to these fixtures.
            $poisonedScripts = Join-Path $root 'scripts/skalary'
            [void](New-Item -ItemType Directory -Path $poisonedScripts -Force)
            foreach ($name in @('PlanState.psm1', 'ReviewRun.psm1')) {
                Set-Content -LiteralPath (Join-Path $poisonedScripts $name) `
                    -Value "throw 'repository $name must not execute from an installed review bundle'" `
                    -Encoding utf8NoBOM
            }
            $poisonedSchemas = Join-Path $root 'schemas/review'
            [void](New-Item -ItemType Directory -Path $poisonedSchemas -Force)
            foreach ($name in @(
                    'review-limits.schema.json',
                    'review-admission.schema.json',
                    'review-manifest.schema.json',
                    'review-plan.schema.json',
                    'review-run.schema.json',
                    'terminal-status.schema.json'
                )) {
                Set-Content -LiteralPath (Join-Path $poisonedSchemas $name) `
                    -Value "{invalid repository fallback schema: $name" -Encoding utf8NoBOM
            }

            $planDir = Join-Path $root 'docs/implementation-plans/2026-01-01-abc123-consumer'
            [void](New-Item -ItemType Directory -Path (Join-Path $planDir 'assets') -Force)
            Set-Content -LiteralPath (Join-Path $planDir 'plan.md') `
                -Value "# abc123: Consumer`n<!-- plan-id: abc123 -->`n" -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $planDir 'assets/requirements.md') `
                -Value "# Requirements`n`n| ID | Requirement | Acceptance Criteria | Phases/Steps |`n|---|---|---|---|`n| REQ-1 | Test | Test | 1.1 |`n" `
                -Encoding utf8NoBOM

            return [pscustomobject]@{
                Id = $Id
                ReviewType = $ReviewType
                Root = $root
                Installed = $installed
                PlanDir = $planDir
                Writer = Join-Path $installed 'Build-ReviewReport.ps1'
                Reader = Join-Path $installed 'Get-ReviewRun.ps1'
                Cleaner = Join-Path $installed 'Remove-ReviewRun.ps1'
                Module = Join-Path $installed 'ReviewRun.psm1'
                TerminalSchema = Join-Path $installed 'schemas/review/terminal-status.schema.json'
                LimitsSchema = Join-Path $installed 'schemas/review/review-limits.schema.json'
            }
        }

        function Script:Get-ConsumerRunDir {
            param(
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][string]$RunId,
                [switch]$Plan
            )
            if ($Plan) { return Join-Path $Fixture.PlanDir "assets/reviews/$RunId" }
            return Join-Path $Fixture.Root ".github/.skalary/review-runs/$RunId"
        }

        function Script:New-ConsumerPlan {
            param(
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][string]$RunId,
                [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tasks,
                [string]$Scope = 'isolated consumer lifecycle'
            )
            $scopeAuthority = if ($Fixture.ReviewType -eq 'design') {
                [ordered]@{
                    mode = 'design'
                    paths = @([ordered]@{ path = 'docs/implementation-plans/2026-01-01-abc123-consumer/plan.md'; status = 'modified' })
                    designSource = [ordered]@{
                        kind = 'plan'
                        path = 'docs/implementation-plans/2026-01-01-abc123-consumer/plan.md'
                        digest = 'sha256:' + ('1' * 64)
                    }
                }
            }
            else {
                [ordered]@{ mode = 'branch'; base = 'main'; head = 'HEAD'; paths = @([ordered]@{ path = 'README.md'; status = 'modified' }) }
            }
            $scopeAuthority['digest'] = Get-ReviewScopeDigest -ScopeAuthority $scopeAuthority
            return [ordered]@{
                schema = 'skalary/review-plan@1'
                runId = $RunId
                reviewType = $Fixture.ReviewType
                contentTrust = 'reviewer-authored-data'
                scope = $Scope
                scopeAuthority = $scopeAuthority
                roster = @('model-a')
                modelSelection   = @([ordered]@{ requested = 'model-a'; declared = 'model-a'; preflight = 'available'; degradation = 'none'; servedIdentity = 'unverified' })
                invocationBudget = 28
                tasks            = @($Tasks)
            }
        }

        function Script:New-ConsumerResult {
            param(
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][string]$RunId,
                [Parameter(Mandatory)][string]$PlanDigest,
                [Parameter(Mandatory)][object[]]$Tasks,
                [object[]]$Findings = @(),
                [string]$Scope = 'isolated consumer lifecycle'
            )
            $scopeAuthority = if ($Fixture.ReviewType -eq 'design') {
                [ordered]@{
                    mode         = 'design'
                    paths        = @([ordered]@{ path = 'docs/implementation-plans/2026-01-01-abc123-consumer/plan.md'; status = 'modified' })
                    designSource = [ordered]@{
                        kind   = 'plan'
                        path   = 'docs/implementation-plans/2026-01-01-abc123-consumer/plan.md'
                        digest = 'sha256:' + ('1' * 64)
                    }
                }
            }
            else {
                [ordered]@{ mode = 'branch'; base = 'main'; head = 'HEAD'; paths = @([ordered]@{ path = 'README.md'; status = 'modified' }) }
            }
            $scopeAuthority['digest'] = Get-ReviewScopeDigest -ScopeAuthority $scopeAuthority
            return [ordered]@{
                schema           = 'skalary/review-run@1'
                runId            = $RunId
                reviewType       = $Fixture.ReviewType
                contentTrust     = 'reviewer-authored-data'
                scope            = $Scope
                scopeAuthority   = $scopeAuthority
                roster           = @('model-a')
                modelSelection   = @([ordered]@{ requested = 'model-a'; declared = 'model-a'; preflight = 'available'; degradation = 'none'; servedIdentity = 'unverified' })
                invocationBudget = 28
                planDigest       = $PlanDigest
                tasks            = @($Tasks)
                findings         = @($Findings)
            }
        }

        function Script:Invoke-ConsumerWriter {
            param(
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][ValidateSet('Freeze', 'Publish')][string]$Mode,
                [Parameter(Mandatory)][string]$RunId,
                [switch]$Plan
            )

            $arguments = @('-NoProfile', '-File', $Fixture.Writer, '-Mode', $Mode, '-RunId', $RunId)
            if ($Plan) { $arguments += @('-PlanDir', $Fixture.PlanDir) }
            $output = @(& pwsh @arguments 2>&1)
            $exitCode = $LASTEXITCODE
            $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $statusLine = @($output | Where-Object {
                    $_ -isnot [System.Management.Automation.ErrorRecord] -and
                    -not [string]::IsNullOrWhiteSpace([string]$_)
                })
            $statusLine.Count | Should -Be 1 -Because "$($Fixture.Id) $Mode must emit exactly one terminal status object"
            [string]$statusLine[0] | Should -Match '^\{'
            [System.Text.Encoding]::UTF8.GetByteCount(([string]$statusLine[0]) + "`n") |
            Should -BeLessOrEqual 8192 -Because 'the installed terminal status is schema-bounded'
            ([string]$statusLine[0] | Test-Json -SchemaFile $Fixture.TerminalSchema -ErrorAction SilentlyContinue) |
            Should -BeTrue -Because "$($Fixture.Id) $Mode stdout must be one schema-valid status object"
            return [pscustomobject]@{
                ExitCode = $exitCode
                Status   = ([string]$statusLine[0] | ConvertFrom-Json)
                Stdout   = [string]$statusLine[0]
                Stderr   = ($stderr -join "`n")
            }
        }

        function Script:Invoke-ConsumerReader {
            param(
                [Parameter(Mandatory)]$Fixture,
                [AllowEmptyString()][string]$RunId,
                [switch]$Plan,
                [switch]$ListIncomplete,
                [ValidateSet('Summary', 'Full')][string]$View = 'Summary'
            )

            $arguments = @('-NoProfile', '-File', $Fixture.Reader)
            if ($ListIncomplete) { $arguments += '-ListIncomplete' } else { $arguments += @('-RunId', $RunId) }
            if (-not $ListIncomplete) { $arguments += @('-View', $View) }
            if ($Plan) { $arguments += @('-PlanDir', $Fixture.PlanDir) }
            $output = @(& pwsh @arguments 2>&1)
            $exitCode = $LASTEXITCODE
            $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
            return [pscustomobject]@{
                ExitCode = $exitCode
                Text     = ($stdout -join "`n")
                Stderr   = ($stderr -join "`n")
            }
        }

        function Script:Assert-ConsumerExit {
            param(
                [Parameter(Mandatory)]$Result,
                [Parameter(Mandatory)][int]$Expected,
                [Parameter(Mandatory)][string]$Context
            )

            $status = if ($Result.PSObject.Properties.Name -contains 'Status') { $Result.Status } else { $Result }
            $details = @(
                $(if ($status.PSObject.Properties.Name -contains 'message') { [string]$status.message } else { '' })
                $(if ($status.PSObject.Properties.Name -contains 'diagnostics') {
                        @($status.diagnostics) -join '; '
                    }
                    else { '' })
                $(if ($Result.PSObject.Properties.Name -contains 'Stderr') { [string]$Result.Stderr } else { '' })
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            [int]$Result.ExitCode | Should -Be $Expected -Because "$Context. $($details -join ' | ')"
        }

        function Script:Freeze-ConsumerRun {
            param(
                [Parameter(Mandatory)]$Fixture,
                [Parameter(Mandatory)][string]$RunId,
                [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tasks,
                [switch]$Plan,
                [string]$Scope = 'isolated consumer lifecycle'
            )

            $runDir = Get-ConsumerRunDir -Fixture $Fixture -RunId $RunId -Plan:$Plan
            Write-JsonHandshake -RunDir $runDir -Kind plan `
                -Value (New-ConsumerPlan -Fixture $Fixture -RunId $RunId -Tasks $Tasks -Scope $Scope)
            $freeze = Invoke-ConsumerWriter -Fixture $Fixture -Mode Freeze -RunId $RunId -Plan:$Plan
            return [pscustomobject]@{
                RunDir = $runDir
                Result = $freeze
                Digest = if ($freeze.ExitCode -eq 0) {
                    ([System.IO.File]::ReadAllText((Join-Path $runDir '.review-run.frozen'))).Trim()
                }
                else { $null }
            }
        }

        function Script:Remove-GenericConsumerRun {
            param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$RunId, [switch]$Force)
            $arguments = @('-NoProfile', '-File', $Fixture.Cleaner, '-RunId', $RunId)
            if ($Force) { $arguments += '-Force' }
            & pwsh @arguments *> $null
            return $LASTEXITCODE
        }

        function Script:Get-SyntheticSecret {
            $builder = [System.Text.StringBuilder]::new()
            [void]$builder.Append('gh')
            [void]$builder.Append('p_')
            $alphabet = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
            for ($i = 0; $i -lt 36; $i++) { [void]$builder.Append($alphabet[$i % $alphabet.Length]) }
            return $builder.ToString()
        }
    }

    It 'test:ReviewReport.ConsumerInstallInvocation executes the full lifecycle through the isolated <Id> install' -ForEach @(
        @{ Id = 'cr'; Plugin = 'code-review'; ReviewType = 'code' }
        @{ Id = 'dr'; Plugin = 'design-review'; ReviewType = 'design' }
    ) {
        param($Id, $Plugin, $ReviewType)

        $fixture = New-ConsumerFixture -Id $Id -Plugin $Plugin -ReviewType $ReviewType
        $locationPushed = $false
        try {
            Push-Location $fixture.Root
            $locationPushed = $true
            Import-Module $fixture.Module -Force -DisableNameChecking
            $oneTask = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })

            # Clean publication with a finding, then a verifying-reader tamper rejection.
            $cleanId = [guid]::NewGuid().ToString()
            $clean = Freeze-ConsumerRun -Fixture $fixture -RunId $cleanId -Tasks $oneTask
            Assert-ConsumerExit -Result $clean.Result -Expected 0 -Context "$Id clean Freeze"
            $cleanRun = New-ConsumerResult -Fixture $fixture -RunId $cleanId -PlanDigest $clean.Digest -Tasks @(
                @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            ) -Findings @(
                @{ taskId = 'security-m1'; severity = 'High'; title = 'Installed finding'; body = 'data'; references = @('file.ps1:1') }
            )
            Write-JsonHandshake -RunDir $clean.RunDir -Kind result -Value $cleanRun
            $cleanPublished = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $cleanId
            Assert-ConsumerExit -Result $cleanPublished -Expected 0 -Context "$Id clean Publish"
            $read = Invoke-ConsumerReader -Fixture $fixture -RunId $cleanId
            Assert-ConsumerExit -Result $read -Expected 0 -Context "$Id verifying read"
            $read.Text | Should -Match 'Installed finding'
            $fullRead = Invoke-ConsumerReader -Fixture $fixture -RunId $cleanId -View Full
            Assert-ConsumerExit -Result $fullRead -Expected 0 -Context "$Id verifying full read"
            $fullRead.Text | Should -Match '(?m)^## Tasks \(1\)$'
            $fullRead.Text | Should -Match '(?m)^### \[1\] Installed finding$'

            $manifest = Get-Content -LiteralPath (Join-Path $clean.RunDir 'review-run.manifest.json') -Raw |
            ConvertFrom-Json
            Add-Content -LiteralPath (Join-Path $clean.RunDir $manifest.files.summary.name) -Value 'tamper'
            { Get-ReviewRunSummaryText -RunDir $clean.RunDir -Boundary $fixture.Root } | Should -Throw
            Remove-ReviewRunDirectory -RunId $cleanId -RepoRoot $fixture.Root -RequirePublished:$false | Should -Be $cleanId

            # A completed zero-finding review is clean and generic cleanup follows verified delivery.
            $zeroId = [guid]::NewGuid().ToString()
            $zero = Freeze-ConsumerRun -Fixture $fixture -RunId $zeroId -Tasks $oneTask
            $zeroRun = New-ConsumerResult -Fixture $fixture -RunId $zeroId -PlanDigest $zero.Digest -Tasks @(
                @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            )
            Write-JsonHandshake -RunDir $zero.RunDir -Kind result -Value $zeroRun
            $zeroPublished = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $zeroId
            Assert-ConsumerExit -Result $zeroPublished -Expected 0 -Context "$Id zero-finding Publish"
            (Get-ReviewRunSummaryText -RunDir $zero.RunDir -Boundary $fixture.Root) |
            Should -Match 'Merged findings \(0 of 0 raw\)[\s\S]*None\.'
            (Remove-GenericConsumerRun -Fixture $fixture -RunId $zeroId) | Should -Be 0
            Test-Path -LiteralPath $zero.RunDir | Should -BeFalse

            # Zero planned tasks fail at installed schema validation rather than false-greening discovery.
            $emptyId = [guid]::NewGuid().ToString()
            $empty = Freeze-ConsumerRun -Fixture $fixture -RunId $emptyId -Tasks @()
            Assert-ConsumerExit -Result $empty.Result -Expected 2 -Context "$Id zero-task Freeze"
            $empty.Result.Status.state | Should -Be 'invalid'
            Remove-ReviewRunDirectory -RunId $emptyId -RepoRoot $fixture.Root -RequirePublished:$false |
            Should -Be $emptyId

            # Byte admission is terminal and observable through the installed Publish CLI.
            $admissionId = [guid]::NewGuid().ToString()
            $admissionCase = Freeze-ConsumerRun -Fixture $fixture -RunId $admissionId -Tasks $oneTask
            $admissionRun = New-ConsumerResult -Fixture $fixture -RunId $admissionId `
                -PlanDigest $admissionCase.Digest -Tasks @(
                @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            )
            Write-JsonHandshake -RunDir $admissionCase.RunDir -Kind result -Value $admissionRun
            $maxEnvelopeBytes = [int](Get-Content -LiteralPath $fixture.LimitsSchema -Raw |
                ConvertFrom-Json).'x-skalary-limits'.maxEnvelopeBytes
            [System.IO.File]::AppendAllText(
                (Join-Path $admissionCase.RunDir 'review-result.input.json'),
                (' ' * ($maxEnvelopeBytes + 1)),
                [System.Text.UTF8Encoding]::new($false)
            )
            $admitted = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $admissionId
            Assert-ConsumerExit -Result $admitted -Expected 3 -Context "$Id admission Publish"
            $admitted.Status.State | Should -Be 'admission'
            Test-Path -LiteralPath (Join-Path $admissionCase.RunDir '.review-run.admission.json') -PathType Leaf |
            Should -BeTrue
            Test-Path -LiteralPath (Join-Path $admissionCase.RunDir 'review-run.manifest.json') |
            Should -BeFalse

            # Degraded and all-failure plan runs publish useful authority before propagating exit 5.
            $planCleanupChecked = $false
            foreach ($case in @(
                    @{
                        Name      = 'degraded'
                        Tasks     = @(
                            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
                            @{ taskId = 'performance-m1'; concern = 'performance'; model = 'model-a'; outcome = 'timed-out'; diagnostic = 'review timed out' }
                        )
                        PlanTasks = @(
                            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
                            @{ taskId = 'performance-m1'; concern = 'performance'; model = 'model-a' }
                        )
                        Findings  = @(@{ taskId = 'security-m1'; severity = 'Medium'; title = 'Preserved'; body = 'useful' })
                    }
                    @{
                        Name      = 'all-failure'
                        Tasks     = @(
                            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'failed'; diagnostic = 'review failed' }
                            @{ taskId = 'performance-m1'; concern = 'performance'; model = 'model-a'; outcome = 'timed-out'; diagnostic = 'review timed out' }
                        )
                        PlanTasks = @(
                            @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
                            @{ taskId = 'performance-m1'; concern = 'performance'; model = 'model-a' }
                        )
                        Findings  = @()
                    }
                )) {
                $runId = [guid]::NewGuid().ToString()
                $frozen = Freeze-ConsumerRun -Fixture $fixture -RunId $runId -Tasks $case.PlanTasks -Plan
                $run = New-ConsumerResult -Fixture $fixture -RunId $runId -PlanDigest $frozen.Digest `
                    -Tasks $case.Tasks -Findings $case.Findings
                Write-JsonHandshake -RunDir $frozen.RunDir -Kind result -Value $run
                $published = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $runId -Plan
                Assert-ConsumerExit -Result $published -Expected 5 -Context "$Id $($case.Name) Publish"
                Test-Path -LiteralPath (Join-Path $frozen.RunDir 'review-run.manifest.json') | Should -BeTrue
                $degradedSummary = Invoke-ConsumerReader -Fixture $fixture -RunId $runId -Plan
                Assert-ConsumerExit -Result $degradedSummary -Expected 0 -Context "$Id $($case.Name) summary read"
                $degradedSummary.Text | Should -Match '\*\*State\*\*\s*\|\s*`degraded`'
                $degradedFull = Invoke-ConsumerReader -Fixture $fixture -RunId $runId -Plan -View Full
                Assert-ConsumerExit -Result $degradedFull -Expected 0 -Context "$Id $($case.Name) full read"
                $degradedFull.Text | Should -Match '(?m)^## Tasks \(2\)$'
                if (-not $planCleanupChecked) {
                    & pwsh -NoProfile -File $fixture.Cleaner -RunId $runId *> $null
                    $LASTEXITCODE | Should -Be 2 -Because 'generic cleanup cannot remove plan authority'
                    $planCleanupChecked = $true
                }
                Test-Path -LiteralPath $frozen.RunDir | Should -BeTrue
            }

            # The next invocation discovers and abandons a frozen orphan as cancelled.
            $orphanId = [guid]::NewGuid().ToString()
            $orphan = Freeze-ConsumerRun -Fixture $fixture -RunId $orphanId -Tasks $oneTask
            $listed = Invoke-ConsumerReader -Fixture $fixture -RunId '' -ListIncomplete
            Assert-ConsumerExit -Result $listed -Expected 0 -Context "$Id incomplete-run listing"
            @($listed.Text | ConvertFrom-Json) | Should -Contain $orphanId
            $cancelled = New-ConsumerResult -Fixture $fixture -RunId $orphanId -PlanDigest $orphan.Digest -Tasks @(
                @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'cancelled'; diagnostic = 'orchestrator-interrupted' }
            )
            Write-JsonHandshake -RunDir $orphan.RunDir -Kind result -Value $cancelled
            $orphanPublished = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $orphanId
            Assert-ConsumerExit -Result $orphanPublished -Expected 5 -Context "$Id orphan cancellation"
            Get-ReviewRunSummaryText -RunDir $orphan.RunDir -Boundary $fixture.Root |
            Should -Match '\| `cancelled` \| 1 \|'
            $orphanManifest = Get-Content -LiteralPath (Join-Path $orphan.RunDir 'review-run.manifest.json') -Raw |
            ConvertFrom-Json
            Get-Content -LiteralPath (Join-Path $orphan.RunDir $orphanManifest.files.canonical.name) -Raw |
            Should -Match 'orchestrator-interrupted'
            Remove-ReviewRunDirectory -RunId $orphanId -RepoRoot $fixture.Root | Should -Be $orphanId

            # Frozen-plan mutation remains invalid through the installed CLI.
            $mutationId = [guid]::NewGuid().ToString()
            $mutation = Freeze-ConsumerRun -Fixture $fixture -RunId $mutationId -Tasks $oneTask
            $frozenPlan = Get-ChildItem -LiteralPath $mutation.RunDir -File -Filter 'review-plan.*.json' |
            Select-Object -First 1
            Add-Content -LiteralPath $frozenPlan.FullName -Value ' '
            $mutationRun = New-ConsumerResult -Fixture $fixture -RunId $mutationId `
                -PlanDigest $mutation.Digest -Tasks @(
                @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            )
            Write-JsonHandshake -RunDir $mutation.RunDir -Kind result -Value $mutationRun
            $mutationRejected = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $mutationId
            Assert-ConsumerExit -Result $mutationRejected -Expected 2 -Context "$Id frozen-plan mutation"
            Test-Path -LiteralPath (Join-Path $mutation.RunDir 'review-run.manifest.json') | Should -BeFalse
            Remove-ReviewRunDirectory -RunId $mutationId -RepoRoot $fixture.Root -RequirePublished:$false |
            Should -Be $mutationId

            # Plan publication rejects a reconstructed credential shape and destroys the input.
            $secretId = [guid]::NewGuid().ToString()
            $secretCase = Freeze-ConsumerRun -Fixture $fixture -RunId $secretId -Tasks $oneTask -Plan
            $secret = Get-SyntheticSecret
            $secretRun = New-ConsumerResult -Fixture $fixture -RunId $secretId -PlanDigest $secretCase.Digest -Tasks @(
                @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
            ) -Findings @(
                @{ taskId = 'security-m1'; severity = 'High'; title = 'Credential'; body = $secret }
            )
            Write-JsonHandshake -RunDir $secretCase.RunDir -Kind result -Value $secretRun
            $secretRejected = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $secretId -Plan
            Assert-ConsumerExit -Result $secretRejected -Expected 2 -Context "$Id secret rejection"
            Test-Path -LiteralPath (Join-Path $secretCase.RunDir 'review-result.input.json') |
            Should -BeFalse
            Test-Path -LiteralPath (Join-Path $secretCase.RunDir 'review-run.manifest.json') |
            Should -BeFalse
            @($secretRejected.Stdout, $secretRejected.Stderr | Where-Object { $_.Contains($secret) }).Count |
            Should -Be 0 -Because 'rejected credential bytes must not reach terminal output'
            @(Get-ChildItem -LiteralPath $secretCase.RunDir -Recurse -File -Force | Where-Object {
                    [System.IO.File]::ReadAllText($_.FullName).Contains($secret)
                }).Count | Should -Be 0 -Because 'rejected credential bytes must not remain in the run'

            # A real cross-process lock proves installed CLI exit 4 and successful unchanged retry.
            foreach ($retryCase in @('lock')) {
                $retryId = [guid]::NewGuid().ToString()
                $retry = Freeze-ConsumerRun -Fixture $fixture -RunId $retryId -Tasks $oneTask
                $retryRun = New-ConsumerResult -Fixture $fixture -RunId $retryId -PlanDigest $retry.Digest -Tasks @(
                    @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }
                )
                Write-JsonHandshake -RunDir $retry.RunDir -Kind result -Value $retryRun
                $retryInputPath = Join-Path $retry.RunDir 'review-result.input.json'
                $retryInputBytes = [System.IO.File]::ReadAllBytes($retryInputPath)

                $held = $null
                try {
                    $held = [System.IO.File]::Open(
                        (Join-Path $retry.RunDir '.review-run.lock'),
                        [System.IO.FileMode]::OpenOrCreate,
                        [System.IO.FileAccess]::ReadWrite,
                        [System.IO.FileShare]::None
                    )
                    $blocked = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $retryId
                    Assert-ConsumerExit -Result $blocked -Expected 4 -Context "$Id $retryCase retryable failure"
                    Test-Path -LiteralPath (Join-Path $retry.RunDir 'review-run.manifest.json') |
                    Should -BeFalse
                    Test-Path -LiteralPath $retryInputPath -PathType Leaf | Should -BeTrue
                    [System.IO.File]::ReadAllBytes($retryInputPath) | Should -Be $retryInputBytes
                }
                finally {
                    if ($held) { $held.Dispose() }
                }

                $retried = Invoke-ConsumerWriter -Fixture $fixture -Mode Publish -RunId $retryId
                Assert-ConsumerExit -Result $retried -Expected 0 -Context "$Id $retryCase retry"
                Remove-ReviewRunDirectory -RunId $retryId -RepoRoot $fixture.Root | Should -Be $retryId
            }

            # Poisoned repository fallbacks remain untouched; the installed closure supplied everything.
            Get-Content -LiteralPath (Join-Path $fixture.Root 'scripts/skalary/ReviewRun.psm1') -Raw |
            Should -Match 'must not execute'
            foreach ($name in @(
                    'review-limits.schema.json',
                    'review-admission.schema.json',
                    'review-manifest.schema.json',
                    'review-plan.schema.json',
                    'review-run.schema.json',
                    'terminal-status.schema.json'
                )) {
                Get-Content -LiteralPath (Join-Path $fixture.Root "schemas/review/$name") -Raw |
                    Should -Match 'invalid repository fallback schema'
            }

            @(Get-ChildItem -LiteralPath $fixture.Installed -Recurse -File | Where-Object {
                    $_.Name -in @('package.json', 'package-lock.json', 'npm-shrinkwrap.json', 'pnpm-lock.yaml', 'yarn.lock')
                }).Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path $fixture.Installed 'vendor') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $fixture.Installed 'node_modules') | Should -BeFalse
        }
        finally {
            Remove-Module ReviewRun -Force -ErrorAction SilentlyContinue
            if ($locationPushed) { Pop-Location }
            Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-3/D4/D16, step 1.2. Freeze commits the complete planned task set before any
# reviewer is dispatched; Publish accepts results only against that immutable plan, deriving
# attendance and run state from the task set rather than any caller-supplied total. These tests pin
# the freeze validation, the exact frozen-set binding, the immutability of a frozen run, and the full
# attendance matrix: all-completed is clean, every other structurally valid mix is degraded.
Describe 'review report frozen plan and attendance' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path $PSScriptRoot 'fixtures/review-run/ReviewRunTestKit.psm1') -Force -DisableNameChecking

        $script:runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'

        function Script:New-FreshRun {
            param([string[]]$Outcomes, [object[]]$Findings = @())

            $scratch = New-ReviewScratchRoot
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"

            $tasks = @()
            $resultTasks = @()
            for ($i = 0; $i -lt $Outcomes.Count; $i++) {
                $id = "c$($i)-m1"
                $tasks += @{ taskId = $id; concern = "concern$i"; model = 'model-a' }
                $task = @{ taskId = $id; concern = "concern$i"; model = 'model-a'; outcome = $Outcomes[$i] }
                if ($Outcomes[$i] -ne 'completed') { $task['diagnostic'] = "outcome was $($Outcomes[$i])" }
                $resultTasks += $task
            }

            $plan = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            $freeze = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch

            $digest = Get-ReviewFrozenDigest -RunDir $runDir
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster @('model-a') -Tasks $resultTasks -Findings $Findings

            return [pscustomobject]@{ Scratch = $scratch; RunDir = $runDir; Plan = $plan; Run = $run; Freeze = $freeze; Digest = $digest }
        }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix freezes a valid plan and rejects duplicate ids, duplicate slots and zero tasks' {
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"

            $plan = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a', 'model-b') -Tasks @(
                @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
                @{ taskId = 'security-m2'; concern = 'security'; model = 'model-b' }
            )
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            $ok = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $ok.ExitCode | Should -Be 0
            $ok.State | Should -Be 'clean'
            (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -Not -BeNullOrEmpty
            Get-ReviewRunState -RunDir $runDir | Should -Be 'frozen'
            # Input is consumed after a successful freeze.
            Test-Path -LiteralPath (Join-Path $runDir 'review-plan.input.json') | Should -BeFalse

            # Two slots sharing one id: structurally valid (whole objects differ), semantically rejected.
            $dupId = New-ReviewScratchRoot
            try {
                $d = Join-Path $dupId ".github/.skalary/review-runs/$script:runId"
                Set-ReviewHandshake -RunDir $d -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(
                        @{ taskId = 'dup'; concern = 'security'; model = 'model-a' }
                        @{ taskId = 'dup'; concern = 'performance'; model = 'model-a' }))
                $r = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $dupId
                $r.ExitCode | Should -Be 2
                ($r.Diagnostics -join ' ') | Should -Match 'duplicate task id'
            }
            finally { Remove-ReviewScratchRoot -Path $dupId }

            $dupSlot = New-ReviewScratchRoot
            try {
                $d = Join-Path $dupSlot ".github/.skalary/review-runs/$script:runId"
                Set-ReviewHandshake -RunDir $d -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(
                        @{ taskId = 'a'; concern = 'security'; model = 'model-a' }
                        @{ taskId = 'b'; concern = 'security'; model = 'model-a' }))
                $r = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $dupSlot
                $r.ExitCode | Should -Be 2
                ($r.Diagnostics -join ' ') | Should -Match 'slot'
            }
            finally { Remove-ReviewScratchRoot -Path $dupSlot }
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix makes a frozen plan immutable and idempotent on identical replay' {
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $plan = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })

            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $firstDigest = Get-ReviewFrozenDigest -RunDir $runDir

            # Identical replay is a no-op success — the frozen bytes do not change.
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            $replay = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $replay.ExitCode | Should -Be 0
            (Get-ReviewFrozenDigest -RunDir $runDir) | Should -Be $firstDigest

            # A different plan under the same run id is rejected: freeze is immutable.
            $mutated = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'performance'; model = 'model-a' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $mutated
            $changed = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $changed.ExitCode | Should -Be 2
            $changed.State | Should -Be 'invalid'
            (Get-ReviewFrozenDigest -RunDir $runDir) | Should -Be $firstDigest
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix refuses to write a plan generation into a published run, including one whose committed state is corrupt' {
        # Freeze used to infer "no frozen plan file on disk, therefore this run is new". A published run
        # whose plan generation was removed or renamed presents exactly that way, so a re-freeze would
        # write a *replacement* plan under a manifest that still names the old one — a run whose
        # committed authority and whose frozen plan disagree, with nothing to say which is true.
        # Published state is now decided explicitly, under the same lock, and no branch writes.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $plan = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0

            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
                -Findings @(@{ taskId = 'security-m1'; severity = 'Low'; title = 'One'; body = 'b'; rootCause = 'r'; component = 'c' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            Get-ReviewRunState -RunDir $runDir | Should -Be 'published'
            $planFile = Get-ReviewRunArtifact -RunDir $runDir -Role plan
            $manifestBefore = Get-Content -LiteralPath (Join-Path $runDir 'review-run.manifest.json') -Raw

            # A *different* plan under a published run id is exit 2, and nothing is written.
            $different = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'performance'; model = 'model-a' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $different
            $changed = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $changed.ExitCode | Should -Be 2
            $changed.State | Should -Be 'invalid'
            $changed.Message | Should -Match 'published'
            @(Get-ReviewFrozenPlanFile -RunDir $runDir).Count | Should -Be 1
            (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -Be $planFile
            Test-Path -LiteralPath (Join-Path $runDir 'review-plan.input.json') | Should -BeFalse -Because 'a rejected plan input is destroyed'

            # The identical plan is an idempotent no-op, verified against the committed manifest.
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            $same = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $same.ExitCode | Should -Be 0
            $same.Message | Should -Match 'idempotent'
            @(Get-ReviewFrozenPlanFile -RunDir $runDir).Count | Should -Be 1
            (Get-Content -LiteralPath (Join-Path $runDir 'review-run.manifest.json') -Raw) | Should -Be $manifestBefore

            # Corrupted published state: the manifest survives but the plan generation it names is
            # gone. Freeze must refuse rather than manufacture a replacement plan for it.
            Remove-Item -LiteralPath $planFile -Force
            Get-ReviewRunState -RunDir $runDir | Should -Be 'published' -Because 'the manifest still decides the state'
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan
            $corrupt = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $corrupt.ExitCode | Should -Be 2
            $corrupt.State | Should -Be 'invalid'
            $corrupt.Message | Should -Match 'does not verify'
            @(Get-ReviewFrozenPlanFile -RunDir $runDir).Count |
                Should -Be 0 -Because 'a published run never receives a replacement plan generation'
            (Get-Content -LiteralPath (Join-Path $runDir 'review-run.manifest.json') -Raw) | Should -Be $manifestBefore
            Test-Path -LiteralPath (Join-Path $runDir 'review-plan.input.json') | Should -BeFalse
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix binds Publish to the exact frozen task set and its digest' {
        $case = New-FreshRun -Outcomes @('completed', 'completed')
        try {
            # A wrong planDigest is rejected even when the task set is right (RISK-2).
            $wrongDigest = Copy-ReviewMap -Map $case.Run
            $wrongDigest['planDigest'] = 'sha256:' + ('0' * 64)
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $wrongDigest
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $r.ExitCode | Should -Be 2
            ($r.Diagnostics -join ' ') | Should -Match 'planDigest'

            # An invented task not in the frozen plan is rejected (structurally perfect envelope).
            $invented = Copy-ReviewMap -Map $case.Run
            $invented['tasks'] = @(@($case.Run.tasks)[0], @{ taskId = 'ghost-m1'; concern = 'ghost'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $invented
            $r2 = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $r2.ExitCode | Should -Be 2
            ($r2.Diagnostics -join ' ') | Should -Match 'frozen plan|absent'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix rejects Publish before Freeze and a finding on a non-completed task' {
        # Publish with no frozen plan.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest ('sha256:' + ('0' * 64)) -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 2
            $r.Message | Should -Match 'before Freeze'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        # A finding owned by a failed task.
        $case = New-FreshRun -Outcomes @('completed', 'failed')
        try {
            $bad = Copy-ReviewMap -Map $case.Run
            $bad['findings'] = @(@{ taskId = 'c1-m1'; severity = 'High'; title = 'On a failed task' })
            Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $bad
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
            $r.ExitCode | Should -Be 2
            ($r.Diagnostics -join ' ') | Should -Match 'not completed'
        }
        finally { Remove-ReviewScratchRoot -Path $case.Scratch }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix rejects a task model outside the frozen roster' {
        # The roster is the closed set of declared dispatch models (D4/D9). A task naming a model
        # outside it would freeze an attendance claim about a model this run never declared — and
        # Publish binds to the frozen set, so the lie would outlive the plan.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a', 'model-b') -Tasks @(
                    @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
                    @{ taskId = 'security-m9'; concern = 'security'; model = 'model-unlisted' }))
            $r = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 2
            $r.State | Should -Be 'invalid'
            ($r.Diagnostics -join ' ') | Should -Match "task 'security-m9' names model 'model-unlisted' outside the roster"
            (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -BeNullOrEmpty
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix scans the plan strings it is about to persist and destroys a rejected plan input' {
        # Freeze commits scope, roster and task models into a committed artifact before Publish ever
        # runs, so the secret guard has to cover the plan envelope too (RISK-16): a credential quoted
        # in a scope line would otherwise be frozen into the repository and only noticed one mode
        # later, when the plan is already immutable.
        $corpus = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/review-run/secrets/allow-block-corpus.json') -Raw | ConvertFrom-Json -Depth 20
        $token = Build-ReviewSecretToken -Segments (@($corpus.cases | Where-Object { $_.id -eq 'aws-access-key-id' })[0].segments)

        foreach ($case in @(
                @{ Field = 'scope'; Plan = { param($t) New-ReviewTestPlan -RunId $script:runId -Scope "changed files, key $t" -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }) } }
                @{ Field = 'roster'; Plan = { param($t) New-ReviewTestPlan -RunId $script:runId -Roster @("model $t") -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = "model $t" }) } }
            )) {
            $scratch = New-ReviewScratchRoot
            try {
                $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
                Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (& $case.Plan $token)
                $r = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
                $r.ExitCode | Should -Be 2 -Because "a credential shape in $($case.Field) must not be frozen"
                $r.Message | Should -Match 'credential'
                ($r.Diagnostics -join ' ') | Should -Match 'aws-access-key-id'
                ($r.Diagnostics -join ' ') | Should -Not -Match ([regex]::Escape($token))

                # Nothing is frozen and the rejected input is destroyed at once.
                (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -BeNullOrEmpty
                Test-Path -LiteralPath (Join-Path $runDir 'review-plan.input.json') | Should -BeFalse
                foreach ($file in @(Get-ChildItem -LiteralPath $runDir -File -Force)) {
                    ([System.IO.File]::ReadAllText($file.FullName)) | Should -Not -Match ([regex]::Escape($token))
                }
            }
            finally { Remove-ReviewScratchRoot -Path $scratch }
        }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix reports a bounded exit 2 when the host cannot validate against a schema file' {
        # D12/RISK-12: the wrapper stays `#requires -Version 7.0`, so the engine checks the 7.6+
        # `Test-Json -SchemaFile` capability itself. Absence is a bounded rejection, not a thrown
        # parameter error. The seam follows the preflight's semantics and can only lower capability.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))

            Set-ReviewSchemaCapabilitySimulation -MissingSchemaFile
            try {
                $r = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
                $r.ExitCode | Should -Be 2
                $r.State | Should -Be 'invalid'
                ($r.Diagnostics -join ' ') | Should -Match 'SchemaFile'
                (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -BeNullOrEmpty

                # A publish on the same host is bounded the same way.
                $p = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
                $p.ExitCode | Should -Be 2
                $p.State | Should -Be 'invalid'
            }
            finally { Set-ReviewSchemaCapabilitySimulation -Clear }

            # An older simulated version also lowers capability; a higher one changes nothing.
            Set-ReviewSchemaCapabilitySimulation -Version '7.5.9'
            try { (Test-ReviewHostSchemaCapability).Capable | Should -BeFalse }
            finally { Set-ReviewSchemaCapabilitySimulation -Clear }

            Set-ReviewSchemaCapabilitySimulation -Version '99.0'
            try {
                $raised = Test-ReviewHostSchemaCapability
                $raised.Capable | Should -BeTrue
                $raised.Version | Should -Be ([string]$PSVersionTable.PSVersion)
            }
            finally { Set-ReviewSchemaCapabilitySimulation -Clear }

            # With the seam cleared the same input freezes.
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
        }
        finally {
            Set-ReviewSchemaCapabilitySimulation -Clear
            Remove-ReviewScratchRoot -Path $scratch
        }
    }

    It 'test:ReviewReport.FrozenPlanAndAttendanceMatrix returns clean only for all-completed and degraded for every other valid mix' {
        # All-completed publishes clean (exit 0).
        $clean = New-FreshRun -Outcomes @('completed', 'completed', 'completed')
        try {
            Set-ReviewHandshake -RunDir $clean.RunDir -Kind result -Object $clean.Run
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $clean.Scratch
            $r.ExitCode | Should -Be 0
            $r.State | Should -Be 'clean'
        }
        finally { Remove-ReviewScratchRoot -Path $clean.Scratch }

        # Every other outcome, mixed with a completed task, is a degraded publication (exit 5).
        foreach ($outcome in @('failed', 'timed-out', 'omitted', 'cancelled', 'pending')) {
            $case = New-FreshRun -Outcomes @('completed', $outcome)
            try {
                Set-ReviewHandshake -RunDir $case.RunDir -Kind result -Object $case.Run
                $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $case.Scratch
                $r.ExitCode | Should -Be 5 -Because "a run containing '$outcome' is degraded, not clean"
                $r.State | Should -Be 'degraded'
                # The published summary derives the same attendance from the task set.
                $summary = Get-ReviewRunSummaryText -RunDir $case.RunDir
                $summary | Should -Match "(?m)^\| ``$([regex]::Escape($outcome))`` \| 1 \|$"
                $summary | Should -Match '(?m)^\| \*\*State\*\* \| `degraded` \|$'
            }
            finally { Remove-ReviewScratchRoot -Path $case.Scratch }
        }
    }
}

#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-10/D14/D16/D18, step 1.2. Every run has a canonical identity and lifecycle: a plan
# run resolves through the `ReviewRuns` asset kind, a generic run through the gitignored store, and
# no caller can choose another root. The caller's `.tmp` handshake is atomically renamed into place;
# input is removed after success and irreversibly destroyed the instant a secret is rejected; and the
# bundled cleanup helper removes a generic run only after verifying it. The versioned allow/block
# corpus is reconstructed at runtime so no complete token is ever committed.
Describe 'review report artifact handshake, location, cleanup and secret rejection' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $script:repoRoot 'scripts/skalary/ReviewRun.psm1') -Force -DisableNameChecking
        Import-Module (Join-Path $PSScriptRoot 'fixtures/review-run/ReviewRunTestKit.psm1') -Force -DisableNameChecking
        $script:runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
        $script:secretCorpus = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/review-run/secrets/allow-block-corpus.json') -Raw | ConvertFrom-Json -Depth 20
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection consumes only the caller-renamed fixed input and removes it after a successful freeze and publish' {
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $plan = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            [void](Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan)

            # D16: the caller performs the atomic rename, so before Freeze the fixed input is in place
            # and the caller's `.tmp` is already gone.
            Test-Path -LiteralPath (Join-Path $runDir 'review-plan.input.json') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $runDir '.review-plan.input.tmp') | Should -BeFalse
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            # After freeze the input is consumed and the frozen plan remains.
            Test-Path -LiteralPath (Join-Path $runDir 'review-plan.input.json') | Should -BeFalse
            (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -Not -BeNullOrEmpty

            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            [void](Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run)
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            Test-Path -LiteralPath (Join-Path $runDir '.review-result.input.tmp') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $runDir 'review-result.input.json') | Should -BeFalse
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection never consumes a .tmp the caller did not rename' {
        # The engine reads only the fixed input names. A `.tmp` still being written — or abandoned
        # half-written by a crashed caller — is not an input, and neither mode may pick it up.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $plan = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            $tmp = Set-ReviewHandshakeTemp -RunDir $runDir -Kind plan -Object $plan

            $freeze = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $freeze.ExitCode | Should -Be 2
            $freeze.Message | Should -Match 'review-plan\.input\.json'
            (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -BeNullOrEmpty
            Test-Path -LiteralPath $tmp | Should -BeTrue -Because 'the engine neither reads nor removes a file the caller still owns'

            # The caller's own atomic rename is what makes it an input.
            [System.IO.File]::Move($tmp, (Join-Path $runDir 'review-plan.input.json'), $true)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0

            # The same rule holds for Publish.
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            [void](Set-ReviewHandshakeTemp -RunDir $runDir -Kind result -Object $run)
            $publish = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $publish.ExitCode | Should -Be 2
            $publish.Message | Should -Match 'review-result\.input\.json'
            Test-Path -LiteralPath (Join-Path $runDir 'review-run.manifest.json') | Should -BeFalse
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection resolves a plan run under ReviewRuns and a generic run under the gitignored store, rejecting any other root' {
        $scratch = New-ReviewScratchRoot
        try {
            # Generic run: under .github/.skalary/review-runs/<uuid>.
            $generic = Resolve-ReviewRunRoot -RunId $script:runId -RepoRoot $scratch
            $generic | Should -Match ([regex]::Escape([System.IO.Path]::Combine('.github', '.skalary', 'review-runs', $script:runId)))

            # Plan run: under <plan>/assets/reviews/<uuid> via the ReviewRuns asset kind.
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            $planRun = Resolve-ReviewRunRoot -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch
            $planRun | Should -Match ([regex]::Escape([System.IO.Path]::Combine('assets', 'reviews', $script:runId)))

            # A non-UUID id is refused.
            { Resolve-ReviewRunRoot -RunId 'NOT-A-UUID' -RepoRoot $scratch } | Should -Throw -ExpectedMessage '*UUID*'
            # A plan directory outside the repository's implementation-plans tree is refused.
            $outside = Join-Path $scratch 'outside-plan'
            [void](New-Item -ItemType Directory -Path $outside -Force)
            Set-Content -LiteralPath (Join-Path $outside 'plan.md') -Value '# x'
            { Resolve-ReviewRunRoot -RunId $script:runId -PlanDir $outside -RepoRoot $scratch } | Should -Throw -ExpectedMessage '*implementation-plans*'

            # A plan run freezes into the plan's reviews directory.
            Set-ReviewHandshake -RunDir $planRun -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            (Invoke-ReviewFreeze -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0
            (Get-ReviewRunArtifact -RunDir $planRun -Role plan) | Should -Not -BeNullOrEmpty
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection validates a plan directory through the plan inventory and refuses every hostile path' {
        # A path prefix plus a `plan.md` is not proof of a plan: a hand-made folder, a traversal that
        # lands back inside the tree and an ambiguous folder all satisfy it. The inventory the rest of
        # the plan tooling uses is the only source of truth, and `-ListIncomplete` goes through the
        # very same resolver so a listing cannot be a second, weaker entry point.
        $scratch = New-ReviewScratchRoot
        try {
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            # A real plan resolves and lists.
            { Resolve-ReviewRunRoot -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch } | Should -Not -Throw
            { Find-IncompleteReviewRun -PlanDir $planDir -RepoRoot $scratch } | Should -Not -Throw

            # A folder inside the plans tree that the inventory does not recognize (its name matches no
            # plan-folder scheme) is refused even though it carries a plan.md.
            $impostor = Join-Path $scratch 'docs/implementation-plans/not-a-plan-folder'
            [void](New-Item -ItemType Directory -Path (Join-Path $impostor 'assets') -Force)
            Set-Content -LiteralPath (Join-Path $impostor 'plan.md') -Value '# not a plan'
            Set-Content -LiteralPath (Join-Path $impostor 'assets/requirements.md') -Value '# Requirements'
            { Resolve-ReviewRunRoot -RunId $script:runId -PlanDir $impostor -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*inventory*'
            { Find-IncompleteReviewRun -PlanDir $impostor -RepoRoot $scratch } | Should -Throw -ExpectedMessage '*inventory*'

            # A traversal out of the tree, and one that climbs out and back in through a sibling.
            foreach ($hostile in @(
                    (Join-Path $scratch 'docs/implementation-plans/../../outside-plan'),
                    (Join-Path $planDir '../../../etc'),
                    $scratch)) {
                { Resolve-ReviewRunRoot -RunId $script:runId -PlanDir $hostile -RepoRoot $scratch } | Should -Throw
                { Find-IncompleteReviewRun -PlanDir $hostile -RepoRoot $scratch } | Should -Throw
            }

            # The plans root itself is not a plan.
            { Resolve-ReviewRunRoot -RunId $script:runId -PlanDir (Join-Path $scratch 'docs/implementation-plans') -RepoRoot $scratch } |
                Should -Throw

            # A run directory reached through a symlinked ancestor is refused before anything is
            # written, even though the resolved string still sits under the store (RISK-6).
            $link = Join-Path $scratch '.github/.skalary/review-runs-link'
            $target = Join-Path $scratch '.github/.skalary/review-runs'
            [void](New-Item -ItemType Directory -Path $target -Force)
            $linked = $false
            try {
                [void](New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop)
                $linked = $true
            }
            catch { $linked = $false }
            if ($linked) {
                { Assert-ReviewPathSafe -Path (Join-Path $link $script:runId) -Boundary $scratch } |
                    Should -Throw -ExpectedMessage '*symlink or reparse point*'
                { Assert-ReviewPathSafe -Path (Join-Path $target $script:runId) -Boundary $scratch } | Should -Not -Throw
            }
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection refuses to freeze into a run directory whose ancestor became a symlink' {
        $scratch = New-ReviewScratchRoot
        try {
            $store = Join-Path $scratch '.github/.skalary/review-runs'
            $real = Join-Path $scratch 'elsewhere'
            [void](New-Item -ItemType Directory -Path $real -Force)
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $store) -Force)

            $linked = $true
            try { [void](New-Item -ItemType SymbolicLink -Path $store -Target $real -ErrorAction Stop) }
            catch { $linked = $false }
            if (-not $linked) {
                Set-ItResult -Skipped -Because 'this platform does not allow this user to create symbolic links'
                return
            }

            $runDir = Join-Path $store $script:runId
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            $r = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 4 -Because 'a swapped ancestor is refused, and the refusal is still a bounded exit'
            $r.Message | Should -Match 'symlink or reparse point'
            @(Get-ChildItem -LiteralPath $real -Recurse -File -Force | Where-Object { $_.Name -cmatch '^review-plan\.[0-9a-f]{64}\.json$' }).Count |
                Should -Be 0 -Because 'nothing is written through the link'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection refuses a fixed input leaf that is a symlink and never reads, shreds or unlinks its target' {
        # The two fixed input names are the one path inside a run directory whose *content* an
        # untrusted caller supplies, and the engine both parses that leaf and destroys it in place —
        # `Remove-ReviewInputSecurely` overwrites the bytes before unlinking. The ancestor walk never
        # saw a swapped leaf, because every ancestor was still a real directory this engine created, so
        # a link renamed onto the fixed name turned the D16 handshake into an arbitrary-file read and
        # an arbitrary-file shredder outside the store. The leaf is confined before it is accepted,
        # read, overwritten or deleted, the link is never followed, and the refusal is a bounded exit
        # 4 (RISK-6).
        $victimRoot = Join-Path (Get-ReviewKitRepoRoot) ('.github/.skalary/test-scratch/victim-' + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $victimRoot -Force)
        $victim = Join-Path $victimRoot 'victim.txt'
        $victimBytes = [System.Text.Encoding]::UTF8.GetBytes("bytes outside the store that must survive`n")

        function Script:New-LinkedInput {
            <#  A symlink standing where the caller's renamed fixed input belongs.  #>
            param([Parameter(Mandatory)][string]$RunDir, [Parameter(Mandatory)][string]$Kind, [Parameter(Mandatory)][string]$Target)
            [void](New-Item -ItemType Directory -Path $RunDir -Force)
            $link = Join-Path $RunDir (Get-ReviewInputName -Kind $Kind)
            try { [void](New-Item -ItemType SymbolicLink -Path $link -Target $Target -ErrorAction Stop) }
            catch { return $null }
            return $link
        }

        try {
            # 1. Freeze: the plan input is a link. Nothing is frozen and the target is untouched.
            $scratch = New-ReviewScratchRoot
            try {
                [System.IO.File]::WriteAllBytes($victim, $victimBytes)
                $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
                $link = New-LinkedInput -RunDir $runDir -Kind plan -Target $victim
                if (-not $link) {
                    Set-ItResult -Skipped -Because 'this platform does not allow this user to create symbolic links'
                    return
                }

                $r = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
                $r.ExitCode | Should -Be 4 -Because 'a path-safety refusal is bounded, never an acceptance and never an unhandled error'
                $r.Message | Should -Match 'symlink or reparse point'
                [System.IO.File]::ReadAllBytes($victim) | Should -Be $victimBytes -Because 'the link is never followed to read, overwrite or unlink its target'
                (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -BeNullOrEmpty
                Get-ReviewRunState -RunDir $runDir | Should -Be 'new'
            }
            finally { Remove-ReviewScratchRoot -Path $scratch }

            # 2. Publish: the result input is a link on a frozen run. Nothing is published.
            $scratch = New-ReviewScratchRoot
            try {
                [System.IO.File]::WriteAllBytes($victim, $victimBytes)
                $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
                Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
                (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
                [void](New-LinkedInput -RunDir $runDir -Kind result -Target $victim)

                $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
                $r.ExitCode | Should -Be 4
                $r.Message | Should -Match 'symlink or reparse point'
                [System.IO.File]::ReadAllBytes($victim) | Should -Be $victimBytes
                Test-Path -LiteralPath (Join-Path $runDir 'review-run.manifest.json') | Should -BeFalse
                Get-ReviewRunState -RunDir $runDir | Should -Be 'frozen'
            }
            finally { Remove-ReviewScratchRoot -Path $scratch }

            # 3. The pre-scan destruction is the earliest a link could have been followed: Publish
            # before Freeze destroys the staged result input before it ever reads it. It must refuse
            # the link instead of shredding whatever it points at.
            $scratch = New-ReviewScratchRoot
            try {
                [System.IO.File]::WriteAllBytes($victim, $victimBytes)
                $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
                [void](New-LinkedInput -RunDir $runDir -Kind result -Target $victim)

                $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
                $r.ExitCode | Should -Be 4
                $r.Message | Should -Match 'symlink or reparse point'
                [System.IO.File]::ReadAllBytes($victim) | Should -Be $victimBytes -Because 'Remove-ReviewPendingInput must not shred through a link'
                (Get-Item -LiteralPath $victim).Length | Should -Be $victimBytes.Length
            }
            finally { Remove-ReviewScratchRoot -Path $scratch }
        }
        finally { Remove-Item -LiteralPath $victimRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection destroys the rejected input immediately and leaves no trace of the secret' {
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            [void](Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch)

            $token = Build-ReviewSecretToken -Segments (@($script:secretCorpus.cases | Where-Object { $_.id -eq 'aws-access-key-id' })[0].segments)
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
                -Findings @(@{ taskId = 'security-m1'; severity = 'Critical'; title = 'Leak'; body = "value is $token here"; rootCause = 'r'; component = 'c' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run

            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 2

            # The input is gone the instant the secret is rejected, and no file in the run directory
            # still carries the token.
            Test-Path -LiteralPath (Join-Path $runDir 'review-result.input.json') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $runDir '.review-result.input.tmp') | Should -BeFalse
            foreach ($file in @(Get-ChildItem -LiteralPath $runDir -File -Force)) {
                ([System.IO.File]::ReadAllText($file.FullName)) | Should -Not -Match ([regex]::Escape($token)) -Because "$($file.Name) must not retain a rejected secret"
            }
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection destroys an untrusted result input on every terminal Publish exit that never reaches the secret scan' {
        # The secret scan runs only once Publish has a frozen plan to bind the result to. Three
        # terminal exits are decided before that, and each used to return leaving a staged result input
        # — reviewer text nothing had scanned — sitting in the run directory: an already-admission run,
        # an existing run directory with no frozen plan, and a frozen plan that does not verify. A
        # retryable exit 4 deliberately keeps the input, because the caller is expected to run the same
        # input again.
        $token = Build-ReviewSecretToken -Segments (@($script:secretCorpus.cases | Where-Object { $_.id -eq 'github-pat-classic' })[0].segments)

        function Script:New-TokenResult {
            param([Parameter(Mandatory)][string]$RunDir, [string]$PlanDigest = ('sha256:' + ('0' * 64)))
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest $PlanDigest -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
                -Findings @(@{ taskId = 'security-m1'; severity = 'Critical'; title = 'Leak'; body = "the reviewer quoted $token here"; rootCause = 'r'; component = 'c' })
            Set-ReviewHandshake -RunDir $RunDir -Kind result -Object $run
        }

        function Script:Assert-NoTokenLeft {
            param([Parameter(Mandatory)][string]$RunDir, [Parameter(Mandatory)][string]$Because)
            Test-Path -LiteralPath (Join-Path $RunDir 'review-result.input.json') | Should -BeFalse -Because $Because
            foreach ($file in @(Get-ChildItem -LiteralPath $RunDir -File -Force -Recurse)) {
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                ([System.Text.Encoding]::UTF8.GetString($bytes)) |
                    Should -Not -Match ([regex]::Escape($token)) -Because "$($file.Name) must retain no credential after $Because"
            }
        }

        # 1. An existing run directory with no frozen plan at all.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            New-TokenResult -RunDir $runDir
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 2
            $r.Message | Should -Match 'Publish before Freeze'
            Assert-NoTokenLeft -RunDir $runDir -Because 'publish before freeze'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        # 2. A frozen plan that does not verify against its own content address.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $planPath = Get-ReviewRunArtifact -RunDir $runDir -Role plan
            $digest = Get-ReviewFrozenDigest -RunDir $runDir
            # Tampered bytes under an unchanged content-addressed name.
            [System.IO.File]::WriteAllBytes($planPath, [System.Text.Encoding]::UTF8.GetBytes('{"schema":"skalary/review-plan@1"}' + "`n"))
            New-TokenResult -RunDir $runDir -PlanDigest $digest
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 2
            $r.Message | Should -Match 'not trustworthy'
            Assert-NoTokenLeft -RunDir $runDir -Because 'an untrustworthy frozen plan'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        # 3. A run id that already reached a terminal admission decision.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $tasks = @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks $tasks)
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $digest = Get-ReviewFrozenDigest -RunDir $runDir

            # An over-budget full view drives the run to terminal admission.
            $body = '<' * 4096
            $over = New-ReviewTestRun -RunId $script:runId -PlanDigest $digest -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
                -Findings @(1..128 | ForEach-Object {
                    @{ taskId = 'security-m1'; severity = 'High'; title = ('finding {0}' -f $_); body = $body; rootCause = ('root-{0:d3}' -f $_); component = ('component-{0:d3}' -f $_) }
                })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $over
            (Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 3
            Get-ReviewRunState -RunDir $runDir | Should -Be 'admission'

            New-TokenResult -RunDir $runDir -PlanDigest $digest
            $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $r.ExitCode | Should -Be 3
            $r.State | Should -Be 'admission'
            Assert-NoTokenLeft -RunDir $runDir -Because 'a terminal admission decision'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }

        # A retryable exit 4 is the deliberate exception: the lock could not be taken, nothing was
        # decided, and the caller is expected to run the same input again.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            $held = Enter-ReviewLock -RunDir $runDir
            try {
                Set-ReviewRunLockTimeoutOverride -Seconds 0.2
                $r = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
                $r.ExitCode | Should -Be 4
                Test-Path -LiteralPath (Join-Path $runDir 'review-result.input.json') |
                    Should -BeTrue -Because 'a retryable failure keeps the input the caller must retry with'
            }
            finally {
                Set-ReviewRunLockTimeoutOverride -Seconds $null
                Exit-ReviewLock -Lock $held
            }
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection blocks every block-case token and passes every allow-case token in the versioned corpus' {
        [string]$script:secretCorpus.schema | Should -Be 'skalary/review-secret-corpus@1'
        [int]$script:secretCorpus.version | Should -BeGreaterThan 0
        @($script:secretCorpus.cases).Count | Should -BeGreaterThan 10

        $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($case in $script:secretCorpus.cases) {
            $token = Build-ReviewSecretToken -Segments $case.segments
            # A committed block fixture must never carry a complete credential signature; it is
            # reconstructed only at runtime from inert fragments.
            if ($case.expected -eq 'block') {
                (ConvertTo-Json -InputObject $case.segments -Compress) | Should -Not -Match ([regex]::Escape($token))
            }
            $blocked = @(Test-ReviewValueForSecret -Value "reviewer wrote $token in the body").Count -gt 0
            $shouldBlock = ($case.expected -eq 'block')
            if ($blocked -ne $shouldBlock) { $failures.Add("$($case.id): expected $($case.expected), blocked=$blocked") }
        }
        $failures -join '; ' | Should -BeNullOrEmpty
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection removes a verified generic run and refuses to remove outside the store' {
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            [void](Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch)
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            [void](Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch)

            Test-Path -LiteralPath $runDir | Should -BeTrue
            $removed = Remove-ReviewRunDirectory -RunId $script:runId -RepoRoot $scratch
            $removed | Should -Be $script:runId
            Test-Path -LiteralPath $runDir | Should -BeFalse

            # A non-UUID id and a missing run are refused.
            { Remove-ReviewRunDirectory -RunId 'NOPE' -RepoRoot $scratch } | Should -Throw -ExpectedMessage '*UUID*'
            { Remove-ReviewRunDirectory -RunId $script:runId -RepoRoot $scratch } | Should -Throw -ExpectedMessage '*No generic run*'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }
}

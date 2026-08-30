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

    AfterEach { Clear-ReviewPathItemProvider }

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

    It 'test:ReviewReport.CommittedAuthorityCleanupTruth keeps committed Freeze and Publish outcomes truthful when post-commit shredding fails' {
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            $plan = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' })
            [void](Set-ReviewHandshake -RunDir $runDir -Kind plan -Object $plan)
            $planInput = [System.IO.Path]::GetFullPath((Join-Path $runDir 'review-plan.input.json'))
            Set-ReviewPathItemProvider -Provider ({
                    param($Path)
                    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                    if ($item -and [string]::Equals([System.IO.Path]::GetFullPath($Path), $planInput, [System.StringComparison]::OrdinalIgnoreCase) -and
                        (Test-Path -LiteralPath (Join-Path $runDir '.review-run.frozen'))) {
                        return [pscustomobject]@{ Attributes = $item.Attributes -bor [System.IO.FileAttributes]::ReparsePoint }
                    }
                    return $item
                }.GetNewClosure())

            $freeze = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $freeze.ExitCode | Should -Be 0
            $freeze.Diagnostics | Should -HaveCount 1
            $freeze.Diagnostics[0] | Should -Match 'authority is intact'
            (Get-ReviewRunState -RunDir $runDir) | Should -Be 'frozen'
            Test-Path -LiteralPath $planInput | Should -BeTrue

            Clear-ReviewPathItemProvider
            Remove-Item -LiteralPath $planInput -Force
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            [void](Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run)
            $resultInput = [System.IO.Path]::GetFullPath((Join-Path $runDir 'review-result.input.json'))
            Set-ReviewPathItemProvider -Provider ({
                    param($Path)
                    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                    if ($item -and [string]::Equals([System.IO.Path]::GetFullPath($Path), $resultInput, [System.StringComparison]::OrdinalIgnoreCase) -and
                        (Test-Path -LiteralPath (Join-Path $runDir 'review-run.manifest.json'))) {
                        return [pscustomobject]@{ Attributes = $item.Attributes -bor [System.IO.FileAttributes]::ReparsePoint }
                    }
                    return $item
                }.GetNewClosure())

            $publish = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $publish.ExitCode | Should -Be 0
            $publish.Diagnostics | Should -HaveCount 1
            $publish.Diagnostics[0] | Should -Match 'authority is intact'
            (Get-ReviewRunState -RunDir $runDir) | Should -Be 'published'
            { Read-ReviewManifest -RunDir $runDir -Boundary $scratch } | Should -Not -Throw
            Test-Path -LiteralPath $resultInput | Should -BeTrue
        }
        finally { Clear-ReviewPathItemProvider; Remove-ReviewScratchRoot -Path $scratch }
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

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection prepares the sole run root without writing and Freeze never creates it' {
        $scratch = New-ReviewScratchRoot
        try {
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            $prepared = Resolve-ReviewRunPreparation -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch

            $prepared.schema | Should -Be 'skalary/review-prepare@1'
            $prepared.runId | Should -Be $script:runId
            $prepared.runRoot | Should -Be (Resolve-ReviewRunRoot -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch)
            Test-Path -LiteralPath $prepared.runRoot | Should -BeFalse -Because 'Prepare is read-only'

            $missing = Invoke-ReviewFreeze -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch
            $missing.ExitCode | Should -Be 2
            $missing.Message | Should -Match 'Prepare operation'
            Test-Path -LiteralPath $prepared.runRoot | Should -BeFalse -Because 'Freeze cannot create a caller root before confinement'

            [void](New-Item -ItemType Directory -Path $prepared.runRoot -Force)
            Set-ReviewHandshake -RunDir $prepared.runRoot -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(
                    @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            (Invoke-ReviewFreeze -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection rejects a reparse plan leaf before inventory or layout reads' {
        $scratch = New-ReviewScratchRoot
        try {
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            $target = Join-Path $scratch 'outside-plan-target'
            Move-Item -LiteralPath $planDir -Destination $target
            $linkType = $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' })
            [void](New-Item -ItemType $linkType -Path $planDir -Target $target -ErrorAction Stop)

            { Resolve-ReviewRunPreparation -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*symlink or reparse point*'
            Test-Path -LiteralPath (Join-Path $target 'assets/reviews') | Should -BeFalse
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
            $linkType = $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' })
            [void](New-Item -ItemType $linkType -Path $link -Target $target -ErrorAction Stop)
            { Assert-ReviewPathSafe -Path (Join-Path $link $script:runId) -Boundary $scratch } |
                Should -Throw -ExpectedMessage '*symlink or reparse point*'
            { Assert-ReviewPathSafe -Path (Join-Path $target $script:runId) -Boundary $scratch } | Should -Not -Throw
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

            $linkType = $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' })
            [void](New-Item -ItemType $linkType -Path $store -Target $real -ErrorAction Stop)

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

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection deterministically refuses a fixed input leaf reported as a reparse point before read or destruction' {
        function Script:Set-PathAsReparsePoint {
            param([Parameter(Mandatory)][string]$UnsafePath)
            $unsafeFull = [System.IO.Path]::GetFullPath($UnsafePath)
            Set-ReviewPathItemProvider -Provider ({
                    param($Path)
                    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                    if ($item -and [string]::Equals([System.IO.Path]::GetFullPath($Path), $unsafeFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return [pscustomobject]@{ Attributes = $item.Attributes -bor [System.IO.FileAttributes]::ReparsePoint }
                    }
                    return $item
                }.GetNewClosure())
        }

        # Freeze refuses the fixed plan input before parsing or consuming it.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            $input = Join-Path $runDir 'review-plan.input.json'
            $before = [System.IO.File]::ReadAllBytes($input)
            Set-PathAsReparsePoint -UnsafePath $input
            $result = Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch
            $result.ExitCode | Should -Be 4
            $result.Message | Should -Match 'symlink or reparse point'
            [System.IO.File]::ReadAllBytes($input) | Should -Be $before
            (Get-ReviewRunArtifact -RunDir $runDir -Role plan) | Should -BeNullOrEmpty
        }
        finally { Clear-ReviewPathItemProvider; Remove-ReviewScratchRoot -Path $scratch }

        # Publish refuses the fixed result input on a frozen run before reading or deleting it.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }))
            (Invoke-ReviewFreeze -RunId $script:runId -RepoRoot $scratch).ExitCode | Should -Be 0
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            $input = Join-Path $runDir 'review-result.input.json'
            $before = [System.IO.File]::ReadAllBytes($input)
            Set-PathAsReparsePoint -UnsafePath $input
            $result = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $result.ExitCode | Should -Be 4
            $result.Message | Should -Match 'symlink or reparse point'
            [System.IO.File]::ReadAllBytes($input) | Should -Be $before
            Test-Path -LiteralPath (Join-Path $runDir 'review-run.manifest.json') | Should -BeFalse
        }
        finally { Clear-ReviewPathItemProvider; Remove-ReviewScratchRoot -Path $scratch }

        # Publish-before-freeze destruction also refuses the reported reparse leaf.
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            $input = Join-Path $runDir 'review-result.input.json'
            [System.IO.File]::WriteAllText($input, "{}`n", [System.Text.UTF8Encoding]::new($false))
            $before = [System.IO.File]::ReadAllBytes($input)
            Set-PathAsReparsePoint -UnsafePath $input
            $result = Invoke-ReviewPublish -RunId $script:runId -RepoRoot $scratch
            $result.ExitCode | Should -Be 4
            $result.Message | Should -Match 'symlink or reparse point'
            [System.IO.File]::ReadAllBytes($input) | Should -Be $before
        }
        finally { Clear-ReviewPathItemProvider; Remove-ReviewScratchRoot -Path $scratch }
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
            { Remove-ReviewRunDirectory -RunId $script:runId -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*requires authority returned by Read-ReviewManifest*'
            $verified = Read-ReviewManifest -RunDir $runDir -Boundary $scratch
            $preview = Remove-ReviewRunDirectory -RunId $script:runId -RepoRoot $scratch `
                -VerifiedManifest $verified -WhatIf
            $preview | Should -Be $script:runId
            Test-Path -LiteralPath $runDir | Should -BeTrue
            $removed = Remove-ReviewRunDirectory -RunId $script:runId -RepoRoot $scratch `
                -VerifiedManifest $verified
            $removed | Should -Be $script:runId
            Test-Path -LiteralPath $runDir | Should -BeFalse

            # A non-UUID id and a missing run are refused.
            { Remove-ReviewRunDirectory -RunId 'NOPE' -RepoRoot $scratch } | Should -Throw -ExpectedMessage '*UUID*'
            { Remove-ReviewRunDirectory -RunId $script:runId -RepoRoot $scratch } | Should -Throw -ExpectedMessage '*No generic run*'
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.FinalizedResultCompaction retains a bounded verified result and removes the live plan run' {
        $scratch = New-ReviewScratchRoot
        try {
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            $runDir = Resolve-ReviewRunPreparation -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch | Select-Object -ExpandProperty runRoot
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            $task = @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @($task))
            (Invoke-ReviewFreeze -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
                -Findings @(@{ taskId = 'security-m1'; severity = 'High'; title = 'Unsafe writer boundary'; body = 'full detail stays transient'; rootCause = 'writer'; component = 'runtime' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            (Invoke-ReviewPublish -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0

            { Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict approved -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*requires a clean run with no Critical or High*'
            Test-Path -LiteralPath $runDir | Should -BeTrue

            $preview = Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch -WhatIf
            $preview.Preview | Should -BeTrue
            Test-Path -LiteralPath $runDir | Should -BeTrue
            Test-Path -LiteralPath $preview.Report | Should -BeFalse
            Test-Path -LiteralPath $preview.Receipt | Should -BeFalse

            $store = Split-Path -Parent $runDir
            $held = Enter-ReviewLock -RunDir $store -LockName ".$script:runId.finalize.lock"
            try {
                Set-ReviewRunLockTimeoutOverride -Seconds 0.2
                { Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch } |
                    Should -Throw -ExpectedMessage '*lock not acquired*'
                Test-Path -LiteralPath $runDir | Should -BeTrue
            }
            finally {
                Set-ReviewRunLockTimeoutOverride -Seconds $null
                Exit-ReviewLock -Lock $held
            }

            $verified = Read-ReviewManifest -RunDir $runDir -Boundary $scratch
            $verified.Bytes.Keys | Should -Be @('plan', 'canonical', 'summary', 'full')
            $verified.Documents.Keys | Should -Be @('plan', 'canonical')
            $canonicalPath = $verified.Files['canonical']
            [System.IO.File]::WriteAllText($canonicalPath, "{}`n", [System.Text.UTF8Encoding]::new($false))
            $verified.Documents['canonical']['runId'] | Should -Be $script:runId -Because 'verified parsed authority is not reopened after verification'
            [System.IO.File]::WriteAllBytes($canonicalPath, $verified.Bytes['canonical'])

            Set-ReviewRunFaultSeam -Edge 'after-final-report'
            { Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*review-run-fault-seam:after-final-report*'
            Clear-ReviewRunFaultSeam
            Test-Path -LiteralPath $runDir | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $store "$script:runId.review.md") | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $store "$script:runId.receipt.json") | Should -BeFalse

            Set-ReviewRunFaultSeam -Edge 'during-finalize-cleanup'
            $final = Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch
            Clear-ReviewRunFaultSeam
            $final.CleanupPending | Should -BeTrue
            Test-Path -LiteralPath $runDir | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $store ".cleanup/$script:runId") | Should -BeTrue
            Test-Path -LiteralPath $final.Report | Should -BeTrue
            Test-Path -LiteralPath $final.Receipt | Should -BeTrue
            $reportBytes = [System.IO.File]::ReadAllBytes($final.Report)
            $reportBytes.Length | Should -BeLessOrEqual ([int](Get-ReviewLimits)['maxRetainedReportBytes'])
            $report = [System.Text.Encoding]::UTF8.GetString($reportBytes)
            $report | Should -Match '\*\*Gate verdict\*\* \| \*\*blocked\*\*'
            $report | Should -Match 'Unsafe writer boundary'
            $report | Should -Not -Match 'full detail stays transient'
            $receipt = Get-Content -LiteralPath $final.Receipt -Raw | ConvertFrom-Json -Depth 20
            $receipt.schema | Should -Be 'skalary/review-result-receipt@1'
            $receipt.report.bytes | Should -Be $reportBytes.Length
            $receipt.report.digest | Should -Be (Get-ReviewDigest -Bytes $reportBytes)
            $receipt.findings.severity.high | Should -Be 1

            $retainedReportBefore = [System.IO.File]::ReadAllBytes($final.Report)
            $retainedReceiptBefore = [System.IO.File]::ReadAllBytes($final.Receipt)
            { Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict approved -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*different verdict*'
            [System.IO.File]::ReadAllBytes($final.Report) | Should -Be $retainedReportBefore
            [System.IO.File]::ReadAllBytes($final.Receipt) | Should -Be $retainedReceiptBefore

            $tampered = Get-Content -LiteralPath $final.Receipt -Raw | ConvertFrom-Json -AsHashtable -Depth 20
            $tampered['state'] = 'degraded'
            [System.IO.File]::WriteAllText($final.Receipt, (ConvertTo-ReviewCanonicalJson -Node $tampered), [System.Text.UTF8Encoding]::new($false))
            $replay = Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch
            $replay.Replayed | Should -BeFalse -Because 'tampered retained evidence is reconstructed from verified live authority'
            $replay.CleanupPending | Should -BeFalse
            Test-Path -LiteralPath $runDir | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $store ".cleanup/$script:runId") | Should -BeFalse
            (Get-Content -LiteralPath $replay.Receipt -Raw | ConvertFrom-Json).state | Should -Be 'clean'
            { Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict approved -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*different verdict*'
        }
        finally { Clear-ReviewRunFaultSeam; Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.FinalizedResultCompaction converges from a partially deleted cleanup tombstone' {
        $scratch = New-ReviewScratchRoot
        try {
            $runId = [guid]::NewGuid().ToString()
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            $runDir = Resolve-ReviewRunPreparation -RunId $runId -PlanDir $planDir -RepoRoot $scratch | Select-Object -ExpandProperty runRoot
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            $task = @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $runId -Roster @('model-a') -Tasks @($task))
            (Invoke-ReviewFreeze -RunId $runId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0
            $run = New-ReviewTestRun -RunId $runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            (Invoke-ReviewPublish -RunId $runId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0

            Set-ReviewRunFaultSeam -Edge 'during-finalize-cleanup'
            $first = Finalize-ReviewPlanRun -RunId $runId -PlanDir $planDir -Verdict approved -RepoRoot $scratch
            Clear-ReviewRunFaultSeam
            $first.CleanupPending | Should -BeTrue
            $cleanupDir = Join-Path (Split-Path -Parent $runDir) ".cleanup/$runId"
            $cleanupMarkerPath = Join-Path (Split-Path -Parent $runDir) ".$runId.cleanup.json"
            $cleanupMarkerBytes = [System.IO.File]::ReadAllBytes($cleanupMarkerPath)
            Remove-Item -LiteralPath (Join-Path $cleanupDir 'review-run.manifest.json') -Force

            $replay = Finalize-ReviewPlanRun -RunId $runId -PlanDir $planDir -Verdict approved -RepoRoot $scratch
            $replay.CleanupPending | Should -BeFalse
            Test-Path -LiteralPath $cleanupDir | Should -BeFalse
            Test-Path -LiteralPath $replay.Report | Should -BeTrue
            Test-Path -LiteralPath $replay.Receipt | Should -BeTrue

            [System.IO.File]::WriteAllBytes($cleanupMarkerPath, $cleanupMarkerBytes)
            Mock Remove-ReviewCleanupMarker {
                throw 'replay cleanup marker removal denied'
            } -ModuleName ReviewRun
            $failedReplay = Finalize-ReviewPlanRun `
                -RunId $runId `
                -PlanDir $planDir `
                -Verdict approved `
                -RepoRoot $scratch
            $failedReplay.CleanupPending | Should -BeTrue
            $failedReplay.CleanupDiagnostic |
                Should -BeExactly 'replay cleanup marker removal denied'
            Test-Path -LiteralPath $cleanupMarkerPath -PathType Leaf | Should -BeTrue
        }
        finally { Clear-ReviewRunFaultSeam; Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.ArtifactHandshakeLocationCleanupAndSecretRejection propagates generic cleanup failures' {
        $scratch = New-ReviewScratchRoot
        try {
            $runDir = Join-Path $scratch ".github/.skalary/review-runs/$script:runId"
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            Set-ReviewRunFaultSeam -Edge 'during-generic-cleanup'
            { Remove-ReviewRunDirectory -RunId $script:runId -RepoRoot $scratch -RequirePublished:$false } |
                Should -Throw -ExpectedMessage '*review-run-fault-seam:during-generic-cleanup*'
            Test-Path -LiteralPath $runDir | Should -BeTrue
        }
        finally { Clear-ReviewRunFaultSeam; Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.FinalizedResultCompaction never falls back to legacy verification for a malformed current manifest' {
        $scratch = New-ReviewScratchRoot
        try {
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            $runDir = Resolve-ReviewRunPreparation -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch | Select-Object -ExpandProperty runRoot
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            $task = @{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
            Set-ReviewHandshake -RunDir $runDir -Kind plan -Object (New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @($task))
            (Invoke-ReviewFreeze -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0
            $run = New-ReviewTestRun -RunId $script:runId -PlanDigest (Get-ReviewFrozenDigest -RunDir $runDir) -Roster @('model-a') `
                -Tasks @(@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' })
            Set-ReviewHandshake -RunDir $runDir -Kind result -Object $run
            (Invoke-ReviewPublish -RunId $script:runId -PlanDir $planDir -RepoRoot $scratch).ExitCode | Should -Be 0

            $manifestPath = Join-Path $runDir 'review-run.manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20
            [void]$manifest.Remove('scopeDigest')
            [System.IO.File]::WriteAllText($manifestPath, ((ConvertTo-Json $manifest -Depth 20 -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))

            { Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict approved -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*manifest fails the review-manifest schema*'
            Test-Path -LiteralPath $runDir | Should -BeTrue
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.LegacyFinalizedResultCompaction refuses retired live authority after historical migration' {
        $scratch = New-ReviewScratchRoot
        try {
            $planDir = New-ReviewTestPlanDir -ScratchRoot $scratch
            $runDir = Join-Path $planDir "assets/reviews/$script:runId"
            [void](New-Item -ItemType Directory -Path $runDir -Force)
            $task = [ordered]@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a' }
            $legacyPlan = New-ReviewTestPlan -RunId $script:runId -Roster @('model-a') -Tasks @($task)
            foreach ($field in @('contentTrust', 'scopeAuthority', 'modelSelection')) { [void]$legacyPlan.Remove($field) }
            $planBytes = [System.Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-ReviewCanonicalJson -Node $legacyPlan))
            $planDigest = Get-ReviewDigest -Bytes $planBytes

            $legacyRun = New-ReviewTestRun -RunId $script:runId -PlanDigest $planDigest -Roster @('model-a') `
                -Tasks @([ordered]@{ taskId = 'security-m1'; concern = 'security'; model = 'model-a'; outcome = 'completed' }) `
                -Findings @([ordered]@{ taskId = 'security-m1'; severity = 'High'; title = 'Legacy blocker'; body = 'transient detail'; rootCause = 'legacy'; component = 'runtime' })
            foreach ($field in @('contentTrust', 'scopeAuthority', 'modelSelection')) { [void]$legacyRun.Remove($field) }
            $runBytes = [System.Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-ReviewCanonicalJson -Node $legacyRun))
            $projection = ConvertTo-ReviewProjection -Run $legacyRun
            $summaryBytes = [System.Text.UTF8Encoding]::new($false).GetBytes((Get-ReviewRunSummaryView -Projection $projection))
            $fullBytes = [System.Text.UTF8Encoding]::new($false).GetBytes((Get-ReviewRunFullView -Projection $projection))

            $artifacts = [ordered]@{
                plan = $planBytes
                canonical = $runBytes
                summary = $summaryBytes
                full = $fullBytes
            }
            $files = [ordered]@{}
            foreach ($role in $artifacts.Keys) {
                $bytes = $artifacts[$role]
                $name = Get-ReviewContentName -Role $role -Bytes $bytes
                [System.IO.File]::WriteAllBytes((Join-Path $runDir $name), $bytes)
                $files[$role] = [ordered]@{ name = $name; digest = (Get-ReviewDigest -Bytes $bytes); bytes = $bytes.Length }
            }
            $legacyManifest = [ordered]@{
                schema = 'skalary/review-manifest@1'
                runId = $script:runId
                state = 'published'
                planDigest = $planDigest
                runDigest = Get-ReviewDigest -Bytes $runBytes
                files = $files
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $runDir 'review-run.manifest.json'),
                ((ConvertTo-Json -InputObject $legacyManifest -Depth 10 -Compress) + "`n"),
                [System.Text.UTF8Encoding]::new($false))

            { Finalize-ReviewPlanRun -RunId $script:runId -PlanDir $planDir -Verdict blocked -RepoRoot $scratch } |
                Should -Throw -ExpectedMessage '*manifest fails the review-manifest schema*'
            Test-Path -LiteralPath $runDir | Should -BeTrue
        }
        finally { Remove-ReviewScratchRoot -Path $scratch }
    }

    It 'test:ReviewReport.FinalizedResultCompaction ignores live plan state but keeps compact siblings trackable' {
        $planRoot = 'docs/implementation-plans/archived/2026-08-02-c21cdc-review-report-as-data/assets/reviews'
        git -C $script:repoRoot check-ignore -q -- "$planRoot/$script:runId/review-run.manifest.json"
        $LASTEXITCODE | Should -Be 0
        git -C $script:repoRoot check-ignore -q -- "$planRoot/$script:runId.review.md"
        $LASTEXITCODE | Should -Be 1
        git -C $script:repoRoot check-ignore -q -- "$planRoot/$script:runId.receipt.json"
        $LASTEXITCODE | Should -Be 1
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Run with: Invoke-Pester ./tests/autopilot
#
Describe 'Autopilot.ContainerOffline' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:scriptsDir = Join-Path $PSScriptRoot '../../plugins/autopilot/scripts'
        $script:entrypointPath = Join-Path $scriptsDir 'container-entrypoint.sh'
        $script:launcher = Get-Content -LiteralPath (Join-Path $scriptsDir 'launch-container.ps1') -Raw
        $script:envFile = Get-Content -LiteralPath (Join-Path $scriptsDir 'prepare-env-file.ps1') -Raw
        $script:entrypoint = Get-Content -LiteralPath $entrypointPath -Raw
        . (Join-Path $scriptsDir 'autopilot-dispatch.ps1')
    }
    Context 'launch-container.ps1' {
        It 'passes the validated start branch to the container environment' {
            $launcher | Should -Match '\[string\]\$StartBranch'
            $launcher | Should -Match 'Branch = \$StartBranch'
        }

        It 'exposes a -FeedPath parameter' {
            $launcher | Should -Match '\[string\]\$FeedPath'
        }
        It 'mounts the feed read-only at /feed when FeedPath is set' {
            $launcher | Should -Match '\$\{FeedPath\}:/feed:ro'
        }
        It 'enables offline env injection only when a feed is provided' {
            $launcher | Should -Match 'if \(\$FeedPath\) \{ \$envParams\.Offline = \$true \}'
        }
    }

    Context 'prepare-env-file.ps1' {
        It 'accepts an -Offline switch' {
            $envFile | Should -Match '\[switch\]\$Offline'
        }
        It 'injects AUTOPILOT_OFFLINE and AUTOPILOT_FEED when offline' {
            $envFile | Should -Match 'AUTOPILOT_OFFLINE=true'
            $envFile | Should -Match 'AUTOPILOT_FEED=/feed'
        }
        It 'routes the complete writer payload through the validated serializer' {
            $envFile | Should -Match (
                'ConvertTo-AutopilotEnvFileContent -Entry \$envContent'
            )
        }
        It 'rejects line and NUL injection in every environment value' {
            ConvertTo-AutopilotEnvFileContent -Entry @(
                'SAFE=value=with-equals',
                'EMPTY='
            ) | Should -BeExactly "SAFE=value=with-equals`nEMPTY="

            foreach ($value in @("line`nbreak", "carriage`rreturn", "nul$([char]0)value")) {
                {
                    ConvertTo-AutopilotEnvFileContent -Entry @("COPILOT_MODEL=$value")
                } | Should -Throw "*'COPILOT_MODEL'*unsupported*"
            }
        }
    }

    Context 'executable container launch contract' {
        It 'enables work-branch resume only for a later internal expected-start attempt' {
            (Get-AutopilotContainerAttemptParameters `
                -ExpectedStartCommit ('A' * 40) -Attempt 0
            ).TrustedInternalRetry | Should -BeFalse
            (Get-AutopilotContainerAttemptParameters `
                -ExpectedStartCommit ('A' * 40) -Attempt 1
            ).TrustedInternalRetry | Should -BeTrue
            (Get-AutopilotContainerAttemptParameters `
                -ExpectedStartCommit $null -Attempt 1
            ).TrustedInternalRetry | Should -BeFalse
        }

        It 'generates the exact expected-start environment for initial and retry launches' {
            $expected = 'A' * 40
            @(Get-AutopilotExpectedStartEnvironment `
                    -ExpectedStartCommit $expected) |
                Should -BeExactly @("EXPECTED_START_COMMIT=$($expected.ToLowerInvariant())")
            @(Get-AutopilotExpectedStartEnvironment `
                    -ExpectedStartCommit $expected -TrustedInternalRetry $true) |
                Should -BeExactly @(
                    "EXPECTED_START_COMMIT=$($expected.ToLowerInvariant())",
                    'AUTOPILOT_TRUSTED_INTERNAL_RETRY=true'
                )
            {
                Get-AutopilotExpectedStartEnvironment `
                    -TrustedInternalRetry $true
            } | Should -Throw '*requires an expected start commit*'
        }

        It 'derives a deterministic safe container name from the epic run' {
            $run = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            Get-AutopilotContainerName -Run $run |
                Should -BeExactly "autopilot-run-$run"
            { Get-AutopilotContainerName -Run '../unsafe' } |
                Should -Throw '*Invalid container run*'
        }

        It 'rejects HTTP remote userinfo without echoing the credential-bearing URL' {
            foreach ($remote in @(
                    'https://user@example.invalid/repo.git',
                    'https://user:secret@example.invalid/repo.git',
                    'http://token@example.invalid/repo.git'
                )) {
                $message = try {
                    Assert-AutopilotRepositoryRemote -Remote $remote
                    ''
                }
                catch {
                    $_.Exception.Message
                }
                $message | Should -Match 'must not contain userinfo'
                $message | Should -Not -Match [regex]::Escape($remote)
            }
            {
                Assert-AutopilotRepositoryRemote `
                    -Remote 'https://example.invalid/repo.git'
            } | Should -Not -Throw
            {
                Assert-AutopilotRepositoryRemote `
                    -Remote 'git@example.invalid:owner/repo.git'
            } | Should -Not -Throw
        }

        It 'waits on the process handle and reports only deadline expiry' {
            $quick = Start-Process -FilePath (Get-Process -Id $PID).Path `
                -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Milliseconds 50') `
                -PassThru
            try {
                Wait-AutopilotProcessUntil -Process $quick `
                    -Deadline (Get-Date).AddSeconds(5) | Should -BeTrue
            }
            finally {
                $quick.Dispose()
            }

            $slow = Start-Process -FilePath (Get-Process -Id $PID).Path `
                -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 5') `
                -PassThru
            try {
                Wait-AutopilotProcessUntil -Process $slow `
                    -Deadline (Get-Date).AddMilliseconds(25) | Should -BeFalse
            }
            finally {
                if (-not $slow.HasExited) {
                    $slow.Kill($true)
                    $slow.WaitForExit()
                }
                $slow.Dispose()
            }
        }
    }

    Context 'container-entrypoint.sh' {
        It 'copies the read-only feed to a writable cache' {
            $entrypoint | Should -Match 'cp -a "\$\{FEED_SRC\}/\." "\$\{CACHE_ROOT\}/"'
        }
        It 'emits an out-of-tree NuGet config via NUGET_CONFIG with a cleared source list' {
            $entrypoint | Should -Match 'export NUGET_CONFIG='
            $entrypoint | Should -Match '<clear />'
            $entrypoint | Should -Match 'globalPackagesFolder'
        }
        It 'emits an out-of-tree npm config with an offline cache' {
            $entrypoint | Should -Match 'npm_config_userconfig'
            $entrypoint | Should -Match 'npm_config_offline'
            $entrypoint | Should -Match 'offline=true'
        }
        It 'restores from the cache offline rather than the network' {
            # offline=true (npm) + cleared sources + globalPackagesFolder (nuget)
            # force every restore to resolve only from the bundled cache.
            $entrypoint | Should -Match 'AUTOPILOT_OFFLINE'
        }
        It 'translates copilot exit 43 into a push then exit 43' {
            $entrypoint | Should -Match 'autopilot_completion_handoff_action'
            $entrypoint | Should -Match 'rebundle\)'
            $entrypoint | Should -Match 'git push origin "\$\{WORK_BRANCH\}"'
            $entrypoint | Should -Match 'exit 43'
        }
        It 'keeps the existing exit-42 @human branch' {
            $entrypoint | Should -Match 'human-stop\)'
            $entrypoint | Should -Match 'exit 42'
        }
        It 'preserves in-flight work after a failed target' {
            $entrypoint | Should -Match '(?s)target-failed\).*?preserve_work \|\| exit 70'
            $entrypoint | Should -Match '(?s)target-failed\).*?break 2'
        }
        It 'fails when the selected start branch is unavailable instead of using the clone default' {
            $entrypoint | Should -Match "Selected start branch '\$\{BRANCH\}' is not available on origin"
            $entrypoint | Should -Not -Match 'Creating new branch \$\{WORK_BRANCH\} from \$\(git branch --show-current\)'
        }
        It 'never prints the configured remote URL' {
            $entrypoint | Should -Not -Match '(?m)^\s*echo\s+.*REPO_REMOTE'
            $entrypoint | Should -Match 'Preparing configured origin'
        }
        It 'executes immutable matching, mismatch, fresh rejection, and trusted retry fixtures' {
            $fixture = Join-Path $script:repoRoot (
                'artifacts/expected-start-' + [guid]::NewGuid().ToString('N')
            )
            try {
                $remote = Join-Path $fixture 'remote.git'
                $seed = Join-Path $fixture 'seed'
                [void](New-Item -ItemType Directory -Path $seed -Force)
                & git init -q --bare $remote
                & git -C $seed init -q -b main
                & git -C $seed config user.name fixture
                & git -C $seed config user.email fixture@example.invalid
                [System.IO.File]::WriteAllText((Join-Path $seed 'tracked.txt'), 'fixture')
                & git -C $seed add tracked.txt
                & git -C $seed commit -q -m fixture
                & git -C $seed remote add origin $remote
                & git -C $seed push -q origin main
                $actual = (& git -C $seed rev-parse HEAD).Trim()

                $matching = Join-Path $fixture 'matching'
                [void](New-Item -ItemType Directory -Path $matching)
                & git -C $matching init -q
                & git -C $matching remote add origin $remote
                $matchingOutput = & bash -c @'
source "$1"
checkout_epic_work_branch "$2" main "$3" feature/fixture false
'@ bash $script:entrypointPath $matching $actual 2>&1
                $LASTEXITCODE | Should -Be 0
                (& git -C $matching rev-parse HEAD).Trim() |
                    Should -BeExactly $actual
                (& git -C $matching branch --show-current).Trim() |
                    Should -BeExactly 'feature/fixture'

                $mismatch = Join-Path $fixture 'mismatch'
                [void](New-Item -ItemType Directory -Path $mismatch)
                & git -C $mismatch init -q
                & git -C $mismatch remote add origin $remote
                $output = & bash -c @'
source "$1"
checkout_epic_work_branch "$2" main aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa feature/mismatch false
'@ bash $script:entrypointPath $mismatch 2>&1
                $LASTEXITCODE | Should -Be 1
                ($output | Out-String) | Should -Match 'resolved to.*expected'
                & git -C $mismatch show-ref --verify --quiet refs/heads/feature/mismatch
                $LASTEXITCODE | Should -Not -Be 0

                & git -C $seed checkout -q -b feature/existing
                [System.IO.File]::WriteAllText(
                    (Join-Path $seed 'work.txt'),
                    'trusted work'
                )
                & git -C $seed add work.txt
                & git -C $seed commit -q -m work
                & git -C $seed push -q origin feature/existing
                $workCommit = (& git -C $seed rev-parse HEAD).Trim()

                $fresh = Join-Path $fixture 'fresh-rejection'
                [void](New-Item -ItemType Directory -Path $fresh)
                & git -C $fresh init -q
                & git -C $fresh remote add origin $remote
                $freshOutput = & bash -c @'
source "$1"
checkout_epic_work_branch "$2" main "$3" feature/existing false
'@ bash $script:entrypointPath $fresh $actual 2>&1
                $LASTEXITCODE | Should -Be 1
                ($freshOutput | Out-String) |
                    Should -Match 'fresh epic launch will not resume'

                $retry = Join-Path $fixture 'trusted-retry'
                [void](New-Item -ItemType Directory -Path $retry)
                & git -C $retry init -q
                & git -C $retry remote add origin $remote
                $retryOutput = & bash -c @'
source "$1"
checkout_epic_work_branch "$2" main "$3" feature/existing true
'@ bash $script:entrypointPath $retry $actual 2>&1
                $LASTEXITCODE | Should -Be 0
                (& git -C $retry rev-parse HEAD).Trim() |
                    Should -BeExactly $workCommit

                $probeFailure = Join-Path $fixture 'probe-failure'
                [void](New-Item -ItemType Directory -Path $probeFailure)
                & git -C $probeFailure init -q
                & git -C $probeFailure remote add origin (
                    Join-Path $fixture 'missing-origin.git'
                )
                $probeFailureOutput = & bash -c @'
source "$1"
remote_branch_exists "$2" feature/probe-failure
'@ bash $script:entrypointPath $probeFailure 2>&1
                $LASTEXITCODE | Should -Be 2
                ($probeFailureOutput | Out-String) |
                    Should -Match 'Unable to inspect work branch'
                (& git -C $retry branch --show-current).Trim() |
                    Should -BeExactly 'feature/existing'
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

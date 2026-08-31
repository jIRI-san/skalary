Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Run with: Invoke-Pester ./tests/autopilot
#
# Static-content assertions over the container offline path. The launcher and
# entrypoint shell out to docker/git, so this fixture verifies the wiring
# (feed mount, offline env, out-of-tree config, exit-43 handling) by reading
# the scripts rather than executing a container.

Describe 'Autopilot.ContainerOffline' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:scriptsDir = Join-Path $PSScriptRoot '../../plugins/autopilot/scripts'
        $script:entrypointPath = Join-Path $scriptsDir 'container-entrypoint.sh'
        $script:launch = Get-Content -LiteralPath (Join-Path $scriptsDir 'launch.ps1') -Raw
        $script:launcher = Get-Content -LiteralPath (Join-Path $scriptsDir 'launch-container.ps1') -Raw
        $script:envFile = Get-Content -LiteralPath (Join-Path $scriptsDir 'prepare-env-file.ps1') -Raw
        $script:entrypoint = Get-Content -LiteralPath $entrypointPath -Raw
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
        It 'passes the optional expected start commit to environment preparation' {
            $launch | Should -Match '\[string\]\$ExpectedStartCommit'
            $launch | Should -Match '\$dispatchParams\.ExpectedStartCommit'
            $launcher | Should -Match '\[string\]\$ExpectedStartCommit'
            $launcher | Should -Match '\$envParams\.ExpectedStartCommit'
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
        It 'validates and injects EXPECTED_START_COMMIT only when supplied' {
            $envFile | Should -Match 'Invalid expected start commit'
            $envFile | Should -Match 'EXPECTED_START_COMMIT='
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
        It 'fails when the selected start branch is unavailable instead of using the clone default' {
            $entrypoint | Should -Match "Selected start branch '\$\{BRANCH\}' is not available on origin"
            $entrypoint | Should -Not -Match 'Creating new branch \$\{WORK_BRANCH\} from \$\(git branch --show-current\)'
        }
        It 'rejects a fetched start-branch mismatch before creating a work branch' {
            $fixture = Join-Path $script:repoRoot (
                'artifacts/expected-start-' + [guid]::NewGuid().ToString('N')
            )
            try {
                [void](New-Item -ItemType Directory -Path $fixture -Force)
                & git -C $fixture init -q -b main
                & git -C $fixture config user.name fixture
                & git -C $fixture config user.email fixture@example.invalid
                [System.IO.File]::WriteAllText((Join-Path $fixture 'tracked.txt'), 'fixture')
                & git -C $fixture add tracked.txt
                & git -C $fixture commit -q -m fixture
                $actual = (& git -C $fixture rev-parse HEAD).Trim()
                & git -C $fixture update-ref refs/remotes/origin/main $actual

                $output = & bash -c @'
source "$1"
verify_expected_start_commit "$2" main aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
'@ bash $script:entrypointPath $fixture 2>&1

                $LASTEXITCODE | Should -Be 1
                ($output | Out-String) | Should -Match 'resolved to.*expected'
                & git -C $fixture show-ref --verify --quiet refs/heads/feature/fixture
                $LASTEXITCODE | Should -Not -Be 0
                $entrypoint.IndexOf('verify_expected_start_commit /work') |
                    Should -BeLessThan $entrypoint.IndexOf('git checkout -b "${WORK_BRANCH}"')

                $invalidOutput = & bash -c @'
source "$1"
verify_expected_start_commit "$2" main not-a-commit
'@ bash $script:entrypointPath $fixture 2>&1
                $LASTEXITCODE | Should -Be 2
                ($invalidOutput | Out-String) | Should -Match 'must be a full lowercase Git commit id'
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

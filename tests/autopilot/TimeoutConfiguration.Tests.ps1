Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Autopilot timeout configuration' {
    BeforeAll {
        $script:pluginRoot = Join-Path $PSScriptRoot '../../plugins/autopilot'
        $script:example = Get-Content -LiteralPath (Join-Path $pluginRoot '.autopilot.json.example') -Raw | ConvertFrom-Json
        $script:schema = Get-Content -LiteralPath (Join-Path $pluginRoot 'schemas/autopilot.schema.json') -Raw | ConvertFrom-Json
        $script:launcher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch.ps1') -Raw
        $script:containerLauncher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch-container.ps1') -Raw
        $script:hostLauncher = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/launch-host.ps1') -Raw
        $script:entrypoint = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/container-entrypoint.sh') -Raw
        $script:envPrep = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/prepare-env-file.ps1') -Raw
        $script:agent = Get-Content -LiteralPath (Join-Path $pluginRoot 'agents/autopilot.agent.md') -Raw
    }

    It 'documents timeout as per phase and planTimeout as the whole run' {
        $schema.properties.timeout.description | Should -Match 'per phase'
        $schema.properties.planTimeout.description | Should -Match 'whole-run'
        # planTimeout stays optional so existing configs keep working.
        $schema.required | Should -Not -Contain 'planTimeout'
    }

    It 'ships an example whose whole-run cap exceeds a single phase budget' {
        $example.timeout | Should -BeGreaterThan 0
        $example.planTimeout | Should -BeGreaterThan $example.timeout
    }

    It 'rejects a planTimeout below the per-phase timeout' {
        $launcher | Should -Match 'planTimeout \(\$planTimeoutMinutes m\) is below the per-phase timeout'
    }

    It 'defaults planTimeout to 1440 when absent' {
        $launcher | Should -Match '\$planTimeoutMinutes = 1440'
        $containerLauncher | Should -Match "contains 'planTimeout'.*else \{ 1440 \}"
    }

    It 'uses planTimeout, not the per-phase timeout, as the container whole-run deadline' {
        # Regression guard: the container previously used $Config.timeout here, which
        # silently turned a documented per-phase budget into a whole-run one.
        $containerLauncher | Should -Not -Match '\$TimeoutMinutes = \$Config\.timeout'
        $containerLauncher | Should -Match '\$TimeoutMinutes = if \(\$Config\.PSObject\.Properties\.Name -contains ''planTimeout''\)'
    }

    It 'keeps host mode enforcing the per-phase budget around each invocation' {
        $hostLauncher | Should -Match '\$deadline = \(Get-Date\)\.AddMinutes\(\$TimeoutMin\)'
    }

    It 'passes the per-phase budget into the container' {
        $envPrep | Should -Match 'AUTOPILOT_PHASE_TIMEOUT_MIN=\$\(\$Config\.timeout\)'
        $entrypoint | Should -Match 'PHASE_TIMEOUT_MIN="\$\{AUTOPILOT_PHASE_TIMEOUT_MIN:-0\}"'
    }

    It 'enforces the per-phase budget inside the container and exits 124 on breach' {
        $entrypoint | Should -Match 'exceeded per-phase timeout'
        $entrypoint | Should -Match 'exit 124'
    }
}

Describe 'Autopilot work preservation' {
    BeforeAll {
        $script:pluginRoot = Join-Path $PSScriptRoot '../../plugins/autopilot'
        $script:entrypoint = Get-Content -LiteralPath (Join-Path $pluginRoot 'scripts/container-entrypoint.sh') -Raw
        $script:agent = Get-Content -LiteralPath (Join-Path $pluginRoot 'agents/autopilot.agent.md') -Raw
    }

    It 'traps termination signals so a whole-run kill does not discard commits' {
        $entrypoint | Should -Match 'trap on_terminate TERM INT'
        $entrypoint | Should -Match 'preserve_work'
        $entrypoint | Should -Match 'exit 143'
    }

    It 'backgrounds the copilot call so the trap can actually fire' {
        # Bash defers traps while a foreground child runs, so a backgrounded PID plus
        # wait is what makes the handler reachable at all.
        $entrypoint | Should -Match 'COPILOT_PID=\$!'
        $entrypoint | Should -Match 'wait "\$\{COPILOT_PID\}"'
    }

    It 'pushes after every step, not only at phase end' {
        $agent | Should -Match '(?m)^21\. \*\*Push\*\* — `git push origin <current-branch>` immediately after the step commit'
    }

    It 'still forbids force-push everywhere' {
        $agent | Should -Match 'never force-push'
        $entrypoint | Should -Not -Match 'push --force'
    }
}

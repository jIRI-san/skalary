Set-StrictMode -Version Latest

Describe 'Autopilot.RebundleLoop' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..' '..' 'plugins' 'autopilot' 'scripts' 'autopilot-dispatch.ps1')
    }

    Context 'Resolve-OfflinePackagesConfig' {
        It 'defaults to disabled when offlinePackages is absent' {
            $cfg = [pscustomobject]@{ timeout = 30 }
            $r = Resolve-OfflinePackagesConfig -Config $cfg
            $r.Enabled | Should -BeFalse
            $r.MaxRebundles | Should -Be 3
        }

        It 'treats a null offlinePackages as disabled' {
            $cfg = [pscustomobject]@{ offlinePackages = $null }
            (Resolve-OfflinePackagesConfig -Config $cfg).Enabled | Should -BeFalse
        }

        It 'is disabled when enabled is false even if maxRebundles is set' {
            $cfg = [pscustomobject]@{ offlinePackages = [pscustomobject]@{ enabled = $false; maxRebundles = 9 } }
            (Resolve-OfflinePackagesConfig -Config $cfg).Enabled | Should -BeFalse
        }

        It 'defaults maxRebundles to 3 when enabled without maxRebundles' {
            $cfg = [pscustomobject]@{ offlinePackages = [pscustomobject]@{ enabled = $true } }
            $r = Resolve-OfflinePackagesConfig -Config $cfg
            $r.Enabled | Should -BeTrue
            $r.MaxRebundles | Should -Be 3
        }

        It 'honors an explicit maxRebundles' {
            $cfg = [pscustomobject]@{ offlinePackages = [pscustomobject]@{ enabled = $true; maxRebundles = 5 } }
            (Resolve-OfflinePackagesConfig -Config $cfg).MaxRebundles | Should -Be 5
        }

        It 'captures valid ecosystems' {
            $cfg = [pscustomobject]@{ offlinePackages = [pscustomobject]@{ enabled = $true; ecosystems = @('dotnet', 'npm') } }
            (Resolve-OfflinePackagesConfig -Config $cfg).Ecosystems | Should -Be @('dotnet', 'npm')
        }

        It 'throws when offlinePackages is present but enabled is missing' {
            $cfg = [pscustomobject]@{ offlinePackages = [pscustomobject]@{ maxRebundles = 3 } }
            { Resolve-OfflinePackagesConfig -Config $cfg } | Should -Throw
        }

        It 'throws when enabled is not a boolean' {
            $cfg = [pscustomobject]@{ offlinePackages = [pscustomobject]@{ enabled = 'yes' } }
            { Resolve-OfflinePackagesConfig -Config $cfg } | Should -Throw
        }

        It 'throws when maxRebundles is below 1' {
            $cfg = [pscustomobject]@{ offlinePackages = [pscustomobject]@{ enabled = $true; maxRebundles = 0 } }
            { Resolve-OfflinePackagesConfig -Config $cfg } | Should -Throw
        }

        It 'throws on an unknown ecosystem' {
            $cfg = [pscustomobject]@{ offlinePackages = [pscustomobject]@{ enabled = $true; ecosystems = @('maven') } }
            { Resolve-OfflinePackagesConfig -Config $cfg } | Should -Throw
        }
    }

    Context 'Invoke-AutopilotDispatch' {
        It 'runs once and skips the rebundle loop when offline is disabled (host mode)' {
            $state = @{ launch = 0; prep = 0; rebundle = 0; feeds = @(); codes = @(43) }
            $launch = {
                param([string]$FeedPath)
                $state.feeds += , $FeedPath
                $code = $state.codes[$state.launch]
                $state.launch = $state.launch + 1
                return $code
            }.GetNewClosure()
            $prep = { $state.prep = $state.prep + 1; 'feed-initial' }.GetNewClosure()
            $rebundle = { $state.rebundle = $state.rebundle + 1; "feed-rebundle-$($state.rebundle)" }.GetNewClosure()

            $result = Invoke-AutopilotDispatch -Launch $launch -PrepareFeed $prep -Rebundle $rebundle -MaxRebundles 3 -Offline:$false

            $result | Should -Be 43
            $state.launch | Should -Be 1
            $state.prep | Should -Be 0
            $state.rebundle | Should -Be 0
        }

        It 'preps the feed and returns immediately on a clean exit' {
            $state = @{ launch = 0; prep = 0; rebundle = 0; feeds = @(); codes = @(0) }
            $launch = {
                param([string]$FeedPath)
                $state.feeds += , $FeedPath
                $code = $state.codes[$state.launch]
                $state.launch = $state.launch + 1
                return $code
            }.GetNewClosure()
            $prep = { $state.prep = $state.prep + 1; 'feed-initial' }.GetNewClosure()
            $rebundle = { $state.rebundle = $state.rebundle + 1; "feed-rebundle-$($state.rebundle)" }.GetNewClosure()

            $result = Invoke-AutopilotDispatch -Launch $launch -PrepareFeed $prep -Rebundle $rebundle -MaxRebundles 3 -Offline:$true

            $result | Should -Be 0
            $state.prep | Should -Be 1
            $state.rebundle | Should -Be 0
            $state.feeds[0] | Should -Be 'feed-initial'
        }

        It 're-preps and relaunches on exit 43, then returns the resumed code' {
            $state = @{ launch = 0; prep = 0; rebundle = 0; feeds = @(); attempts = @(); codes = @(43, 0) }
            $launch = {
                param([string]$FeedPath, [int]$Attempt)
                $state.feeds += , $FeedPath
                $state.attempts += $Attempt
                $code = $state.codes[$state.launch]
                $state.launch = $state.launch + 1
                return $code
            }.GetNewClosure()
            $prep = { $state.prep = $state.prep + 1; 'feed-initial' }.GetNewClosure()
            $rebundle = { $state.rebundle = $state.rebundle + 1; "feed-rebundle-$($state.rebundle)" }.GetNewClosure()

            $result = Invoke-AutopilotDispatch -Launch $launch -PrepareFeed $prep -Rebundle $rebundle -MaxRebundles 3 -Offline:$true

            $result | Should -Be 0
            $state.launch | Should -Be 2
            $state.rebundle | Should -Be 1
            $state.feeds[0] | Should -Be 'feed-initial'
            $state.feeds[1] | Should -Be 'feed-rebundle-1'
            $state.attempts | Should -BeExactly @(0, 1)
        }

        It 'enforces the maxRebundles cap and returns 43 when never satisfied' {
            $state = @{ launch = 0; prep = 0; rebundle = 0; feeds = @(); codes = @(43, 43, 43, 43) }
            $launch = {
                param([string]$FeedPath)
                $state.feeds += , $FeedPath
                $code = $state.codes[$state.launch]
                $state.launch = $state.launch + 1
                return $code
            }.GetNewClosure()
            $prep = { $state.prep = $state.prep + 1; 'feed-initial' }.GetNewClosure()
            $rebundle = { $state.rebundle = $state.rebundle + 1; "feed-rebundle-$($state.rebundle)" }.GetNewClosure()

            $result = Invoke-AutopilotDispatch -Launch $launch -PrepareFeed $prep -Rebundle $rebundle -MaxRebundles 2 -Offline:$true -WarningAction SilentlyContinue

            $result | Should -Be 43
            $state.launch | Should -Be 3
            $state.rebundle | Should -Be 2
        }
    }
}

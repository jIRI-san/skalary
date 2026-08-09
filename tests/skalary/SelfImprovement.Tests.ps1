#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan b0c0d3 REQ-14 / RISK-10: /si reads model- and operator-authored free text and proposes edits
# to the SKILL.md and agent files that govern every later run. An injected directive that survives
# harvest stops being someone else's text and becomes this repo's own rule, so the wrapping contract
# and the never-execute rule are asserted structurally rather than trusted to prose review.
Describe 'Self-improvement harvest contract' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

        # Source of truth and installed copy: a rule that exists only in plugins/ never reaches a
        # consumer, and one that exists only in .github/ is not shipped by the plugin.
        $script:guidePaths = @(
            'plugins/self-improvement/skills/si/assets/harvest-guide.md',
            '.github/skills/si/assets/harvest-guide.md'
        )
        $script:skillPaths = @(
            'plugins/self-improvement/skills/si/SKILL.md',
            '.github/skills/si/SKILL.md'
        )

        function Script:Get-SiText {
            param([Parameter(Mandatory)][string]$RelativePath)
            $full = Join-Path $script:repoRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                throw "Missing self-improvement payload file '$RelativePath'."
            }
            return Get-Content -LiteralPath $full -Raw -Encoding utf8
        }
    }

    Context 'test:si-wraps-harvested-sources' {
        It 'test:si-wraps-harvested-sources enumerates every harvested source in the guide' {
            foreach ($path in $script:guidePaths) {
                $text = Get-SiText -RelativePath $path

                # Each source is named by path, not by description: a harvest that resolves the wrong
                # location returns nothing and looks like "no lessons this time".
                $text | Should -Match 'docs/review-ledger/' -Because "$path must name the ledger source"
                $text | Should -Match 'learnings\.md' -Because "$path must name the plan learnings log"
                $text | Should -Match 'cr-log\.md' -Because "$path must name the plan cr-log"
                $text | Should -Match 'docs/feedback/queue\.md' -Because "$path must name the feedback queue"

                # Plan logs live at assets/logs/ or the legacy plan root; hard-coding either loses half
                # the corpus silently.
                $text | Should -Match 'Resolve-PlanAssetPath' -Because "$path must resolve plan logs by layout"

                # A queued question nobody answered is an absence of feedback, not a verdict.
                $text | Should -Match '(?i)pending' -Because "$path must exclude unanswered feedback"

                # queue.md is created lazily on first write, so the first run always meets an absent
                # source; leaving that undefined turns it into a silently empty harvest.
                $text | Should -Match '(?i)absent.{0,40}source file is an empty source' -Because "$path must define the absent-file case"
                $text | Should -Match '(?i)missing its expected section header' -Because "$path must keep a headerless present file fail-loud"
            }
        }

        It 'test:si-wraps-harvested-sources wraps every source in UNTRUSTED_INPUT markers' {
            foreach ($path in $script:guidePaths) {
                $text = Get-SiText -RelativePath $path

                # Same marker syntax as every cr/dr reviewer: a second syntax is a second thing to
                # get wrong, and the reviewers already enforce this one.
                $text | Should -Match '<<<UNTRUSTED_INPUT_START id=[^>]*source=' -Because "$path must show the opening marker with an id and its source"
                $text | Should -Match '<<<UNTRUSTED_INPUT_END id=' -Because "$path must close the fence with the matching id"
                $text | Should -Match '(?i)one wrapper per source' -Because "$path must bind one wrapper to one source file"

                # The writers that produce these records strip the entry grammar, not angle brackets,
                # so a record can carry a literal end marker and close the fence early.
                $text | Should -Match '(?i)fresh random `?id`? for every source' -Because "$path must make the fence unforgeable"
                $text | Should -Match '(?i)scan the raw source text for the token' -Because "$path must catch a forged marker before wrapping"
            }
        }

        It 'test:si-wraps-harvested-sources carries the never-execute rule in the guide and the skill' {
            foreach ($path in @($script:guidePaths + $script:skillPaths)) {
                $text = Get-SiText -RelativePath $path

                $text | Should -Match '(?i)never execute (a |any )?directive' -Because "$path must forbid executing harvested directives"
                $text | Should -Match '(?i)data' -Because "$path must state that harvested text is data"
            }

            foreach ($path in $script:guidePaths) {
                $text = Get-SiText -RelativePath $path

                # Reporting an injection attempt is the only sanctioned response to one; silently
                # dropping it loses the signal that someone tried.
                $text | Should -Match '(?i)directive-looking content' -Because "$path must classify directive-looking text as a finding"

                # Storage-time sanitization strips grammar, not meaning: stating that keeps a later
                # reader from treating the sanitizer as the control.
                $text | Should -Match '(?i)not a sanitizer' -Because "$path must not present sanitization as the guard"

                # A one-off injection has recurrence 1 and no target file, so the candidate ranking
                # would discard exactly the finding that matters most.
                $text | Should -Match '(?i)exempt from every ranking rule' -Because "$path must keep injection findings out of the ranking"
                $text | Should -Match '\[SECURITY\] Prompt injection attempt detected' -Because "$path must use the same finding title as the concern reviewers"
                $text | Should -Match '(?i)severity \*\*Critical\*\*' -Because "$path must rate an injection attempt Critical"
            }

            foreach ($path in $script:skillPaths) {
                $text = Get-SiText -RelativePath $path
                $text | Should -Match '(?i)outside the candidate ranking' -Because "$path must not route injection findings through the cap"
            }
        }

        It 'test:si-wraps-harvested-sources requires cited, ranked, capped candidates' {
            foreach ($path in $script:guidePaths) {
                $text = Get-SiText -RelativePath $path

                $text | Should -Match '(?i)recurrence' -Because "$path must rank by recurrence first"
                $text | Should -Match '(?i)cites its sources' -Because "$path must require a citation per candidate"
                $text | Should -Match '(?i)cap the list at \d+' -Because "$path must bound the candidate list"
            }
        }

        It 'test:si-wraps-harvested-sources ships the skill and its assets from the plugin manifest' {
            $manifestPath = Join-Path $script:repoRoot 'plugins/self-improvement/plugin.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 50
            $declared = @($manifest.files | ForEach-Object { ($_.src -replace '\\', '/') })

            foreach ($required in @('skills/si/SKILL.md', 'skills/si/assets/harvest-guide.md',
                    'skills/si/scripts/PlanState.psm1', 'prompts/si.prompt.md')) {
                $declared | Should -Contain $required -Because "installation must materialize '$required'"
            }
        }
    }

    Context 'test:si-offered-at-completion' {
        BeforeAll {
            function Script:Get-FlatText {
                param([Parameter(Mandatory)][string]$RelativePath)
                # Every guide here is hard-wrapped, so anchored phrases would pass or fail on where
                # a line happens to break.
                return [regex]::Replace((Get-SiText -RelativePath $RelativePath), '\s+', ' ')
            }

            function Script:Get-SectionText {
                <#
                    Assertions have to be scoped to the /si text. /pfb sits in the same files and
                    says most of the same things ("never blocking", "not installed", "manual"), so a
                    whole-file match passes with the /si rules inverted or deleted outright.
                #>
                param(
                    [Parameter(Mandatory)][string]$RelativePath,
                    [Parameter(Mandatory)][string]$HeadingPattern
                )
                $text = Get-SiText -RelativePath $RelativePath
                # Single-quoted concatenation: "$(?<body>" in a double-quoted string is parsed as a
                # PowerShell subexpression, not a regex group.
                $pattern = '(?ms)^#{2,4}[^\r\n]*' + $HeadingPattern + '[^\r\n]*$(?<body>.*?)(?=^#{2,4} |\z)'
                $match = [regex]::Match($text, $pattern)
                $match.Success | Should -BeTrue -Because "$RelativePath must carry a '$HeadingPattern' section"
                return [regex]::Replace($match.Groups['body'].Value, '\s+', ' ')
            }

            function Script:Get-HarvestItemText {
                param([Parameter(Mandatory)][string]$RelativePath)
                $text = Get-SiText -RelativePath $RelativePath
                $match = [regex]::Match($text, '(?m)^\d+\.\s+\*\*Self-improvement[^\r\n]*$')
                $match.Success | Should -BeTrue -Because "$RelativePath harvest list must carry an /si item"
                return [regex]::Replace($match.Value, '\s+', ' ')
            }

            $script:ciGuidePaths = @(
                'plugins/continue-implementation/skills/ci/assets/crosscheck-guide.md',
                '.github/skills/ci/assets/crosscheck-guide.md'
            )
            $script:autopilotPaths = @(
                'plugins/autopilot/agents/autopilot.agent.md',
                '.github/agents/autopilot.agent.md'
            )
        }

        It 'test:si-offered-at-completion offers /si at interactive completion, after harvest runs' {
            foreach ($path in $script:ciGuidePaths) {
                $section = Get-SectionText -RelativePath $path -HeadingPattern 'Self-improvement'
                $item = Get-HarvestItemText -RelativePath $path

                $section | Should -Match '\.github/skills/si/SKILL\.md' -Because "$path must read the skill by its installed path"
                $item | Should -Match '\.github/skills/si/SKILL\.md' -Because "$path harvest item must name the same path"

                # Offering before harvest would read a ledger one plan out of date — missing exactly
                # the lessons the finishing plan just wrote. The precondition is ordering, not a
                # commit: a no-op harvest produces none, and that path must still offer.
                $section | Should -Match '(?i)after the harvest step has run' -Because "$path must order the offer after harvest"
                $section | Should -Match '(?i)whether or not it produced an append commit|no-op harvest that produced no append commit' -Because "$path must not gate the offer on a commit that may not exist"

                # An offer that can block completion is a gate, and this one is explicitly not.
                $section | Should -Match '(?i)blocks neither archival nor the PR' -Because "$path must keep the offer non-blocking"
                $item | Should -Match '(?i)never blocking' -Because "$path harvest item must keep the offer non-blocking"
                $section | Should -Match '(?i)skip silently when the .self-improvement. plugin is not installed' -Because "$path must skip silently without the plugin"

                # The guard reads main...HEAD: a branch cut from the plan's branch drags the whole
                # plan diff into scope and is refused every time.
                $section | Should -Match 'origin/main' -Because "$path must pin the proposal branch to the base ref"
            }
        }

        It 'test:si-offered-at-completion keeps the headless path from proposing' {
            foreach ($path in @($script:ciGuidePaths + $script:autopilotPaths)) {
                $flat = Get-FlatText -RelativePath $path

                # A due marker may be queued headlessly, but /si itself must not run because the
                # end of that flow is a PR against the files that govern every later run.
                $flat | Should -Match '(?i)(headless|autopilot run) (completion )?does not run (it|`?/si`?)' -Because "$path must not run /si without an operator"
            }

            foreach ($path in $script:autopilotPaths) {
                $flat = Get-FlatText -RelativePath $path
                $flat | Should -Match '(?i)Self-improvement \(`/si`\) . not run headless' -Because "$path must name the rule where the harvest mirror lives"
                $flat | Should -Match 'Enqueue-SiDue\.ps1' -Because "$path must persist only the due handoff"
                $flat | Should -Match '(?i)never enqueue before that source push' -Because "$path must bind the due to persisted completion"
            }
        }

        It 'test:si-offered-at-completion documents the consumer-repo flow as manual' {
            # Scoped to the sections that own the claim: si/SKILL.md says "not manually" in an
            # unrelated never-merge rule, which a whole-file match would happily accept.
            foreach ($path in @('plugins/self-improvement/skills/si/SKILL.md', '.github/skills/si/SKILL.md')) {
                $section = Get-SectionText -RelativePath $path -HeadingPattern 'Step 0'
                $section | Should -Match '(?i)deliberately manual' -Because "$path must state the upstream round-trip is manual"
                $section | Should -Match '(?i)by hand' -Because "$path must say the candidate list is carried by hand"
            }

            foreach ($path in $script:ciGuidePaths) {
                $section = Get-SectionText -RelativePath $path -HeadingPattern 'Self-improvement'
                $section | Should -Match '(?i)Consumer repos are manual' -Because "$path must state the consumer-repo flow is manual"
                $section | Should -Match '(?i)fork .skalary.' -Because "$path must name the fork/upstream round-trip"
                $section | Should -Match '(?i)not automated' -Because "$path must say the round-trip is not automated"
            }
        }
    }
}

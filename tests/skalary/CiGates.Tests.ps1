#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# REQ-10: a gate inventory written in prose is a list of gates somebody believed were running.
# These cases read the inventory in `ci-gates.design.md` as data and check it against the two
# hosts a gate can live in — the workflow and `validate.ps1` — in both directions, so a gate
# added to one side only is red rather than silently unrecorded.
Describe 'ci gate inventory' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:notePath = Join-Path $script:repoRoot 'docs/design-notes/project/ci-gates.design.md'
        $script:workflowPath = Join-Path $script:repoRoot '.github/workflows/registry-ci.yml'
        $script:validatePath = Join-Path $script:repoRoot 'scripts/validate.ps1'
        $script:explorationPath = Join-Path $script:repoRoot 'docs/design-notes/explorations/review-system-enforcement-gaps.design.md'
        $script:indexPath = Join-Path $script:repoRoot 'docs/design-notes/.design-notes.md'

        # Shared with Ci.Tests.ps1: one parser for the workflow, because a second copy would
        # be a second thing to drift.
        Import-Module (Join-Path $PSScriptRoot '..' 'CiWorkflow.psm1') -Force -DisableNameChecking

        $script:noteText = if (Test-Path -LiteralPath $script:notePath -PathType Leaf) {
            Get-Content -LiteralPath $script:notePath -Raw
        }
        else { $null }

        # The inventory rows, as data. A row is a table line whose first cell is a backticked
        # `gate:`/`support:` id, which is what keeps the parse from swallowing the surrounding
        # prose tables in the same note.
        function Get-GateInventoryRow {
            param([string]$Text)

            $rows = [System.Collections.Generic.List[object]]::new()
            foreach ($line in ($Text -split '\r?\n')) {
                if ($line -notmatch '^\|\s*`(?<id>(?:gate|support):[a-z0-9-]+)`\s*\|') { continue }
                $cells = @(($line.Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
                if ($cells.Count -lt 5) { continue }
                $rows.Add([pscustomobject]@{
                        Id          = $Matches['id']
                        Proves      = $cells[1]
                        Host        = $cells[2].Trim('`')
                        Invocation  = $cells[3].Trim('`')
                        Enforcement = $cells[4]
                    })
            }
            return $rows
        }

        # The scripts `validate.ps1` genuinely invokes, read from its syntax tree rather than
        # from its text. A path that survives only inside a comment or the docstring is prose
        # standing in for an invocation — the failure this file exists to catch — and a
        # `$gate = Join-Path ...` whose `& $gate` call was deleted leaves an assignment nothing
        # runs, so both the literal and its call site are required.
        function Get-ValidateInvokedScript {
            [OutputType([string[]])]
            param([Parameter(Mandatory)][string]$Path)

            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)

            $pathByVariable = @{}
            foreach ($assignment in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                if ($assignment.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
                foreach ($literal in $assignment.Right.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
                    if ($literal.Value -match '(?<name>[A-Za-z0-9-]+)\.ps1$') {
                        $pathByVariable[$assignment.Left.VariablePath.UserPath] = $Matches['name']
                    }
                }
            }

            $invoked = [System.Collections.Generic.List[string]]::new()
            foreach ($command in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $first = $command.CommandElements[0]
                if ($first -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
                $name = $first.VariablePath.UserPath
                if ($pathByVariable.ContainsKey($name)) { $invoked.Add($pathByVariable[$name]) }
            }
            return @($invoked | Sort-Object -Unique)
        }

        function Get-ExclusionId {
            param([string]$Text)

            $ids = [System.Collections.Generic.List[string]]::new()
            foreach ($line in ($Text -split '\r?\n')) {
                if ($line -match '^\|\s*`(?<id>exclusion:[a-z0-9-]+)`\s*\|\s*(?<by>[^|]+)\|\s*(?<why>[^|]+)\|') {
                    $ids.Add($Matches['id'])
                }
            }
            return $ids
        }
    }

    It 'test:CiGates.InventoryMatchesWorkflow keeps every gate on both sides, or red' {
        $script:noteText |
            Should -Not -BeNullOrEmpty -Because "REQ-10 rests on '$($script:notePath)' existing"
        $script:noteText |
            Should -Match '(?s)^---\r?\n.*?description:.*?globs:.*?\r?\n---' -Because 'a note without frontmatter is never auto-loaded, so it documents nothing an agent reads'
        (Get-Content -LiteralPath $script:indexPath -Raw) |
            Should -Match 'ci-gates\.design\.md' -Because 'a note absent from the root index is never loaded'

        $rows = @(Get-GateInventoryRow -Text $script:noteText)
        $rows.Count | Should -BeGreaterThan 5 -Because 'an unparsed inventory would make every assertion below vacuous'
        @($rows | Group-Object Id | Where-Object { $_.Count -gt 1 }).Count |
            Should -Be 0 -Because 'two rows sharing an id means one of them is unreachable from a failure message'

        $workflowText = Get-Content -LiteralPath $script:workflowPath -Raw
        $validateInvoked = @(Get-ValidateInvokedScript -Path $script:validatePath)
        $validateInvoked.Count |
            Should -BeGreaterThan 3 -Because 'an unparsed validate.ps1 would make the mapping below vacuous in both directions'
        $steps = @(Get-CiWorkflowStep -Text $workflowText)
        $steps.Count | Should -BeGreaterThan 1 -Because 'an unparsed workflow would make the mapping below vacuous'

        $declaredExclusions = @(Get-ExclusionId -Text $script:noteText)

        # --- inventory -> host: every row the note claims runs, runs -----------------------
        $claimedSteps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $claimedValidateScripts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

        foreach ($row in $rows) {
            if ($row.Invocation -eq '—') {
                # A gate that does not run is only acceptable as a decision somebody recorded.
                $row.Enforcement |
                    Should -Match 'exclusion:[a-z0-9-]+' -Because "gate '$($row.Id)' runs nowhere, so it must name the exclusion that excluded it"
                $exclusion = [regex]::Match($row.Enforcement, 'exclusion:[a-z0-9-]+').Value
                $declaredExclusions |
                    Should -Contain $exclusion -Because "'$exclusion' must be defined in the exclusions table with the decision that made it"
                continue
            }

            switch ($row.Host) {
                '.github/workflows/registry-ci.yml' {
                    $matching = @($steps | Where-Object { $_.Body -match $row.Invocation })
                    $matching.Count |
                        Should -Be 1 -Because "gate '$($row.Id)' claims to run as one workflow step matching '$($row.Invocation)', and $($matching.Count) step(s) do"
                    [void]$claimedSteps.Add($matching[0].Name)
                }
                'scripts/validate.ps1' {
                    $name = [regex]::Match($row.Invocation, 'scripts/skalary/(?<name>[A-Za-z0-9-]+)\\?\.ps1')
                    $name.Success | Should -BeTrue -Because "gate '$($row.Id)' must name the script validate.ps1 invokes"
                    $validateInvoked |
                        Should -Contain $name.Groups['name'].Value -Because "gate '$($row.Id)' claims scripts/validate.ps1 runs '$($row.Invocation)', and its syntax tree contains no such call"
                    [void]$claimedValidateScripts.Add($name.Groups['name'].Value)
                }
                default {
                    throw "gate '$($row.Id)' names an unknown host '$($row.Host)'; a host nothing reads cannot be checked."
                }
            }

            $row.Enforcement |
                Should -Match '^(blocking|support|advisory ·  ?`?exclusion:[a-z0-9-]+`?.*)$' -Because "gate '$($row.Id)' must state whether its exit code is the verdict; '$($row.Enforcement)' says neither"

            # `support` is the one label with no claim attached to it, so it is the cheapest
            # place to hide a gate: relabelling a real gate as support would otherwise skip
            # every check below. The label and the id prefix therefore have to agree.
            ($row.Enforcement -eq 'support') |
                Should -Be ($row.Id -like 'support:*') -Because "'$($row.Id)' and its enforcement '$($row.Enforcement)' disagree about whether it is a gate at all"
            if ($row.Enforcement -notmatch '^(blocking|support)$') {
                $exclusion = [regex]::Match($row.Enforcement, 'exclusion:[a-z0-9-]+').Value
                $declaredExclusions |
                    Should -Contain $exclusion -Because "'$exclusion' must be defined in the exclusions table with the decision that made it"
            }

            # The enforcement column is the one cell a reader acts on, so it is checked against
            # the step rather than believed. A step's verdict is the exit code of its last
            # statement: a process invocation or a native command carries one, and a cmdlet that
            # writes findings to the output stream does not. Under `shell: pwsh` an uncaught
            # `throw` carries one too, from wherever it sits in the block, so a step that inspects
            # findings and throws can go red even though its last line is a closing brace. The
            # last-statement rule still does the job it was written for: a trailing `exit 0` or a
            # reset of `$LASTEXITCODE` neuters every idiom above it, and claiming to block anyway
            # has to be red.
            if ($row.Host -eq '.github/workflows/registry-ci.yml') {
                $statements = @(Get-CiStepRunLine -Body ($steps | Where-Object { $_.Body -match $row.Invocation })[0].Body)
                $statements.Count | Should -BeGreaterThan 0 -Because "gate '$($row.Id)' must run something"

                $lastStatement = $statements[-1]
                $swallowsVerdict = $lastStatement -match '^(exit +0\b|\$(global:)?LASTEXITCODE *=)'
                $throwsOnFinding = @($statements | Where-Object { $_ -match '^throw\b' }).Count -gt 0
                $enforces = (-not $swallowsVerdict) -and
                    ($lastStatement -match '^(pwsh|git|npm)\b|-EnableExit\b' -or $throwsOnFinding)

                if ($row.Enforcement -eq 'blocking') {
                    $enforces |
                        Should -BeTrue -Because "gate '$($row.Id)' is recorded as blocking, but its step ends in '$lastStatement' and throws on nothing, so it reports no exit code"
                }
                elseif ($row.Enforcement -match '^advisory') {
                    $enforces |
                        Should -BeFalse -Because "gate '$($row.Id)' is recorded as advisory while its step ends in '$lastStatement', which does set the step's verdict — an exclusion for a gate that does enforce hides a working gate"
                }
            }
        }

        # --- host -> inventory: every gate that runs is a gate somebody wrote down ---------
        # The detector is what a gate looks like in each host rather than a list of the gates
        # this repo has today: a list would need updating by the same edit that adds a gate,
        # which is precisely the edit this case exists to catch.
        foreach ($step in $steps) {
            $code = Remove-CiComment -Text $step.Body
            if ($code -notmatch '(scripts|tools)/[A-Za-z0-9/._-]+\.ps1|npm (run|test)\b|Invoke-ScriptAnalyzer|git diff') { continue }
            $claimedSteps |
                Should -Contain $step.Name -Because "workflow step '$($step.Name)' runs repository code that no row in the gate inventory claims"
        }

        foreach ($name in $validateInvoked) {
            $claimedValidateScripts |
                Should -Contain $name -Because "scripts/validate.ps1 runs '$name.ps1', which no row in the gate inventory claims"
        }
    }

    It 'test:CiGates.ClusterRetirementIsRecorded keeps the resolved clusters retired and the deferred one addressed' {
        # RISK-13: the constants cluster was already dropped once by a hand-off that named no
        # receiver. The retirement record is where a reader learns which of these gaps this plan
        # actually closed, so a cluster silently left as "parked" would be the same loss again.
        $exploration = Get-Content -LiteralPath $script:explorationPath -Raw

        # Each cluster is read as its own slice. A whole-file match would let a deleted record
        # be satisfied by the identical sentence in the next cluster down, which is the one way
        # this case could pass while the record it pins is gone.
        $section = @{}
        foreach ($match in [regex]::Matches($exploration, '(?ms)^## Cluster (?<id>[A-H])\b(?<body>.*?)(?=^## |\z)')) {
            $section[$match.Groups['id'].Value] = $match.Groups['body'].Value
        }
        @('A', 'B', 'C', 'E', 'H') | ForEach-Object {
            $section.ContainsKey($_) | Should -BeTrue -Because "cluster $_ must still be in the note to be retired or left open by it"
        }

        $exploration | Should -Match '(?m)^## Status after plan `768d7b`' -Because 'the note must say which of its clusters are still open'
        $section['B'] |
            Should -Match 'Resolved by plan `768d7b`, except the first row' -Because 'the evidence skipped state is 863d97 contract and stays open'
        $section['E'] |
            Should -Match 'Resolved by plan `768d7b`' -Because 'the locale-dependent catalogs are fixed rather than regenerated under invariant culture'
        $section['H'] |
            Should -Match 'Resolved by plan `768d7b`' -Because 'the 29-minute gate is the cluster the runtime budget closed'
        $section['A'] |
            Should -Not -Match 'Resolved by plan `768d7b`' -Because 'this plan did not touch the report-attendance cluster, and a note claiming it did would send the next reader past a live gap'

        # The deferral, with its receiver named. D12 exists because the previous hand-off had no
        # receiving requirement, so naming the child is the whole mitigation.
        $section['C'] |
            Should -Match 'Deferred to `34088e`, not resolved' -Because 'RISK-13: a deferral without a named receiver is a drop'
        $section['C'] |
            Should -Match 'asserts nothing about it' -Because 'this plan must not appear to cover work it deliberately did not do'
    }
}

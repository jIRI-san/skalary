#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plan c21cdc REQ-1/REQ-11/REQ-12, step 1.1. Structural validation of a review run is delegated to
# the host's native `Test-Json`, which means two things have to be proven rather than assumed: that
# the committed schemas say exactly what the contract says, and that the host implements every
# keyword they rely on. The second is what `Test-ReviewSchemaCapability.ps1` is for, and it is
# tested here in all three of its outcomes — capable, too old, and no `-SchemaFile` — because a
# preflight that cannot report absence is indistinguishable from one that never ran.
#
# The layer split is deliberate and is asserted in both directions: the schemas own structure and
# per-string maxima, and the cases marked `semantic` are structurally *valid* on purpose. Each of
# those records a hole no single-document schema can close and names the rule step 1.2 must close
# it with, so nothing here can be mistaken for evidence that the semantic layer already exists.
Describe 'review run schemas' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:schemaRoot = Join-Path $script:repoRoot 'schemas/review'
        $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures/review-run'
        $script:preflight = Join-Path $script:repoRoot 'scripts/skalary/Test-ReviewSchemaCapability.ps1'
        $script:idPrefix = 'https://github.com/jIRI-san/skalary/schemas/review/'
        $script:dialect = 'https://json-schema.org/draft/2020-12/schema'
        $script:schemaNames = @(
            'review-plan.schema.json'
            'review-run.schema.json'
            'review-manifest.schema.json'
            'terminal-status.schema.json'
        )

        # The keywords that decide acceptance rather than describe. Kept next to the assertions that
        # use it so a schema gaining a new one is visible here as well as in the preflight.
        $script:limitKeyword = @(
            'const', 'enum', 'maxItems', 'maxLength', 'maximum', 'minItems', 'minLength', 'minimum',
            'pattern', 'uniqueItems'
        )

        Import-Module (Join-Path $PSScriptRoot '..' 'CiWorkflow.psm1') -Force -DisableNameChecking

        function Script:Read-Json {
            param([Parameter(Mandatory)][string]$Path)

            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Fixture not found: $Path" }
            return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 40)
        }

        function Script:ConvertTo-SortedNode {
            <#
            .SYNOPSIS
                Key-ordered copy of a parsed JSON node, so two documents can be compared as text.
            #>
            param([object]$Node)

            if ($Node -is [System.Collections.IDictionary]) {
                $ordered = [ordered]@{}
                foreach ($key in @($Node.Keys | Sort-Object -CaseSensitive)) {
                    $ordered[[string]$key] = ConvertTo-SortedNode -Node $Node[$key]
                }
                return $ordered
            }
            if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
                $items = [System.Collections.Generic.List[object]]::new()
                foreach ($item in $Node) { $items.Add((ConvertTo-SortedNode -Node $item)) }
                return , $items.ToArray()
            }
            return $Node
        }

        function Script:ConvertTo-ComparableJson {
            param([object]$Node)

            return (ConvertTo-Json -InputObject (ConvertTo-SortedNode -Node $Node) -Depth 40 -Compress)
        }

        function Script:Test-Instance {
            <#
            .SYNOPSIS
                Validates one in-memory instance against one committed schema file.
            #>
            param(
                [Parameter(Mandatory)][object]$Instance,
                [Parameter(Mandatory)][string]$Schema
            )

            $json = ConvertTo-Json -InputObject $Instance -Depth 40
            return [bool](Test-Json -Json $json -SchemaFile (Join-Path $script:schemaRoot $Schema) -ErrorAction SilentlyContinue)
        }

        function Script:Invoke-Preflight {
            <#
            .SYNOPSIS
                Runs the preflight as a real child process and returns its exit code and stdout.
            .DESCRIPTION
                The script writes its status object to the raw stdout stream so the bytes cannot be
                reshaped by a host's formatting; a runspace would not see them. CI runs it as a
                process, so the tests do too.
            #>
            param([string[]]$Arguments = @())

            $output = & pwsh -NoProfile -File $script:preflight @Arguments 2>$null
            return [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Stdout = (@($output) -join "`n")
            }
        }

        $script:limits = Read-Json -Path (Join-Path $script:schemaRoot 'review-limits.schema.json')
        $script:schemas = [ordered]@{}
        foreach ($name in $script:schemaNames) {
            $script:schemas[$name] = Read-Json -Path (Join-Path $script:schemaRoot $name)
        }

        $script:cases = Read-Json -Path (Join-Path $script:fixtureRoot 'edge/cases.json')
        $script:maximumSpec = Read-Json -Path (Join-Path $script:fixtureRoot 'edge/maximum-envelope.spec.json')

        function Script:New-Filler {
            param([Parameter(Mandatory)][int]$Length, [Parameter(Mandatory)][string]$Seed)

            $builder = [System.Text.StringBuilder]::new()
            while ($builder.Length -lt $Length) { [void]$builder.Append("$Seed-") }
            return $builder.ToString(0, $Length)
        }

        function Script:New-MaximumEnvelope {
            <#
            .SYNOPSIS
                The largest envelope the structural contract admits, built from the committed spec.
            #>
            $generation = $script:maximumSpec.generation
            $roster = @(1..$generation.rosterModels | ForEach-Object { New-Filler -Length $generation.modelLength -Seed "model-$_" })
            $tasks = @(1..$generation.tasks | ForEach-Object {
                    $task = [ordered]@{
                        concern = ('concern-{0:d3}' -f $_)
                        model = $roster[($_ - 1) % $generation.rosterModels]
                        outcome = $(if ($_ -le $generation.diagnosticTasks) { 'failed' } else { 'completed' })
                        taskId = ('t{0:d3}' -f $_)
                    }
                    if ($_ -le $generation.diagnosticTasks) {
                        $task['diagnostic'] = New-Filler -Length $generation.diagnosticLength -Seed "diagnostic-$_"
                    }
                    $task
                })
            $findings = @(1..$generation.findings | ForEach-Object {
                    $index = $_
                    # The merge key is seeded from the group index, not the finding index: 256 raw
                    # findings collapse into exactly `mergedGroups` merged entries, which is the
                    # merged maximum the vocabulary declares. Every string stays at its maximum.
                    $group = ('{0:d3}' -f ((($index - 1) % $generation.mergedGroups) + 1))
                    [ordered]@{
                        action = New-Filler -Length $generation.actionLength -Seed "action-$index"
                        body = New-Filler -Length $generation.bodyLength -Seed "body-$index"
                        component = New-Filler -Length $generation.componentLength -Seed "component-$group"
                        references = @(1..$generation.references | ForEach-Object { New-Filler -Length $generation.referenceLength -Seed "ref-$index-$_" })
                        rootCause = New-Filler -Length $generation.rootCauseLength -Seed "root-$group"
                        severity = 'Critical'
                        taskId = ('t{0:d3}' -f ((($index - 1) % ($generation.tasks - $generation.diagnosticTasks)) + $generation.diagnosticTasks + 1))
                        title = New-Filler -Length $generation.titleLength -Seed "title-$index"
                    }
                })

            return [ordered]@{
                findings = $findings
                invocationBudget = $generation.invocationBudget
                planDigest = 'sha256:' + ('0' * 64)
                reviewType = 'code'
                roster = $roster
                runId = '8f3c1d2e-5a47-4b90-9c61-2d7e0f4a6b35'
                schema = 'skalary/review-run@1'
                scope = New-Filler -Length $generation.scopeLength -Seed 'scope'
                tasks = $tasks
            }
        }
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics commits four canonical schemas with repository ids on one dialect' {
        foreach ($name in $script:schemaNames) {
            $schema = $script:schemas[$name]
            [string]$schema['$schema'] | Should -Be $script:dialect -Because "$name must declare the one dialect the preflight proves"
            [string]$schema['$id'] | Should -Be ($script:idPrefix + $name) -Because 'D2: schema identity is a repository URL'
            $schema['additionalProperties'] | Should -BeFalse -Because "$name must close its root object"
            $schema.Contains('$defs') | Should -BeTrue
        }

        [string]$script:limits['$id'] | Should -Be ($script:idPrefix + 'review-limits.schema.json')
        [string]$script:limits['$schema'] | Should -Be $script:dialect
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics keeps every shared limit in one schema-owned vocabulary' {
        $vocabulary = $script:limits['$defs']
        @($vocabulary.Keys).Count | Should -BeGreaterThan 20

        # Each schema embeds the definitions it needs rather than referencing the vocabulary across
        # files: step 2.1 distributes these files one at a time, and an external `$ref` would make a
        # distributed copy resolve against a file that is not there. The copies are therefore
        # required to be deep-equal to the vocabulary, which is what keeps the duplication honest.
        $drift = [System.Collections.Generic.List[string]]::new()
        $shared = 0
        foreach ($name in $script:schemaNames) {
            $defs = $script:schemas[$name]['$defs']
            foreach ($key in @($defs.Keys)) {
                if (-not $vocabulary.Contains($key)) { continue }
                $shared++
                $expected = ConvertTo-ComparableJson -Node $vocabulary[$key]
                $actual = ConvertTo-ComparableJson -Node $defs[$key]
                if ($actual -ne $expected) { $drift.Add("$name#/`$defs/$key") }
            }
        }
        $shared | Should -BeGreaterThan 30 -Because 'a comparison that matched nothing would be vacuous'
        $drift -join '; ' | Should -BeNullOrEmpty -Because 'an embedded definition that drifts from the vocabulary is a second contract'

        # Every limit lives inside `$defs`, so the vocabulary comparison above covers all of them:
        # a maxLength written directly into a property would be a limit nothing compares.
        $strays = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $script:schemaNames) {
            $queue = [System.Collections.Generic.Queue[object]]::new()
            foreach ($key in @($script:schemas[$name].Keys)) {
                if ($key -eq '$defs') { continue }
                if ($script:limitKeyword -contains [string]$key) { $strays.Add("$name#/$key") }
                $queue.Enqueue($script:schemas[$name][$key])
            }
            while ($queue.Count -gt 0) {
                $node = $queue.Dequeue()
                if ($node -is [System.Collections.IDictionary]) {
                    foreach ($key in @($node.Keys)) {
                        if ($script:limitKeyword -contains [string]$key) { $strays.Add("$name :: $key outside `$defs") }
                        $queue.Enqueue($node[$key])
                    }
                }
                elseif ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) {
                    foreach ($item in $node) { $queue.Enqueue($item) }
                }
            }
        }
        $strays -join '; ' | Should -BeNullOrEmpty

        # The numbers the semantic layer will read must be the numbers the validator enforces.
        $limits = $script:limits['x-skalary-limits']
        [int]$limits.maxTitleLength | Should -Be ([int]$vocabulary.title.maxLength)
        [int]$limits.maxBodyBytes | Should -Be ([int]$vocabulary.body.maxLength)
        [int]$limits.maxScopeLength | Should -Be ([int]$vocabulary.scope.maxLength)
        [int]$limits.maxReferences | Should -Be ([int]$vocabulary.references.maxItems)
        [int]$limits.maxReferenceLength | Should -Be ([int]$vocabulary.reference.maxLength)
        [int]$limits.maxTaskDiagnosticBytes | Should -Be ([int]$vocabulary.diagnostic.maxLength)
        [int]$limits.maxRosterModels | Should -Be ([int]$vocabulary.roster.maxItems)
        [int]$limits.maxInvocationBudget | Should -Be ([int]$vocabulary.invocationBudget.maximum)
        [int]$limits.maxEnvelopeBytes | Should -Be ([int]$vocabulary.byteCount.maximum)
        [int]$limits.maxArtifactNameLength | Should -Be ([int]$vocabulary.artifactName.maxLength)
        [int]$limits.maxTasks | Should -Be ([int]$script:schemas['review-plan.schema.json']['$defs'].plannedTasks.maxItems)
        [int]$limits.maxTasks | Should -Be ([int]$script:schemas['review-run.schema.json']['$defs'].resultTasks.maxItems)
        [int]$limits.maxFindings | Should -Be ([int]$script:schemas['review-run.schema.json']['$defs'].findings.maxItems)
        [int]$limits.minTasks | Should -Be ([int]$script:schemas['review-plan.schema.json']['$defs'].plannedTasks.minItems)
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics closes every object the contract defines' {
        $open = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $script:schemaNames) {
            $queue = [System.Collections.Generic.Queue[object]]::new()
            $queue.Enqueue($script:schemas[$name])
            while ($queue.Count -gt 0) {
                $node = $queue.Dequeue()
                if ($node -is [System.Collections.IDictionary]) {
                    # An object schema is one that enumerates properties; the conditional fragments
                    # (`if`/`then` subschemas) constrain an object described elsewhere and close nothing.
                    if ([string]$node['type'] -eq 'object' -and $node.Contains('properties') -and $node['additionalProperties'] -ne $false) {
                        $open.Add($name)
                    }
                    foreach ($key in @($node.Keys)) { $queue.Enqueue($node[$key]) }
                }
                elseif ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) {
                    foreach ($item in $node) { $queue.Enqueue($item) }
                }
            }
        }
        $open -join '; ' | Should -BeNullOrEmpty -Because 'RISK-1/REQ-3: an open object is where an aggregate or an unknown field gets in'
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics accepts every minimum and maximum structural fixture' {
        $accepted = @($script:cases.cases | Where-Object { $_.layer -eq 'structural' -and $_.expectedStructural })
        $accepted.Count | Should -BeGreaterThan 10

        $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($case in $accepted) {
            if (-not (Test-Instance -Instance $case.instance -Schema $case.schema)) {
                $failures.Add("$($case.id) ($($case.schema)) - $($case.why)")
            }
        }
        $failures -join '; ' | Should -BeNullOrEmpty
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics rejects unknown versions, unknown properties, one-above maxima, manifest path violations and aggregate spoofs' {
        $rejected = @($script:cases.cases | Where-Object { $_.layer -eq 'structural' -and -not $_.expectedStructural })
        $rejected.Count | Should -BeGreaterThan 20

        # Each named rejection class REQ-1 enumerates must actually be present, or the loop below
        # could pass over a fixture set somebody quietly emptied.
        foreach ($required in @(
                'plan-unknown-version', 'plan-unknown-property', 'plan-one-above-budget-maximum',
                'run-one-above-title-maximum', 'run-one-above-reference-maximum', 'run-aggregate-spoof',
                'manifest-traversal-name', 'manifest-absolute-name', 'manifest-nested-name',
                'manifest-name-one-above-maximum-length', 'manifest-missing-role',
                'manifest-unknown-role', 'status-exit-state-mismatch', 'status-freeze-degraded')) {
            @($rejected | Where-Object { $_.id -eq $required }).Count |
                Should -Be 1 -Because "'$required' is a rejection class REQ-1 names"
        }

        $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($case in $rejected) {
            if (Test-Instance -Instance $case.instance -Schema $case.schema) {
                $failures.Add("$($case.id) ($($case.schema)) - $($case.why)")
            }
        }
        $failures -join '; ' | Should -BeNullOrEmpty
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics bounds an artifact name at 96 characters, extension included' {
        # The name pattern caps the *tail* at 94 characters, so on its own it admits a 100-character
        # `.json` name while the vocabulary advertises 96. `maxLength` is what closes that gap, and
        # the two fixtures below sit on either side of it with the extension counted in.
        $vocabulary = $script:limits['$defs'].artifactName
        [int]$vocabulary.maxLength | Should -Be ([int]$script:limits['x-skalary-limits'].maxArtifactNameLength)
        [int]$vocabulary.maxLength | Should -Be 96

        $embedded = $script:schemas['review-manifest.schema.json']['$defs'].artifactName
        [int]$embedded.maxLength | Should -Be 96 -Because 'the distributed copy must carry the same bound'

        $accepted = @($script:cases.cases | Where-Object { $_.id -eq 'manifest-name-at-maximum-length' })[0]
        $rejected = @($script:cases.cases | Where-Object { $_.id -eq 'manifest-name-one-above-maximum-length' })[0]
        $acceptedName = [string]$accepted.instance.files.summary.name
        $rejectedName = [string]$rejected.instance.files.summary.name

        $acceptedName.Length | Should -Be 96 -Because 'the accepted edge is exactly the maximum, extension included'
        $rejectedName.Length | Should -Be 97 -Because 'the rejected edge is exactly one character above it'
        $acceptedName | Should -Match '\.json$'
        $rejectedName | Should -Match '\.json$'

        # Both names satisfy the pattern, which is what makes this a maxLength test rather than a
        # restatement of the pattern: without the length bound the 97-character name would pass.
        foreach ($name in @($acceptedName, $rejectedName)) {
            $name | Should -Match ([string]$vocabulary.pattern)
        }

        Test-Instance -Instance $accepted.instance -Schema 'review-manifest.schema.json' | Should -BeTrue
        Test-Instance -Instance $rejected.instance -Schema 'review-manifest.schema.json' |
            Should -BeFalse -Because 'RISK-1: a name longer than the vocabulary claims is a bound nothing enforces'
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics leaves duplicates, slot mismatch, dangling findings and byte budgets to the semantic layer' {
        $semantic = @($script:cases.cases | Where-Object { $_.layer -eq 'semantic' })
        $semantic.Count | Should -BeGreaterThan 6

        foreach ($required in @(
                'semantic-plan-duplicate-task-id', 'semantic-plan-duplicate-slot',
                'semantic-run-dangling-finding', 'semantic-run-finding-on-failed-task',
                'semantic-run-task-set-differs-from-plan', 'semantic-run-body-over-utf8-budget',
                'semantic-status-over-8-kib')) {
            @($semantic | Where-Object { $_.id -eq $required }).Count |
                Should -Be 1 -Because "'$required' is a hole the structural layer cannot close"
        }

        $unexpected = [System.Collections.Generic.List[string]]::new()
        foreach ($case in $semantic) {
            [string]$case.semanticRule | Should -Not -BeNullOrEmpty -Because "'$($case.id)' must name the rule that rejects it"
            if (-not (Test-Instance -Instance $case.instance -Schema $case.schema)) {
                # If a schema starts rejecting one of these, the case has moved layer and the note
                # that says the semantic layer owns it is now wrong.
                $unexpected.Add($case.id)
            }
        }
        $unexpected -join '; ' |
            Should -BeNullOrEmpty -Because 'these fixtures record what the schema cannot see; a rejected one is documenting the wrong layer'

        # The two byte-budget cases are the reason the split exists at all: every string is inside
        # its maximum length while the UTF-8 encoding is over budget.
        $body = @($semantic | Where-Object { $_.id -eq 'semantic-run-body-over-utf8-budget' })[0]
        $text = [string]$body.instance.findings[0].body
        $text.Length | Should -Be 4096
        [System.Text.Encoding]::UTF8.GetByteCount($text) | Should -BeGreaterThan 4096

        $status = @($semantic | Where-Object { $_.id -eq 'semantic-status-over-8-kib' })[0]
        $statusBytes = [System.Text.Encoding]::UTF8.GetByteCount((ConvertTo-Json -InputObject $status.instance -Depth 10 -Compress))
        $statusBytes | Should -BeGreaterThan 8192
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics proves the validator can reject at all' {
        # A validator that answered True to everything would make every positive case above pass and
        # every negative one fail loudly — except that a broken `-SchemaFile` path could also answer
        # True silently. The always-rejecting schema is the control: it must refuse an instance the
        # real schema accepts.
        $alwaysReject = Join-Path $script:fixtureRoot 'edge/always-reject.schema.json'
        (Get-Content -LiteralPath $alwaysReject -Raw).Trim() | Should -Be 'false'

        $minimum = @($script:cases.cases | Where-Object { $_.id -eq 'plan-minimum' })[0]
        Test-Instance -Instance $minimum.instance -Schema 'review-plan.schema.json' | Should -BeTrue

        $json = ConvertTo-Json -InputObject $minimum.instance -Depth 40
        [bool](Test-Json -Json $json -SchemaFile $alwaysReject -ErrorAction SilentlyContinue) |
            Should -BeFalse -Because 'a host whose Test-Json accepts a false schema is not validating anything'
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics accepts the committed 44-finding corpus as plan and envelope' {
        $planPath = Join-Path $script:fixtureRoot 'corpus/gate-10.7-cr-branch.plan.json'
        $runPath = Join-Path $script:fixtureRoot 'corpus/gate-10.7-cr-branch.run.json'

        [bool](Test-Json -Json (Get-Content -LiteralPath $planPath -Raw) -SchemaFile (Join-Path $script:schemaRoot 'review-plan.schema.json') -ErrorAction SilentlyContinue) |
            Should -BeTrue
        [bool](Test-Json -Json (Get-Content -LiteralPath $runPath -Raw) -SchemaFile (Join-Path $script:schemaRoot 'review-run.schema.json') -ErrorAction SilentlyContinue) |
            Should -BeTrue
    }

    It 'test:ReviewReport.MaximumEnvelopeFixtureStructural admits the largest legal envelope inside the 2 MiB input cap' {
        # RISK-3: record maxima and a byte cap are two different promises, and D3 makes both. This is
        # the arithmetic that says they are compatible at all — it is not, and does not claim to be,
        # evidence that Publish can render this envelope. Step 1.2 owns that measurement.
        $envelope = New-MaximumEnvelope
        $json = ConvertTo-Json -InputObject $envelope -Depth 40 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($json)

        @($envelope.tasks).Count | Should -Be ([int]$script:maximumSpec.generation.tasks)
        @($envelope.findings).Count | Should -Be ([int]$script:maximumSpec.generation.findings)
        @($envelope.tasks | Where-Object { $_.outcome -ne 'completed' }).Count |
            Should -Be ([int]$script:maximumSpec.generation.diagnosticTasks)
        @($envelope.tasks | Where-Object { $_.diagnostic.Length -eq $script:maximumSpec.generation.diagnosticLength }).Count |
            Should -Be ([int]$script:maximumSpec.generation.diagnosticTasks)
        @($envelope.findings | Where-Object {
                $taskId = $_.taskId
                @($envelope.tasks | Where-Object { $_.taskId -eq $taskId })[0].outcome -ne 'completed'
            }).Count | Should -Be 0 -Because 'only completed tasks may own findings'

        # A maximum envelope must be maximal in every dimension the contract bounds, and merged
        # findings are one of them: 256 raw findings seeded with 256 distinct merge keys would
        # describe a run of 256 merged entries, twice what `maxMergedFindings` admits. The keys are
        # therefore seeded per group, and the collapse is asserted rather than assumed.
        $normalizedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $membersByKey = @{}
        foreach ($finding in @($envelope.findings)) {
            $key = ([regex]::Replace(([string]$finding.rootCause).ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim() +
            [string][char]1 +
            ([regex]::Replace(([string]$finding.component).ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim()
            [void]$normalizedKeys.Add($key)
            if (-not $membersByKey.ContainsKey($key)) { $membersByKey[$key] = 0 }
            $membersByKey[$key]++
        }
        $normalizedKeys.Count | Should -Be ([int]$script:maximumSpec.expected.mergedGroups)
        $normalizedKeys.Count | Should -Be ([int]$script:limits['x-skalary-limits'].maxMergedFindings)
        [int]$script:maximumSpec.expected.maxMergedFindings | Should -Be ([int]$script:limits['x-skalary-limits'].maxMergedFindings)
        @($membersByKey.Values | Sort-Object -Unique) -join ',' |
            Should -Be ([string][int]$script:maximumSpec.expected.findingsPerGroup) -Because 'every group carries the same number of raw findings, so the collapse is even rather than lopsided'

        # The maxima the merge does not touch are still maxima: one key per group, but a distinct
        # title, body, action and reference set per raw finding.
        @(@($envelope.findings | ForEach-Object { [string]$_.title }) | Sort-Object -Unique).Count |
            Should -Be ([int]$script:maximumSpec.generation.findings)
        foreach ($finding in @($envelope.findings)) {
            ([string]$finding.rootCause).Length | Should -Be ([int]$script:maximumSpec.generation.rootCauseLength)
            ([string]$finding.component).Length | Should -Be ([int]$script:maximumSpec.generation.componentLength)
            ([string]$finding.title).Length | Should -Be ([int]$script:maximumSpec.generation.titleLength)
            ([string]$finding.body).Length | Should -Be ([int]$script:maximumSpec.generation.bodyLength)
            ([string]$finding.action).Length | Should -Be ([int]$script:maximumSpec.generation.actionLength)
            @($finding.references).Count | Should -Be ([int]$script:maximumSpec.generation.references)
        }
        $json.Length | Should -Be $bytes -Because 'the filler alphabet is ASCII, so the fixture cannot drift by an escape sequence'
        $bytes | Should -Be ([int]$script:maximumSpec.expected.envelopeBytes)
        $bytes | Should -BeLessOrEqual ([int]$script:maximumSpec.expected.maxEnvelopeBytes)
        ([int]$script:maximumSpec.expected.maxEnvelopeBytes - $bytes) | Should -Be ([int]$script:maximumSpec.expected.headroomBytes)

        [bool](Test-Json -Json $json -SchemaFile (Join-Path $script:schemaRoot 'review-run.schema.json') -ErrorAction SilentlyContinue) |
            Should -BeTrue -Because 'the structural maximum must be admissible, or the maxima describe an envelope nothing can send'

        $overBudget = New-MaximumEnvelope
        $nextTask = @($overBudget.tasks | Where-Object { $_.taskId -eq 't012' })[0]
        $nextTask.outcome = 'failed'
        $nextTask['diagnostic'] = New-Filler -Length $script:maximumSpec.generation.diagnosticLength -Seed 'diagnostic-12'
        foreach ($finding in @($overBudget.findings | Where-Object { $_.taskId -eq 't012' })) {
            $finding.taskId = 't013'
        }
        $overBudgetJson = ConvertTo-Json -InputObject $overBudget -Depth 40 -Compress
        [bool](Test-Json -Json $overBudgetJson -SchemaFile (Join-Path $script:schemaRoot 'review-run.schema.json') -ErrorAction SilentlyContinue) |
            Should -BeTrue -Because 'the input-byte admission bound is semantic, not a structural schema keyword'
        [System.Text.Encoding]::UTF8.GetByteCount($overBudgetJson) |
            Should -BeGreaterThan ([int]$script:maximumSpec.expected.maxEnvelopeBytes) -Because 'one more maximum diagnostic is the first structurally valid record mix above admission'

        # Built twice: a fixture whose size depends on enumeration order would pin nothing.
        (ConvertTo-Json -InputObject (New-MaximumEnvelope) -Depth 40 -Compress) | Should -Be $json
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics exits 0 with one bounded status object on a capable host' {
        $result = Invoke-Preflight
        $result.ExitCode | Should -Be 0 -Because "this host is PowerShell $($PSVersionTable.PSVersion)"

        $result.Stdout | Should -Not -Match "`r" -Because 'D15: LF only'
        $result.Stdout | Should -Not -Match "`u{feff}" -Because 'D15: UTF-8 without BOM'
        @($result.Stdout -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count |
            Should -Be 1 -Because 'REQ-11: exactly one terminal status object, never a transcript'
        [System.Text.Encoding]::UTF8.GetByteCount($result.Stdout) | Should -BeLessOrEqual 8192

        $status = $result.Stdout | ConvertFrom-Json
        [string]$status.schema | Should -Be 'skalary/review-terminal-status@1'
        [string]$status.mode | Should -Be 'capability'
        [string]$status.state | Should -Be 'capable'
        [int]$status.exitCode | Should -Be 0
        $status.PSObject.Properties.Name | Should -Not -Contain 'runId'
        [bool](Test-Json -Json $result.Stdout -SchemaFile (Join-Path $script:schemaRoot 'terminal-status.schema.json') -ErrorAction SilentlyContinue) |
            Should -BeTrue -Because 'the status it prints is covered by the schema that owns it'

        # Every assertion keyword the four schemas use is proven, and the count is reported rather
        # than implied: a schema that starts using an unproven keyword fails the preflight itself.
        $keywords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $assertion = @('$ref', 'additionalProperties', 'allOf', 'const', 'else', 'enum', 'if', 'items',
            'maxItems', 'maxLength', 'maximum', 'minItems', 'minLength', 'minimum', 'not', 'pattern',
            'properties', 'required', 'then', 'type', 'uniqueItems')
        foreach ($name in $script:schemaNames) {
            $queue = [System.Collections.Generic.Queue[object]]::new()
            $queue.Enqueue($script:schemas[$name])
            while ($queue.Count -gt 0) {
                $node = $queue.Dequeue()
                if ($node -is [System.Collections.IDictionary]) {
                    foreach ($key in @($node.Keys)) {
                        if ($assertion -contains [string]$key) { [void]$keywords.Add([string]$key) }
                        $queue.Enqueue($node[$key])
                    }
                }
                elseif ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) {
                    foreach ($item in $node) { $queue.Enqueue($item) }
                }
            }
        }
        [string]$status.message | Should -Match "$($keywords.Count) keyword\(s\) proven"
        [string]$status.message | Should -Match '4 schema\(s\)'
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics exits 2 with one bounded status object when the host is below PowerShell 7.6' {
        $result = Invoke-Preflight -Arguments @('-SimulateVersion', '7.5.9')
        $result.ExitCode | Should -Be 2 -Because 'D12: an absent capability is a rejection, not a warning'

        @($result.Stdout -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count | Should -Be 1
        [System.Text.Encoding]::UTF8.GetByteCount($result.Stdout) | Should -BeLessOrEqual 8192

        $status = $result.Stdout | ConvertFrom-Json
        [int]$status.exitCode | Should -Be 2
        [string]$status.state | Should -Be 'incapable'
        [string]$status.mode | Should -Be 'capability'
        @($status.diagnostics) -join ' ' | Should -Match 'powershell-below-minimum'
        @($status.diagnostics) -join ' ' | Should -Match '7\.5\.9'
        [bool](Test-Json -Json $result.Stdout -SchemaFile (Join-Path $script:schemaRoot 'terminal-status.schema.json') -ErrorAction SilentlyContinue) |
            Should -BeTrue -Because 'the rejection object is the one a caller parses, so it is schema-covered too'
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics exits 2 when Test-Json exposes no -SchemaFile' {
        # The two halves of D12 fail differently and are reported differently: a supported version
        # whose Test-Json lacks the parameter would otherwise pass a version check and then crash.
        $result = Invoke-Preflight -Arguments @('-SimulateMissingSchemaFile')
        $result.ExitCode | Should -Be 2

        $status = $result.Stdout | ConvertFrom-Json
        [string]$status.state | Should -Be 'incapable'
        @($status.diagnostics) -join ' ' | Should -Match 'test-json-schemafile-absent'
        @($status.diagnostics) -join ' ' | Should -Not -Match 'powershell-below-minimum'
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics cannot be argued into capability by its own test seams' {
        # The seam exists to simulate absence. If it could also simulate presence, every gate below
        # it would be optional on the host that most needs it.
        $raised = Invoke-Preflight -Arguments @('-SimulateVersion', '99.9.9')
        $raised.ExitCode | Should -Be 0 -Because 'this host is genuinely capable, and a higher simulated version changes nothing'
        ($raised.Stdout | ConvertFrom-Json).message |
            Should -Match ([regex]::Escape($PSVersionTable.PSVersion.ToString())) -Because 'the status reports the real version, not the simulated one'

        $script = Get-Content -LiteralPath $script:preflight -Raw
        $script | Should -Match '#requires -Version 7\.0' -Because 'D12: the wrapper stays loadable on 7.0 so it can report the absence rather than fail to parse'
        $script | Should -Match 'if \(\$simulated -lt \$version\) \{ \$version = \$simulated \}' -Because 'the seam may only lower the reported version'
        $script | Should -Match '-not \$SimulateMissingSchemaFile' -Because 'the seam may only remove the capability'
    }

    It 'test:ReviewReport.SchemaCapabilityAndSemantics runs as a named CI preflight before the repository and unit gates' {
        $workflowPath = Join-Path $script:repoRoot '.github/workflows/registry-ci.yml'
        $workflowText = Get-Content -LiteralPath $workflowPath -Raw
        $steps = @(Get-CiWorkflowStep -Text $workflowText)
        $steps.Count | Should -BeGreaterThan 1

        $names = @($steps | ForEach-Object { $_.Name })
        $preflightSteps = @($steps | Where-Object { $_.Body -match 'Test-ReviewSchemaCapability\.ps1' })
        $preflightSteps.Count | Should -Be 1 -Because 'RISK-10: one gate, one named step'

        $preflightIndex = [array]::IndexOf($names, $preflightSteps[0].Name)
        foreach ($later in @('scripts/validate\.ps1', 'Run-UnitTests\.ps1[^\r\n]*-TestResultPath')) {
            $laterStep = @($steps | Where-Object { $_.Body -match $later })[0]
            $laterStep | Should -Not -BeNullOrEmpty
            $preflightIndex |
                Should -BeLessThan ([array]::IndexOf($names, $laterStep.Name)) -Because "the capability gate must run before '$later'"
        }

        # Both matrix legs run every step, and the matrix is what makes this a Windows and Linux
        # proof rather than a Linux one.
        $workflowText | Should -Match 'ubuntu-latest'
        $workflowText | Should -Match 'windows-latest'

        # The gate inventory is the contract CiGates.Tests.ps1 reads; a gate missing from it is
        # a gate nobody recorded.
        $note = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/design-notes/project/ci-gates.design.md') -Raw
        $note | Should -Match '`gate:review-schema-capability`'
        $note | Should -Match 'Test-ReviewSchemaCapability'
    }
}

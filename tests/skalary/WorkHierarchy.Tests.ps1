#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Work hierarchy synchronization' {
    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        Import-Module (Join-Path $repoRoot 'scripts/skalary/WorkHierarchy.psm1') -Force
        Import-Module (Join-Path $repoRoot 'scripts/skalary/GitHubWorkHierarchy.psm1') -Force
        $goldenPath = Join-Path $PSScriptRoot 'fixtures/work-hierarchy/projection.golden.json'

        $newFixture = {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('work-hierarchy-' + [guid]::NewGuid().ToString('N'))
            $epicDir = Join-Path $root 'docs/implementation-plans/epics/2026-01-01-a1b2c3-fixture'
            $firstDir = Join-Path $root 'docs/implementation-plans/2026-01-01-111aaa-first'
            $secondDir = Join-Path $root 'docs/implementation-plans/2026-01-02-222bbb-second'
            foreach ($path in @($epicDir, (Join-Path $firstDir 'assets'), (Join-Path $secondDir 'assets'))) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }

            Set-Content -LiteralPath (Join-Path $epicDir 'epic.md') -Encoding utf8NoBOM -Value @'
# a1b2c3: Fixture epic
<!-- epic-id: a1b2c3 -->

## Goal

Ship the fixture hierarchy.

## Child plans

Generated content is not projection authority.
'@
            Set-Content -LiteralPath (Join-Path $firstDir 'plan.md') -Encoding utf8NoBOM -Value @'
# 111aaa: First child
<!-- plan-id: 111aaa -->
<!-- epic: a1b2c3 -->

## Phase 1: Establish behavior

- [x] 1.1 Build the first slice (REQ-1) `S`
'@
            Set-Content -LiteralPath (Join-Path $firstDir 'assets/intent.md') -Encoding utf8NoBOM -Value @'
# Intent

## Goal

Deliver the first slice.

## Desired outcome

The first slice works.

## Success signals

- First signal.

## Non-goals

- No extras.

## Definition of done

- First done.
'@
            Set-Content -LiteralPath (Join-Path $firstDir 'assets/requirements.md') -Encoding utf8NoBOM -Value @'
# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | First requirement. | First acceptance. `test:first` | 1.1 |
'@
            Set-Content -LiteralPath (Join-Path $firstDir 'assets/risks.md') -Encoding utf8NoBOM -Value @'
# Risks

| ID | Risk |
|----|------|
| RISK-1 | Fixture risk. |
'@
            Set-Content -LiteralPath (Join-Path $firstDir 'assets/decisions.md') -Encoding utf8NoBOM -Value @'
# Decisions

- Keep the fixture small.
'@

            Set-Content -LiteralPath (Join-Path $secondDir 'plan.md') -Encoding utf8NoBOM -Value @'
# 222bbb: Second child
<!-- plan-id: 222bbb -->
<!-- epic: a1b2c3 -->
<!-- depends-on: 111aaa -->

## Phase 1: Extend behavior

- [ ] 1.1 Build the second slice (REQ-1) `M`
'@
            Set-Content -LiteralPath (Join-Path $secondDir 'assets/intent.md') -Encoding utf8NoBOM -Value @'
# Intent

## Goal

Deliver the second slice.

## Desired outcome

The second slice works.

## Success signals

- Second signal.

## Non-goals

- No extras.

## Definition of done

- Second done.
'@
            Set-Content -LiteralPath (Join-Path $secondDir 'assets/requirements.md') -Encoding utf8NoBOM -Value @'
# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Second requirement. | Second acceptance. `test:second` | 1.1 |
'@
            Set-Content -LiteralPath (Join-Path $secondDir 'assets/risks.md') -Encoding utf8NoBOM -Value @'
# Risks

| ID | Risk |
|----|------|
| RISK-1 | Fixture risk. |
'@
            Set-Content -LiteralPath (Join-Path $secondDir 'assets/decisions.md') -Encoding utf8NoBOM -Value @'
# Decisions

- Keep the fixture small.
'@
            return $root
        }

        $newMappingEntry = {
            param($Desired, [int]$Number, [string]$ProviderId, [string]$Title, [string]$ManagedBody)
            [pscustomobject][ordered]@{
                kind = [string]$Desired.kind
                number = $Number
                providerId = $ProviderId
                titleHash = Get-WorkHierarchyDigest -Value $Title
                managedBodyHash = Get-WorkHierarchyDigest -Value $ManagedBody
            }
        }

        $newRemoteIssue = {
            param($Desired, [int]$Number, [string]$ProviderId, [string]$Title, [string]$Body)
            [pscustomobject][ordered]@{
                kind = 'issue'
                providerId = $ProviderId
                nodeId = "I_$ProviderId"
                number = $Number
                title = $Title
                body = $Body
                state = 'open'
                url = "https://github.example/issues/$Number"
            }
        }
    }

    Context 'test:WorkHierarchy.Projection' {
        It 'produces stable byte-identical ordered projection output' {
            $fixture = & $newFixture
            try {
                $first = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture |
                    ConvertTo-WorkHierarchyProjectionJson
                $second = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture |
                    ConvertTo-WorkHierarchyProjectionJson

                $first | Should -BeExactly $second
                $first | Should -BeExactly (Get-Content -LiteralPath $goldenPath -Raw).TrimEnd()
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }

        It 'projects hierarchy, dependencies, phases, purpose, and acceptance content' {
            $fixture = & $newFixture
            try {
                $projection = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture

                $projection.epic.localId | Should -Be 'a1b2c3'
                @($projection.children.localId) | Should -Be @('111aaa', '222bbb')
                @($projection.relations | Where-Object kind -eq 'parent-child') | Should -HaveCount 2
                $dependency = $projection.relations | Where-Object kind -eq 'depends-on'
                $dependency.sourceId | Should -Be '222bbb'
                $dependency.targetId | Should -Be '111aaa'
                $projection.children[1].managedBody | Should -Match '(?m)^## Purpose$'
                $projection.children[1].managedBody | Should -Match '(?m)^## Phases$'
                $projection.children[1].managedBody | Should -Match '(?m)^## Acceptance criteria$'
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }

        It 'refuses ambiguous canonical child identities before emission' {
            $fixture = & $newFixture
            try {
                $duplicate = Join-Path $fixture 'docs/implementation-plans/2026-01-03-333ccc-duplicate'
                New-Item -ItemType Directory -Path $duplicate -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $duplicate 'plan.md') -Encoding utf8NoBOM -Value @'
# 111aaa: Duplicate identity
<!-- plan-id: 111aaa -->
<!-- epic: a1b2c3 -->

## Phase 1: Duplicate

- [ ] 1.1 Duplicate identity `S`
'@

                { New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture } |
                    Should -Throw "*more than one child plan with canonical id '111aaa'*"

                Remove-Item -LiteralPath $duplicate -Recurse -Force
                $collision = Join-Path $fixture 'docs/implementation-plans/2026-01-03-444ddd-collision'
                New-Item -ItemType Directory -Path $collision -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $collision 'plan.md') -Encoding utf8NoBOM -Value @'
# a1b2c3: Epic identity collision
<!-- plan-id: a1b2c3 -->
<!-- epic: a1b2c3 -->

## Phase 1: Collision

- [ ] 1.1 Collide with epic identity `S`
'@

                { New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture } |
                    Should -Throw "*have the same canonical id*"
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }
    }

    Context 'test:WorkHierarchy.GitHubAdapter' {
        It 'uses the narrow read boundary and inert gh argument arrays' {
            $calls = [System.Collections.Generic.List[object]]::new()
            $runner = {
                param([string[]]$Arguments)
                $calls.Add(@($Arguments))
                [pscustomobject]@{
                    ExitCode = 0
                    Output = '{"id":42,"node_id":"I_node","number":7,"title":"Remote","body":"body","state":"open","html_url":"https://github.example/issues/7"}'
                    Error = 'benign warning on stderr'
                }
            }.GetNewClosure()
            $provider = New-GitHubWorkHierarchyProvider -CommandRunner $runner

            $issue = Invoke-WorkHierarchyProviderRead -Provider $provider -Request ([pscustomobject]@{
                kind = 'issue'
                repository = 'owner/repo'
                number = 7
            })

            $provider.name | Should -Be 'github'
            $calls[0] | Should -Be @('api', 'repos/owner/repo/issues/7')
            $issue.providerId | Should -Be '42'
            $issue.nodeId | Should -Be 'I_node'
            $issue.title | Should -Be 'Remote'
        }

        It 'maps one provider-neutral create operation to gh api' {
            $calls = [System.Collections.Generic.List[object]]::new()
            $runner = {
                param([string[]]$Arguments)
                $calls.Add(@($Arguments))
                [pscustomobject]@{
                    ExitCode = 0
                    Output = '{"id":43,"node_id":"I_created","number":8,"title":"Created","body":"managed","state":"open","html_url":"https://github.example/issues/8"}'
                }
            }.GetNewClosure()
            $provider = New-GitHubWorkHierarchyProvider -CommandRunner $runner

            $created = Invoke-WorkHierarchyProviderWrite -Provider $provider -Operation ([pscustomobject]@{
                kind = 'create-issue'
                repository = 'owner/repo'
                title = 'Created'
                body = 'managed'
            })

            $calls[0] | Should -Be @(
                'api', '--method', 'POST', 'repos/owner/repo/issues',
                '-f', 'title=Created', '-f', 'body=managed'
            )
            $created.number | Should -Be 8
        }

        It 'refuses malformed GitHub issue results with an adapter diagnostic' {
            $runner = {
                param([string[]]$Arguments)
                [pscustomobject]@{
                    ExitCode = 0
                    Output = '{"number":7}'
                }
            }
            $provider = New-GitHubWorkHierarchyProvider -CommandRunner $runner

            {
                Invoke-WorkHierarchyProviderRead -Provider $provider -Request ([pscustomobject]@{
                    kind = 'issue'
                    repository = 'owner/repo'
                    number = 7
                })
            } | Should -Throw "*missing required property 'id'*"
        }

        It 'refuses pull requests returned by the issues endpoint' {
            $runner = {
                param([string[]]$Arguments)
                [pscustomobject]@{
                    ExitCode = 0
                    Output = '{"id":42,"node_id":"PR_node","number":7,"title":"PR","body":"body","state":"open","html_url":"https://github.example/pull/7","pull_request":{"url":"https://api.github.example/pulls/7"}}'
                }
            }
            $provider = New-GitHubWorkHierarchyProvider -CommandRunner $runner

            {
                Invoke-WorkHierarchyProviderRead -Provider $provider -Request ([pscustomobject]@{
                    kind = 'issue'
                    repository = 'owner/repo'
                    number = 7
                })
            } | Should -Throw '*pull request where an issue was required*'
        }

        It 'maps hierarchy and dependency reads to bounded gh api requests' {
            $calls = [System.Collections.Generic.List[object]]::new()
            $runner = {
                param([string[]]$Arguments)
                $calls.Add(@($Arguments))
                [pscustomobject]@{
                    ExitCode = 0
                    Output = '[{"id":42,"node_id":"I_node","number":7,"title":"Remote","body":"body","state":"open","html_url":"https://github.example/issues/7"}]'
                }
            }.GetNewClosure()
            $provider = New-GitHubWorkHierarchyProvider -CommandRunner $runner

            $subIssues = @(Invoke-WorkHierarchyProviderRead -Provider $provider -Request ([pscustomobject]@{
                kind = 'sub-issues'
                repository = 'owner/repo'
                number = 2
            }))
            $blockedBy = @(Invoke-WorkHierarchyProviderRead -Provider $provider -Request ([pscustomobject]@{
                kind = 'blocked-by'
                repository = 'owner/repo'
                number = 7
            }))

            $calls[0] | Should -Be @('api', 'repos/owner/repo/issues/2/sub_issues?per_page=100&page=1')
            $calls[1] | Should -Be @('api', 'repos/owner/repo/issues/7/dependencies/blocked_by?per_page=100&page=1')
            $subIssues[0].providerId | Should -Be '42'
            $blockedBy[0].providerId | Should -Be '42'
        }

        It 'refuses relation results with more than 100 issues' {
            $issue = [pscustomobject]@{
                id = 42
                node_id = 'I_node'
                number = 7
                title = 'Remote'
                body = 'body'
                state = 'open'
                html_url = 'https://github.example/issues/7'
            }
            $firstPage = ConvertTo-Json -InputObject @(1..100 | ForEach-Object { $issue }) -Depth 5 -Compress
            $overflowPage = ConvertTo-Json -InputObject @($issue) -Depth 5 -Compress
            $runner = {
                param([string[]]$Arguments)
                [pscustomobject]@{
                    ExitCode = 0
                    Output = $(if ($Arguments[1] -match 'page=101') { $overflowPage } else { $firstPage })
                }
            }.GetNewClosure()
            $provider = New-GitHubWorkHierarchyProvider -CommandRunner $runner

            {
                Invoke-WorkHierarchyProviderRead -Provider $provider -Request ([pscustomobject]@{
                    kind = 'sub-issues'
                    repository = 'owner/repo'
                    number = 2
                })
            } | Should -Throw "*relation read 'sub-issues' returned more than 100 issues*"
        }
    }

    Context 'test:WorkHierarchy.DryRunAndConfirmation' {
        It 'defers in-epic dependency links until newly created issues exist' {
            $fixture = & $newFixture
            try {
                $projection = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture
                $mapping = [pscustomobject][ordered]@{
                    schema = 'skalary/work-hierarchy-mapping@1'
                    repository = 'Owner/Repo'
                    items = [ordered]@{}
                }
                $provider = New-WorkHierarchyProvider -Name github -Read {
                    throw 'an empty mapping must not query the provider'
                } -Write { throw 'dry run must not write' }

                $dryRun = New-WorkHierarchyDryRun `
                    -Projection $projection `
                    -Repository 'owner/repo' `
                    -Mapping $mapping `
                    -Provider $provider

                @($dryRun.actions | Where-Object kind -eq 'create') | Should -HaveCount 3
                @($dryRun.actions | Where-Object kind -eq 'link') | Should -HaveCount 3
                @($dryRun.actions | Where-Object kind -eq 'refuse') | Should -HaveCount 0
                ($dryRun.actions | Where-Object subject -eq 'relation:depends-on:222bbb:111aaa').reason |
                    Should -Be 'relation-missing-after-create'
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }

        It 'reads mapped state without writes and renders ordered create, link, and no-op actions' {
            $fixture = & $newFixture
            try {
                $projection = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture
                $epic = $projection.epic
                $first = $projection.children[0]
                $mapping = [pscustomobject][ordered]@{
                    schema = 'skalary/work-hierarchy-mapping@1'
                    repository = 'owner/repo'
                    items = [ordered]@{
                        'a1b2c3' = & $newMappingEntry $epic 10 '100' $epic.title $epic.managedBody
                        '111aaa' = & $newMappingEntry $first 11 '101' $first.title $first.managedBody
                    }
                }
                $remote = @{
                    10 = & $newRemoteIssue $epic 10 '100' $epic.title $epic.managedBody
                    11 = & $newRemoteIssue $first 11 '101' $first.title $first.managedBody
                }
                $reads = [System.Collections.Generic.List[string]]::new()
                $writes = [System.Collections.Generic.List[object]]::new()
                $read = {
                    param($Request)
                    $reads.Add("$($Request.kind):$($Request.number)")
                    switch ($Request.kind) {
                        'issue' { return $remote[[int]$Request.number] }
                        'sub-issues' { return @($remote[11]) }
                        'blocked-by' { return @() }
                    }
                }.GetNewClosure()
                $write = {
                    param($Operation)
                    $writes.Add($Operation)
                }.GetNewClosure()
                $provider = New-WorkHierarchyProvider -Name github -Read $read -Write $write

                $dryRun = New-WorkHierarchyDryRun `
                    -Projection $projection `
                    -Repository 'owner/repo' `
                    -Mapping $mapping `
                    -Provider $provider
                $text = ConvertTo-WorkHierarchyDryRunText -DryRun $dryRun

                $writes | Should -HaveCount 0
                $reads | Should -Be @('issue:11', 'issue:10', 'sub-issues:10')
                @($dryRun.actions.kind) | Should -Be @('no-op', 'no-op', 'create', 'no-op', 'link', 'link')
                $dryRun.hasChanges | Should -BeTrue
                $dryRun.hasRefusals | Should -BeFalse
                $text | Should -Match '(?m)^\[CREATE\] item:222bbb - mapping-missing$'
                $text | Should -Match '(?m)^\[LINK\] relation:depends-on:222bbb:111aaa - relation-missing-after-create$'
                $text | Should -Match "(?m)^Action digest: $($dryRun.actionDigest)$"

                $repeat = New-WorkHierarchyDryRun `
                    -Projection $projection `
                    -Repository 'owner/repo' `
                    -Mapping $mapping `
                    -Provider $provider
                $repeat.actionDigest | Should -BeExactly $dryRun.actionDigest
                (ConvertTo-Json $repeat.actions -Depth 30) |
                    Should -BeExactly (ConvertTo-Json $dryRun.actions -Depth 30)
                $writes | Should -HaveCount 0
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }

        It 'updates only a clean baseline and preserves unmanaged body text' {
            $fixture = & $newFixture
            try {
                $projection = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture
                $first = $projection.children[0]
                $oldTitle = 'Earlier first child'
                $oldManagedBody = $first.managedBody.Replace('Deliver the first slice.', 'Deliver the earlier slice.')
                $mapping = [pscustomobject][ordered]@{
                    schema = 'skalary/work-hierarchy-mapping@1'
                    repository = 'owner/repo'
                    items = [ordered]@{
                        '111aaa' = & $newMappingEntry $first 11 '101' $oldTitle $oldManagedBody
                    }
                }
                $remote = & $newRemoteIssue $first 11 '101' $oldTitle "human prefix`n$oldManagedBody`nhuman suffix"
                $provider = New-WorkHierarchyProvider -Name github -Read ({
                    param($Request)
                    return $remote
                }.GetNewClosure()) -Write { throw 'dry run must not write' }

                $dryRun = New-WorkHierarchyDryRun `
                    -Projection $projection `
                    -Repository 'owner/repo' `
                    -Mapping $mapping `
                    -Provider $provider
                $update = $dryRun.actions | Where-Object subject -eq 'item:111aaa'

                $update.kind | Should -Be 'update'
                $update.detail.title | Should -Be $first.title
                $update.detail.body | Should -Be "human prefix`n$($first.managedBody)`nhuman suffix"
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }

        It 'refuses remote managed edits and malformed markers' {
            $fixture = & $newFixture
            try {
                $projection = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture
                $first = $projection.children[0]
                $mapping = [pscustomobject][ordered]@{
                    schema = 'skalary/work-hierarchy-mapping@1'
                    repository = 'owner/repo'
                    items = [ordered]@{
                        '111aaa' = & $newMappingEntry $first 11 '101' $first.title $first.managedBody
                    }
                }
                $remoteEdited = $first.managedBody.Replace('First acceptance.', 'Human remote edit.')
                $remote = & $newRemoteIssue $first 11 '101' $first.title $remoteEdited
                $provider = New-WorkHierarchyProvider -Name github -Read ({
                    param($Request)
                    return $remote
                }.GetNewClosure()) -Write { throw 'dry run must not write' }

                $editedRun = New-WorkHierarchyDryRun `
                    -Projection $projection `
                    -Repository 'owner/repo' `
                    -Mapping $mapping `
                    -Provider $provider
                ($editedRun.actions | Where-Object subject -eq 'item:111aaa').reason |
                    Should -Be 'managed-body-remote-change'

                $remote.body = '<!-- skalary:work-hierarchy:plan:111aaa:start -->broken'
                $markerRun = New-WorkHierarchyDryRun `
                    -Projection $projection `
                    -Repository 'owner/repo' `
                    -Mapping $mapping `
                    -Provider $provider
                ($markerRun.actions | Where-Object subject -eq 'item:111aaa').reason |
                    Should -Be 'duplicate-or-nested-marker'
                $markerRun.hasRefusals | Should -BeTrue

                $remote.body = "$($first.managedBody)`n<!-- skalary:work-hierarchy:plan:111aaa:bogus -->"
                $extraMarkerRun = New-WorkHierarchyDryRun `
                    -Projection $projection `
                    -Repository 'owner/repo' `
                    -Mapping $mapping `
                    -Provider $provider
                ($extraMarkerRun.actions | Where-Object subject -eq 'item:111aaa').reason |
                    Should -Be 'malformed-marker'
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }

        It 'keeps mapping refusals in parent-then-child item order' {
            $fixture = & $newFixture
            try {
                $projection = New-WorkHierarchyProjection -Epic a1b2c3 -RepoRoot $fixture
                $first = $projection.children[0]
                $mapping = [pscustomobject][ordered]@{
                    schema = 'skalary/work-hierarchy-mapping@1'
                    repository = 'owner/repo'
                    items = [ordered]@{
                        '111aaa' = [pscustomobject]@{
                            kind = $first.kind
                            number = 11
                            providerId = 'invalid'
                            titleHash = Get-WorkHierarchyDigest $first.title
                            managedBodyHash = Get-WorkHierarchyDigest $first.managedBody
                        }
                    }
                }
                $provider = New-WorkHierarchyProvider -Name github -Read {
                    throw 'invalid mapping identity must be refused before remote reads'
                } -Write { throw 'dry run must not write' }

                $dryRun = New-WorkHierarchyDryRun `
                    -Projection $projection `
                    -Repository 'owner/repo' `
                    -Mapping $mapping `
                    -Provider $provider

                @($dryRun.actions | Select-Object -First 3 | ForEach-Object subject) |
                    Should -Be @('item:a1b2c3', 'item:111aaa', 'item:222bbb')
                ($dryRun.actions | Where-Object subject -eq 'item:111aaa').kind | Should -Be 'refuse'
            }
            finally {
                Remove-Item -LiteralPath $fixture -Recurse -Force
            }
        }
    }
}

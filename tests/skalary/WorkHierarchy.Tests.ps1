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
    }
}

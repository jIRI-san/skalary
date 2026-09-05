# SI lifecycle

Use this guide only after `/si` is invoked.

1. Invoke installed `Invoke-SiLifecycle.ps1 -Operation Surface -RepoRoot .` with bound arguments. It
   fetches and pins authoritative `origin/main` and returns metadata only. Select or resume a surfaced
   due; never open SI state or run files directly, and stop on explicit Surface degradation.
2. Create a detached worktree at the returned pinned OID when the fixed branch is absent, or at the
   surfaced fixed-branch head when present. Run every later resolver and lifecycle command with that
   worktree as `-RepoRoot`. `Begin` creates or resumes `si/<due-id>` before the first state mutation.
   Resume from any other checkout is refused.
3. Resolve and pin the source commit before reading input. Pass the plan reference and pinned OID to
   installed `Get-SiHarvest.ps1`.
4. Rank the wrapped harvest, then invoke `Get-SiHarvest.ps1 -IssueReceipt` with bound `-DueId`, `-RunId`,
   and `-CandidateJson`. Use only returned candidate IDs, digest, and receipt. Write a temporary closed
   `{ "candidates": [...] }` input with that exact ranking and invoke
   `Invoke-SiLifecycle.ps1 -Operation Begin` with bound `-DueId`, `-RunId`, `-Receipt`, and `-InputPath`.
   Stop on freshness, replay-identity, or candidate-equality refusal.
5. After the operator chooses, write exactly one accepted, declined, or deferred choice per receipt
   candidate to a temporary closed `{ "choices": [...] }` input with `proposalPr: null`. Invoke
   `Invoke-SiLifecycle.ps1 -Operation RecordChoices` with bound arguments. Omitted, extra, duplicate,
   fabricated, stale, or rewritten input is a refusal.
6. Commit only lifecycle-managed `docs/self-improvement/**` changes and retain that commit as
   `lifecycleHeadOid`; proposal edits descend from it and may not alter state paths. Declining all
   candidates still preserves the durable ranked set and outcome for the state-only record PR.

# SI Lifecycle State Machine

The plugin-canonical `plugins/self-improvement/scripts/Invoke-SiLifecycle.ps1`, installed as `skills/si/scripts/Invoke-SiLifecycle.ps1`, is the only transition writer. Every interactive action starts by fetching and pinning `origin/main`; local state deltas are refused unless they match the deterministic correlation branch being resumed.

Correlation is the due ID. Every outcome uses one fixed branch identity `si/<due-id>`; proposal and record-only runs differ in content, not identity. Deleted branches recreate that name from fresh main plus the immutable run. Repair does not require a parseable due: Inspect returns canonical observation bytes, Snapshot persists them, `observation-id=sha256('si-repair-observation-v1' UTF8 || exact observation bytes)`, and its branch is `si-repair/<observation-id>`.

| Observed authoritative/remote state | Transition |
|---|---|
| pending, no branch/PR | create fixed due branch from pinned main before mutation |
| pending, operator deferred | record required `deferUntilUtc` in a state-only PR; due remains pending and is hidden until eligible after merge |
| pending, declined before ranking | complete explicit declined-before-ranking run in a state-only PR, then consume on merge |
| pending, harvest has no candidates | complete no-candidate run in a state-only PR, then consume on merge |
| branch exists, no PR | resume branch; merge current main, re-derive, and trusted-validate before push |
| PR open/draft | resume the same fixed branch and PR; never create another while it is open |
| PR closed unmerged | retain audit; reopen when supported or create another PR from the same fixed branch after trusted sync |
| branch deleted without merged PR | recreate the same fixed branch from fresh main plus immutable run |
| PR merged and consumed state present | terminal complete |
| PR merged but due missing run / run missing manifest transition | integrity failure; corruption-independent repair branch required, no silent retry |
| due absent but open PR exists | stale PR integrity finding; never resurrect automatically |
| concurrent different-due PR merged first | fetch, merge current main, re-derive manifest transition, rerun trusted validation before push |

Candidate choices are accepted only with a resolver receipt binding the source snapshot and complete 0-5 ranked set. Omitted, extra, duplicate, fabricated, stale, or rewritten candidates are refusal states. `proposal-pending`, PR URL, completed run, and consumed transition are separate recoverable commits; each goes through trusted synchronization, which owns the push and verifies the remote PR head equals the current process's validated OID. Operator completion freshly fetches the live OID, validates that same OID, and passes it as `expectedHeadOid` without an intervening commit.
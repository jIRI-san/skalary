## Learnings Capture
Phase: 1
- [7.3] [trigger:overflow-summary] Folded 9 additional learnings into this summary.


## Learnings Capture
Phase: 2
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.


## Learnings Capture
Phase: 3
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.

No entries for this phase.

## Learnings Capture
Phase: 4
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.


## Learnings Capture
Phase: 5
No entries for this phase.
No entries for this phase.
No entries for this phase.
No entries for this phase.


## Learnings Capture
Phase: 6
No entries for this phase.
No entries for this phase.
No entries for this phase.


## Learnings Capture
Phase: 7
No entries for this phase.


## Learnings Capture
Phase: 8

- [8.1] [trigger:reusable-pattern] A prose injection fence is only as strong as its closing token: storage-time sanitizers strip the entry grammar, not the fence, so any wrapper around model-authored text needs an unpredictable per-read id and a pre-wrap scan for its own marker.
- [8.2] [trigger:reusable-pattern] Any git-derived path allowlist must pass --no-renames and judge the literal path before resolving symlinks: rename detection hides the source path, and a destination-only verdict turns symlink resolution from a restriction into a laundering channel.
- [8.4] [trigger:reusable-pattern] A structural test over a shared guide must be scoped to the section it governs: sibling features in the same file repeat the same stock phrases, so a whole-file match passes with the rule under test deleted.

## Learnings Capture
Phase: 9

- [9.1] [trigger:reusable-pattern] Generated mirrors of marker state must be rebuilt for every affected owner, not just the invocation target, or the losing side goes stale.
- [9.2] [trigger:reusable-pattern] A skill's scripts must resolve their assets relative to the installed skill folder; repo-layout paths only work while dogfooding.
- [9.3] [trigger:reusable-pattern] Pester assertions that read a property off a filtered array fail only under the strict-mode suite runner; pipe through Select-Object -First 1.

## Learnings Capture
Phase: 10

- [10.1] [trigger:reusable-pattern] Any plugin payload edit must regenerate marketplace.json AND registry.json in the same commit; Pester alone does not catch the drift.
- [10.2] [trigger:reusable-pattern] A content stripper feeding a security/bootstrap gate must fail closed on malformed input; blanking the remainder turns an authoring slip into a silent gate bypass.
- [10.3] [trigger:reusable-pattern] A machine-readable declaration is only worth its truth: assert the declared owner/helper exists in the declaring plugin's payload, or the manifest becomes prose that passes gates.

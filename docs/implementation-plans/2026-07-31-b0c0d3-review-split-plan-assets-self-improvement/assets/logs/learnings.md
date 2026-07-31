## Learnings Capture
Phase: 1
- [4.6] [trigger:overflow-summary] Folded 4 additional learnings into this summary.


## Learnings Capture
Phase: 2
No entries for this phase.
No entries for this phase.


## Learnings Capture
Phase: 3
No entries for this phase.
No entries for this phase.
No entries for this phase.

No entries for this phase.

## Learnings Capture
Phase: 4
No entries for this phase.


## Learnings Capture
Phase: 5

- [5.1] [trigger:reusable-pattern] PowerShell functions unroll single-element arrays: return , @(...) whenever a caller indexes or counts the result
- [5.1] [trigger:reusable-pattern] Any git file-list consumed by a script must use -z: the default output C-quotes non-ASCII paths and silently loses them

## Learnings Capture
Phase: 6

- [6.3] [trigger:reusable-pattern] Plugin payload edits bump plugin.json versions via Sync-PluginScripts, so any test pinning a literal plugin version breaks; assert derived versions instead.

## Learnings Capture
Phase: 7

- [7.2] [trigger:reusable-pattern] PowerShell variable names are case-insensitive, so a local $plan silently overwrites the -Plan parameter and its mismatch guard; name locals resolvedX when they derive from a parameter.
- [7.3] [trigger:reusable-pattern] Writing a literal .github/skills/<other-skill>/scripts/<file>.ps1 path into a payload file makes Sync-PluginScripts bundle that script into the referencing plugin; name the script without the installed path when only mentioning it.

## Learnings Capture
Phase: 8

- [8.1] [trigger:reusable-pattern] A prose injection fence is only as strong as its closing token: storage-time sanitizers strip the entry grammar, not the fence, so any wrapper around model-authored text needs an unpredictable per-read id and a pre-wrap scan for its own marker.
- [8.2] [trigger:reusable-pattern] Any git-derived path allowlist must pass --no-renames and judge the literal path before resolving symlinks: rename detection hides the source path, and a destination-only verdict turns symlink resolution from a restriction into a laundering channel.
- [8.4] [trigger:reusable-pattern] A structural test over a shared guide must be scoped to the section it governs: sibling features in the same file repeat the same stock phrases, so a whole-file match passes with the rule under test deleted.

## Learnings Capture
Phase: 9

- [9.1] [trigger:reusable-pattern] Generated mirrors of marker state must be rebuilt for every affected owner, not just the invocation target, or the losing side goes stale.

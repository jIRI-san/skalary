## Learnings Capture
Phase: 1

- [1.4] [trigger:reusable-pattern] Pester suites that Import-Module PlanState.psm1 -Force unload it from the calling session, so any crosscheck harness must parse all evidence markers before the first Invoke-Pester call; also, evidence test filters must anchor on the marker boundary or a substring test id (planstate- vs getplanstate-) inflates the case count.

## Learnings Capture
Phase: 2

- [2.1] [trigger:reusable-pattern] Structural guide tests must bind the documented contract to the script that produces it (gate section list <-> New-Plan scaffold), otherwise a rename silently disarms the gate.
- [2.3] [trigger:reusable-pattern] Any new plan.md parsing must read raw lines, not the fence-stripped copy, whenever the captured text is shown to a human or checked for content.

## Learnings Capture
Phase: 3

No entries for this phase.

## Learnings Capture
Phase: 4

- [4.6] [trigger:reusable-pattern] Deterministic formatters need a composite ordinal sort key: PowerShell Sort-Object is neither stable nor ordinal, so multi-property sorts leak input order and locale.

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

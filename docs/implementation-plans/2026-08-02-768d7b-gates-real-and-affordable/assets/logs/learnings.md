## Learnings Capture
Phase: 1

No entries for this phase.

## Learnings Capture
Phase: 2

- [2.1] [trigger:reusable-pattern] A fixture rewrite loses coverage where the old fixture supplied state implicitly (.github payload, shared commit SHA); assert the precondition is non-empty rather than trusting the loop over it.

## Learnings Capture
Phase: 5

- [5.2] [trigger:reusable-pattern] Pester splits failures across FailedCount, FailedBlocksCount and FailedContainersCount; any runner that decides on FailedCount alone reports green for a test file that never loaded. Use Pester's own verdict, or sum all three.

## Learnings Capture
Phase: 6

- [6.2] [trigger:reusable-pattern] Sync-PluginScripts bundles a new script by closure but plugin.json files() is hand-maintained, so the copy is bundled and never installed; the manifest-coverage test only checked .md and missed it. Extended it to .ps1/.psm1.
- [6.3] [trigger:reusable-pattern] A gate added at one entry point is not a gate: check every caller that performs the same check before claiming the guarantee, and give them one shared decision rather than two agreeing copies.

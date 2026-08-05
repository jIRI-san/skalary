## Learnings Capture
Phase: 1
- [1.3] [trigger:overflow-summary] Folded 2 additional learnings into this summary.


## Learnings Capture
Phase: 2

- [2.3] [trigger:reusable-pattern] A gate whose threshold lives in the document the measuring run rewrites can be zeroed by omitting a parameter; pin thresholds in a file no run writes and cross-check set equality both ways.

## Learnings Capture
Phase: 5

- [5.2] [trigger:reusable-pattern] Pester splits failures across FailedCount, FailedBlocksCount and FailedContainersCount; any runner that decides on FailedCount alone reports green for a test file that never loaded. Use Pester's own verdict, or sum all three.

## Learnings Capture
Phase: 6

- [6.2] [trigger:reusable-pattern] Sync-PluginScripts bundles a new script by closure but plugin.json files() is hand-maintained, so the copy is bundled and never installed; the manifest-coverage test only checked .md and missed it. Extended it to .ps1/.psm1.
- [6.3] [trigger:reusable-pattern] A gate added at one entry point is not a gate: check every caller that performs the same check before claiming the guarantee, and give them one shared decision rather than two agreeing copies.

## Learnings Capture
Phase: 7

- [7.2] [trigger:reusable-pattern] PowerShell enumerates statement output, so '$keys = if (...) { @(x) } else { @(y) } collapses a one-element array to a scalar; the string then indexes by character and .Length is the character count. Assign inside each branch when the value must stay an array.

## Learnings Capture
Phase: 3

- [3.1] [trigger:reusable-pattern] A determinism test that compares two copies of one cached artifact proves nothing about the build that produced it; discard the cache between the two builds.
- [3.3] [trigger:reusable-pattern] An order-independence test needs a paired non-blindness check that runs each probe's own body over a tainted input; run-to-run equality alone is satisfied by a probe that reports a constant.

## Learnings Capture
Phase: 4

- [4.3] [trigger:reusable-pattern] A gate that measures a command spanning several processes needs the clock cleared before every exit, not only the successful one: a clock stranded by a red run is charged to the next run as time it never spent.
- [4.3] [trigger:reusable-pattern] Under Set-StrictMode -Version Latest a missing key read with dot notation is terminating, so a config typo exits 1 - the code reserved for 'tests failed'. Name every field in the guard before reading any of it.

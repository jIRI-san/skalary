## Learnings Capture
Phase: 1

No entries for this phase.

## Learnings Capture
Phase: 2

- [2.3] [trigger:reusable-pattern] Pester mocks for external npm did not intercept npm ci/install (real npm ran ~20s); mock the script's own restore helper functions (Invoke-NpmRestore/Invoke-DotnetRestore) instead - reliable and fast. Avoid angle brackets in It names (Pester scriptblock-creates names containing hyphens like x-y, throwing ParseException).

## Learnings Capture
Phase: 5

- [5.2] [trigger:reusable-pattern] Extracted launcher dispatch into a side-effect-free, dot-sourceable library (autopilot-dispatch.ps1) so loop logic is unit-testable without launch.ps1's mandatory params (avoids the Pester mandatory-param prompt hang). Test scriptblock deps via .GetNewClosure() sharing a single hashtable for call-count/feed-path state.

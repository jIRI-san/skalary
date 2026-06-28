## Learnings Capture
Phase: 1

No entries for this phase.

## Learnings Capture
Phase: 2

- [2.3] [trigger:reusable-pattern] Pester mocks for external npm did not intercept npm ci/install (real npm ran ~20s); mock the script's own restore helper functions (Invoke-NpmRestore/Invoke-DotnetRestore) instead - reliable and fast. Avoid angle brackets in It names (Pester scriptblock-creates names containing hyphens like x-y, throwing ParseException).

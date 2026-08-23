## Learnings Capture
Phase: 1

- [1.1] [trigger:reusable-pattern] A production-installer fixture can keep its oracle independent by hashing manifest sources, auditing receipts and installed files separately, and comparing manifests to the generated registry as a second boundary.
- [1.1] [trigger:rework>1] Filesystem inventory oracles must use ordinal comparisons for both lookup keys and exclusion rules; PowerShell operators such as -in and -eq are case-insensitive by default.
- [1.2] [trigger:rework>1] Runtime-reference scanners must distinguish executable paths from PowerShell comments and Join-Path-relative bundled sidecars before widening a closed root grammar.

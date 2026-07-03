## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Med] gh Version pin unenforceable via winget/apt/brew and no checksum; resolved by explicit VersionPolicy (waza=exact+checksum, gh=floor+MinVersion, manager-signed) so the consumer branch is unambiguous.
- [1.2] [src:code-review] [sev:High] Test-SchemaCompat was defined+tested but never called in the run path (DESCRIPTION promised hard-fail on unverified schema). FIX: added Assert-WazaSchemaSupport (synthetic eval.yaml + waza migrate probe) and wired it into Invoke-EnsureEvalTools after waza resolves; verified live (1.2=>pass, 9.9=>throws).
- [1.2] [src:code-review] [sev:Med] SKIP catch branch added skip to skipped list but left decision.Action=install, so Tools output mislabeled a skipped tool as installed. FIX: reassign decision to a skip object before break (mirrors declined-approval path); also track wazaSkipped.
- [1.2] [src:code-review] [sev:Low] CheckUpdates param doc over-promised on-approval manifest pin-bump (not implemented). FIX: trimmed doc + newer-branch message to surface-only; pin-bump remains a separate reviewable change.

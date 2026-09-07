# Recent learning

Source plan: `7ce29c script-surface-cleanup-and-simplification`
Source commit: `a6dd95654019b606f036e2c2765a738ceeda8aa3`

## Lessons

- Replace historical implementation snapshots with bounded current-state absence tests when Git already preserves the retired bytes. — `tests/skalary/ArchitectureRetirement.Tests.ps1`
- Generated dogfood sync is copy-only, so retiring mapped payloads requires explicit deletion before regeneration. — `scripts/skalary/Sync-Dogfood.ps1`
- Structural simplification evidence should bind exact exports to parser-derived private-function and token-bearing-line reductions. — `tests/skalary/ScriptSurfaceCleanup.Tests.ps1`

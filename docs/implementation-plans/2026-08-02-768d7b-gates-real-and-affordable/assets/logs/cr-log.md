## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Med] Measure-SuiteProfile could overwrite the committed cost model with an all-zero profile from a subtree run; fixed by refusing the default output path for a partial scope and refusing to write when zero samples were recorded.
- [1.2] [src:code-review] [sev:Med] Regenerating the coverage baseline bypassed the removal-with-a-reason rule; Get-TestInventory now refuses to drop or shrink a recorded name unless it is already enumerated in removals.

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:High] Synthetic fixture dropped .github, making the install-rollback assertion vacuous; restored .github to the payload allowlist and added a non-empty guard.
- [2.1] [src:code-review] [sev:High] Per-fixture commits diverged, so Install-Plugin's registry-parity check silently stopped running; fixture commit timestamps pinned so every fixture shares one SHA.
- [2.1] [src:code-review] [sev:Med] SuiteFixture cases shared one mutable fixture and pinned .github absence as an invariant; each case now builds its own fixture and the allowlist assertion checks tracked files.
- [2.1] [src:code-review] [sev:Low] New-SkalaryFixtureRepo leaked its temp root when a git step failed mid-build; wrapped in try/catch cleanup.

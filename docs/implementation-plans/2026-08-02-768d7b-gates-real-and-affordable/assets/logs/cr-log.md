## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Med] Measure-SuiteProfile could overwrite the committed cost model with an all-zero profile from a subtree run; fixed by refusing the default output path for a partial scope and refusing to write when zero samples were recorded.
- [1.2] [src:code-review] [sev:Med] Regenerating the coverage baseline bypassed the removal-with-a-reason rule; Get-TestInventory now refuses to drop or shrink a recorded name unless it is already enumerated in removals.

# Recent learning

Source plan: `3a4498 simple-self-improvement`
Source commit: `281e1316458b821413d674065377d2df78a1e3f1`

## Lessons

- Post-write confinement must enumerate the worktree itself; a caller-supplied path list can omit an unintended mutation. — `scripts/skalary/Test-SiWriteScope.ps1`
- A canonical non-script plugin payload change needs its owner version bumped before catalogs are regenerated so consumers can discover the update. — `scripts/skalary/Sync-PluginScripts.ps1`

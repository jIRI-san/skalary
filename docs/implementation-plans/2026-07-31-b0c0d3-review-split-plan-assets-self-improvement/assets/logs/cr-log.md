## CR Capture
Phase: 1

- [1.7] [src:code-review] [sev:High] New-Plan -Force silently overwrote authored assets/ files: the -and -not $Force guard was dead code because the folder-exists throw already required -Force
- [1.7] [src:code-review] [sev:High] Get-PlanLayout flipped a legacy plan to the assets layout on mere assets/ directory presence, orphaning root logs/receipt mid-run
- [1.7] [src:code-review] [sev:Med] autopilot.agent.md archival gate and log fail-loud contract still read plan-root evidence.md/capture.md while writers moved to assets/
- [1.7] [src:code-review] [sev:Med] Test-Plan phase-budget-points marker threw on an out-of-range integer instead of taking the warn-and-default branch
- [1.7] [src:code-review] [sev:Med] Resolve-PlanSection malformed check accepted rows the requirement parser discards, so an asset could resolve with zero requirements
- [1.7] [src:code-review] [sev:Low] Migration-invariant tests could pass with zero assertions executed once the plan set changes

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:Med] intent gate hard-coded assets/intent.md; reworded to the layout-resolved path via Resolve-PlanAssetPath
- [2.1] [src:code-review] [sev:Med] guide referenced ./assets/intent-template.md before step 2.2 creates it; template reference deferred to 2.2
- [2.1] [src:code-review] [sev:Low] test alternation made the anchored branch dead and section list was unbound to the New-Plan scaffold; both fixed
- [2.2] [src:code-review] [sev:Med] template TBD assertion was satisfied by the instructional comment; now asserted per section body
- [2.2] [src:code-review] [sev:Low] ci block predicate said TBD-only while cip blocks on any TBD section; predicates aligned and bound by test
- [2.3] [src:code-review] [sev:High] detail capture read fence-stripped lines, silently dropping fenced operator commands; now captured from raw lines
- [2.3] [src:code-review] [sev:Med] unterminated blocks were dropped mid-file but accepted at EOF; flush now happens at every reset and an unindented step line always terminates
- [2.3] [src:code-review] [sev:Med] nested details truncated the block and only the first block was read; depth counting plus multi-block capture added
- [2.3] [src:code-review] [sev:Low] IsArchived derived from a possibly-relative RepoRoot and gate regex rejected bulleted labels; both fixed
- [2.4] [src:code-review] [sev:Med] handoff doc assertion used a file-wide (?s) span satisfied by an unrelated line; now anchored to the Handoff sentence
- [2.4] [src:code-review] [sev:Low] template example count asserted only >0, so losing an @human example passed silently; now pinned to exactly 2

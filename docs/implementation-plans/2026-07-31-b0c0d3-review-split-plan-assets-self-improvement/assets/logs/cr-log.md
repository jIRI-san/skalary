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

## CR Capture
Phase: 3

- [3.1] [src:code-review] [sev:Med] Get-PlanIndex resolved a wrong -RepoRoot to an empty index, silently unblocking the prior-art gate; now throws when docs/implementation-plans is absent

## CR Capture
Phase: 4

- [4.1] [src:code-review] [sev:High] Test-ModelAllowlist enumerated agents without -Force, silently skipping every hidden .github/agents dogfood copy; fixed and pinned with a hidden-path fixture.
- [4.6] [src:code-review] [sev:High] Build-ReviewReport sort had no total order (unstable, culture-sensitive Sort-Object), so tied entries followed reviewer return order; replaced with a composite ordinal key and pinned by a tie fixture.
- [4.4] [src:code-review] [sev:Med] Dispatch roster lived only in the guide, outside the allowlist gate; Test-ModelAllowlist now validates guide roster rows, the Pro-tier fallback, and denied vendors.

## CR Capture
Phase: 5

- [5.1] [src:code-review] [sev:High] Test helper returned an unrolled array: a one-file scope became a string and .Count threw under StrictMode; fixed with comma-wrapped return
- [5.1] [src:code-review] [sev:High] git --name-only C-quoted non-ASCII/quoted paths, so those files were silently dropped from the scope; all file-list calls now use -z with NUL splitting
- [5.1] [src:code-review] [sev:Med] Sort-Object -Unique deduped case-insensitively, losing distinct files on case-sensitive filesystems; replaced with an ordinal SortedSet
- [5.1] [src:code-review] [sev:Med] paths mode accepted paths outside the repo root and emitted a mangled relative path that resolved to nothing; now rejected loudly
- [5.1] [src:code-review] [sev:Med] Get-ChildItem without -Force skipped dot-prefixed files on Unix, making paths mode platform-dependent
- [5.1] [src:code-review] [sev:Med] smart mode resolved the default branch before checking for a first commit, so a fresh repo failed instead of listing untracked files
- [5.2] [src:code-review] [sev:Med] Orchestrator Steps 5-6 still re-derive the merge/dedup/elevation/sort rules in prose while the dispatch guide forbids it; deferred to step 6.5, which repoints both orchestrators at Build-ReviewReport.ps1
- [5.2] [src:code-review] [sev:Med] Build-ReviewReport.ps1 is not bundled by either review plugin, so the guide step resolves to nothing in a consumer install; that bundling is step 6.5 (REQ-18)
- [5.3] [src:code-review] [sev:Low] Design note still described cr/dr as three per-model reviewers and listed the six deleted agents; corrected to the seven-concern split in this step

## CR Capture
Phase: 6

- [6.5] [src:code-review] [sev:High] Documented formatter call used pwsh -File, which binds args as strings and drops typed findings; switched both skills and the collation guide to an in-session call operator and added a round-trip test.
- [6.3] [src:code-review] [sev:High] dr.agent.md shim lacked the execute tool its skill now needs to run Build-ReviewReport; added execute and a shim assertion.
- [6.2] [src:code-review] [sev:Med] dr's UNTRUSTED_INPUT fence moved into the skill with no positive test; added an assertion that both installed dr skill copies carry the markers and the never-follow rule.
- [6.3] [src:code-review] [sev:Med] waza specs bundled only ../../agents, so the shims dereferenced a skill outside the bundle; added ../../skills to both eval specs.

## CR Capture
Phase: 7

- [7.1] [src:code-review] [sev:Critical] Update-FeedbackQueue -Date was unvalidated and interpolated raw into the entry line, so it could forge fields and whole entries; fixed with ValidatePattern plus a round-trip check before write.
- [7.1] [src:code-review] [sev:High] A zero-byte queue.md bricked every action under StrictMode; fixed with a string cast on the raw read and a temp-file plus Move-Item atomic write.
- [7.1] [src:code-review] [sev:High] pfb shipped without the PlanState module and cip its own SKILL.md requires; fixed by referencing the bundled module path and declaring the create-implementation-plan dependency.
- [7.2] [src:code-review] [sev:High] Record -Id hard-failed every correction after the first because the marker was already consumed; it now falls back to the recorded entry and only fails on an id that belongs to no marker.
- [7.2] [src:code-review] [sev:Med] Marker-id and content-id key spaces do not intersect, so the same verdict could be recorded twice; dedup now matches on plan plus text as well as id.
- [7.2] [src:code-review] [sev:Med] List dropped its array guard so an empty section returned null under StrictMode; restored the unary comma and asserted the empty case in tests.

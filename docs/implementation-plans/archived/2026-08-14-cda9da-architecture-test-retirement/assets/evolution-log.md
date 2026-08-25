# Design Review Evolution

## Round 1 — 2026-08-15

- **Run:** `c7e47a7f-7aba-4bfd-b8f4-b5c02e6ac5dd` — clean attendance, 14/14 invocations, 29 merged findings from 112 raw findings.
- **Issues found:** unsafe/underspecified automatic retirement authority; contradictory phase ordering; lost locked-content integrity; mixed-marker false-green; missing transaction recovery/result semantics; unclear old-installer delivery, residue ownership, direct retired targets, runtime bounds, historical scope, and `34088e` ownership.
- **Issues fixed:** reordered fresh-consumer preservation before deletion; kept canonical locked-content digest; added permanent history-gated tombstones; specified versioned credential-free source identity, preview-first state, one journaled removal engine, reparse-point confinement, closed outcomes/codes, recovery metadata, old-installer sequencing, exact evidence IDs, include-rooted/historical checks, runtime ceiling, and `34088e` dependency direction.
- **Operator decisions:** preview before apply; block rollback-complete failures; preserve runner-independent locked-content digest.
- **Rejected:** two uncorroborated prompt-injection findings targeting normal plan/dispatch workflow prose.
- **Deferred:** none.

## Round 2 — 2026-08-15

- **Run:** `2e924941-4d5d-4ff6-9c0e-1eb6eb99df6a` — clean attendance, 14/14 invocations, 47 findings.
- **Issues found:** imports/tests could outlive deleted runtime; old installer/history fixtures were scheduled too late; lock authorship lacked an always-on gate; baseline/journal/state confinement and preview refusal were underspecified; runtime and cross-plan evidence ownership remained loose.
- **Issues fixed:** froze fixtures first; decoupled all manifest-derived bundles before deletion; separated generic catalog proof from atomic tombstone use; added explicit one-blob CI history comparison, lock authority, old-schema behavior, hostile-state/journal checks, failed-state recovery, bootstrap exit propagation, complete-state/bounded-output semantics, exact evidence ownership, four-process cap, existing suite-budget authority, and `34088e` consumption criteria.
- **Rejected:** one uncorroborated normal-workflow-prose injection finding.
- **Deferred:** none.

## Round 3 — 2026-08-15

- **Run:** `3c8e9a73-5f88-411c-b71e-8a783550da0d` — clean attendance, 14/14 invocations, 21 merged findings from 45 raw findings.
- **Issues found:** fixture reuse was prose-only; outcomes conflicted; deletion ownership and marker sequencing overlapped; human identity was overstated; CI host/gate rows, immutable deletion authority, first-publication behavior, manual residue, recurring work bounds, and digest ownership remained incomplete.
- **Issues fixed:** stable fixture path and `34088e` step/REQ binding; exhaustive outcome table and exit 20/21; sole deletion step; reviewer-enforced human promotion; tokenization before evaluator removal; exact registry workflow/inventory ownership; tombstone-pinned payload/manual residue; stale-preview transition; 8-plugin/64-path fair replay; state reconfinement; canonical digest helper; corrected phase titles and mappings.
- **Rejected:** repeated uncorroborated normal-plan-prose injection finding.
- **Known plan issues:** none.
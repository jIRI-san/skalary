# Design review evolution

## Round 1

All 14 concern passes completed. The review reported 23 findings: current-HEAD self-invalidation; ambiguous test-ID binding; swallowed outer exits; missing deterministic gate host; architecture advisory mismatch; incomplete runtime ownership; late synchronization; stale-green interruption; unproven degraded aggregates; unbound waiver approval; unsafe free text; multiple suite-scope authorities; scope confinement/installation ambiguity; per-marker rediscovery; unspecified timeout/isolation; unresolved fixture/platform budget; overloaded status ownership; incomplete Pester mapping; duplicate inventory derivation; undefined legacy migration; competing skip authorities; self-proof; and incomplete docs/handoff.

Resolved in the plan:

- Replaced current-HEAD freshness with a v2 evidence-input digest and fail-closed running-to-terminal atomic lifecycle.
- Chose batched exact leading-token discovery from one repo-local `.github/.skalary` scope, a killable child worker, 5-minute default/10-minute maximum, and total Pester result mapping.
- Hosted the sole completion verdict in `Test-Plan -Stage PlanCrosscheck`; added advisory disposition for draft/provisional architecture outcomes.
- Added exact active-waiver rendering plus one human-reviewed aggregate waiver-set digest that invalidates on policy/inventory change.
- Split execution status from typed gate findings; persisted aggregate counts so degraded can be independently derived.
- Required independent CI/autopilot bundles and same-step synchronization for every bundled mutation; made red evidence terminal through all outer launchers.
- Preserved `evidence: required` opt-in, made old strict receipts rebuild before completion, and retired prose/family-specific evidence skip exceptions in favor of typed policy.
- Added fixed-field escaping/bounds, one shared marker inventory, hand-authored parser goldens, ordinary/focused cross-checks, current Linux/Windows receipts, full documentation/generated-output inventory, and an expanded human handoff.

No finding was deferred. The simplicity gate is preserved: no second receipt format, persistent test index, new architecture contract, package dependency, or separate waiver artifact.

## Round 2

All 14 concern passes completed. The review reported 33 findings covering semantic-eval advisory reuse, complete consumer inventory, fail-closed digest membership, stale evidence IDs, publication identity/cutover, tracked scope ownership, machine-admitted platform proof, unattended approval authority, cardinality/secret limits, suite-host parity, installed-test hosting, static test closure, always-on skip enforcement, independent coverage baselines, changed-class diagnostics, approval/CI ordering, migration order, untrusted receipt text, digest ownership, final CR ordering, crosscheck scope, executable handoff, absent policy, approval audit, and timeout attribution. One unrelated prompt-injection finding against an existing design note was rejected as a false positive; it identified no plan-directed behavior or executable gap.

Resolved in the plan:

- Reuse `Get-ArchGateOutcome` for the total architecture mapping and inventory all CI/CIP/CEP/autopilot/architecture-tests copies.
- Hash all tracked regular files except a closed lifecycle-output exclusion list through one bounded digest module; add class subdigests and hand-authored membership goldens.
- Extend `Run-UnitTests` rather than create a second host; use tracked `.github/evidence-test-scope.json`, exact leading tokens, budget-derived timeout, and ordinary-suite fast seams.
- Keep waiver approval in root-only interactive finalization tooling with approve/revoke capture audit; unattended bundles are read-only and absent policy is canonical empty state.
- Set explicit admission limits and reuse the secret guard for committed diagnostics/reasons.
- Introduce v2 dormant, migrate callers, then atomically switch PlanCrosscheck authority and remove v1; UUID publication owns blocked start, terminal replacement, abandonment, and restart.
- Generalize always-on skipped evidence enforcement through typed policy, preserve independent coverage/removal baseline, separate host exclusions from evidence discovery, and scope phase versus final reruns.
- Move human approval before authoritative two-platform proof, run final CR before terminal receipt rebuild, and add exact approval/verify/revoke commands to the handoff.

No finding was deferred. The simplicity gate still holds: no second receipt, persistent index, new architecture contract, package, or additional CI gate.

## Round 3

All 14 concern passes completed. The 48 rendered findings reduce to 34 substantive items after merging repeated REQ-7, finalization-order, exit, phase-scope, CI-provenance, digest-bound, provisioning, and handoff reports. They covered suite-wide waiver scope, conflict with `cda9da`, publisher races, autopilot dependency references, CI provenance, file/time admission, scope lifecycle, OS authority, final proof ordering, mixed plan projection, exits, phase completeness, stale marker IDs, proof admission, load-bearing review/approval, snapshot binding, predecessor identity, policy lookup cost, budget floor, executable handoff, interactive enforcement, documentation globs, schema/instance naming, Git modes, and fail-closed independent output. The repeated prompt-injection classification against standard asset metadata was rejected as a false positive.

Resolved in the plan:

- Added external dependency on `cda9da`; removed architecture-tests, `arch:`, advisory, and `Get-ArchGateOutcome` ownership from this plan.
- Ordinary suite loads active non-archived strict plan policies once; archived/unowned skips fail closed.
- Added stable publication lock, UUID/state/digest CAS, predecessor reason, phase/final scope, complete-scope rules, and canonical mixed plan projection.
- Declared autopilot's continue-implementation manifest dependency, installed-path reference/allowlist, and no-copy/root-fallback proof.
- Selected authenticated `gh api` workflow/run/job/artifact verification and delivered an exact root finalization command/test.
- Added 20,000-file and 30-second digest ceilings, Git mode/gitlink refusal, independently bound review/audit/CI proof, host-derived OS, and matching approval audit.
- Closed focused/parser/launcher exit allocation, timeout floor, phase/final publication, current REQ-7 markers, marker ownership, and exact requirement-step mappings.
- Reordered finalization to CR/fixes, nonempty policy approval, exact-commit CI proof, final receipt, and PlanCrosscheck; any source mutation restarts the sequence.
- Clarified managed scope installation, schema versus policy instance, module owners, design-note globs, post-installed-matrix measurement, empty-policy branch, and fail-closed ordinary-output cross-check.

No Known Plan Issues remain. The simplicity gate still holds: one line receipt, ephemeral maps, existing suite/workflow/plugin machinery, no new architecture contract, package, or CI gate.
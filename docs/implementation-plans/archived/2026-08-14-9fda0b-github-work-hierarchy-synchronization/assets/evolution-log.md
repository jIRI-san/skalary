# Evolution Log

## Draft Baseline

- 2026-08-21: Operator confirmed the epic-derived intent and full interview summary.
- Draft validation passed with expected warnings for implementation evidence targets not yet created.

## Round 1

- Review run: `eaa8e878-a9c4-4e95-8d55-25ea7d92edc5`; clean 14/14 attendance; verdict Blocked; 26 Critical, 5 High, 5 Medium findings.
- Issues found: missing request/cost/byte/time bounds; competing authority wording; horizontal packaging/docs; weak red controls and Slow budgets; unsafe mutation retries; transport parity gap; unbound approval; late preflight; provider-port ownership gap; broad smoke authority; forgeable live proof; undefined fingerprints/checkpoint/state/lock/exit contracts; unbounded discovery; marker over-trust; mixed packaging ownership; per-action TOCTOU; unjournaled smoke creation; raw-body context risk; weak diagnostics/history/truncation/redaction/risk evidence; unnamed docs/maps; unclear remote vocabulary.
- Issues fixed: added numeric admission and storage limits; separated config and store authority; made every phase installable; added seeded negative controls and Fast/Slow ownership; classified retries and journal-before-mutate reconciliation; added transport-policy parity; capability-bound approvals and immediate pre-state checks; moved deterministic preflight before writes; added provider-port promotion criteria; immutable target binding; tool-generated live proof; exact managed fingerprints; manifest-last generations; closed states/exits and partial recovery; explicit parameterized scaffolds; bounded remote search/cost; operator-confirmed marker adoption; coherent plugin ownership; stable never-unlinked cross-worktree lock; bounded retained receipts/diagnostics; centralized redaction; named docs/catalog/suite artifacts; fixed vocabulary ownership.
- Operator decisions: active ambient `gh` auth retained with immutable target binding; automatic marker recovery replaced by operator-confirmed immutable-node adoption.
- Operational incident: the DR helper unexpectedly ran `git checkout` and `git clean` after freezing review input, reverting tracked draft files and deleting untracked draft assets. The plan was reconstructed from the validated session draft, hardened against all findings, and revalidated before continuing.
- Deferred issues: none. Post-merge-only verification is explicitly not claimed; all required final gates are executable pre-merge.

## Round 2

- Review mode: read-only, clean 14/14 attendance; no durable run artifact because repository mutation was prohibited; verdict Blocked; 5 Critical, 12 High, 3 Medium findings.
- Issues found: request/action caps did not compose; per-action cumulative snapshots were quadratic; seam/evidence completeness remained circular; phase evidence was aggregate; live proof was locally forgeable; timing lacked injectable enforcement; writes preceded recovery/distribution; parser/config/schema/scaffold/epic-store ownership conflicted; provider port was not typed; approval custody and smoke target timing were incomplete; state/lock/retention/redaction/fingerprint/parity/naming contracts still had gaps.
- Issues fixed: raised and partitioned request/cost budgets; bounded append records and terminal snapshots; independent seam/evidence maps; per-phase test/eval/tier/platform ownership; GitHub-hosted generated-registry proof; injectable clocks/processes and cleanup reserve; hard-disabled writes until full Phase-3 closure; restored canonical parser bundling; explicit consumer config, schema, epic-store, and ignored host-state lifecycle; typed opaque port; owner-only approval custody; two-stage smoke confirmation; normative state/exit/next-command matrix; confined never-unlinked lock; pinned retention/refusal; publication-wide redaction; typed fingerprint framing; concrete parity and docs owners; one `work-hierarchy-sync` vocabulary.
- Phase adjustment: split live preparation from live execution/finalization so every phase stays within the six-point advisory budget.
- Deferred issues: none.

## Round 3

- Review mode: read-only, clean 14/14 attendance; no durable run artifact because repository mutation was prohibited; verdict Blocked; 4 Critical, 27 High/Medium findings.
- Issues found: autonomous runtime could not consume host authority and exposed broad OAuth; limits/retention lacked compositional equations; approval expiry, cross-clone races, hosted trust/selection/cancellation, write enablement, sidecar/config/epic ownership, seam grammar, traceability, Phase-4 evidence, fingerprint framing, recovery/redaction ordering, diagram loop, raw-text storage/context, host-state confinement, admin payload scope, state inspection, phase granularity, and naming remained incomplete.
- Issues fixed: switched to manual host product execution; added exact action/request/cost/time/store equations and reserves; residual-digest reapproval; atomic remote-ref exclusion; full state/exit/next-command matrix; digest-pinned write capability; protected exact-SHA hosted workflow and unique API artifact binding; canonical parser/schema/tool bundling; registry `consumerFiles[]`; dependency/extension of `25aa23` epic resolver; closed AST seam grammar; generated traceability parity; Phase-4 evidence gate; versioned binary fingerprint framing; schema-minimal recovery-before-redaction; terminal-only snapshot diagram; no raw remote text persistence/model exposure; ACL-before-content ignored host state; repo-root admin tooling; read-only state command; three `M` steps in implementation phases; canonical `work-hierarchy-sync` naming.
- Deferred issues: none. No Known Plan Issues remain after repair; the default three-round review cap is reached.
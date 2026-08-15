# Design Review — full report

<!-- skalary/review-full@1 -->
<!-- content-trust: reviewer-authored-data -->

| | |
|---|---|
| **Run** | `2e924941-4d5d-4ff6-9c0e-1eb6eb99df6a` |
| **Review type** | `design` |
| **State** | `clean` |
| **Plan digest** | `sha256:b635a89088a4ac709d51908856c711890d94d550326245fed4f9a8c47bb3e040` |
| **Scope digest** | `sha256:f171b4ec213c9048a1026628e6a1c8d87c485978850802ed6c2fa60fbd2aee37` |
| **Scope** | DR round 2 of architecture-test retirement plan cda9da and all linked assets after reading the round-1 evolution log. Verify round-1 blockers: green sequencing, permanent registry tombstones, 34088e ownership, credential-free source identity and secret handling, preview-before-apply, one removal engine, transaction journal/recovery, modified-residue ownership and indexed cost, direct retired-name behavior, result/exit semantics, old-installer sequencing, independent mixed-marker tokenization, install confinement and reparse points, lockedContentSha256 human authority, historical boundary, runtime budget, and exact evidence ownership. Apply a simplicity gate: report only concrete implementation blockers or meaningful risks, and identify overengineering. |
| **Content trust** | `reviewer-authored-data` |
| **Requested → declared models** | GPT-5.6 Sol (copilot) → GPT-5.6 Sol (copilot) (preflight: available; degradation: none; served identity: unverified) · Claude Opus 5 (copilot) → Claude Opus 5 (copilot) (preflight: available; degradation: none; served identity: unverified) |
| **Invocations** | 14 of 28 budgeted |

## Tasks (14)

| # | Task | Concern | Declared model | Outcome | Raw findings | Diagnostic |
|---|---|---|---|---|---|---|
| 1 | `architecture-patterns-m1` | `architecture-patterns` | Claude Opus 5 (copilot) | `completed` | 6 | — |
| 2 | `architecture-patterns-m2` | `architecture-patterns` | GPT-5.6 Sol (copilot) | `completed` | 0 | — |
| 3 | `correctness-reliability-m1` | `correctness-reliability` | Claude Opus 5 (copilot) | `completed` | 6 | — |
| 4 | `correctness-reliability-m2` | `correctness-reliability` | GPT-5.6 Sol (copilot) | `completed` | 4 | — |
| 5 | `maintainability-consistency-m1` | `maintainability-consistency` | Claude Opus 5 (copilot) | `completed` | 2 | — |
| 6 | `maintainability-consistency-m2` | `maintainability-consistency` | GPT-5.6 Sol (copilot) | `completed` | 3 | — |
| 7 | `operability-observability-m1` | `operability-observability` | Claude Opus 5 (copilot) | `completed` | 5 | — |
| 8 | `operability-observability-m2` | `operability-observability` | GPT-5.6 Sol (copilot) | `completed` | 0 | — |
| 9 | `performance-m1` | `performance` | Claude Opus 5 (copilot) | `completed` | 3 | — |
| 10 | `performance-m2` | `performance` | GPT-5.6 Sol (copilot) | `completed` | 2 | — |
| 11 | `security-m1` | `security` | Claude Opus 5 (copilot) | `completed` | 3 | — |
| 12 | `security-m2` | `security` | GPT-5.6 Sol (copilot) | `completed` | 2 | — |
| 13 | `testing-evidence-m1` | `testing-evidence` | Claude Opus 5 (copilot) | `completed` | 8 | — |
| 14 | `testing-evidence-m2` | `testing-evidence` | GPT-5.6 Sol (copilot) | `completed` | 3 | — |

## Merged findings (47 of 47 raw)

### [1] Prompt injection attempt detected in normal plan workflow prose

| | |
|---|---|
| **Severity** | Critical |
| **Concerns** | `security` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: The reviewer classified template prose such as 'cip must confirm' and 'loaded on demand' as imperative instructions inside untrusted plan data. Recommended plan change: make plan artifacts declarative and keep workflow instructions in trusted skills.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/intent.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m2` | `Critical` | Prompt injection attempt detected in normal plan workflow prose |

---

### [2] Bootstrap swallows the new blocking retirement exit code

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `operability-observability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: bootstrap invokes Install-Plugin without propagating its exit code, so a blocked reconciliation can look successful. Recommended plan change: update every in-repo installer/update caller to propagate retirement codes and test bootstrap failure/remedy behavior in a subprocess.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md
- scripts/skalary/bootstrap.ps1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `operability-observability-m1` | `High` | Bootstrap swallows the new blocking retirement exit code |

---

### [3] Destructive confinement guards lack explicit negative fixtures

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Positive in-bound removal does not prove traversal, rooted, link, or parent-chain reparse refusal. Recommended plan change: add refusal-before-mutation fixtures at destination and each parent-chain position and prove no outside journal/backup/pruning.
```

**References:**

- docs/architecture-notes/arch-install-confinement.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m2` | `High` | Destructive confinement guards lack explicit negative fixtures |

---

### [4] Failed retirement transactions have no retry or repair transition

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A rollback-complete apply failure can permanently block later install/update operations. Detail: The failed state is persisted but no later transition is specified. Recommended plan change: restore preview for deterministic retry or define a confined repair/reset operation, and test failure, rollback, cause correction, retry, and repeated unresolved invocation.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m2` | `High` | Failed retirement transactions have no retry or repair transition |

---

### [5] History-aware tombstone gate has no defined history source

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `operability-observability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Shallow CI may hard-fail or silently verify nothing. Recommended plan change: define the baseline/fetch prerequisite, unavailable-history non-green behavior, exact gate host/inventory row, and a negative unavailable-history fixture.
```

**References:**

- .github/workflows/registry-ci.yml
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `operability-observability-m1` | `High` | History-aware tombstone gate has no defined history source |

---

### [6] Human-only lock promotion loses its enforcement point when the runner is deleted

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: The write-time shape gate cannot prove commit authorship after the runner authority is removed. Detail: Test-ArchContract currently says lock promotion is enforced by the runner, while the plan deletes that runner yet claims autonomous promotion remains rejected. Recommended plan change: add a real post-commit validation gate for promotion/content changes or explicitly downgrade the claim to human review and rewrite REQ-4.
```

**References:**

- docs/design-notes/architecture/architecture-tests.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `High` | Human-only lock promotion loses its enforcement point when the runner is deleted |

---

### [7] Phase 1 deletes the evidence executor dependency before arch evaluator removal

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: PlanEvidence cannot load after ArchReceipt deletion, so Phase 1-2 crosschecks produce no receipt. Recommended plan change: atomically remove the arch evaluator/import, resync bundles, and prove plan validation/evidence generation at each crosscheck before deleting the module.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md
- scripts/skalary/PlanEvidence.psm1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `High` | Phase 1 deletes the evidence executor dependency before arch evaluator removal |

---

### [8] Pre-retirement fixture is captured after retirement changes

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `maintainability-consistency` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: The old-installer fixture is first scheduled after source deletion and shared installer changes. Detail: Reconstructing it later from history leaves ownership and reproducibility undefined. Recommended plan change: freeze old installer scripts, registry, receipt, and installed payload as one immutable fixture before 1.3 and make later plans consume it.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `maintainability-consistency-m2` | `High` | Pre-retirement fixture is captured after retirement changes |

---

### [9] Preview override lacks refusal evidence

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Positive preview/apply tests do not prove ApplyRetirements refuses absent, stale, or mismatched preview. Recommended plan change: require no mutation plus exact refusal code/remedy for missing and mismatched preview authority.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m2` | `High` | Preview override lacks refusal evidence |

---

### [10] Recovery trusts an underspecified transaction journal

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `security` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Crafted or corrupted journal paths could steer startup writes/deletes. Recommended plan change: declare journals untrusted; version/schema validate, bind repository/plugin/transaction/receipt/tombstone identity, re-confine every destination/backup/temp ancestor, reject links/reparse/ADS/traversal, verify backup hashes, and add hostile-journal fixtures.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m2` | `High` | Recovery trusts an underspecified transaction journal |

---

### [11] Renaming lockedBodySha256 has no migration path for scaffolded consumer schemas

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Existing consumers prefer an old no-overwrite scaffolded schema that rejects lockedContentSha256. Detail: Fresh foreign-install proof cannot expose this incompatible old schema. Recommended plan change: define version detection and a confined schema upgrade or precise refusal remedy, with a fixture seeded from the old scaffold.
```

**References:**

- docs/design-notes/architecture/architecture-notes.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `High` | Renaming lockedBodySha256 has no migration path for scaffolded consumer schemas |

---

### [12] Retired plugin name becomes a state path with no declared confinement

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `security` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A registry-supplied name drives .github/.skalary/retirements/&lt;name&gt;.json. Recommended plan change: constrain names to the plugin-name grammar, resolve the state path through the confinement helper, reject traversal/rooted/ADS forms, and add hostile-name fixtures.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `High` | Retired plugin name becomes a state path with no declared confinement |

---

### [13] Runtime deletion still precedes gate and fixture migration

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Step 1.3 can leave the repository red until Phase 3 repairs inventories and tests. Detail: Marker tests, eval inventories, suite profile/coverage, and CI exclusions are deferred after source deletion. Recommended plan change: move every deletion-coupled test, eval, inventory, and coverage update before or atomically with 1.3.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m2` | `High` | Runtime deletion still precedes gate and fixture migration |

---

### [14] Step 1.3 deletes ArchReceipt.psm1 while PlanEvidence.psm1 still imports it until step 3.1

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: The plan validator module closure is broken between steps 1.3 and 3.1, so intervening phase crosschecks cannot be green. Detail: Step 1.3 deletes the root module, but PlanEvidence.psm1 and bundled CI/CIP/CEP copies still import it until arch evaluation is removed in 3.1; plan validation, evidence receipt generation, and bundle drift gates fail. Recommended plan change: move arch evaluator/import removal and bundle resync before deletion, and delete only assets with no remaining importer.
```

**References:**

- docs/design-notes/architecture/plan-workflow.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `High` | Step 1.3 deletes ArchReceipt.psm1 while PlanEvidence.psm1 still imports it until step 3.1 |

---

### [15] Step 1.3 deletes the arch runtime while evaluator bundles and suite metadata still depend on it

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Green sequencing remains broken from step 1.3 through Phase 3. Detail: ArchReceipt imports, architecture-test eval/profile entries, and ArchEvidence tests remain after their sources are deleted, so plan, bundle, eval, and unit gates can fail. Recommended plan change: atomically decouple consumers, remove stale tests/inventories, resync bundles, and refresh suite metadata with the deletion.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md
- tools/suite-coverage-baseline.json
- tools/suite-profile.json

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `High` | Step 1.3 deletes the arch runtime while evaluator bundles and suite metadata still depend on it |

---

### [16] The pre-change historical manifest is captured after mutation phases

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A baseline built in 3.2 cannot detect historical edits in Phases 1-2. Recommended plan change: capture the bounded manifest and base commit before step 1.1 and compare final state to that frozen asset.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `High` | The pre-change historical manifest is captured after mutation phases |

---

### [17] The replacement lock digest does not preserve human authority

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A digest stored beside content cannot reject an editor that changes both content and digest. Detail: Human-only promotion does not cover later locked content edits after runner removal. Recommended plan change: define trusted historical comparison and reject locked content/digest changes without a verified human-authorized transition; test recomputed digest in a non-human commit.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m2` | `High` | The replacement lock digest does not preserve human authority |

---

### [18] lockedContentSha256 has no always-on verifier after runner removal

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `security` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A write-time script can be bypassed and cannot by itself preserve human authority. Recommended plan change: add an always-on contract sweep and post-commit human-authority check, with red fixtures for direct locked edits and recomputed digests; register the replacement gate.
```

**References:**

- docs/design-notes/project/ci-gates.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `High` | lockedContentSha256 has no always-on verifier after runner removal |

---

### [19] Added-runtime ceiling is unquantified and duplicates existing budget authority

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `performance` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: No number, baseline, or enforcing host makes the ceiling falsifiable. Recommended plan change: drop the bespoke ceiling and pass existing suite-budget platform ceilings using canonical measurement, with no new raise unless separately justified.
```

**References:**

- docs/design-notes/project/ci-gates.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m1` | `Medium` | Added-runtime ceiling is unquantified and duplicates existing budget authority |

---

### [20] Capped path records can under-report the preview and deletion audit

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `operability-observability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: If persisted paths are truncated, preview may promise less deletion than apply performs. Recommended plan change: persist the complete receipt-matching set; cap only emitted output with total/truncation metadata and test preview-set equals apply-set above the cap.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `operability-observability-m1` | `Medium` | Capped path records can under-report the preview and deletion audit |

---

### [21] Design-note ownership for retirement and architecture-test removal is not explicit

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `maintainability-consistency` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Generic references to architecture/design notes do not name deletion and surviving subsystem owners. Detail: The obsolete architecture-tests note/index row and cross-note references can survive, while the permanent retirement contract exists only in a plan asset. Recommended plan change: name exact design-note deletions/updates and extend plugin-registry.design.md with retirement authority, state, source identity, shared engine, and result vocabulary.
```

**References:**

- docs/design-notes/.design-notes.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `maintainability-consistency-m1` | `Medium` | Design-note ownership for retirement and architecture-test removal is not explicit |

---

### [22] Hard-kill recovery tests duplicate deterministic journal fault seams

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Boundary fault injection already proves exact recovery; many process kills add flaky cost. Recommended plan change: keep deterministic seams at every boundary and at most one representative hard-kill commit-boundary case.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Medium` | Hard-kill recovery tests duplicate deterministic journal fault seams |

---

### [23] Historical baseline is introduced after mutation begins

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Step 3.2 can bless earlier historical changes. Recommended plan change: capture before 1.1 or derive from immutable plan-start commit, compare final tree, and seed one historical mutation to prove red behavior.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m2` | `Medium` | Historical baseline is introduced after mutation begins |

---

### [24] Historical baseline is scheduled after repository mutation

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `maintainability-consistency` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A pre-change manifest created in 3.2 can bless earlier accidental historical edits. Recommended plan change: generate and bind it to the starting tree before step 1.1; only verify it later.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `maintainability-consistency-m2` | `Medium` | Historical baseline is scheduled after repository mutation |

---

### [25] History-aware permanence gate has an unstated growing cost

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `performance` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A full ancestry walk and fetch-depth zero would grow forever. Recommended plan change: compare against one resolved baseline blob in bounded work, or explicitly budget the checkout/history cost.
```

**References:**

- .github/workflows/registry-ci.yml
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m1` | `Medium` | History-aware permanence gate has an unstated growing cost |

---

### [26] Journal recovery has no declared owner scope or relationship to existing rollback

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Startup recovery can grant an unrelated operation authority over another transaction and duplicates existing rollback authority. Detail: The plan does not name which entry points recover which journals or whether the journal wraps or supersedes existing backup/rollback. Recommended plan change: scope recovery to authorized same-plugin/source transactions, block on unrelated journals, and define its relationship to the existing transactional path.
```

**References:**

- docs/design-notes/architecture/plugin-registry.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | Journal recovery has no declared owner scope or relationship to existing rollback |

---

### [27] Measured added-runtime ceiling has no owner artifact marker or failure condition

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Any measurement can satisfy the prose. Recommended plan change: bind REQ-8 to the existing platform budget contract and a named test, with no new ceiling raise.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md
- tools/suite-budget.psd1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Medium` | Measured added-runtime ceiling has no owner artifact marker or failure condition |

---

### [28] Mixed-version installer copies can mutate over a pending journal

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A pre-journal bootstrap copy can take the same lock without recognizing pending recovery state. Detail: It may mutate a half-applied transaction and make later replay unsafe. Recommended plan change: validate recorded pre-state before recovery, fail closed on mismatch, and test old-copy invocation while a journal is pending.
```

**References:**

- docs/design-notes/architecture/plugin-registry.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `Medium` | Mixed-version installer copies can mutate over a pending journal |

---

### [29] PluginCatalog.GeneratedArtifacts names a test no step owns

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: The marker does not exist and no step explicitly authors it, so archival can fail unrun. Recommended plan change: assign exact test authorship in 1.3 or replace it with an existing deterministic gate-backed marker.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Medium` | PluginCatalog.GeneratedArtifacts names a test no step owns |

---

### [30] Preview and journal may drive deletion without re-derivation from receipt authority

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `security` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Persisted runtime state must not widen the deletion set. Recommended plan change: re-derive apply paths from the same-source receipt and current tombstone, use preview only as matching confirmation, re-confine journal paths on recovery, and test preview/journal tampering.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `Medium` | Preview and journal may drive deletion without re-derivation from receipt authority |

---

### [31] Retirement absence checks lack seeded-violation proof

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Misrooted or empty active-surface scans can pass vacuously. Recommended plan change: seed forbidden references under each declared active root and require zero-candidate root sets to fail loud.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/references.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Medium` | Retirement absence checks lack seeded-violation proof |

---

### [32] Retirement records are routed into the Copilot CLI marketplace catalog

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Step 1.3 appears to emit retiredPlugins into a foreign-spec marketplace artifact that cannot act on skalary retirement. Detail: Marketplace schema has a closed root and CLI installs live outside the confinement boundary; fresh CLI acquisition is already blocked by source removal. Recommended plan change: keep retirement authority in registry-retirements.json and registry.json, remove only the plugin from marketplace.json, and scope CLI-installed copies as unreconcilable residue.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md
- schemas/marketplace/marketplace.schema.json

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | Retirement records are routed into the Copilot CLI marketplace catalog |

---

### [33] Retirement-specific runtime ceiling duplicates the budget authority

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `maintainability-consistency` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Step 3.3 creates a second budget convention. Recommended plan change: use deterministic subprocess timeouts and existing Linux/Windows suite ceilings; keep added-runtime measurement as evidence through existing metadata only.
```

**References:**

- docs/design-notes/project/ci-gates.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `maintainability-consistency-m2` | `Medium` | Retirement-specific runtime ceiling duplicates the budget authority |

---

### [34] Runtime ceiling remains undefined

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `performance` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Neither allowed runtime increase nor subprocess fan-out is quantified. Recommended plan change: require current platform ceilings without a raise and state maximum focused subprocess launches and shared timeout; keep the remainder in-process.
```

**References:**

- docs/design-notes/project/ci-gates.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m2` | `Medium` | Runtime ceiling remains undefined |

---

### [35] Step 1.3 fuses the generic retirement mechanism with its first use

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: One large step introduces a registry-wide capability, consumes it, and deletes the subsystem, leaving no independently revertible boundary. Detail: Only the real tombstone and source deletion must be atomic; schema, generator, and validation support can be proven separately. Recommended plan change: split mechanism/fixture work from the atomic architecture-tests tombstone and deletion.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | Step 1.3 fuses the generic retirement mechanism with its first use |

---

### [36] Step 3.3 invents an added-runtime ceiling beside the repository budget contract

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A second plan-local ceiling adds machinery without defining what happens when the real CI ceiling is missed. Detail: Run-UnitTests and suite-budget are the sole platform authority. Recommended plan change: use Measure-SuiteRuntime and existing platform ceilings, state the subprocess-reduction lever, and record any permitted raise through the existing contract only.
```

**References:**

- docs/design-notes/project/ci-gates.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `Medium` | Step 3.3 invents an added-runtime ceiling beside the repository budget contract |

---

### [37] Subprocess and bundle test fan-out is called bounded but has no cap

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `performance` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Ten subprocess families plus installed bundle/stage combinations can reintroduce linear fixture cost. Recommended plan change: state maximum launches, shared fixture reuse, and require in-process proof for state/fault/result cases that do not need process boundaries.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m1` | `Medium` | Subprocess and bundle test fan-out is called bounded but has no cap |

---

### [38] Successful journal recovery leaves no result in the closed outcome set

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `operability-observability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: An operator cannot tell a normal run from one that repaired a hard-killed transaction. Recommended plan change: add a recovered result or field with transaction id/path count and assert it at recovery seams.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `operability-observability-m1` | `Medium` | Successful journal recovery leaves no result in the closed outcome set |

---

### [39] Terminal states can become silent while manual work remains

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `operability-observability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Out-of-confinement residue or payload restored by git may never be reported again. Detail: Metadata-only replay can cheaply stat recorded paths without hashing. Recommended plan change: recheck existence and re-emit manual-required/residue while recorded paths remain, with restored-payload and manual-residue tests.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `operability-observability-m1` | `Medium` | Terminal states can become silent while manual work remains |

---

### [40] The 34088e ownership boundary has no acceptance evidence

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Step 3.2 edits another plan's ownership but no cda9da criterion proves the edit landed. Detail: 34088e still names overlapping retirement cases. Recommended plan change: name the exact 34088e records to edit and add a file evidence marker asserting it consumes cda9da's protocol/fixture.
```

**References:**

- docs/implementation-plans/2026-08-02-34088e-consumer-install-correctness/assets/requirements.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `Medium` | The 34088e ownership boundary has no acceptance evidence |

---

### [41] The 34088e ownership boundary is asserted without evidence

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Overlapping retirement matrices can persist silently. Recommended plan change: add a file marker asserting 34088e depends on cda9da and names its retirement fixture/protocol owner.
```

**References:**

- docs/implementation-plans/2026-08-02-34088e-consumer-install-correctness/assets/requirements.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Medium` | The 34088e ownership boundary is asserted without evidence |

---

### [42] The CEP bundle is missing from marker and bundle reconciliation

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Step 3.1 lists CI/CIP/CR/DR/PFB/SI but CEP also ships PlanEvidence and ArchReceipt. Detail: A stale installed CEP bundle preserves the retired evaluator/import and violates the false-green prevention goal. Recommended plan change: include CEP explicitly or derive every affected bundle from manifests/import closure.
```

**References:**

- docs/design-notes/architecture/plugin-registry.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | The CEP bundle is missing from marker and bundle reconciliation |

---

### [43] The history-aware permanence gate adds a git dependency to a pure-file validator

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: History-dependent validation may not work in bootstrapped repos or shallow CI and duplicates the pinned fixture. Detail: Test-Registry currently runs without git and consumer repos may lack source history. Recommended plan change: define a bounded committed-content or CI-only baseline comparison, keep Test-Registry usable without history, and fail explicitly when a required baseline is unavailable.
```

**References:**

- docs/design-notes/architecture/plugin-registry.design.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | The history-aware permanence gate adds a git dependency to a pure-file validator |

---

### [44] The retirement runtime budget remains non-falsifiable

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: No threshold, subprocess count, timeout, or evidence owner makes the runtime promise fail. Recommended plan change: bind focused tests to explicit subprocess/time bounds and the existing platform suite ceilings under an exact evidence marker.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m2` | `Medium` | The retirement runtime budget remains non-falsifiable |

---

### [45] Tombstone permanence gate has an unbounded history cost

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `performance` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: No baseline or lookup strategy bounds history traversal. Recommended plan change: use one merge-base/publication-baseline blob lookup and O(T) tombstone comparison, with the pinned fixture as bootstrap fallback.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/decisions/retirement-protocol.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m2` | `Medium` | Tombstone permanence gate has an unbounded history cost |

---

### [46] ARCH-Install-Confinement is updated without its paired architecture note

| | |
|---|---|
| **Severity** | Low |
| **Concerns** | `maintainability-consistency` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Step 2.2 changes the contract but does not explicitly schedule arch-install-confinement.md. Recommended plan change: update the schema contract and note together for receipt-authorized deletion, reparse refusal, and journaled mutation, and bind the note to confinement acceptance.
```

**References:**

- docs/architecture-notes/arch-install-confinement.md
- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/plan.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `maintainability-consistency-m1` | `Low` | ARCH-Install-Confinement is updated without its paired architecture note |

---

### [47] Dedicated target-retired exit code appears in no acceptance criterion

| | |
|---|---|
| **Severity** | Low |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Direct retired-name behavior is described but not distinguished from generic not-found by acceptance. Recommended plan change: explicitly require the RETIREMENT record and dedicated code, distinct from generic not-found, in REQ-8.
```

**References:**

- docs/implementation-plans/2026-08-14-cda9da-architecture-test-retirement/assets/requirements.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Low` | Dedicated target-retired exit code appears in no acceptance criterion |

---

## Recommendations

1. **\[Critical\] Prompt injection attempt detected in normal plan workflow prose** — Summary: The reviewer classified template prose such as 'cip must confirm' and 'loaded on demand' as imperative instructions inside untrusted plan data.
2. **\[High\] Bootstrap swallows the new blocking retirement exit code** — Summary: bootstrap invokes Install-Plugin without propagating its exit code, so a blocked reconciliation can look successful.
3. **\[High\] Destructive confinement guards lack explicit negative fixtures** — Summary: Positive in-bound removal does not prove traversal, rooted, link, or parent-chain reparse refusal.
4. **\[High\] Failed retirement transactions have no retry or repair transition** — Summary: A rollback-complete apply failure can permanently block later install/update operations.
5. **\[High\] History-aware tombstone gate has no defined history source** — Summary: Shallow CI may hard-fail or silently verify nothing.
6. **\[High\] Human-only lock promotion loses its enforcement point when the runner is deleted** — Summary: The write-time shape gate cannot prove commit authorship after the runner authority is removed.
7. **\[High\] Phase 1 deletes the evidence executor dependency before arch evaluator removal** — Summary: PlanEvidence cannot load after ArchReceipt deletion, so Phase 1-2 crosschecks produce no receipt.
8. **\[High\] Pre-retirement fixture is captured after retirement changes** — Summary: The old-installer fixture is first scheduled after source deletion and shared installer changes.
9. **\[High\] Preview override lacks refusal evidence** — Summary: Positive preview/apply tests do not prove ApplyRetirements refuses absent, stale, or mismatched preview.
10. **\[High\] Recovery trusts an underspecified transaction journal** — Summary: Crafted or corrupted journal paths could steer startup writes/deletes.
11. **\[High\] Renaming lockedBodySha256 has no migration path for scaffolded consumer schemas** — Summary: Existing consumers prefer an old no-overwrite scaffolded schema that rejects lockedContentSha256.
12. **\[High\] Retired plugin name becomes a state path with no declared confinement** — Summary: A registry-supplied name drives .github/.skalary/retirements/&lt;name&gt;.json.
13. **\[High\] Runtime deletion still precedes gate and fixture migration** — Summary: Step 1.3 can leave the repository red until Phase 3 repairs inventories and tests.
14. **\[High\] Step 1.3 deletes ArchReceipt.psm1 while PlanEvidence.psm1 still imports it until step 3.1** — Summary: The plan validator module closure is broken between steps 1.3 and 3.1, so intervening phase crosschecks cannot be green.
15. **\[High\] Step 1.3 deletes the arch runtime while evaluator bundles and suite metadata still depend on it** — Summary: Green sequencing remains broken from step 1.3 through Phase 3.
16. **\[High\] The pre-change historical manifest is captured after mutation phases** — Summary: A baseline built in 3.2 cannot detect historical edits in Phases 1-2.
17. **\[High\] The replacement lock digest does not preserve human authority** — Summary: A digest stored beside content cannot reject an editor that changes both content and digest.
18. **\[High\] lockedContentSha256 has no always-on verifier after runner removal** — Summary: A write-time script can be bypassed and cannot by itself preserve human authority.
19. **\[Medium\] Added-runtime ceiling is unquantified and duplicates existing budget authority** — Summary: No number, baseline, or enforcing host makes the ceiling falsifiable.
20. **\[Medium\] Capped path records can under-report the preview and deletion audit** — Summary: If persisted paths are truncated, preview may promise less deletion than apply performs.
21. **\[Medium\] Design-note ownership for retirement and architecture-test removal is not explicit** — Summary: Generic references to architecture/design notes do not name deletion and surviving subsystem owners.
22. **\[Medium\] Hard-kill recovery tests duplicate deterministic journal fault seams** — Summary: Boundary fault injection already proves exact recovery; many process kills add flaky cost.
23. **\[Medium\] Historical baseline is introduced after mutation begins** — Summary: Step 3.2 can bless earlier historical changes.
24. **\[Medium\] Historical baseline is scheduled after repository mutation** — Summary: A pre-change manifest created in 3.2 can bless earlier accidental historical edits.
25. **\[Medium\] History-aware permanence gate has an unstated growing cost** — Summary: A full ancestry walk and fetch-depth zero would grow forever.
26. **\[Medium\] Journal recovery has no declared owner scope or relationship to existing rollback** — Summary: Startup recovery can grant an unrelated operation authority over another transaction and duplicates existing rollback authority.
27. **\[Medium\] Measured added-runtime ceiling has no owner artifact marker or failure condition** — Summary: Any measurement can satisfy the prose.
28. **\[Medium\] Mixed-version installer copies can mutate over a pending journal** — Summary: A pre-journal bootstrap copy can take the same lock without recognizing pending recovery state.
29. **\[Medium\] PluginCatalog.GeneratedArtifacts names a test no step owns** — Summary: The marker does not exist and no step explicitly authors it, so archival can fail unrun.
30. **\[Medium\] Preview and journal may drive deletion without re-derivation from receipt authority** — Summary: Persisted runtime state must not widen the deletion set.
31. **\[Medium\] Retirement absence checks lack seeded-violation proof** — Summary: Misrooted or empty active-surface scans can pass vacuously.
32. **\[Medium\] Retirement records are routed into the Copilot CLI marketplace catalog** — Summary: Step 1.3 appears to emit retiredPlugins into a foreign-spec marketplace artifact that cannot act on skalary retirement.
33. **\[Medium\] Retirement-specific runtime ceiling duplicates the budget authority** — Summary: Step 3.3 creates a second budget convention.
34. **\[Medium\] Runtime ceiling remains undefined** — Summary: Neither allowed runtime increase nor subprocess fan-out is quantified.
35. **\[Medium\] Step 1.3 fuses the generic retirement mechanism with its first use** — Summary: One large step introduces a registry-wide capability, consumes it, and deletes the subsystem, leaving no independently revertible boundary.
36. **\[Medium\] Step 3.3 invents an added-runtime ceiling beside the repository budget contract** — Summary: A second plan-local ceiling adds machinery without defining what happens when the real CI ceiling is missed.
37. **\[Medium\] Subprocess and bundle test fan-out is called bounded but has no cap** — Summary: Ten subprocess families plus installed bundle/stage combinations can reintroduce linear fixture cost.
38. **\[Medium\] Successful journal recovery leaves no result in the closed outcome set** — Summary: An operator cannot tell a normal run from one that repaired a hard-killed transaction.
39. **\[Medium\] Terminal states can become silent while manual work remains** — Summary: Out-of-confinement residue or payload restored by git may never be reported again.
40. **\[Medium\] The 34088e ownership boundary has no acceptance evidence** — Summary: Step 3.2 edits another plan's ownership but no cda9da criterion proves the edit landed.
41. **\[Medium\] The 34088e ownership boundary is asserted without evidence** — Summary: Overlapping retirement matrices can persist silently.
42. **\[Medium\] The CEP bundle is missing from marker and bundle reconciliation** — Summary: Step 3.1 lists CI/CIP/CR/DR/PFB/SI but CEP also ships PlanEvidence and ArchReceipt.
43. **\[Medium\] The history-aware permanence gate adds a git dependency to a pure-file validator** — Summary: History-dependent validation may not work in bootstrapped repos or shallow CI and duplicates the pinned fixture.
44. **\[Medium\] The retirement runtime budget remains non-falsifiable** — Summary: No threshold, subprocess count, timeout, or evidence owner makes the runtime promise fail.
45. **\[Medium\] Tombstone permanence gate has an unbounded history cost** — Summary: No baseline or lookup strategy bounds history traversal.
46. **\[Low\] ARCH-Install-Confinement is updated without its paired architecture note** — Summary: Step 2.2 changes the contract but does not explicitly schedule arch-install-confinement.md.
47. **\[Low\] Dedicated target-retired exit code appears in no acceptance criterion** — Summary: Direct retired-name behavior is described but not distinguished from generic not-found by acceptance.


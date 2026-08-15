# Design Review — full report

<!-- skalary/review-full@1 -->
<!-- content-trust: reviewer-authored-data -->

| | |
|---|---|
| **Run** | `3c8e9a73-5f88-411c-b71e-8a783550da0d` |
| **Review type** | `design` |
| **State** | `clean` |
| **Plan digest** | `sha256:6ffcc7e55f4bff54e6672131e446c48eaa231e267fdd58b54860621080994a88` |
| **Scope digest** | `sha256:33b138e030fbbd6f795cfc7dbe6c0ec3721b24062eb746c5533d65fc25417c52` |
| **Scope** | DR round 3 (final default round) of architecture-test retirement plan cda9da after reading the evolution log first and all supporting assets. Report only concrete blockers still present after rounds 1-2, focused on green phase/commit sequencing; one-blob tombstone permanence and CI availability; locked digest and human transition authority; old-installer/scaffold and historical fixture timing; preview refusal, confinement, retry/recovery, bootstrap exits, and exact result semantics; modified-residue ownership and bounded replay cost; exact evidence ids, 34088e consumption, suite budget and four-process cap; and simplicity. |
| **Content trust** | `reviewer-authored-data` |
| **Requested → declared models** | GPT-5.6 Sol (copilot) → GPT-5.6 Sol (copilot) (preflight: available; degradation: none; served identity: unverified) · Claude Opus 5 (copilot) → Claude Opus 5 (copilot) (preflight: available; degradation: none; served identity: unverified) |
| **Invocations** | 14 of 28 budgeted |

## Tasks (14)

| # | Task | Concern | Declared model | Outcome | Raw findings | Diagnostic |
|---|---|---|---|---|---|---|
| 1 | `architecture-patterns-m1` | `architecture-patterns` | Claude Opus 5 (copilot) | `completed` | 6 | — |
| 2 | `architecture-patterns-m2` | `architecture-patterns` | GPT-5.6 Sol (copilot) | `completed` | 3 | — |
| 3 | `correctness-reliability-m1` | `correctness-reliability` | Claude Opus 5 (copilot) | `completed` | 5 | — |
| 4 | `correctness-reliability-m2` | `correctness-reliability` | GPT-5.6 Sol (copilot) | `completed` | 4 | — |
| 5 | `maintainability-consistency-m1` | `maintainability-consistency` | Claude Opus 5 (copilot) | `completed` | 2 | — |
| 6 | `maintainability-consistency-m2` | `maintainability-consistency` | GPT-5.6 Sol (copilot) | `completed` | 3 | — |
| 7 | `operability-observability-m1` | `operability-observability` | Claude Opus 5 (copilot) | `completed` | 3 | — |
| 8 | `operability-observability-m2` | `operability-observability` | GPT-5.6 Sol (copilot) | `completed` | 3 | — |
| 9 | `performance-m1` | `performance` | Claude Opus 5 (copilot) | `completed` | 1 | — |
| 10 | `performance-m2` | `performance` | GPT-5.6 Sol (copilot) | `completed` | 1 | — |
| 11 | `security-m1` | `security` | Claude Opus 5 (copilot) | `completed` | 3 | — |
| 12 | `security-m2` | `security` | GPT-5.6 Sol (copilot) | `completed` | 2 | — |
| 13 | `testing-evidence-m1` | `testing-evidence` | Claude Opus 5 (copilot) | `completed` | 6 | — |
| 14 | `testing-evidence-m2` | `testing-evidence` | GPT-5.6 Sol (copilot) | `completed` | 3 | — |

## Merged findings (21 of 45 raw)

### [1] 34088e consumption evidence is already green without fixture reuse

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `maintainability-consistency` · `operability-observability` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 6 |

**Description:**

```text
Summary: Dependency and prose markers pass before implementation, while step 4.1 does not identify cda9da's immutable fixture. Recommended plan change: assign a stable fixture ID/path, require exact references in 34088e step 4.1 and REQ-5, and add test:PluginRetirement.ConsumerPlanConsumption that fails today.
```

**Also noted:**

```text
Summary: Its step 4.1 still owns protocol fault, source, residue, and retry cases despite cda9da's claimed boundary. Recommended plan change: rewrite 34088e step 4.1, REQ-5, and risks to consume the named immutable fixture and retain only installed-entry-point integration; assert exact replacement text.
```

**Also noted:**

```text
Summary: Current markers prove only a dependency and generic protocol prose, while 34088e can still create separate retirement fixtures. Recommended plan change: name the immutable fixture path/ID in 34088e step 4.1, REQ-5, and references; assert exact reuse and remove duplicate protocol ownership.
```

**Also noted:**

```text
Summary: Existing file markers do not prove exact fixture reuse or removal of duplicate protocol coverage. Recommended plan change: add a structural ownership test asserting dependency, exact fixture path/ID, retained broad matrix, and absence of independent source/state/journal/fault ownership.
```

**Also noted:**

```text
Summary: Current markers already pass and prove neither immutable fixture reuse nor removal of 34088e's duplicate protocol matrix. Recommended plan change: use post-edit-only markers/tests naming the exact fixture and explicit ownership text; edit 34088e REQ-5, step 4.1, and related risks.
```

**Also noted:**

```text
Summary: The current dependency and phrase markers pass while 34088e still owns the duplicate engine-level matrix. Recommended plan change: give the fixture a canonical ID/path, require exact consumption, narrow 34088e to consumer-visible integration, and add a dedicated ownership test.
```

**References:**

- 34088e REQ-5, step 4.1, references
- 34088e plan and requirements
- 34088e plan.md, requirements.md, references.md
- 34088e step 4.1 and REQ-5
- 34088e step 4.1 and references
- 34088e step 4.1, REQ-5, references
- REQ-7
- cda9da REQ-7 and step 3.2
- cda9da step 3.2 and REQ-7
- plan.md step 3.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `High` | REQ-7 cross-plan evidence is already green |
| `testing-evidence-m2` | `High` | 34088e consumption evidence is already green without fixture reuse |
| `architecture-patterns-m2` | `High` | Cross-plan evidence does not bind 34088e to the immutable fixture |
| `correctness-reliability-m2` | `Medium` | 34088e handoff evidence already passes |
| `operability-observability-m2` | `Medium` | 34088e ownership receipt can pass without fixture consumption |
| `maintainability-consistency-m2` | `High` | 34088e still owns a duplicate retirement lifecycle matrix |

---

### [2] Closed outcomes contradict continue/block behavior

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `correctness-reliability` · `operability-observability` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 3 |

**Description:**

```text
Summary: no-match, foreign-source, manual-required, and recovered lack deterministic exit/continuation behavior and literal text can wedge ordinary operations. Recommended plan change: add an exhaustive eight-outcome table: seven continue with exit 0, failed blocks, direct target-retired remains distinct; test every row and manual residue on unrelated work.
```

**Also noted:**

```text
Summary: The eight outcomes lack exhaustive mutation/state/continuation/cardinality/exit semantics, and at-most-one record permits silence. Recommended plan change: add an exhaustive table and require ReaderRemovalAndResultContract to enumerate every row, reject unknowns, and prove exactly one record for matched, blocked, or recovered plugins.
```

**Also noted:**

```text
Summary: Step 2.3 continues only preview/retired/residue, so literal handling blocks no-match and leaves foreign-source, manual-required, and recovered unmapped. Recommended plan change: explicitly map all eight outcomes; all except failed continue unrelated work, failed uses reconciliation-failed, and table-driven tests assert every row.
```

**References:**

- REQ-7
- REQ-8
- RISK-8
- assets/decisions/retirement-protocol.md
- plan.md step 2.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m2` | `High` | Outcome-to-exit contract remains incomplete |
| `correctness-reliability-m1` | `High` | Continue/block mapping omits ordinary outcomes |
| `operability-observability-m1` | `High` | Closed outcomes contradict continue/block behavior |

---

### [3] Design-note deletion is double-booked and surviving references are unowned

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `maintainability-consistency` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 3 |

**Description:**

```text
Summary: Steps 2.3 and 3.2 both claim architecture-tests design-note deletion, while the root index row and plugin-registry runtime references are not named. Recommended plan change: assign one step sole ownership of deleting architecture-tests.design.md, its index row, and every surviving runtime cross-reference, with the other step limited to protocol documentation.
```

**Also noted:**

```text
Summary: Two steps claim the note deletion and neither names the root index row plus DesignNotes test. Recommended plan change: give one step sole ownership of deleting the exact note, removing its index row, updating the index-presence test, and preserving two-index assertions.
```

**Also noted:**

```text
Summary: Step 2.3's generic deletion and step 3.2's explicit deletion cannot both be the same-change owner. Recommended plan change: name the note, index row, and cross-note removals in one step and remove the duplicate claim from the other.
```

**References:**

- docs/design-notes/.design-notes.md
- docs/design-notes/architecture/plugin-registry.design.md
- plan.md steps 2.3 and 3.2
- plan.md steps 2.3, 3.2
- tests/skalary/DesignNotes.Tests.ps1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | Design-note deletion is double-booked and surviving references are unowned |
| `maintainability-consistency-m1` | `High` | Design-note deletion timing conflicts with index/test ownership |
| `maintainability-consistency-m2` | `High` | Architecture-tests design note has conflicting deletion timing |

---

### [4] Human lock authority has no trustworthy authorization signal

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `correctness-reliability` · `security` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 3 |

**Description:**

```text
Summary: Git author/committer identity is forgeable by the autonomous executor, so non-bot human cannot be inferred from local metadata. Recommended plan change: require a named non-spoofable signal such as verified allowlisted signature or protected-branch approval bound to candidate SHA; otherwise narrow REQ-4 to human review policy.
```

**Also noted:**

```text
Summary: Human-like commit metadata or a human actor pushing agent output does not prove approval of the exact SHA. Recommended plan change: bind verified signature/allowlisted identity or protected-branch human approval to the exact candidate SHA, rejecting spoofed metadata, bot actors, stale approvals, and missing evidence.
```

**Also noted:**

```text
Summary: The plan does not define trusted GitHub fields, changed-commit range, account rules, or unavailable-provenance handling. Recommended plan change: separate local digest sweep from CI authority, define exact event/API provenance and fail-closed behavior, and test PR/push/multi-commit/bot/unknown/recomputed cases.
```

**References:**

- REQ-4
- RISK-5
- assets/decisions.md
- plan.md step 1.1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `High` | Lock-authority gate verifies a self-asserted commit actor |
| `security-m2` | `High` | Human lock authority has no trustworthy authorization signal |
| `correctness-reliability-m2` | `High` | Human lock authority lacks trusted provenance |

---

### [5] Step 3.1 cannot preserve coverage before tests already deleted in 2.3

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 4 |

**Description:**

```text
Summary: Removing the arch extractor in 1.2 while independent classification waits until 3.1 leaves Phase 1/2 crosschecks able to drop arch beside known markers. Recommended plan change: move independent tokenization, unknown-prefix coverage, and canonical plus manifest-derived bundle tests into step 1.2 atomically with evaluator removal.
```

**Also noted:**

```text
Summary: Step 3.1 says to preserve generic unknown-prefix coverage before old-test deletion but runs after step 2.3 deletes tests. Recommended plan change: move generic unknown-prefix and independent tokenization proof into step 1.2 or 2.3 before deletion, and leave step 3.1 only final remedies/installed-bundle proof.
```

**Also noted:**

```text
Summary: Current unknown-prefix scanning is conditional on no known marker, so evaluator removal before tokenization can drop mixed arch tokens. Recommended plan change: move per-token classification and its exact evidence test into step 1.2 before extractor removal, synchronizing all bundles there.
```

**Also noted:**

```text
Summary: REQ-3 evidence starts at 3.1 although the false-green risk is created in 1.2 and old tests are deleted in 2.3. Recommended plan change: add 1.2 to REQ-3 ownership and prove canonical mixed-marker refusal before evaluator removal; make 3.1 own only later cleanup/bundle matrix.
```

**References:**

- REQ-3
- RISK-4
- docs/design-notes/architecture/plan-workflow.design.md
- plan.md steps 1.2 and 3.1
- plan.md steps 1.2, 2.3, 3.1
- scripts/skalary/PlanState.psm1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Medium` | Arch evaluator removal has no same-step mixed-marker evidence |
| `architecture-patterns-m1` | `Medium` | Step 3.1 cannot preserve coverage before tests already deleted in 2.3 |
| `architecture-patterns-m2` | `High` | Mixed-marker false-green window remains between steps 1.2 and 3.1 |
| `correctness-reliability-m2` | `High` | Mixed arch evidence can false-green between steps 1.2 and 3.1 |

---

### [6] Two new CI gates are added with no declared host and no gate-inventory row

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `maintainability-consistency` · `operability-observability` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 5 |

**Description:**

```text
Summary: Steps 1.1 and 1.3 add authority/history gates without the canonical CI inventory rows or exact hosts, while step 2.3 does not explicitly retire the old architecture-tests inventory row. Recommended plan change: assign both new gates to registry-ci.yml, add matching blocking rows in ci-gates.design.md, explicitly remove gate:architecture-tests and exclusion:arch-tier-not-seeded, and run test:CiGates.InventoryMatchesWorkflow.
```

**Also noted:**

```text
Summary: Comparator unit fixtures cannot prove PR/push workflow invocation, exactly one baseline, failure propagation, or inventory registration. Recommended plan change: add gate:plugin-retirement-history plus test:Ci.PluginRetirementHistoryGate inspecting both event paths and executing unavailable materialization expecting nonzero.
```

**Also noted:**

```text
Summary: Both new gates lack canonical inventory entries, and the history gate does not pin authoritative PR/push SHAs. Recommended plan change: add exact gate rows/hosts, use pull_request.base.sha and event.before, materialize only the tombstone blob, reject invalid inputs, and test inventory plus unavailable baseline.
```

**Also noted:**

```text
Summary: New CI invocations lack authoritative inventory rows and the old architecture-tests row/exclusion is not exactly assigned for removal. Recommended plan change: add gate/support rows with exact hosts and invocation patterns in steps 1.1/1.3, remove old rows in 2.3, and run inventory parity in 3.3.
```

**Also noted:**

```text
Summary: Steps 1.1 and 1.3 add CI-wired scripts without matching authoritative rows. Recommended plan change: add named blocking rows with exact host and regex in the same commits as each CI invocation.
```

**References:**

- REQ-2
- docs/design-notes/project/ci-gates.design.md
- plan.md step 1.3
- plan.md steps 1.1 and 1.3
- plan.md steps 1.1, 1.3, 2.3, 3.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m2` | `Medium` | One-blob CI wiring lacks a falsifying gate test |
| `architecture-patterns-m1` | `High` | Two new CI gates are added with no declared host and no gate-inventory row |
| `operability-observability-m2` | `High` | New CI authorities lack operable host and baseline contracts |
| `maintainability-consistency-m1` | `High` | New gates and retired gate row are not reconciled with CI inventory |
| `maintainability-consistency-m2` | `High` | New always-on gates are absent from canonical gate inventory |

---

### [7] Prompt injection attempt detected in plan asset prose

| | |
|---|---|
| **Severity** | Critical |
| **Concerns** | `operability-observability` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Reviewer classified the plan's loaded-on-demand instruction as AI-directed untrusted text. Recommended plan change: make the sentence declarative and keep loading policy in trusted workflow customizations.
```

**References:**

- plan.md Assets section

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `operability-observability-m2` | `Critical` | Prompt injection attempt detected in plan asset prose |

---

### [8] Always-on authority gate has no materialization or actor-resolution cost bound

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `architecture-patterns` · `operability-observability` · `performance` · `security` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 4 |

**Description:**

```text
Summary: Test-ArchContractAuthority.ps1 has no exact path/ownership or pure-file versus CI-materialization boundary. Recommended plan change: make it an explicit repo-root gate following Test-ArchDocFreshness, reuse a plugin-owned canonical helper, and define base/candidate plus actor inputs with fail-loud unavailable-input behavior.
```

**Also noted:**

```text
Summary: Transition checks cannot run in plain local/shallow/first-push contexts, but no fail/degraded contract exists. Recommended plan change: split always-on digest validation from one-blob transition authority, fail when required base cannot be supplied, and test both explicit digest-only and unavailable-base outcomes.
```

**Also noted:**

```text
Summary: Local, shallow, or squashed contexts may lack transition base and actor metadata, with no specified fail/degraded signal. Recommended plan change: name base/actor sources, fail closed when required, emit explicit digest-only status outside commit context, and test silent-downgrade refusal.
```

**Also noted:**

```text
Summary: The new gate can require unbounded history walks/API calls outside the suite budget. Recommended plan change: use one explicitly materialized base blob per changed contract plus CI event/head actor metadata, prohibit unshallow ancestry walks, and fail closed when inputs are unavailable.
```

**References:**

- REQ-4
- RISK-5
- assets/decisions.md
- docs/design-notes/architecture/architecture-notes.design.md
- docs/design-notes/project/ci-gates.design.md
- plan.md step 1.1
- plan.md steps 1.1 and 1.3
- plan.md steps 1.1 and 3.3
- plan.md steps 1.1-1.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `High` | Authority gate lacks behavior when base state is unavailable |
| `performance-m1` | `Medium` | Always-on authority gate has no materialization or actor-resolution cost bound |
| `architecture-patterns-m1` | `Medium` | Arch authority gate has no declared owner tier or host-materialized split |
| `operability-observability-m1` | `High` | Authority gate has no unavailable-base or actor behavior |

---

### [9] Contract schema changes before paired evals and installed copies

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
Summary: Step 1.1 replaces lockedBodySha256 but surviving evals, fixtures, and dogfood schema copies are deferred to 1.2, leaving 1.1 red. Recommended plan change: update architecture-notes evals/fixtures and regenerate installed schema assets in the same 1.1 commit, with schema ownership removed from 1.2.
```

**Also noted:**

```text
Summary: Architecture-notes evals and locked fixtures assert lockedBodySha256 and go red when 1.1 changes the closed schema. Recommended plan change: update the surviving eval and canonical/dogfood fixtures to lockedContentSha256 in step 1.1, preserving explicit missing/bad/valid digest cases.
```

**References:**

- REQ-4
- RISK-6
- plan.md steps 1.1 and 1.2
- plan.md steps 1.1, 1.2, 2.3
- plugins/architecture-notes/evals/architecture-notes.Tests.ps1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `High` | Schema change has no same-step surviving-eval update |
| `correctness-reliability-m1` | `High` | Contract schema changes before paired evals and installed copies |

---

### [10] Historical immutability compares the frozen manifest to itself

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Requiring the manifest file to remain byte-identical detects no edits to listed historical files. Recommended plan change: rehash every listed path, assert a non-zero expected count, and prove red on one listed-file mutation plus empty/zero-entry manifest.
```

**References:**

- REQ-6
- RISK-7
- plan.md steps 1.1 and 3.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `High` | Historical immutability compares the frozen manifest to itself |

---

### [11] Mutable receipts can widen automatic deletion authority

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `security` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: A forged same-source receipt and preview can name an unmanaged in-bound .github file because tombstones do not pin authorized payload paths/hashes. Recommended plan change: tombstone-pin immutable destination/hash authority per source/ref/version and delete only the exact intersection; legacy/unknown sets become manual-required; test forged receipts targeting unmanaged and other-plugin files.
```

**References:**

- REQ-7
- REQ-8
- assets/decisions/retirement-protocol.md
- plan.md steps 1.3 and 2.1-2.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m2` | `High` | Mutable receipts can widen automatic deletion authority |

---

### [12] One-blob permanence gate cannot introduce the first tombstone

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` · `operability-observability` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 3 |

**Description:**

```text
Summary: The plan does not distinguish first publication, fork/new branch, shallow checkout, or wrong baseline while providing no unavailable-path fixture/host. Recommended plan change: define exact PR/push baseline SHA and first-publication semantics, print baseline identity/count, fail closed on unresolvable input, and test unavailable materialization.
```

**Also noted:**

```text
Summary: The base branch lacks registry-retirements.json on first publication, but the plan says unavailable baseline materialization fails. Recommended plan change: treat a resolvable baseline with no tombstone file as an empty set, fail only when the baseline ref is unresolvable, and test both cases.
```

**Also noted:**

```text
Summary: Changed/removed/name-reuse fixtures do not falsify CI materialization failure or distinguish first publication. Recommended plan change: define missing/empty/malformed refusal and explicit first-publication handling, then execute the workflow's unavailable-baseline path expecting nonzero.
```

**References:**

- REQ-2
- RISK-4
- assets/decisions/retirement-protocol.md
- plan.md step 1.3
- plan.md steps 1.3 and 3.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Medium` | Permanence gate lacks unavailable or empty baseline proof |
| `correctness-reliability-m1` | `High` | One-blob permanence gate cannot introduce the first tombstone |
| `operability-observability-m1` | `Medium` | Required retirement baseline is undefined |

---

### [13] Root-scaffold residue loses durable discovery authority

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: After deleting the architecture-tests manifest, the reconciler no longer has a durable inventory of out-of-.github scaffold paths it must report. Recommended plan change: add tombstone-pinned manualResidue records generated from the old manifest and test recurring manual-required reporting without deletion.
```

**References:**

- assets/decisions/retirement-protocol.md
- plan.md steps 1.1, 2.1, 3.2
- plugins/architecture-tests/plugin.json scaffolds

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m2` | `High` | Root-scaffold residue loses durable discovery authority |

---

### [14] Stale automatic preview has no transition or outcome

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Explicit ApplyRetirements refuses stale preview, but the automatic path has no defined behavior when receipt/tombstone/payload changes between preview and apply. Recommended plan change: refresh stale automatic state to a new zero-deletion preview record; keep explicit apply refusal as failed with a remedy; test drift between operations.
```

**References:**

- REQ-7
- REQ-8
- RISK-2
- plan.md step 2.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `High` | Stale automatic preview has no transition or outcome |

---

### [15] Automatic retirement bypasses approval-key removal

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Explicit uninstall removes auto-approval keys before payload deletion, but automatic retirement invokes the lower removal primitive and leaves stale .vscode/settings.json entries. Recommended plan change: detect and report approval keys as manual-required residue with an exact Set-ScriptApproval.ps1 -Remove remedy, and document this skill-owned limitation without mutating .vscode automatically.
```

**References:**

- docs/design-notes/architecture/plugin-manager.design.md
- plan.md steps 2.2, 2.3, 3.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | Automatic retirement bypasses approval-key removal |

---

### [16] Irreversible publication is hidden behind an intra-step green condition

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Step 2.3 both proves the reconciler and publishes the permanent tombstone/deletes the subsystem, with no enforced boundary between them. Recommended plan change: split mechanism wiring/proof into 2.3 and atomic real tombstone plus deletion into a new dependent 2.4, adjusting the phase budget.
```

**References:**

- REQ-1
- REQ-2
- RISK-4
- plan.md step 2.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `Medium` | Irreversible publication is hidden behind an intra-step green condition |

---

### [17] Residue replay caps records but not total recurring work

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `performance` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Permanent states can stat unbounded paths and emit one record per plugin on every operation; small suite fixtures do not bound growth. Recommended plan change: impose a global per-invocation plugin/path replay budget with persisted cursor, aggregate bounded output, no hashing, fairness, and a scale fixture proving eventual sweep.
```

**References:**

- REQ-7
- RISK-8
- assets/decisions/retirement-protocol.md
- plan.md steps 2.1 and 2.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m2` | `Medium` | Residue replay caps records but not total recurring work |

---

### [18] Retirement state contents are not treated as untrusted

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `security` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: State file paths are schema-valid but recorded entries are used for stat/remedy without explicit re-confinement, enabling disclosure or misleading manual deletion guidance. Recommended plan change: re-confine every recorded path before stat/output/transition and add hostile traversal/rooted/reparse state fixtures with no outside path echo.
```

**References:**

- RISK-2
- assets/decisions/retirement-protocol.md
- plan.md steps 2.1 and 2.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `Medium` | Retirement state contents are not treated as untrusted |

---

### [19] lockedContentSha256 has no canonical computation owner

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: The plan does not define the hashed projection, self-field exclusion, normalization, or shared owner, so write and CI gates may compute incompatible digests. Recommended plan change: assign one architecture-notes-owned helper, define a closed deterministic projection/encoding, and require both gates to call it using shared canonical vectors.
```

**References:**

- REQ-4
- assets/decisions.md
- plan.md step 1.1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m2` | `Medium` | lockedContentSha256 has no canonical computation owner |

---

### [20] Phase titles hide the destructive publication boundary

| | |
|---|---|
| **Severity** | Low |
| **Concerns** | `architecture-patterns` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: Phase 1 publishes no tombstone, while Phase 2 performs the irreversible retirement and deletion under a non-destructive title. Recommended plan change: rename Phase 1 for fixtures/authority/mechanism and Phase 2 for retirement publication and subsystem deletion.
```

**References:**

- plan.md Phase 1
- plan.md Phase 2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Low` | Phase titles hide the destructive publication boundary |

---

### [21] REQ-1 step mapping contradicts step annotations

| | |
|---|---|
| **Severity** | Low |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Summary: REQ-1 maps to 1.3/3.1/3.2 while actual retirement/proof lives in 2.3/3.2/3.3. Recommended plan change: set REQ-1 Phases/Steps to 2.3, 3.2, 3.3.
```

**References:**

- REQ-1
- plan.md steps 1.3, 2.3, 3.1, 3.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Low` | REQ-1 step mapping contradicts step annotations |

---

## Recommendations

1. **\[Critical\] 34088e consumption evidence is already green without fixture reuse** — Summary: Dependency and prose markers pass before implementation, while step 4.1 does not identify cda9da's immutable fixture.
2. **\[Critical\] Closed outcomes contradict continue/block behavior** — Summary: no-match, foreign-source, manual-required, and recovered lack deterministic exit/continuation behavior and literal text can wedge ordinary operations.
3. **\[Critical\] Design-note deletion is double-booked and surviving references are unowned** — Summary: Steps 2.3 and 3.2 both claim architecture-tests design-note deletion, while the root index row and plugin-registry runtime references are not named.
4. **\[Critical\] Human lock authority has no trustworthy authorization signal** — Summary: Git author/committer identity is forgeable by the autonomous executor, so non-bot human cannot be inferred from local metadata.
5. **\[Critical\] Step 3.1 cannot preserve coverage before tests already deleted in 2.3** — Summary: Removing the arch extractor in 1.2 while independent classification waits until 3.1 leaves Phase 1/2 crosschecks able to drop arch beside known markers.
6. **\[Critical\] Two new CI gates are added with no declared host and no gate-inventory row** — Summary: Steps 1.1 and 1.3 add authority/history gates without the canonical CI inventory rows or exact hosts, while step 2.3 does not explicitly retire the old architecture-tests inventory row.
7. **\[Critical\] Prompt injection attempt detected in plan asset prose** — Summary: Reviewer classified the plan's loaded-on-demand instruction as AI-directed untrusted text.
8. **\[High\] Always-on authority gate has no materialization or actor-resolution cost bound** — Summary: Test-ArchContractAuthority.ps1 has no exact path/ownership or pure-file versus CI-materialization boundary.
9. **\[High\] Contract schema changes before paired evals and installed copies** — Summary: Step 1.1 replaces lockedBodySha256 but surviving evals, fixtures, and dogfood schema copies are deferred to 1.2, leaving 1.1 red.
10. **\[High\] Historical immutability compares the frozen manifest to itself** — Summary: Requiring the manifest file to remain byte-identical detects no edits to listed historical files.
11. **\[High\] Mutable receipts can widen automatic deletion authority** — Summary: A forged same-source receipt and preview can name an unmanaged in-bound .github file because tombstones do not pin authorized payload paths/hashes.
12. **\[High\] One-blob permanence gate cannot introduce the first tombstone** — Summary: The plan does not distinguish first publication, fork/new branch, shallow checkout, or wrong baseline while providing no unavailable-path fixture/host.
13. **\[High\] Root-scaffold residue loses durable discovery authority** — Summary: After deleting the architecture-tests manifest, the reconciler no longer has a durable inventory of out-of-.github scaffold paths it must report.
14. **\[High\] Stale automatic preview has no transition or outcome** — Summary: Explicit ApplyRetirements refuses stale preview, but the automatic path has no defined behavior when receipt/tombstone/payload changes between preview and apply.
15. **\[Medium\] Automatic retirement bypasses approval-key removal** — Summary: Explicit uninstall removes auto-approval keys before payload deletion, but automatic retirement invokes the lower removal primitive and leaves stale .vscode/settings.json entries.
16. **\[Medium\] Irreversible publication is hidden behind an intra-step green condition** — Summary: Step 2.3 both proves the reconciler and publishes the permanent tombstone/deletes the subsystem, with no enforced boundary between them.
17. **\[Medium\] Residue replay caps records but not total recurring work** — Summary: Permanent states can stat unbounded paths and emit one record per plugin on every operation; small suite fixtures do not bound growth.
18. **\[Medium\] Retirement state contents are not treated as untrusted** — Summary: State file paths are schema-valid but recorded entries are used for stat/remedy without explicit re-confinement, enabling disclosure or misleading manual deletion guidance.
19. **\[Medium\] lockedContentSha256 has no canonical computation owner** — Summary: The plan does not define the hashed projection, self-field exclusion, normalization, or shared owner, so write and CI gates may compute incompatible digests.
20. **\[Low\] Phase titles hide the destructive publication boundary** — Summary: Phase 1 publishes no tombstone, while Phase 2 performs the irreversible retirement and deletion under a non-destructive title.
21. **\[Low\] REQ-1 step mapping contradicts step annotations** — Summary: REQ-1 maps to 1.3/3.1/3.2 while actual retirement/proof lives in 2.3/3.2/3.3.


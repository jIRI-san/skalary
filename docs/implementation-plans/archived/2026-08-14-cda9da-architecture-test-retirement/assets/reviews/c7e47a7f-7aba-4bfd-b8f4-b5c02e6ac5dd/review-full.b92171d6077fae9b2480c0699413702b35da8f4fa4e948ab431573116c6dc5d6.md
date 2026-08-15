# Design Review — full report

<!-- skalary/review-full@1 -->
<!-- content-trust: reviewer-authored-data -->

| | |
|---|---|
| **Run** | `c7e47a7f-7aba-4bfd-b8f4-b5c02e6ac5dd` |
| **Review type** | `design` |
| **State** | `clean` |
| **Plan digest** | `sha256:abb634644e0e1830e247c0337a8705c6b46200b856202355f0a167020b3f6e1b` |
| **Scope digest** | `sha256:3cce65168afa2091b5657491916760ed6ec75fdbdf8807217e534e1cf71771c4` |
| **Scope** | DR round 1 of architecture-test retirement plan cda9da, including its intent, requirements, risks, decisions, retirement protocol, references, and evolution log; assess implementation feasibility and coherency with explicit attention to retirement tombstone safety and scope, transactional cleanup/replay/rollback, fail-loud arch marker retirement, retained human-owned locked maturity, first-phase verticality, overlap with plan 34088e, typed evidence falsifiability, and simplicity versus overengineering. |
| **Content trust** | `reviewer-authored-data` |
| **Requested → declared models** | GPT-5.6 Sol (copilot) → GPT-5.6 Sol (copilot) (preflight: available; degradation: none; served identity: unverified) · Claude Opus 5 (copilot) → Claude Opus 5 (copilot) (preflight: available; degradation: none; served identity: unverified) |
| **Invocations** | 14 of 28 budgeted |

## Tasks (14)

| # | Task | Concern | Declared model | Outcome | Raw findings | Diagnostic |
|---|---|---|---|---|---|---|
| 1 | `architecture-patterns-m1` | `architecture-patterns` | Claude Opus 5 (copilot) | `completed` | 12 | — |
| 2 | `architecture-patterns-m2` | `architecture-patterns` | GPT-5.6 Sol (copilot) | `completed` | 6 | — |
| 3 | `correctness-reliability-m1` | `correctness-reliability` | Claude Opus 5 (copilot) | `completed` | 13 | — |
| 4 | `correctness-reliability-m2` | `correctness-reliability` | GPT-5.6 Sol (copilot) | `completed` | 6 | — |
| 5 | `maintainability-consistency-m1` | `maintainability-consistency` | Claude Opus 5 (copilot) | `completed` | 11 | — |
| 6 | `maintainability-consistency-m2` | `maintainability-consistency` | GPT-5.6 Sol (copilot) | `completed` | 6 | — |
| 7 | `operability-observability-m1` | `operability-observability` | Claude Opus 5 (copilot) | `completed` | 9 | — |
| 8 | `operability-observability-m2` | `operability-observability` | GPT-5.6 Sol (copilot) | `completed` | 8 | — |
| 9 | `performance-m1` | `performance` | Claude Opus 5 (copilot) | `completed` | 7 | — |
| 10 | `performance-m2` | `performance` | GPT-5.6 Sol (copilot) | `completed` | 3 | — |
| 11 | `security-m1` | `security` | Claude Opus 5 (copilot) | `completed` | 8 | — |
| 12 | `security-m2` | `security` | GPT-5.6 Sol (copilot) | `completed` | 7 | — |
| 13 | `testing-evidence-m1` | `testing-evidence` | Claude Opus 5 (copilot) | `completed` | 10 | — |
| 14 | `testing-evidence-m2` | `testing-evidence` | GPT-5.6 Sol (copilot) | `completed` | 6 | — |

## Merged findings (29 of 112 raw)

### [1] Consumer fixtures do not name the existing harness or 34088e boundary

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `maintainability-consistency` · `operability-observability` · `performance` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 9 |

**Description:**

```text
34088e consumes the protocol while both epic graphs allow independent execution and duplicate fixture ownership.
```

**Also noted:**

```text
Both plans can create foreign-repo fixture infrastructure and own consumer-install lifecycle semantics.
```

**Also noted:**

```text
Schedulers see both plans as unblocked despite lifecycle consumption and overlapping fixture ownership.
```

**Also noted:**

```text
The consumer-correctness plan can run first or implement a competing protocol and lifecycle matrix.
```

**Also noted:**

```text
cda9da and 34088e can repeat subprocess-heavy scenarios in separate fixture implementations.
```

**Also noted:**

```text
Two active plans claim the same lifecycle surface without an enforceable dependency.
```

**Also noted:**

```text
Separate active plans can build incompatible consumer-install harnesses.
```

**Also noted:**

```text
The plan can create a third fixture idiom for installed behavior.
```

**Also noted:**

```text
Different test ids can green competing protocol implementations.
```

**References:**

- assets/references.md
- both epic indexes
- epic 33b1f9
- epic bcece1
- plan 34088e
- plan.md step 1.3
- plan.md step 3.1
- plan.md steps 1.3 and 2.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m2` | `Medium` | Overlapping lifecycle matrices duplicate expensive foreign-repo work |
| `testing-evidence-m2` | `Medium` | 34088e retirement overlap is not machine-sequenced |
| `architecture-patterns-m1` | `Medium` | Cross-epic ownership with 34088e is undeclared |
| `architecture-patterns-m2` | `High` | 34088e relationship is not represented in execution dependencies |
| `correctness-reliability-m1` | `Medium` | Foreign-repo fixture ownership overlaps 34088e |
| `correctness-reliability-m2` | `High` | 34088e dependency and ownership boundary is missing |
| `operability-observability-m2` | `Medium` | 34088e dependency exists only in prose |
| `maintainability-consistency-m1` | `Medium` | Consumer fixtures do not name the existing harness or 34088e boundary |
| `maintainability-consistency-m2` | `High` | 34088e reuse relationship is not encoded in execution order |

---

### [2] Degraded residue causes permanent recurring hash and report cost

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `performance` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 4 |

**Description:**

```text
Permanent reconciliation may parse every receipt, build ownership maps and hash retired payloads before an already-current return.
```

**Also noted:**

```text
Every install/update may grow to nested tombstone-receipt scans and unnecessary hashing.
```

**Also noted:**

```text
A preserved modified path is rehashed and warned on every future install/update.
```

**Also noted:**

```text
Registry disjointness and consumer matching can become nested scans.
```

**References:**

- REQ-2
- RISK-2
- plan.md step 1.1
- plan.md step 1.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m1` | `Low` | Permanent tombstone growth has no lookup cost model |
| `performance-m1` | `High` | No-op install path pays unbounded retirement work |
| `performance-m1` | `Medium` | Degraded residue causes permanent recurring hash and report cost |
| `performance-m2` | `High` | Mandatory reconciliation lacks a hot-path cost bound |

---

### [3] Design-note reconciliation is deferred past contradictory implementation

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `maintainability-consistency` · `operability-observability` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 12 |

**Description:**

```text
One large step mixes tests, irreversible deletion, shared scripts, bundles and catalogs, while headline proof lands in Phase 3.
```

**Also noted:**

```text
Tests, deletion, shared marker changes, bundle pruning and catalog generation have no clean resume boundary.
```

**Also noted:**

```text
Always-loaded notes retain arch receipt and lockedBodySha256 semantics while implementation removes them.
```

**Also noted:**

```text
A truthful inventory still sees active runner-dependent schemas, skills and guidance after step 1.3.
```

**Also noted:**

```text
crosscheck-guide and execution-guide remain installable guidance after their runner is deleted.
```

**Also noted:**

```text
Active architecture-notes workflows still point to removed runtime and receipt semantics.
```

**Also noted:**

```text
Interrupted whole-plan execution can leave catalogs, bundles and scripts inconsistent.
```

**Also noted:**

```text
Deletion precedes preservation schema, skill, eval and active-doc reconciliation.
```

**Also noted:**

```text
Installed execution and crosscheck guides remain broken until a later phase.
```

**Also noted:**

```text
Active consumers and suite metadata remain runner-dependent after deletion.
```

**Also noted:**

```text
Runtime deletion precedes schema, skill, eval and design-note decoupling.
```

**Also noted:**

```text
Deleted tests remain required until metadata regeneration in Phase 3.
```

**References:**

- REQ-1
- REQ-5
- REQ-6
- RISK-6
- RISK-7
- plan.md phase 1
- plan.md phases 1-3
- plan.md step 1.3
- plan.md steps 1.3 and 3.2
- plan.md steps 1.3-3.1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m2` | `High` | Phase 1 cannot prove its advertised vertical MVP |
| `architecture-patterns-m1` | `High` | Shipped ci assets keep instructions for the deleted architecture runner |
| `architecture-patterns-m1` | `Medium` | Phase 1 is not independently coherent or revertible |
| `architecture-patterns-m2` | `High` | Phase 1 leaves the preserved architecture tier incoherent |
| `correctness-reliability-m1` | `High` | Active ci guidance invokes the deleted runner |
| `correctness-reliability-m1` | `Medium` | Step 1.3 is an oversized inconsistent mutation |
| `correctness-reliability-m2` | `High` | Phase 1 leaves an invalid intermediate repository |
| `operability-observability-m1` | `Medium` | Mass-deletion step has no operational checkpoint |
| `operability-observability-m2` | `High` | Phase 1 does not end in an operable vertical slice |
| `maintainability-consistency-m1` | `High` | Pinned suite metadata stays stale across phases |
| `maintainability-consistency-m1` | `High` | Design-note reconciliation is deferred past contradictory implementation |
| `maintainability-consistency-m2` | `High` | Phase 1 does not leave a coherent vertical slice |

---

### [4] Forced residue removal is undefined and generic Force may over-authorize deletion

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `maintainability-consistency` · `operability-observability` · `security` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 9 |

**Description:**

```text
List, ownership, update, and explicit removal readers are not assigned behavior for a retired receipt absent from the active registry.
```

**Also noted:**

```text
The plan tests forced cleanup without assigning it to the existing uninstall path or preserving ownership on non-force removal.
```

**Also noted:**

```text
Remove-Plugin may require registry state absent in installed-only consumers and the retired name is no longer active.
```

**Also noted:**

```text
Update-Plugin -Force for unrelated drift could accidentally become permission to delete modified retired files.
```

**Also noted:**

```text
Install/update begin deleting files and list/uninstall encounter retired receipts without owning docs changes.
```

**Also noted:**

```text
A degraded retired receipt reserves paths indefinitely and collision outcomes/remedies are unspecified.
```

**Also noted:**

```text
List, remove, ownership and update can fail or overwrite residue while reconciler tests remain green.
```

**Also noted:**

```text
The protocol says forced removal without naming a command that works after catalog retirement.
```

**Also noted:**

```text
Ownership, listing and explicit cleanup semantics are missing from plan steps.
```

**References:**

- REQ-2
- RISK-2
- RISK-8
- plan.md step 1.2
- plan.md step 1.3
- plan.md steps 1.1-1.3
- plan.md steps 1.2-1.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `Medium` | Permanent residue ownership can block future destinations |
| `security-m1` | `Medium` | Forced residue removal is undefined and generic Force may over-authorize deletion |
| `testing-evidence-m1` | `Medium` | Existing receipt readers lack negative coverage for retired state |
| `architecture-patterns-m1` | `High` | Retired residue receipt has no complete reader contract |
| `correctness-reliability-m1` | `Medium` | Modified-residue remedy is not proven reachable in a foreign repo |
| `operability-observability-m1` | `High` | Residue state has no concrete operator handoff |
| `maintainability-consistency-m1` | `High` | Retired receipt has writers but no scheduled readers or removal owner |
| `maintainability-consistency-m1` | `Medium` | Plugin-manager documentation is missing from behavior reconciliation |
| `maintainability-consistency-m2` | `High` | Retired-residue removal lacks a canonical lifecycle owner |

---

### [5] Installer delete authority is absent from its architecture contract

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `maintainability-consistency` · `security` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 4 |

**Description:**

```text
Receipt-derived deletion has no contract-level requirement to resolve every target through the confinement chokepoint.
```

**Also noted:**

```text
Lexical .github confinement can follow a consumer-created junction or symlink outside the tree.
```

**Also noted:**

```text
ARCH-Install-Confinement describes writes, not automatic receipt-driven deletion and pruning.
```

**Also noted:**

```text
A new implementation could prune above .github after deleting the sole payload.
```

**References:**

- ARCH-Install-Confinement
- REQ-2
- plan.md step 1.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `High` | Automatic delete authority is not covered by install confinement |
| `security-m1` | `Medium` | Empty-parent pruning has no stated floor |
| `security-m2` | `High` | Automatic cleanup lacks link-safe path confinement |
| `maintainability-consistency-m1` | `High` | Installer delete authority is absent from its architecture contract |

---

### [6] Locked loses structural binding and enforcement while retaining its authoritative name

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `maintainability-consistency` · `operability-observability` · `security` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 9 |

**Description:**

```text
Existing contracts are provisional and lack removed fields; a stale conditional can make locked unsatisfiable without detection.
```

**Also noted:**

```text
Assert-ArchLock contains executable autonomous-transition refusal that prose and optional evals cannot replace.
```

**Also noted:**

```text
After runner fields are removed, no normative owner or deterministic Test-ArchContract behavior is specified.
```

**Also noted:**

```text
Schema shape and optional waza cases cannot prevent autonomous promotion after Assert-ArchLock is deleted.
```

**Also noted:**

```text
The executable transition authority is deleted before a replacement is assigned to architecture-notes.
```

**Also noted:**

```text
No artifact identifies the exact contract body a human approved or detects later autonomous drift.
```

**Also noted:**

```text
Deleting the body hash and lock gate leaves only prose and optional behavioral evaluation.
```

**Also noted:**

```text
A later autonomous body edit can retain locked maturity after the body hash is removed.
```

**Also noted:**

```text
Shape tests and optional behavioral evals cannot prove autonomous promotion is refused.
```

**References:**

- REQ-4
- REQ-5
- RISK-5
- plan.md phase 2
- plan.md step 2.1
- plan.md steps 1.3 and 2.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `High` | Human-only lock guard is deleted instead of re-homed |
| `security-m2` | `High` | Human-only lock authority becomes prose-only |
| `testing-evidence-m1` | `High` | REQ-4 and REQ-5 do not exercise the locked path |
| `testing-evidence-m2` | `High` | Human-only lock authority has no runnable refusal seam |
| `architecture-patterns-m1` | `Medium` | Locked loses structural binding and enforcement while retaining its authoritative name |
| `correctness-reliability-m1` | `High` | Human-only lock promotion becomes unenforced prose |
| `correctness-reliability-m2` | `High` | Locked contracts lose reviewed-content integrity |
| `operability-observability-m2` | `High` | Locked authority loses its content-binding receipt |
| `maintainability-consistency-m1` | `Medium` | Locked is defined in multiple places and checked in none |

---

### [7] Reconciliation outcomes lack exit-code and stream semantics

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `operability-observability` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 3 |

**Description:**

```text
The clean receipt is deleted, leaving no local account of what was removed or why.
```

**Also noted:**

```text
Automation cannot distinguish clean, residue, source mismatch and no match.
```

**Also noted:**

```text
Named outcomes have no structured result, persistence or exit semantics.
```

**References:**

- REQ-2
- assets/decisions/retirement-protocol.md
- plan.md step 1.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `operability-observability-m1` | `High` | Clean retirement leaves no durable deletion record |
| `operability-observability-m1` | `High` | Reconciliation outcomes lack exit-code and stream semantics |
| `operability-observability-m2` | `Medium` | Reconciliation outcomes lack a durable signalling contract |

---

### [8] Source identity can retain or disclose credentials

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `security` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
Raw repository URLs may persist userinfo and appear in diagnostics while identity semantics remain ambiguous.
```

**Also noted:**

```text
Raw repository URLs may include userinfo and become comparison keys and visible mismatch output.
```

**References:**

- REQ-2
- RISK-1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `Medium` | Receipt source can disclose embedded credentials |
| `security-m2` | `High` | Source identity can retain or disclose credentials |

---

### [9] Source normalization is the sole safety control but remains unspecified

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `maintainability-consistency` · `security` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 6 |

**Description:**

```text
Receipts combine local paths or remote URLs with changing SHAs; strict and loose comparisons fail in opposite safety directions.
```

**Also noted:**

```text
Raw receipt source labels cannot safely distinguish equivalent spellings from forks and local-to-remote transitions.
```

**Also noted:**

```text
Install and update duplicate source-context construction while legacy receipts encode unstable labels.
```

**Also noted:**

```text
Legacy free-form labels mix catalog identity with commit SHA and ambiguous URL/path forms.
```

**Also noted:**

```text
Local, remote, fork, typosquat and malformed source forms have no fail-closed rule.
```

**Also noted:**

```text
The destructive equality relation lacks a versioned identity type and legacy rules.
```

**References:**

- REQ-2
- RISK-1
- plan.md step 1.2
- plan.md steps 1.1-1.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `High` | Source normalization is the sole safety control but remains unspecified |
| `architecture-patterns-m1` | `High` | Normalized source identity is undefined against the receipt shape |
| `architecture-patterns-m2` | `High` | Source identity normalization is unspecified |
| `correctness-reliability-m1` | `High` | Same-source equivalence is left undefined |
| `correctness-reliability-m2` | `High` | Destructive source identity is underspecified |
| `maintainability-consistency-m2` | `High` | Source identity has no single migration-safe owner |

---

### [10] Successful transactions have no temporary-storage cleanup contract

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `operability-observability` · `performance` · `security` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 9 |

**Description:**

```text
Every injected fault can mean whatever seams implementation chooses and omits later-operation failure semantics.
```

**Also noted:**

```text
A killed process can split payload and receipt state because no durable journal or startup recovery exists.
```

**Also noted:**

```text
No journal distinguishes killed cleanup from user modification or records recovery direction.
```

**Also noted:**

```text
A killed process can leave an old receipt naming missing files and orphaned staging state.
```

**Also noted:**

```text
Catch rollback cannot recover process termination between payload and receipt mutation.
```

**Also noted:**

```text
No durable state supports recovery after a kill between payload and receipt changes.
```

**Also noted:**

```text
Foreign-process tests cannot mock internals and no closed mutation list exists.
```

**Also noted:**

```text
Backups can accumulate after commit, rollback, mismatch and replay.
```

**Also noted:**

```text
Backups may accumulate on successful and replayed operations.
```

**References:**

- REQ-2
- RISK-3
- plan.md step 1.2
- plan.md steps 1.2-1.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m2` | `High` | Rollback covers exceptions, not process termination |
| `performance-m1` | `Medium` | Retirement transaction staging has no cleanup bound |
| `performance-m2` | `Medium` | Successful transactions have no temporary-storage cleanup contract |
| `testing-evidence-m1` | `High` | Rollback on every injected fault is unbounded and has no seam |
| `testing-evidence-m2` | `High` | Retirement fault coverage is self-defining |
| `architecture-patterns-m2` | `High` | Transaction design handles exceptions but not crashes |
| `correctness-reliability-m2` | `High` | Crash recovery is not defined |
| `operability-observability-m1` | `Medium` | Hard-interruption replay and already-absent files are undefined |
| `operability-observability-m2` | `High` | Retirement transactions cannot recover from process interruption |

---

### [11] Tombstone removal rejection has no mechanism or falsifying test

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `maintainability-consistency` · `operability-observability` · `security` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 7 |

**Description:**

```text
Removing a retirement from both mutable canonical and generated files leaves no current-tree evidence of prior publication.
```

**Also noted:**

```text
Current generation cannot detect a record removed from both canonical and generated surfaces.
```

**Also noted:**

```text
Canonical and generated surfaces can be deleted together without a failing authority.
```

**Also noted:**

```text
Current-tree validation can green coordinated canonical and generated deletion.
```

**Also noted:**

```text
Mutable current inputs cannot prove prior publication or prevent later reuse.
```

**Also noted:**

```text
A generator cannot tell never-existed from deleted using only current input.
```

**Also noted:**

```text
The canonical current file cannot prove its own append-only history.
```

**References:**

- REQ-2
- plan.md step 1.1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m2` | `Medium` | Tombstone permanence has no durable authority |
| `testing-evidence-m1` | `High` | Tombstone removal rejection has no mechanism or falsifying test |
| `testing-evidence-m2` | `High` | Permanent tombstones have no append-only witness |
| `architecture-patterns-m2` | `High` | Tombstone permanence has no durable comparison authority |
| `correctness-reliability-m2` | `Medium` | Tombstone permanence has no trusted baseline |
| `operability-observability-m2` | `High` | Permanent tombstone removal is not detectably enforceable |
| `maintainability-consistency-m2` | `Medium` | Tombstone-removal rejection has no comparison authority |

---

### [12] Unknown-marker fallback can silently drop mixed arch evidence

| | |
|---|---|
| **Severity** | Critical (elevated — flagged under every declared model label) |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `operability-observability` · `security` |
| **Declared model labels** | Claude Opus 5 (copilot) · GPT-5.6 Sol (copilot) |
| **Raw findings** | 5 |

**Description:**

```text
A known marker in the same segment suppresses unknown-prefix scanning after the arch extractor is removed.
```

**Also noted:**

```text
Generic unknown-marker output does not explain that arch was retired or what evidence should replace it.
```

**Also noted:**

```text
Segment-level fallback skips an unknown arch token beside a recognized marker.
```

**Also noted:**

```text
A known token can suppress unknown-token discovery in the same segment.
```

**Also noted:**

```text
Unknown scanning is conditional on no recognized marker in the segment.
```

**References:**

- REQ-3
- RISK-4
- plan.md step 1.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m2` | `Medium` | Mixed evidence can hide a retired arch marker |
| `architecture-patterns-m2` | `High` | Mixed evidence markers can silently drop retired arch tokens |
| `correctness-reliability-m1` | `High` | Unknown-marker fallback can silently drop mixed arch evidence |
| `operability-observability-m1` | `Medium` | Retired arch marker gets no retirement-specific remedy |
| `operability-observability-m2` | `High` | Retired arch evidence can disappear beside a known marker |

---

### [13] Prompt injection attempt detected in plan workflow prose

| | |
|---|---|
| **Severity** | Critical |
| **Concerns** | `maintainability-consistency` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Reviewer flagged imperative workflow language inside reviewed plan assets as AI-directed data.
```

**References:**

- assets/intent.md
- plan.md Assets section

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `maintainability-consistency-m2` | `Critical` | Prompt injection attempt detected in plan workflow prose |

---

### [14] Prompt injection attempt detected in untrusted dispatch wrapper

| | |
|---|---|
| **Severity** | Critical |
| **Concerns** | `operability-observability` · `security` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
Reviewer flagged routing and handling prose placed inside the untrusted boundary.
```

**Also noted:**

```text
Reviewer flagged AI-directed handling text placed inside the untrusted boundary.
```

**References:**

- DR dispatch payload

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m2` | `Critical` | Prompt injection attempt detected in untrusted task wrapper |
| `operability-observability-m2` | `Critical` | Prompt injection attempt detected in untrusted dispatch wrapper |

---

### [15] Automatic cleanup is code-gated and cannot converge on the first old-installer operation

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `architecture-patterns` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
Existing consumers execute old bundled installer code, which ignores the new registry field until plugin-manager itself is updated.
```

**Also noted:**

```text
All planned tests can run new scripts and miss the legacy consumer transition.
```

**References:**

- REQ-2
- assets/decisions/retirement-protocol.md
- plan.md step 1.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Medium` | No fixture proves delivery through an old installed installer |
| `architecture-patterns-m1` | `High` | Automatic cleanup is code-gated and cannot converge on the first old-installer operation |

---

### [16] Coverage-baseline removal contract and generic marker coverage are unowned

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `architecture-patterns` · `maintainability-consistency` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 6 |

**Description:**

```text
One test id can green source binding, residue, replay, reporting and rollback; REQ-3 also omits the legacy warn-only condition.
```

**Also noted:**

```text
RuntimeSurfaceAbsent appears only in requirements while Phase 1 deletion precedes the active-surface proof in Phase 3.
```

**Also noted:**

```text
Deleting ArchEvidence tests requires explicit inventory removals while unknown-prefix coverage must migrate.
```

**Also noted:**

```text
A test marker can appear in the receipt without any executable test carrying that id.
```

**Also noted:**

```text
Generic unknown-prefix coverage can be deleted with arch-specific tests.
```

**Also noted:**

```text
Unknown-marker severity depends on evidence-required, not stage.
```

**References:**

- REQ-1
- REQ-2
- REQ-3
- REQ-6
- RISK-4
- assets/requirements.md
- plan.md step 1.3
- plan.md steps 1.3 and 3.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m1` | `Low` | REQ-3 conflates unsupported with unrun and omits warn-only behavior |
| `testing-evidence-m1` | `High` | REQ-1 evidence is authored by no owning step |
| `testing-evidence-m1` | `High` | Coverage-baseline removal contract and generic marker coverage are unowned |
| `testing-evidence-m1` | `Medium` | Test evidence ids are not bound to discovered test names |
| `architecture-patterns-m1` | `Medium` | Evidence ids are coarser than the behaviors they gate |
| `maintainability-consistency-m1` | `Medium` | Architecture test deletion has no explicit test disposition list |

---

### [17] Direct install or update of a retired name fails before reconciliation

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Registry name lookup throws before the proposed reconciler, so the most likely user action gets a generic not-found error and no cleanup.
```

**References:**

- REQ-2
- plan.md step 1.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `High` | Direct install or update of a retired name fails before reconciliation |

---

### [18] Foreign-repo fixtures can breach suite runtime with no lawful escape

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `performance` · `testing-evidence` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 3 |

**Description:**

```text
The plan adds many subprocess scenarios but its local proof may not run the clocked budget gate.
```

**Also noted:**

```text
Subprocess-per-case foreign-repo tests and per-mutation fault coverage can add tens of seconds.
```

**Also noted:**

```text
Profiles can be clean while suite-runtime remains stale.
```

**References:**

- REQ-6
- plan.md step 3.2
- plan.md steps 1.3 and 2.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m1` | `High` | End-to-end fault matrix has no runtime budget |
| `performance-m1` | `Medium` | Suite metadata refresh does not remeasure the enforced ceiling |
| `testing-evidence-m1` | `Medium` | Foreign-repo fixtures can breach suite runtime with no lawful escape |

---

### [19] No step owns atomic insertion of the architecture-tests tombstone

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Adding it before source deletion violates disjointness; omitting it until later leaves mechanism tests detached from the real record.
```

**References:**

- REQ-2
- plan.md steps 1.1 and 1.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `High` | No step owns atomic insertion of the architecture-tests tombstone |

---

### [20] One reconciliation fault can block unrelated operations without bypass

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `correctness-reliability` · `operability-observability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
A locked or unreadable retired file prevents the mandatory transaction reaching any closed outcome.
```

**Also noted:**

```text
Malformed receipts, locks and ACL failures can brick all plugin management.
```

**References:**

- RISK-3
- assets/decisions/retirement-protocol.md
- plan.md step 1.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `High` | Retirement failure can wedge every unrelated install and update |
| `operability-observability-m1` | `High` | One reconciliation fault can block unrelated operations without bypass |

---

### [21] Retirement reconciler duplicates Remove-Plugin instead of extending one removal engine

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `architecture-patterns` · `maintainability-consistency` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
A second receipt-driven deletion path would diverge from Remove-Plugin, especially around modified residue and receipt disposition.
```

**Also noted:**

```text
The reconciler repeats Remove-Plugin hash, delete, prune and receipt semantics.
```

**References:**

- assets/decisions/retirement-protocol.md
- plan.md step 1.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `High` | Retirement reconciler duplicates Remove-Plugin instead of extending one removal engine |
| `maintainability-consistency-m1` | `High` | Receipt removal logic would have two sources of truth |

---

### [22] Rollback data is destroyed and no executable runbook is named

| | |
|---|---|
| **Severity** | High |
| **Concerns** | `architecture-patterns` · `operability-observability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
A restored prior-ref payload is automatically retired again on a later current-source operation.
```

**Also noted:**

```text
Deleting the receipt removes the prior ref needed for pinned recovery.
```

**References:**

- RISK-8
- assets/decisions/retirement-protocol.md
- plan.md step 3.1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | Permanent tombstone defeats the documented external rollback |
| `operability-observability-m1` | `High` | Rollback data is destroyed and no executable runbook is named |

---

### [23] Active-surface inventory can scan growing archived history

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `performance` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
An exclusion scan scales with immutable archive growth.
```

**References:**

- RISK-7
- plan.md step 3.2

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `performance-m1` | `Medium` | Active-surface inventory can scan growing archived history |

---

### [24] Generic automatic retirement is overengineered without a rejected simpler path

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` · `correctness-reliability` · `maintainability-consistency` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 3 |

**Description:**

```text
A broad deletion framework is introduced for one unused plugin without evidence of affected consumers or a recorded cheaper alternative.
```

**Also noted:**

```text
The highest-risk deletion mechanism is justified without establishing that any reconcilable install exists.
```

**Also noted:**

```text
A permanent schema, registry field, receipt state and transaction engine are added for one unused plugin.
```

**References:**

- RISK-8
- assets/decisions.md
- assets/references.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | Permanent generic retirement subsystem lacks the forcing constraint |
| `correctness-reliability-m1` | `Medium` | Affected consumer population is asserted rather than verified |
| `maintainability-consistency-m1` | `Medium` | Generic automatic retirement is overengineered without a rejected simpler path |

---

### [25] Historical immutability is proved only on synthetic boundaries

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `testing-evidence` |
| **Declared model labels** | GPT-5.6 Sol (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
An overreach fixture does not prove actual archived plans, transcripts and reports stayed byte-identical.
```

**References:**

- REQ-6
- RISK-7

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `testing-evidence-m2` | `Medium` | Historical immutability is proved only on synthetic boundaries |

---

### [26] Irreversible deletion ships without preview or staged release

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `operability-observability` · `security` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
Consumers cannot inspect planned deletion before an unrelated install mutates their repo.
```

**Also noted:**

```text
The first tombstone and deletion engine land together with no kill switch.
```

**References:**

- RISK-8
- plan.md step 1.2
- plan.md steps 1.2-1.3

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `security-m1` | `Medium` | Irreversible deletion ships without preview or staged release |
| `operability-observability-m1` | `Medium` | Destructive cleanup has no preview |

---

### [27] Retired receipt breaks older mixed-version tooling

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
Closed older schemas and readers may reject the new state and observed-hash shape.
```

**References:**

- REQ-2
- plan.md step 1.1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `correctness-reliability-m1` | `Medium` | Retired receipt breaks older mixed-version tooling |

---

### [28] Scaffolded consumer state is unreachable and unreported

| | |
|---|---|
| **Severity** | Medium |
| **Concerns** | `architecture-patterns` · `correctness-reliability` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 2 |

**Description:**

```text
Architecture-tests may scaffold config and receipts under docs, which installer confinement cannot delete.
```

**Also noted:**

```text
First-use files outside .github remain after receipt cleanup and violate the stated end state.
```

**References:**

- ARCH-Install-Confinement
- assets/intent.md

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `architecture-patterns-m1` | `Medium` | Retirement omits scaffold residue outside .github |
| `correctness-reliability-m1` | `Medium` | Scaffolded consumer state is unreachable and unreported |

---

### [29] Registry retirement file paths and gate wiring are unspecified

| | |
|---|---|
| **Severity** | Low |
| **Concerns** | `maintainability-consistency` |
| **Declared model labels** | Claude Opus 5 (copilot) |
| **Raw findings** | 1 |

**Description:**

```text
The canonical file, schema location, registry schema update and payload-scope inclusion are not pinned.
```

**References:**

- plan.md step 1.1

**Raw records:**

| Task | Severity | Title |
|---|---|---|
| `maintainability-consistency-m1` | `Low` | Registry retirement file paths and gate wiring are unspecified |

---

## Recommendations

1. **\[Critical\] Consumer fixtures do not name the existing harness or 34088e boundary** — Add the cross-epic dependency and define protocol versus broad-matrix ownership.
2. **\[Critical\] Degraded residue causes permanent recurring hash and report cost** — Bound report cardinality and define a cheap acknowledged steady state.
3. **\[Critical\] Design-note reconciliation is deferred past contradictory implementation** — Decouple architecture-notes and refresh suite metadata before deleting runtime; add a Phase-1 install crosscheck.
4. **\[Critical\] Forced residue removal is undefined and generic Force may over-authorize deletion** — Add reader-side retired receipt cases, including collision and explicit cleanup.
5. **\[Critical\] Installer delete authority is absent from its architecture contract** — Reject reparse points through every target path, revalidate under a mutation lock and test hostile links.
6. **\[Critical\] Locked loses structural binding and enforcement while retaining its authoritative name** — Add a script-mediated decision with injectable execution context or narrow the requirement to policy.
7. **\[Critical\] Reconciliation outcomes lack exit-code and stream semantics** — Define a closed result object, operation summary, remedies and exact process behavior.
8. **\[Critical\] Source identity can retain or disclose credentials** — Strip and redact userinfo before persistence/comparison/output and add sentinel-secret tests.
9. **\[Critical\] Source normalization is the sole safety control but remains unspecified** — Create one shared source API with stable catalog identity, ref separation and legacy parsing.
10. **\[Critical\] Successful transactions have no temporary-storage cleanup contract** — Add a durable closed-state journal and hard-kill tests at every mutation boundary.
11. **\[Critical\] Tombstone removal rejection has no mechanism or falsifying test** — Add a durable baseline and red cases for canonical-only and coordinated removal.
12. **\[Critical\] Unknown-marker fallback can silently drop mixed arch evidence** — Classify every marker token independently and test mixed forms in source and installed bundles.
13. **\[Critical\] Prompt injection attempt detected in plan workflow prose** — Keep workflow policy in trusted customizations and make plan status descriptive.
14. **\[Critical\] Prompt injection attempt detected in untrusted dispatch wrapper** — Keep routing metadata outside the untrusted payload and pass only plan data or opaque paths inside it.
15. **\[High\] Automatic cleanup is code-gated and cannot converge on the first old-installer operation** — Document the delivery sequence and add an old-installer fixture; narrow the one-operation convergence claim.
16. **\[High\] Coverage-baseline removal contract and generic marker coverage are unowned** — Author the inventory test in step 1.3 and extend it with historical boundaries later.
17. **\[High\] Direct install or update of a retired name fails before reconciliation** — Resolve tombstones before missing-plugin failure and test direct retired-name install/update.
18. **\[High\] Foreign-repo fixtures can breach suite runtime with no lawful escape** — Cap process tests, move fault seams in-process, reuse fixtures and declare an added-runtime budget.
19. **\[High\] No step owns atomic insertion of the architecture-tests tombstone** — Assign tombstone insertion and source deletion to one green commit and gate each step boundary.
20. **\[High\] One reconciliation fault can block unrelated operations without bypass** — Define a rollback-complete failure outcome and whether unrelated requested work proceeds, with an explicit escape path.
21. **\[High\] Retirement reconciler duplicates Remove-Plugin instead of extending one removal engine** — Extract one shared removal primitive and make Remove-Plugin an explicit touched surface.
22. **\[High\] Rollback data is destroyed and no executable runbook is named** — Persist source/ref in a retirement record and document a literal recovery command, verification and re-retirement caveat.
23. **\[Medium\] Active-surface inventory can scan growing archived history** — Use include-rooted active paths and synthetic archived overreach fixtures.
24. **\[Medium\] Generic automatic retirement is overengineered without a rejected simpler path** — Adopt report-and-instruct cleanup or document why automatic deletion is required.
25. **\[Medium\] Historical immutability is proved only on synthetic boundaries** — Capture a bounded pre-retirement path-and-SHA manifest and verify it after the change.
26. **\[Medium\] Irreversible deletion ships without preview or staged release** — Add report-only preview and per-invocation opt-out; consider shipping the engine before the tombstone.
27. **\[Medium\] Retired receipt breaks older mixed-version tooling** — Define backward compatibility or a version floor and test the prior reader plus zero-residue case.
28. **\[Medium\] Scaffolded consumer state is unreachable and unreported** — Report scaffold residue and its manual remedy without deleting it.
29. **\[Low\] Registry retirement file paths and gate wiring are unspecified** — Name all paths and validation/generator wiring in step 1.1.


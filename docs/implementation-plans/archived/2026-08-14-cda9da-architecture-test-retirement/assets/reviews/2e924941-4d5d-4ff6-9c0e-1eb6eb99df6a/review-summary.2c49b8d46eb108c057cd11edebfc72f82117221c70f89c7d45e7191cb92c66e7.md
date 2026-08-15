# Design Review — summary

<!-- skalary/review-summary@1 -->

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

## Attendance

| Outcome | Tasks |
|---|---|
| `completed` | 14 |
| `failed` | 0 |
| `timed-out` | 0 |
| `omitted` | 0 |
| `cancelled` | 0 |
| `pending` | 0 |
| **planned** | 14 |

## Merged findings (47 of 47 raw)

| # | Severity | Title |
|---|---|---|
| 1 | Critical | Prompt injection attempt detected in normal plan workflow prose |
| 2 | High | Bootstrap swallows the new blocking retirement exit code |
| 3 | High | Destructive confinement guards lack explicit negative fixtures |
| 4 | High | Failed retirement transactions have no retry or repair transition |
| 5 | High | History-aware tombstone gate has no defined history source |
| 6 | High | Human-only lock promotion loses its enforcement point when the runner is deleted |
| 7 | High | Phase 1 deletes the evidence executor dependency before arch evaluator removal |
| 8 | High | Pre-retirement fixture is captured after retirement changes |
| 9 | High | Preview override lacks refusal evidence |
| 10 | High | Recovery trusts an underspecified transaction journal |
| 11 | High | Renaming lockedBodySha256 has no migration path for scaffolded consumer schemas |
| 12 | High | Retired plugin name becomes a state path with no declared confinement |
| 13 | High | Runtime deletion still precedes gate and fixture migration |
| 14 | High | Step 1.3 deletes ArchReceipt.psm1 while PlanEvidence.psm1 still imports it until step 3.1 |
| 15 | High | Step 1.3 deletes the arch runtime while evaluator bundles and suite metadata still depend on it |
| 16 | High | The pre-change historical manifest is captured after mutation phases |
| 17 | High | The replacement lock digest does not preserve human authority |
| 18 | High | lockedContentSha256 has no always-on verifier after runner removal |
| 19 | Medium | Added-runtime ceiling is unquantified and duplicates existing budget authority |
| 20 | Medium | Capped path records can under-report the preview and deletion audit |
| 21 | Medium | Design-note ownership for retirement and architecture-test removal is not explicit |
| 22 | Medium | Hard-kill recovery tests duplicate deterministic journal fault seams |
| 23 | Medium | Historical baseline is introduced after mutation begins |
| 24 | Medium | Historical baseline is scheduled after repository mutation |
| 25 | Medium | History-aware permanence gate has an unstated growing cost |
| 26 | Medium | Journal recovery has no declared owner scope or relationship to existing rollback |
| 27 | Medium | Measured added-runtime ceiling has no owner artifact marker or failure condition |
| 28 | Medium | Mixed-version installer copies can mutate over a pending journal |
| 29 | Medium | PluginCatalog.GeneratedArtifacts names a test no step owns |
| 30 | Medium | Preview and journal may drive deletion without re-derivation from receipt authority |
| 31 | Medium | Retirement absence checks lack seeded-violation proof |
| 32 | Medium | Retirement records are routed into the Copilot CLI marketplace catalog |
| 33 | Medium | Retirement-specific runtime ceiling duplicates the budget authority |
| 34 | Medium | Runtime ceiling remains undefined |
| 35 | Medium | Step 1.3 fuses the generic retirement mechanism with its first use |
| 36 | Medium | Step 3.3 invents an added-runtime ceiling beside the repository budget contract |
| 37 | Medium | Subprocess and bundle test fan-out is called bounded but has no cap |
| 38 | Medium | Successful journal recovery leaves no result in the closed outcome set |
| 39 | Medium | Terminal states can become silent while manual work remains |
| 40 | Medium | The 34088e ownership boundary has no acceptance evidence |
| 41 | Medium | The 34088e ownership boundary is asserted without evidence |
| 42 | Medium | The CEP bundle is missing from marker and bundle reconciliation |
| 43 | Medium | The history-aware permanence gate adds a git dependency to a pure-file validator |
| 44 | Medium | The retirement runtime budget remains non-falsifiable |
| 45 | Medium | Tombstone permanence gate has an unbounded history cost |
| 46 | Low | ARCH-Install-Confinement is updated without its paired architecture note |
| 47 | Low | Dedicated target-retired exit code appears in no acceptance criterion |


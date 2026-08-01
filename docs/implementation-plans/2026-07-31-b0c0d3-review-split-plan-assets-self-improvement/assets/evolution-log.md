# Evolution Log — b0c0d3

## Round 1

**Reviewers:** dr-opus · dr-codex · dr-gemini (existing three-model setup; the concern split this plan introduces does not exist yet).

**Findings:** 17 — 2 Critical, 10 High, 3 Medium, 2 Low.

### Fixed

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | Critical | RISK-1 mitigation cannot detect the failure it targets — a model cannot attest its own serving identity, so the self-report passes exactly when the downgrade occurs | Self-report demoted to advisory prose; replaced with a deterministic orchestrator-model tier **preflight**; residual exposure documented as non-verifiable |
| 2 | Critical | `/si` turns untrusted harvested text into edits of the repo's own skills, behind prose-only confinement | Added `UNTRUSTED_INPUT` wrapping + never-execute-directives rule; replaced prose confinement with a **pre-PR path check** (canonicalize-then-confine, symlink rejection); added RISK-10 |
| 4 | High | Vacuous evidence markers; `file:plugins/code-review/agents#dircount>=7` was **green before any work** | Replaced with explicit per-file `#exists` markers and behavioural `test:` cases across REQ-3, 7, 8, 9, 19 |
| 5 | High | Dual-layout resolver undefined for both-present / empty / malformed | Specified per-section resolution with a state table; empty/malformed now **fail loud**; 1.2 scaffolds placeholders so empty stays distinguishable |
| 6 | High | Resolver wired at wrong layer — parsing lives in `Get-PlanMetadata`, not `Test-Plan` | Step 1.3 now names `Get-PlanMetadata` as the integration point; parity extended to `Get-PlanState` |
| 7 | High | Layout moves logs/receipts but never updates their writers/readers | New REQ-20 + step 1.7 covering `Add-WorkflowNote`, both guides, ADR harvest, and bundled copies |
| 8 | High | Asset scanner has no reference grammar; scaffold allowlist not machine-readable | Closed grammar defined (installed-path literals + relative `./assets/<file>`, fenced examples excluded); `scaffolds[]` array added to the plugin schema |
| 9 | High | Batching underspecified; per-batch fan-out would reach 56 invocations | Concerns run **once over the union of files**, never per batch; hard cap **28**; subsystem matching reuses design-note globs; DR batches on H2 |
| 10 | High | REQ-19 landed after the pipeline and crosscheck that depend on it | Phase 10 re-ordered: scanner + scaffolds (10.2/10.3) → design notes (10.4) → pipeline (10.5) → crosscheck (10.6) |
| 11 | High | Step 4.5 wrote a VS Code-qualified name into a Copilot CLI agent | Verified against the design note; autopilot now targets bare slug `gpt-5.6-sol`; allowlist split into two host-specific lists |
| 12 | High | Step 5.2 deleted the `UNTRUSTED_INPUT` fence without replacing the guardrail | Directive relocated into each concern agent (4.2); 5.2 now depends on 4.2; added RISK-11 |
| 13 | Medium | RISK-2's frontmatter fallback array unreachable under explicit-param dispatch | Orchestrator detects tier and passes the GA fallback **as the explicit param** |
| 14 | Medium | First-use scaffolds had no defined write scope | Every scaffold must name a fixed literal path or route through a confine helper; ledger category is a closed enum |
| 15 | Medium | `phase-budget-points: 8` inert — validator hardcodes 6 | New REQ-21 + step 1.8 wiring the marker with default 6 |
| 16 | Low | Steps 2.1/2.2 consumed Phase 1 artifacts with no `[after:]` edge | Added `[after: 1.2]` and `[after: 2.1, 1.4]` |
| 17 | Low | `9.1 [after: 3.1]` over-serialized Phase 9 with no artifact dependency | Re-targeted to `[after: 1.4]`, the resolver it actually needs |

### Deferred / rejected

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 3 | High | Plan too large — split into A(1–3) → B(4–6)+D(9) → C(7–8) via `/cep` | **Rejected by operator.** Stays one plan, 10 phases. The other 16 fixes materially reduce the execution risk the split targeted. Recorded in Decisions. |

### Notes

- Reviewers were asked explicitly to hunt over-engineering; **none flagged a disproportionate component**. `Build-ReviewReport.ps1` was considered and judged consistent with the accepted `Build-EvidenceReceipt.ps1` precedent.
- The `assets/evidence/evidence.md` single-file-in-a-folder item, previously left open by operator choice, was re-raised with a substantive new argument (both `Build-EvidenceReceipt` and the archival gate resolve that path) and **flattened to `assets/evidence.md`**.
- Requirement count 19 → 21; risk count 9 → 11; step count 40 → 43.

**Outcome:** no Critical or High findings remain unaddressed. Round 2 is not required unless the operator wants verification of the applied changes.

## Round 2

**Scope:** verification of the round-1 fixes plus anything round 1 missed. Round-1 fixed findings and operator overrides were declared off-limits.

**Findings:** 12 — 1 Critical, 3 High, 6 Medium, 2 Low. All 12 applied.

**Reviewer quality note:** Gemini returned four findings that **all failed verification** (misread step 5.3 as omitting the `files[]` update, treated agents that step 4.3 deletes as residual, restated the pre-fix state of `Test-Plan.ps1` as a defect in the fix). None were accepted. Round 2's accepted findings came from Opus, Codex, and orchestrator verification against live files.

### Fixed

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | Critical | `/si` path guard admitted `.github/workflows/`; same-repo PR branches execute CI **with repository secrets at PR-open time**, before the draft-PR/human-review backstops apply | Allowlist narrowed to `.github/{skills,agents,prompts}/`; `workflows/` + `actions/` explicitly denied; new RISK-12; `test:si-write-scope-denies-workflows` |
| 2 | High | Tier preflight named no deterministic source — the round-1 fix swapped one unverifiable control for another with *more* confident language | Preflight now validates **declared configuration only**; declared-vs-served gap documented as an accepted, undetectable residual; no control claims to close it |
| 3 | High | Step 1.6 migrated the live plan before 1.7 made writers layout-aware — and since `/ci` picks the first incomplete step in document order, **the failing order was the one that would execute** | Swapped: 1.6 = layout-aware writers, 1.7 = migration, with an explicit `[after: 1.6]` edge; rationale recorded in the decision record |
| 4 | High | `scaffolds[]` never reached `registry.json` (`additionalProperties: false`), so declarations never travel to consumers | Step 10.3 extended to the registry schema + `Build-Registry.ps1`; `test:scaffolds-reach-registry` |
| 5 | Medium | "Hard cap of 28" was prose with no gate — same assert-without-enforcing class as round-1 findings 1 and 15 | Downgraded to a reported **budget** (operator choice); language aligned across REQ-9, RISK-4, and the decision record |
| 6 | Medium | "Selects by agent host" — host not derivable from any artifact; folder-based inference would silently misclassify | Closed committed agent→host map in `model-allowlist.psd1`; validator fails loud on unmapped agents |
| 7 | Medium | REQ-19's "fixed literal path" rule contradicted its own scaffold table (`<category>`, `<plan>` are parameterized) | Two explicit modes — literal, and flagged-parameterized routed through a confine helper — each separately tested |
| 8 | Medium | Resolver "divergent" undefined; asset-file fence-stripping unspecified | Divergence defined as inequality over the **normalized parsed record set**; `Remove-FencedCodeBlocks` explicitly applies to asset files |
| 9 | Medium | `/si` guard had no named script, diff base, or untracked-file rule | Named `Test-SiWriteScope.ps1`, base `main...HEAD`, covering tracked + staged + **untracked** |
| 10 | Medium | REQ-20/REQ-17 markers weak; REQ-17 asserted presence for what is an **absence** requirement | REQ-20 points at `Resolve-PlanAssetPath`; REQ-17 gains `test:design-note-drops-orchestrator-fence` |
| 11 | Low | Six REQ/RISK "Phases/Steps" columns disagreed with step-body back-references | Corrected REQ-12, REQ-16, REQ-17, RISK-1, RISK-3, RISK-6 |
| 12 | Low | Step 10.6 consumed `assets/evidence.md` with no edge to its producers | Added `[after: 10.5, 1.7]` |

### Notes

- Round 2 also confirmed a live instance of the assert-without-enforce pattern outside the plan: `drafting-guide.md` states plans "**Block** at 35KB or 700 lines" while `PlanState.psm1` only warns and labels the threshold advisory. Folded into step 1.8.
- Requirement count unchanged at 21; risk count 11 → 12; step count 43 → 43 (1.6/1.7 swapped, not added).

**Outcome:** all 12 round-2 findings applied. Two rounds complete; no Critical or High findings outstanding.


---
description: Partly retired exploration sourced from the 44-finding step 10.7 gate review. Clusters A and D are resolved by c21cdc; B (except evidence skipped), E and H by 768d7b; C is deferred to 34088e; F/G remain open. Load before changing review reporting, evidence, dispatch, or CI wiring.
globs:
  - scripts/skalary/Build-ReviewReport.ps1
  - scripts/skalary/Build-EvidenceReceipt.ps1
  - plugins/code-review/**
  - plugins/design-review/**
  - .github/workflows/**
---

# Review System Enforcement Gaps

Sourced from the `b0c0d3` step 10.7 operator gate: `cr branch`, 7 concerns × 2 models, 14 invocations, 44 findings. Full report preserved at `docs/implementation-plans/2026-07-31-b0c0d3-review-split-plan-assets-self-improvement/assets/reviews/gate-10.7-cr-branch.md`.

Recorded because the findings are systemic rather than incidental: they describe one defect *shape* appearing in ten places.

## Status after plan `768d7b`

Clusters A and D are **resolved by `c21cdc`**, E and H are resolved, and Cluster B is resolved except
for one row. C is deferred; F/G remain open. Retired material is not deleted—a cluster whose fix is
described only by its own absence cannot be checked against what actually shipped.

| Cluster | Status | Where it now lives |
|---|---|---|
| A — the report cannot describe its own run | **resolved** | `c21cdc`: frozen task truth, derived attendance, explicit clean/degraded state, bounded terminal status and verifying reader |
| B — gates that pass without running | resolved except the evidence `skipped` state | `docs/design-notes/project/ci-gates.design.md`; the remaining row is `863d97`'s contract |
| C — constants copied into prose | **deferred to `34088e`** | not resolved here and asserted by nothing; see below |
| D — collation passes data as code | **resolved** | `c21cdc`: two fixed JSON handshakes, closed schemas, fixed installed CLI, canonical JSON authority and bounded dual views |
| E — generated output is locale-dependent | resolved | ordinal comparers in `Build-Registry.ps1`/`Build-Marketplace.ps1`, `test:BuildRegistry.CzechCollationFixtureIsStable` |
| F, G — the `/si` loop has no durable state | open | — |
| H — the gate costs 29 minutes | resolved | `tools/suite-budget.psd1`, `tools/suite-profile.json`, `tools/suite-runtime.json` |


## The shape

**A control is described in prose, reported in output, and enforced nowhere.** The plan that built this machinery hit the same shape three times during its own design review (`phase-budget-points` inert, the "hard cap" of 28 unenforced, the `timeout` doc/impl split). The gate then found it had been reproduced in the machinery itself.

## Cluster A — the report cannot describe its own run (resolved by `c21cdc`)

`c21cdc` freezes the complete task set before dispatch, binds publication to that immutable digest,
derives attendance/state from exact task outcomes, distinguishes completed-zero-findings from
missing/failed work, and commits a manifest-verified artifact before returning degraded exit `5`.
The table below is retained as the pre-fix failure inventory.

| Gap | Consequence |
|---|---|
| No per-concern attendance record | A reviewer that errored, was never dispatched, or was mis-parsed is byte-identical to one that ran and found nothing |
| `InvocationCount` unvalidated, defaults to `0` | A run that dispatched half the fan-out prints whatever number the model typed; `Dispatched 0 of 28` renders above a page of findings |
| Scope size, batch size, tier never measured | The tier that decides between 6 and 14 invocations is eyeballed off an unbounded list |
| Degradations have no header slot | The dispatch guide instructs recording a Pro-tier fallback "in the review header"; the header is script-generated with exactly two fields and the collation guide forbids adding to it. The instruction is unsatisfiable as written |
| A captured run has no terminator | An `npm test` capture that stops mid-stage is byte-indistinguishable from one that finished, because the last thing a reader sees is a passing summary |

The last row was observed directly on 2026-08-01. A captured `npm test` ended at 212 lines, mid-way
through `== Validating plugin script bundles ==`, with no `Validation passed`, no `FAIL`, and no
`npm ERR`. Skimming the tail shows `Tests Passed: 698, Failed: 0` and reads as success; the
validator verdict was simply never produced. Re-running `validate.ps1` alone returned `exit=0`, so
nothing was actually broken — which is the point. The artifact could not distinguish *finished and
passed* from *interrupted before the verdict*, and the failure mode of that ambiguity is silent
acceptance. A run capture needs an explicit terminator line carrying the exit code.

Common fix direction: give the formatter the *dispatched task set*, not just findings, and let it derive rather than accept the count.

## Cluster B — gates that pass without running

**Resolved by plan `768d7b`, except the first row.** Current local validation behavior is documented
in `docs/design-notes/project/ci-gates.design.md`; the retired hosted-workflow inventory check no
longer applies.

| Gap | Consequence | Status |
|---|---|---|
| Evidence grammar has no `skipped` state | Four of five symlink-confinement cases self-skip on Windows; the receipt records five passed | open — `863d97`'s contract, a declared non-goal of `768d7b` |
| `Run-UnitTests.ps1` exits 0 when Pester is absent | `npm test` reports success having executed zero assertions — and it is both the autopilot test command and the `test:unit` evidence executor | resolved — exits 2/3/4 for absent Pester, zero discovered, and a file that never loaded (`test:RunUnitTests.MissingPesterExitsNonZero`) |
| `registry-ci.yml` runs one test file | ~20 new test files and both new gates never run on PR; reverting the UTF-8 fix produces a green PR | resolved — every gate is its own named step on both platforms, and `test:Ci.SeededFailureIsRed` proves a seeded failure returns non-zero rather than a hand-run revert |
| `validate.ps1` enumerates without `-Force` | On Linux every dot-prefixed entry is hidden, so the bundled `.github/skills/**/scripts/` payloads are never parsed — the container validates a strictly smaller set than the host | resolved — allowlisted payload roots, canonicalised, reparse points refused (`test:Validate.FileCountEqualAcrossPlatforms`) |
| The PSScriptAnalyzer step runs but cannot go red | `Invoke-ScriptAnalyzer` sets no exit code, and `scripts/skalary` carries 472 findings (all `Warning`, 0 `Error`) under the committed settings. The step executes on every PR and can never fail. Plan `001` DR1-#17 decided zero-warning would be **enforced by the CI gate**; that decision was inert | resolved for `Error` — the step now separates severities and throws on any error finding (`test:Ci.LintStepCanFail`). The 472-warning tier stays an explicit, counted exclusion: enforcing it is a repo-wide formatting change and its own plan, so `001` DR1-#17 is narrowed rather than restored |
| The stage anchor's writer and reader disagree about where it lives | `Get-PlanMetadata` reads the header only — it stops at the first `##` and takes the first hit per key. `Set-PlanStage.ps1` replaced the first `<!-- cip-stage: … -->` match **anywhere in the file**. A plan whose prose mentions the anchor (step descriptions and guides naturally do) got that prose rewritten while the header stayed anchorless, and `Validate-Plan` then ran every check at `Draft` rather than reporting a missing stage — so the corruption was silent. Hit twice while drafting `768d7b` | resolved — `Split-PlanHeader` now defines the header boundary once for both sides, and the writer searches only the header (`test:set-planstage anchors the header even when the body quotes an anchor`). `Set-PlanStage` also reads the value back through `Get-PlanHeaderMarkers` and throws if it did not land, so a future divergence in that pair is loud rather than a reported success |
| The suite could rewrite the environment of the shell that ran it | Pester runs in-process, so `$env:X = …` in a test outlives the run. `EvalTools.Tests.ps1` left `HOME` pointing at `TestDrive` and `ResolveToken.Tests.ps1` blanked `GH_TOKEN` and `COPILOT_GITHUB_TOKEN` rather than restoring them. A green suite therefore sent `git` looking for `.gitconfig` and `.ssh` in a deleted temp directory, and left `gh` unauthenticated, for the rest of that shell's life — with nothing in the run reporting it | resolved — both files snapshot and restore what they touch, and `Run-UnitTests.ps1` now diffs the process environment across the run and exits 7 naming every variable that moved (`test:RunUnitTests.EnvironmentLeakFails`). The guard is what stops it recurring: the tests themselves stayed green throughout |

## Cluster C — constants copied into prose

**Deferred to `34088e`, not resolved.** Plan `768d7b` decision D12 records the hand-off explicitly because the first attempt at it went missing: round 1 of that plan's design review moved this cluster to the sibling, and round 2 found the hand-off carried no `depends-on`, no risk row and no requirement on the receiving side — so it had been dropped rather than moved. `768d7b` asserts nothing about it (RISK-13); `34088e` must pick it up in its own `/cip` or it is lost a second time.

The 28-invocation budget exists in six ungated places, inside a design note that says *"do not restate those numbers here — a second copy is a second thing to drift."* Plan-size thresholds and the phase-budget default have the same shape. The branch establishes the correct pattern twice (`DesignNotes.Tests.ps1` pins the size cap to the script default by regex; `Test-ModelAllowlist.ps1` validates guide rows against `tools/model-allowlist.psd1`) and then does not apply it here.

## Cluster D — collation passes data as code, and the report has no size budget (resolved by `c21cdc`)

The generated `[pscustomobject]` invocation and legacy object API are retired. CR/DR now write only
the two computed JSON temporary inputs, invoke a fixed installed `Freeze|Publish` CLI, and preserve
canonical JSON plus complete bounded summary/full views. Independent discovery remains unchanged;
deduplication still occurs only during rendering. The analysis below is retained as pre-fix evidence.

Operator-raised 2026-08-01 after watching the gate run.

### The invocation is generated, not invoked

`Build-ReviewReport.ps1` is correctly generic — it owns the merge, dedup, elevation and sort rules. But `-Finding` accepts **PowerShell objects**, so `collation-guide.md` and both `SKILL.md` files instruct the orchestrator to emit `[pscustomobject]` literals inside a `pwsh -NoProfile -Command @'…'@` here-string, and explicitly forbid `-File`. Every run therefore generates a bespoke script whose *body is the data* — 66 KB of it in the gate run.

Three consequences:

| | |
|---|---|
| Security | Reviewer text derives from attacker-influenced source, and security reviewers are *required* to quote offending content. One `'` closes the literal; the rest is code. This is gate finding [3], Critical, both models — the orchestrator refused to follow its own skill and said so |
| Un-approvable | Content differs every run, so it can never be pre-approved. Worse, VS Code prefix-matches sub-commands, so wrapping in `pwsh -Command` makes the matched prefix `pwsh` — the two `Build-ReviewReport.ps1` keys in `.vscode/settings.json` are dead config that reads as working approval |
| Inconsistent | `queue-guide.md` and `crosscheck-guide.md` both mandate argument arrays, never shell-interpolated strings. Collation is the one place that rule is inverted |

**Direction:** add `-FindingPath <file>`; the orchestrator writes findings as JSON with a file-write tool (never the shell), and the script deserializes and validates. The command shape becomes fixed and `-File` usable, so it is approvable once. Validating on deserialize also closes gate finding [18] — an off-roster `Model` string currently passes silently and suppresses severity elevation.

### The report has no size budget

Measured from the two gate reports: cr 66,093 B over 44 findings (1,502 B each, 16 `_Also noted:_`); dr 70,072 B over 36 findings (1,946 B each, 20 `_Also noted:_`).

Levers, ranked by measured win:

| Lever | Mechanism | Note |
|---|---|---|
| Collapse cross-model duplicates | On merge, keep the strongest body; record agreement in `Models` and keep only genuinely-new detail as a short delta | ~36 duplicate bodies across the two reports; the largest single win and a pure formatter change |
| Severity-tiered detail | Critical/High full body, Medium ~2 sentences, Low title + one line | cr's long tail was 14 Low findings each carrying a full body |
| Body cap | Formatter truncates at N chars deterministically | Needs no reviewer cooperation, so it cannot be ignored |
| Per-concern finding cap | Top N by severity | Ranked last — risks discarding real findings to hit a number |

**Direction:** one formatter, two renderings (`-Detail Summary|Full`). The summary goes to chat where context is the scarce resource; the full report is written to `assets/reviews/` where size is free. That takes the win where it costs without losing anything — and the durable artefact is what a later `/si` harvest reads.

### Constraint — independent discovery is not negotiable

Considered and **rejected 2026-08-01**: feeding model A's findings to model B with instructions to skip them. It removes duplicate bodies at the source, but destroys the property the whole split exists to produce.

Measured from the two gate runs:

| Report | Findings | Flagged by both models | Elevated |
|---|---|---|---|
| cr | 44 | 12 | 11 |
| dr | 36 | 18 | 18 |

Seven of cr's eight Criticals were Critical *only* because both models found them independently. Severity elevation is defined as "flagged by every dispatched model", so priming B with A's output makes agreement unobservable and the rule inert. The `Test-SiWriteScope` encoding bug — the best catch of the gate — was found by two concerns on both models independently; under primed dispatch whoever ran second would have been told to skip it.

Three further costs: anchoring (the VS Code subagent docs give fresh, unanchored context as the explicit reason for parallel fan-out), serialization (14 parallel invocations become 7 sequential pairs), and injection surface (A's findings become instruction-shaped input to B — the RISK-10 shape).

**Any size optimisation must preserve independent parallel discovery.** Deduplicate at *render* time, never at dispatch time.

### Open option — adversarial triage pass

Sequential feeding is sound *after* collation rather than before it: hand one model the merged report and have it challenge weak findings, merge near-duplicates the keying missed, and prune noise. This is post-hoc critique, not primed discovery, so corroboration and elevation are already computed and cannot be affected.

Attacks the real noise problem — cr's long tail was 14 Low findings. **Undecided**; weigh against the extra invocation and the risk of a triage pass discarding a finding that later proves real. If adopted, the pruned entries must remain in the durable report with a recorded triage verdict, never silently dropped.

## What the gate also proved works

Recorded so a future reader does not over-correct: the concern split found a real security bug that a single comprehensive reviewer plausibly misses. `Test-SiWriteScope.ps1` carried the same UTF-8 decoding defect as `Get-ReviewScope.ps1`, silently disabling the symlink half of the `/si` write guard — flagged independently by `security` and `correctness-reliability`, on both models. Cross-model unanimity elevated 7 of the 8 Criticals.

## Cluster E — generated output is locale-dependent

**Resolved by plan `768d7b`.** Every culture-sensitive comparison in `Build-Registry.ps1` and `Build-Marketplace.ps1` is an ordinal comparer, and the fixture that proves it genuinely diverges between `cs-CZ` and `en-US` was demonstrated red against the pre-fix code first (`test:BuildRegistry.FixtureIsRedBeforeFix`, `test:BuildRegistry.CzechCollationFixtureIsStable`). The operator's 2026-08-01 "regenerate under invariant culture to unblock the merge" is superseded: the latent defect below is fixed rather than worked around.

Found by **CI**, 2026-08-01, on the `b0c0d3` merge attempt — the first time CI produced a meaningful verdict on this work.

`Build-Registry.ps1` sorts `files[]` with bare `Sort-Object`, which is **culture-aware**. On a `cs-CZ` host, `ch` is a single collating letter sorting after `c`, so `skills/autopilot/s·ch·emas/…` sorts *after* `skills/autopilot/s·c·ripts/…`; on an invariant/en-US runner it sorts before.

```
cs-CZ      compare =  1     schemas AFTER scripts
en-US      compare = -1     schemas BEFORE scripts
invariant  compare = -1
ordinal    compare = -10
```

`registry.json` ordering therefore depends on the locale of whoever last ran the build, and the freshness gate fails for everyone else. Affected sort sites: `Build-Registry.ps1` lines 21, 81, 96, 101, 127, plus any equivalent in `Build-Marketplace.ps1`. Fix is `-Culture ordinal` / `[StringComparer]::Ordinal`, with a regression test that runs the generator under `cs-CZ` and asserts byte-identical output.

**Operator decision 2026-08-01:** regenerate under invariant culture to unblock the merge; fix the sort properly in the next plan. The latent defect is unchanged — the next person to run `Build-Registry.ps1` on a Czech-locale machine reintroduces the diff.

### Why this one matters beyond itself

The gate-1 `cr` review stated it had verified *"`Build-Registry.ps1` output is byte-identical on regeneration and its `Sort-Object` ordering is stable across en-US/sv-SE/tr-TR/de-DE/cs-CZ."* CI falsified that within the hour. The reviewer evidently exercised the sort but not the `schemas`/`scripts` pair — the single input where the Czech `ch` digraph actually changes the result.

So a reviewer can report verification it did not fully perform, in the same voice it reports verification it did. That is the Cluster A problem one level up: **the review output cannot distinguish a checked claim from an asserted one.** Any fix for reviewer attendance//coverage reporting should consider whether verification claims need the same treatment.

It is also the strongest available argument for cr finding [15] (CI runs one test file, never `validate.ps1` or `npm test`): the one check CI *does* perform caught a real cross-platform defect that two models, seven concerns and a human gate all missed.

## Cluster F — the self-improvement loop has no durable state at either end

Operator-noticed 2026-08-01: *"did we run `/si` on this plan we just finished?"* It had not. `b0c0d3` built the loop and then never closed it on itself.

The skip was **correct by design** — `crosscheck-guide.md` rule 3: *"Headless completion does not run `/si`. The harvest is cheap; a proposal is not — it opens a PR against the repo's own instructions with nobody to have asked. Queue nothing and skip."* `b0c0d3` completed in the container, so `/si` was properly declined.

The gap is the asymmetry with its sibling:

| | Headless behaviour | Durable trace |
|---|---|---|
| `/pfb` | writes a queued marker, consumed next interactive session | yes — `docs/feedback/queue.md` |
| `/si` | *"queue nothing and skip"* | **none** |

So an autopilot run that generates excellent harvest material leaves no record that `/si` was ever due. It ran here only because the operator remembered to ask. Pair that with gate finding [17] — `/si` leaves no committed record of what it proposed or what was declined — and the loop has no state at **either** end: nothing says it is owed, and nothing says what happened when it ran.

**Direction:** headless completion writes an `si-due` marker in the same shape as the `/pfb` queue (content-addressed, refuses duplicates), consumed on the next interactive completion. That preserves rule 3's actual intent — *do not open a PR with nobody to ask* — without losing the signal that a proposal is owed. Pairs naturally with finding [17]'s proposal/decline record; both are the same missing artefact viewed from opposite ends.

## Cluster G — the first real `/si` run, and what it found

`/si` was run interactively from `main` on 2026-08-01, after `b0c0d3` merged. Four sources harvested: 15 ledger entries, 73 cr-log findings, 10 learnings, 3 recorded operator verdicts. No injection findings. The operator accepted three candidates and directed them here rather than to an `/si` draft PR — **this section is that decision's durable record**, which is precisely the artefact Cluster F says does not exist. It was written by hand; nothing in the loop would have written it.

**G1 — the ledger is only written at the end of a plan.** All 12 `b0c0d3` ledger entries carry `#phase-10` and `src:autopilot`; none come from phases 1–9. The cr-log holds 73 findings across all ten phases, including four Critical and roughly twenty High. So ~61 findings never reached the artifact later CR rounds actually read. The ledger is meant to be curated rather than exhaustive, but zero-from-nine-phases against twelve-from-one is a distribution that means per-phase promotion never fired, not that nine phases taught nothing. Recurrence counting — the harvest's top-weighted ranking axis — is measuring a sample drawn from one phase.

**G2 — two silent data losses at the point the loop captures its most valuable input.** `Update-FeedbackQueue.ps1` sets `$maxEntryLength = 300` and applies a bare `Substring` with no ellipsis and no warning; all three recorded operator verdicts are cut mid-word at exactly 365 characters (`"All three non-goal"`, `"the guides own a"`, `"yet the receip"`). Those are the operator's acceptance judgements — the scarcest and least reproducible input the loop has. Separately, `Add-WorkflowNote.ps1` writes `Folded 10 additional learnings into this summary.` *after deleting the ten lines it names*; the "summary" contains none of them, so it is a tally, and phase 1's ten learnings are unrecoverable. Both are the same bug as Cluster A: the artifact cannot describe its own degradation.

**G3 — the guide's own commands do not run as written.** Running `/si` per its documentation failed three times before a single source was read: `Import-Module .github/skills/…` fails without a `./` prefix; `Resolve-Plan -Reference` blocks on a mandatory `-RepoRoot` the guide never passes; `Resolve-PlanAssetPath` takes `-PlanDir`/`-Kind`, not the `-PlanPath` the guide implies. The harvest already knows this defect class — cr-log [9.2] *"repo-layout paths only work while dogfooding"*, [6.5] the `pwsh -File` call that silently dropped typed findings, [5.2] a script no plugin bundles — and operator feedback `[095e99d0]` logs it as a MISS against a success signal. A skill whose documented invocation was never executed is Cluster B in the instructions rather than the tests.

**Declined, recorded so they are not re-raised as new:** the fence-forgery scan has no self-reference exemption and produced two false positives on its first real run (cr-log [6.2], [8.1] — entries *describing* the fence); and the 44-finding step 10.7 gate wrote no cr-log entries at all, so its findings survive only as prose here and can never be counted toward recurrence.

## Cluster H — the gate costs 29 minutes, and one file is 82% of it

**Resolved by plan `768d7b`.** The 1741.8s below became **108.998s** on `ubuntu-latest` and **223.142s** on `windows-latest`, both measured on the runners the gate is enforced on (`tools/suite-runtime.json`, commit `c99d5d1`), against a ceiling bound at 600s *before* any optimisation so later work could not redefine success. The direction the note proposed — a shared fixture, and a slow tier split out of `npm test` — was not the one taken: a shared fixture fits 1–2 of ~20 executions, and the tier split held in reserve for a 10× platform gap was never needed once per-case process startup and git construction went away (D13, D15). What the note got right is the framing: the 29-minute figure was a behaviour problem, and the fix is only real because the ceiling is enforced per platform by `Run-UnitTests.ps1` on every run.

Measured from a full `npm test` capture on 2026-08-01: 1741.8s wall clock for 698 passing tests.

| File | Time | Share |
|---|---|---|
| `tests/skalary/Skalary.Tests.ps1` | 1419.6s | **81.5%** |
| `ReviewScope.Tests.ps1` | 44.4s | 2.6% |
| `Add-LedgerEntry.Tests.ps1` | 40.9s | 2.4% |
| `Test-Plan.Tests.ps1` | 40.9s | 2.4% |
| `SiWriteScope.Tests.ps1` | 32.9s | 1.9% |
| the other 27 files combined | ~163s | 9.4% |

`Skalary.Tests.ps1` is 482 lines and 14 `It` blocks — roughly **101 seconds per test case**. It contains 10 `Install-Plugin` calls, 8 `Build-Registry` calls and a `git clone`, and the run log shows exactly 10 `Bootstrap ref: main` / `Generated registry … with 11 plugin(s)` pairs. So each case performs a genuine end-to-end scratch install from a cloned repo. That is the right thing to test and the wrong thing to do fourteen times per run.

An earlier reading of this data claimed the registry was rebuilt *per test case*; the capture shows 10 rebuilds total, not one per case. Recorded because the corrected number is what makes the fix obvious — the cost is whole scratch installs, not registry generation.

**Why it belongs in this note.** A 29-minute gate is not merely slow; it changes behaviour. It is the autopilot test command and the `test:unit` evidence executor, so every phase pays it, and the pressure to skip it or to trust a stale capture is exactly what produced the Cluster A truncation above. Cluster B already records that this same entry point exits 0 when Pester is absent — a gate that is both expensive and silently skippable is the worst combination available.

**Direction:** share one bootstrapped install fixture across the cases that only read it, keep a small number of genuine end-to-end installs, and consider splitting the slow integration tier out of the default `npm test` so the fast suite stays usable per-step. Any split must not let the slow tier become the thing nobody runs — Cluster B's CI gap is that failure already.

## Sequencing

These are the machinery's self-verification, not its function; `b0c0d3` delivers working behaviour. Fixing them first is nonetheless preferable to building on top, because every later plan's evidence receipt inherits Cluster B's trustworthiness problem.

G1–G3 have a sequencing claim of their own: they degrade the evidence every *later* `/si` run reasons from. G1 biases the recurrence axis, G2 destroys the records outright, G3 means the next operator to invoke the skill hits the same three failures. Fixing them is cheap and is a precondition for trusting any subsequent harvest — including the one that would judge whether the rest of this note's clusters were worth fixing.

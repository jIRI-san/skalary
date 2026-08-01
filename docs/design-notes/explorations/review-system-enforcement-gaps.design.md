---
description: Deferred exploration — the review and plan machinery reports its own controls rather than enforcing them, and its evidence cannot distinguish a degraded run from a clean one. Sourced from the 44-finding step 10.7 gate review. Load before changing Build-ReviewReport, Build-EvidenceReceipt, the dispatch guides, or CI wiring.
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

## The shape

**A control is described in prose, reported in output, and enforced nowhere.** The plan that built this machinery hit the same shape three times during its own design review (`phase-budget-points` inert, the "hard cap" of 28 unenforced, the `timeout` doc/impl split). The gate then found it had been reproduced in the machinery itself.

## Cluster A — the report cannot describe its own run

| Gap | Consequence |
|---|---|
| No per-concern attendance record | A reviewer that errored, was never dispatched, or was mis-parsed is byte-identical to one that ran and found nothing |
| `InvocationCount` unvalidated, defaults to `0` | A run that dispatched half the fan-out prints whatever number the model typed; `Dispatched 0 of 28` renders above a page of findings |
| Scope size, batch size, tier never measured | The tier that decides between 6 and 14 invocations is eyeballed off an unbounded list |
| Degradations have no header slot | The dispatch guide instructs recording a Pro-tier fallback "in the review header"; the header is script-generated with exactly two fields and the collation guide forbids adding to it. The instruction is unsatisfiable as written |

Common fix direction: give the formatter the *dispatched task set*, not just findings, and let it derive rather than accept the count.

## Cluster B — gates that pass without running

| Gap | Consequence |
|---|---|
| Evidence grammar has no `skipped` state | Four of five symlink-confinement cases self-skip on Windows; the receipt records five passed |
| `Run-UnitTests.ps1` exits 0 when Pester is absent | `npm test` reports success having executed zero assertions — and it is both the autopilot test command and the `test:unit` evidence executor |
| `registry-ci.yml` runs one test file | ~20 new test files and both new gates never run on PR; reverting the UTF-8 fix produces a green PR |
| `validate.ps1` enumerates without `-Force` | On Linux every dot-prefixed entry is hidden, so the bundled `.github/skills/**/scripts/` payloads are never parsed — the container validates a strictly smaller set than the host |

## Cluster C — constants copied into prose

The 28-invocation budget exists in six ungated places, inside a design note that says *"do not restate those numbers here — a second copy is a second thing to drift."* Plan-size thresholds and the phase-budget default have the same shape. The branch establishes the correct pattern twice (`DesignNotes.Tests.ps1` pins the size cap to the script default by regex; `Test-ModelAllowlist.ps1` validates guide rows against `tools/model-allowlist.psd1`) and then does not apply it here.

## Cluster D — collation passes data as code, and the report has no size budget

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

## What the gate also proved works

Recorded so a future reader does not over-correct: the concern split found a real security bug that a single comprehensive reviewer plausibly misses. `Test-SiWriteScope.ps1` carried the same UTF-8 decoding defect as `Get-ReviewScope.ps1`, silently disabling the symlink half of the `/si` write guard — flagged independently by `security` and `correctness-reliability`, on both models. Cross-model unanimity elevated 7 of the 8 Criticals.

## Sequencing

These are the machinery's self-verification, not its function; `b0c0d3` delivers working behaviour. Fixing them first is nonetheless preferable to building on top, because every later plan's evidence receipt inherits Cluster B's trustworthiness problem.

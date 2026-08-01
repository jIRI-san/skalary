# Reviewer dispatch guide (shared by `/cr` and `/dr`)

This guide owns everything about **how reviewers are dispatched**: the model roster, the preflight,
concern selection, batching, and the invocation budget. Both review orchestrators read it, and the
two installed copies (`.github/skills/cr/assets/dispatch-guide.md` and
`.github/skills/dr/assets/dispatch-guide.md`) are byte-identical by construction — edit one and the
drift gate fails until both match.

## 1. Reviewers are split by concern, not by model

There are seven concern reviewers per review type, and they declare **no model**:

| Concern id | Lens |
|---|---|
| `security` | OWASP Top 10, trust boundaries, injection, secrets, path confinement, authz |
| `correctness-reliability` | logic errors, error handling, retries/timeouts, race conditions, corner cases, fail-loud behaviour |
| `architecture-patterns` | design-note conformance, architecture-contract violations, abstraction fit, composition vs inheritance |
| `performance` | allocations, hot-path I/O, N+1, unbounded growth, latency/throughput targets |
| `testing-evidence` | coverage gaps, weak or missing typed evidence markers, fixture quality, flaky patterns |
| `maintainability-consistency` | naming drift, duplication, dead code, commented-out code, style deviation, docs sync |
| `operability-observability` | structured logging, metrics, diagnosability, audit/receipt visibility, rollback clarity |

Agent ids are `cr-<concern>` for code review and `dr-<concern>` for design review.

## 2. Model roster and per-invocation override

| Role | Model | Notes |
|---|---|---|
| Reviewer A | `Claude Opus 5 (copilot)` | GA |
| Reviewer B | `GPT-5.6 Sol (copilot)` | GA |
| Pro-tier fallback | `Claude Sonnet 4.6 (copilot)` | GA, available on Copilot Pro |

Dispatch each selected concern **once per model**, passing the model as the **explicit model
parameter** of the subagent invocation. VS Code resolves a subagent's model as:

1. explicit parameter supplied at invocation → 2. `model:` in the agent frontmatter → 3. the parent
   conversation's model.

Because the concern agents deliberately declare no `model:`, the explicit parameter is the only
binding that matters. That is what keeps the agent count at 7 per review type instead of 14 and lets
the roster change without touching agent files.

The operator may override the roster for a single run. Honour the override, and report the models
actually requested in the review header.

## 3. Preflight: validate the declared model configuration

Before dispatching anything, run the declared-model preflight:

```
pwsh -NoProfile -File scripts/skalary/Test-ModelAllowlist.ps1
```

It reads committed files — `tools/model-allowlist.psd1`, every `*.agent.md`, and every
`.autopilot.json` — so it is deterministic. A non-zero exit is **fail-loud: stop and report the
violation. Never fall back to "review anyway with whatever model answers"**, and never downgrade the
failure to a warning. If the script is not present (a consumer repo that installed only the review
plugins), state that the preflight could not run and continue — an absent script is a known
limitation, not a silent pass.

Every model you dispatch must be a name from the roster above, in the qualified
`Model Name (vendor)` form used by VS Code-hosted agents.

### What the preflight cannot see

The preflight validates the **declared** configuration. It cannot observe the **served** model:

- A subagent's model request is capped by the parent conversation's cost tier. A cheap orchestrator
  model silently collapses both reviewer passes onto that cheap model, with no error.
- Asking a reviewer to report its own model is worthless — a served model cannot attest its serving
  identity, so the report passes in exactly the case it exists to catch.

This gap between declared and served is an **accepted, undetectable residual**. Reviewer
self-reports may appear in the report as advisory colour, explicitly labelled as *not evidence*. No
control here claims to close this gap.

### Pro-tier degradation

`Claude Opus 5` and `GPT-5.6 Sol` are unavailable on the Copilot **Pro** plan (Pro+, Max, Business,
Enterprise only). A frontmatter fallback array does not help: explicit-param dispatch outranks
frontmatter, so the array is never consulted and the subagent silently falls back to the *parent*
model. When the tier does not carry the roster models, pass the GA fallback
`Claude Sonnet 4.6 (copilot)` **as the explicit parameter**, and say so in the review header.

## 4. Concern selection scales with change size

Seven concerns × two models is disproportionate for a one-file change, so the concern set scales:

| Scope size (`cr`: changed files · `dr`: plan lines) | Concerns dispatched | Invocations |
|---|---|---|
| ≤ 3 files / ≤ 150 lines | `security`, `correctness-reliability`, `architecture-patterns` | 3 × 2 = 6 |
| 4–15 files / 151–400 lines | all 7 | 7 × 2 = 14 |
| > 15 files / > 400 lines | all 7, with **reading** batched by matched subsystem | 14 |

An explicit concern filter from the operator overrides this selection in both directions — it can
narrow the set below the threshold or widen it above it.

## 5. Batching splits reading, never concern passes

Concerns run **once over the union of the files (or plan sections) under review**, never once per
batch. Running a concern per batch would cost `7 × 2 × batches` — a 40-file change across 4
subsystems would be 56 invocations and re-trigger exactly the cost problem the scaling tier exists
to tame. Batching tells a reviewer how to *read*, not how many times to *run*.

- **Batch size bound:** at most **15 files per batch**; split a larger subsystem into several
  batches rather than handing a reviewer an unbounded list.
- **Subsystem matching (`cr`):** map each changed path against the `globs` column of the
  `docs/design-notes/.design-notes.md` index. A file matching several notes joins the **first match
  in index order**; unmatched files go to a `general` bucket.
- **Batching contract (`dr`):** design review batches on **H2 boundaries** — one phase heading per
  batch, or, under the plan-assets layout, **one `assets/` file per batch**. Never split a phase or
  an asset file across batches: a reviewer that sees half a phase reports gaps that the other half
  fills.

## 6. Invocation budget: 28 per review round

**Budget: 28 invocations per review round.** This is a budget the orchestrator **reports against**,
not an enforced gate — dispatch is a model-driven sequence of subagent calls, and nothing counts or
wraps them at runtime. Calling it a hard cap would claim an enforcement that does not exist.

Report the count in the review header, in this shape:

```
Dispatched 14 of 28 budgeted invocations (7 concerns × 2 models).
```

If the plan of record for a run would exceed 28, narrow the concern set or the scope and say why in
the header rather than silently spending the credits.

## 7. After the reviewers return

1. Collect every `## Findings (<Concern>)` section from every dispatched reviewer.
2. Hand the typed findings to `Build-ReviewReport.ps1` and write the text it returns. The merge rule,
   the dedup rule, the severity-elevation rule, and the sort order live in that script — never
   re-derive them in prose.
3. Map findings to review-ledger categories with [`concern-ledger-map.md`](concern-ledger-map.md)
   when harvesting; the map is deterministic, so harvest stops being a judgment call.

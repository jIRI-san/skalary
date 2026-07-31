# Decision: reviewer fan-out and model binding

## Models

| Role | Model | Notes |
|---|---|---|
| Reviewer A | `GPT-5.6 Sol (copilot)` | GA. VS Code ≥ `1.128.0`. Available in Copilot CLI. Supports 1M context + configurable reasoning. |
| Reviewer B | `Claude Opus 5 (copilot)` | GA. VS Code ≥ `1.128.0`. Available in Copilot CLI. Supports 1M context + configurable reasoning. |
| Dropped | `Gemini 3.1 Pro (Preview) (copilot)` | Still **Public preview**; not available in Copilot CLI. Removed entirely. |
| Autopilot | `gpt-5.3-codex` → `GPT-5.6 Sol (copilot)` | Aligns the autonomous runner with the review tier. |

Both chosen models are **excluded from the Copilot Pro plan** (Pro+, Max, Business, Enterprise only). A frontmatter fallback array does **not** solve this: explicit-param dispatch outranks frontmatter, so the array is never consulted and the subagent falls back to the *parent* model instead. The orchestrator therefore detects the tier and passes the GA fallback **as the explicit parameter**. See RISK-2.

## Model binding

Concern agents are **model-agnostic** — no `model:` pin that forces a single model. VS Code resolves a subagent's model in this priority order:

1. Explicit model parameter supplied by the main agent when invoking `runSubagent`.
2. The `model:` property in the subagent's `.agent.md` frontmatter.
3. The model running the parent conversation.

The orchestrator therefore dispatches each concern **twice** — once per model — using the explicit parameter. This keeps the agent count at 7 per review type instead of 14, and lets the model roster change without touching 14 files.

### Two name formats, never normalized

The qualified `Model Name (vendor)` form above applies to **VS Code-hosted** agents. The `autopilot` agent runs under **Copilot CLI**, which expects a bare slug (`gpt-5.6-sol`). Writing a qualified name into the CLI agent breaks autonomous execution.

Host is **not inferable** from folder layout — "anything under `plugins/autopilot/` is CLI" silently misclassifies the next CLI agent added elsewhere, reintroducing the exact drift REQ-7 exists to catch. So `tools/model-allowlist.psd1` carries the two lists **plus a closed committed agent→host map**, and the validator fails loud on any agent absent from that map. The failure mode is a hard error, never a silent misclassification.

### Tier-cap hazard (RISK-1)

> "The requested model cannot exceed the cost tier of the main model. If you request a more expensive model, the subagent falls back to the main model."

A cheap orchestrator model silently collapses both reviewer passes onto that cheap model, with **no error**.

**Nothing inside the session can observe this.** Two separate attempts fail for the same underlying reason:

- A reviewer self-report is worthless — a served model cannot attest its own serving identity, so the report passes *exactly* in the case it exists to catch.
- A "preflight on the orchestrator's own model" is barely better: the orchestrator is a skill running in the main conversation, whose model is the user's picker selection. Agent files carry no `model:` to read back, and skills carry no model declaration at all. "Read your own configured model" collapses into "ask the running model what it is" — the same non-verifiable operation.

What is actually done:

- The preflight validates **declared configuration only** — deterministic because it reads committed files, and genuinely useful for catching a misconfigured roster.
- The gap between *declared* and *served* is an **accepted residual**, documented in the dispatch guide and design note. No control claims to close it.
- Reviewer self-reports remain in the report as advisory colour, explicitly labelled as not-evidence.

## Size-scaled concern set (RISK-4)

7 concerns × 2 models = 14 invocations is disproportionate for a one-file change.

| Scope size | Concerns dispatched |
|---|---|
| ≤ 3 changed files (cr) / ≤ 150 lines (dr) | `security`, `correctness-reliability`, `architecture-patterns` (3 × 2 = 6 invocations) |
| 4 – 15 files / 151 – 400 lines | all 7 (14 invocations) |
| > 15 files / > 400 lines | all 7, with reading batched by matched subsystem |

### Batching semantics

Batching splits **reading**, not concern passes. Concerns run **once over the union of files**, never once per batch — otherwise a 40-file change across 4 subsystems would cost 7 × 2 × 4 = 56 invocations and re-trigger RISK-4 at exactly the size the tier exists to tame. This matters more now that REQ-11 has reviewers read the codebase themselves rather than receiving an extracted diff, so each invocation carries its own file-reading cost.

- **Budget: 28 invocations** per review round. This is a *budget the orchestrator reports against*, not an enforced gate — dispatch is a model-driven sequence of `runSubagent` calls and nothing counts or wraps them at runtime. Calling it a "hard cap" would repeat the assert-without-enforcing mistake this document already calls out for RISK-1.
- **Subsystem matching** reuses the existing design-note glob mapping. A file matching multiple notes joins the first match in index order; unmatched files go to a `general` bucket.
- **Design review** batches on H2 boundaries — phase headings, or one asset file per batch under the new plan layout — since its input is plan sections, not changed files.

An explicit concern-filter argument overrides the automatic selection in both directions. The review header reports the invocation count so credit cost is visible.

## Why per-concern instead of per-model

The VS Code subagent documentation lists "multi-perspective code review" as a first-class orchestration pattern precisely because a single comprehensive pass anchors on whatever it noticed first. Splitting by concern gives each reviewer a clean context and a narrow lens; splitting by model on top of that preserves the existing cross-model corroboration and severity-elevation behaviour.

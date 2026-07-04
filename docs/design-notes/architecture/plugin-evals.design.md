---
description: Two-tier plugin evaluation harness (structural + LLM), report generation, sandboxed backend execution, and judge contract
globs:
  - plugins/**/evals/**
  - scripts/skalary/Test-Evals.ps1
  - tests/evals/**
  - schemas/eval-case.schema.json
---

# Plugin Evals

## Architecture

| Tier | Scope | Execution mode | Gate policy |
|---|---|---|---|
| Structural | Pester evals in `plugins/<name>/evals/*.Tests.ps1` validate frontmatter, required keys, names, links, and referenced assets | Always-on via `scripts/skalary/Test-Evals.ps1` | Always-on in `npm run eval`; not part of `npm test` / `scripts/validate.ps1` |
| LLM | Declarative scenarios in `plugins/<name>/evals/llm/*.eval.json` scored by LLM-as-judge | Opt-in with `-IncludeLlm` | Never part of `npm test` / `scripts/validate.ps1` |

The harness entry point is `scripts/skalary/Test-Evals.ps1`. `npm run eval` is the documented pre-commit path for this subsystem.

## File Layout and Contracts

| Surface | Contract |
|---|---|
| `plugins/<name>/evals/*.Tests.ps1` | Tier-1 structural assertions per plugin, using shared helpers |
| `plugins/<name>/evals/llm/*.eval.json` | Tier-2 cases with `{ artifact, scenario, rubric[], passThreshold }` |
| `tests/evals/EvalCommon.psm1` | Structural helper module (frontmatter parse, required keys, link/file resolution, section checks) |
| `tests/evals/EvalLlm.psm1` | LLM helper module (config/auth preflight, sandbox lifecycle, backend invocation, judge validation) |
| `schemas/eval-case.schema.json` | Documentation/IDE aid for case shape; runtime validation is explicit field/type checks in PowerShell |

## Backend and Isolation Boundary

Tier-2 execution is backend-pluggable (`copilot-cli` now, `container` reserved). Current execution uses Copilot CLI headless inside a disposable sandbox clone created once per run:

- clone repo to temp dir
- replace sandbox `plugins/` with live working-tree `plugins/` (delete-then-copy)
- run `Sync-Dogfood.ps1` in sandbox
- set sandbox `origin` fetch URL to the real GitHub URL
- disable sandbox push URL (`DISABLED`)
- run cases, then delete sandbox in `finally`

This prevents live-tree mutation during no-approval `--allow-all` eval runs. The isolation boundary is sandbox cwd only; container backend is the stronger filesystem boundary. Under `--allow-all`, a scenario can still target live-repo absolute paths, so sandbox cwd is not a filesystem containment guarantee.

## Config and Auth

Tier-2 reads a gitignored `.eval.config.json` (shape documented by committed `.eval.config.json.example`):

| Key | Purpose |
|---|---|
| `judgeModel` | Judge model slug (no identity hardcoded in committed files) |
| `credentialTarget` | Optional Windows Credential Manager target holding the eval PAT; loaded into `COPILOT_GITHUB_TOKEN`/`GH_TOKEN`, mirroring autopilot `copilotAuth.credentialTarget`. A dedicated eval secret (e.g. `copilot-eval`) keeps eval auth separate from `copilot-autopilot` |
| `temperature` / `passThreshold` / `timeoutSeconds` | Judge/run tuning; optional fields fall back to `.example` defaults |

Credential resolution is skip-not-error: an unset `credentialTarget` falls back to ambient `copilot` auth; a set-but-missing target (or missing `CredentialManager` module) records an actionable `skip` and keeps the run green.

On first `-IncludeLlm` run, a missing `.eval.config.json` is bootstrapped from the example; the scaffolded file keeps the `<slug>` placeholder so the run skips with a note pointing at the new file to fill in.

### gh-token Copilot entitlement (1.4 gate)

waza's embedded copilot-sdk requires a `COPILOT_GITHUB_TOKEN`/`GH_TOKEN`; `Resolve-EvalToken` prefers `gh auth token` because gh's OAuth token auto-refreshes and so sidesteps the corp 7-day PAT cap. Whether a `gh auth token` OAuth token actually **carries the Copilot entitlement** copilot-sdk accepts depends on the account/org (GitHub app grant + SSO) and must be confirmed live before gh is committed as the single seamless source. The confirmation is a repeatable one-per-machine script, `scripts/skalary/Probe-GhEntitlement.ps1` (pure decision helpers covered by `tests/evals/ProbeGhEntitlement.Tests.ps1`): it pre-seeds PATH with an installed-but-not-on-PATH gh/waza, runs `gh auth login` if needed, resolves via `Resolve-EvalToken` asserting `Source = gh`, then confirms entitlement with `waza models` (decisive, ~0 cost) and one live `cr flag-planted-bug` task; it writes a gitignored result JSON + a table row and never prints the token.

**Live-probe status (2026-07-04, personal dev machine `jIRI-san @ github.com`): VERIFIED — ENTITLED.** `Probe-GhEntitlement.ps1` resolved the token from **gh** (not the Cred-Manager fallback), `waza models` listed **16 models**, and the live `cr flag-planted-bug` task passed 100% (score 1.00, 1 premium request, exit 0). So a personal `gh auth token` OAuth token carries the Copilot entitlement copilot-sdk accepts. The gate remains `@human` only because the browser OAuth step cannot run unattended.

Live-probe entitlement record (account @ host | source | models | task | verdict):

| Account @ host | Source | Models | Live `cr` task | Verdict |
|---|---|---|---|---|
| `jIRI-san @ github.com` (personal dev) | gh | 16 | PASS | **ENTITLED** |
| _corp work machine under SSO_ | — | — | — | **PENDING** (re-run the same probe at work) |

Verified autonomously in support of the gate:

| Check | Result |
|---|---|
| Token-resolver precedence (`gh` → ambient → Cred-Manager → skip) | Passing (`test:resolvetoken-precedence`, step 1.3) |
| Fallback token source | Cred-Manager `copilot-eval` PAT present and resolvable; PoC ran 2/2 green against the real `cr` bundle on this token — retained as the CI/unattended fallback |
| gh provisioning (`Ensure-EvalTools`) | winget resolves the pinned `GitHub.cli 2.96.0` and verifies the installer hash, but the MSI **requires elevation** — a non-elevated install aborts (winget exit `1602`). gh must therefore be pre-installed or installed from an elevated context on dev/CI machines (feeds the Phase 3 ADO rollout). |

**Decision:** on a machine where a human can auth, **gh is the promoted seamless source** — the personal-box probe confirms a gh OAuth token is entitled and auto-refreshes, sidestepping the 7-day PAT regen. The Cred-Manager `copilot-eval` PAT stays the unattended/CI fallback (resolver precedence already prefers gh when present). **Corp orgs remain PENDING** a work-machine run of the same probe under corp SSO; record the entitled orgs in the table above when known.

## Known Limitations

| Limitation | Current handling |
|---|---|
| `cr`/`dr` CLI fidelity | `cr`/`dr` are VS Code-hosted orchestrators; headless `copilot --agent` may not reproduce full subagent fan-out/model-vendor resolution. Tier-2 rubrics for these plugins target observable orchestrator behavior (e.g., injection-safe handling and structured findings), not exact multi-model consensus output. |

## Waza Behavior

The Tier-2 backend is migrating from bespoke `EvalLlm.psm1` to **waza** (Microsoft Go CLI, pinned `0.38.0`, `copilot-sdk` executor). Specs live at `plugins/<name>/evals/waza/eval.yaml` (+ `tasks/*.yaml`). This section records the live-verified behavior that the shipped conventions depend on. Confidence is per-**claim**, not per-row: **verified** = observed on this box against the real `cr` bundle; **inferred** = not yet observed, extrapolated from related evidence (must be observed before a grader depends on it); **schema** = confirmed from waza's own embedded JSON schema but not executed; **deferred** = characterized, live-fire left to Phase 2.

### Hard gates (a failing answer blocks the affected cases)

| Gate | Answer | Convention | Confidence |
|---|---|---|---|
| (a) Workspace isolation / absolute-path containment | **Partial.** Each task runs in a fresh temp workspace (`%TEMP%\waza-<id>`) with agent cwd = that dir; fixtures are copied in. **Relative** writes are contained there; an agent instructed to write an **absolute** repo path **escapes** and mutates the live tree — waza has **no** OS-level/container executor. A read-only `cr` run (tools resolved to `glob`+`view`) left the live tree byte-clean; a relative-write probe stayed inside the temp workspace. | **Read-only cases** run as-is on the live box. **Write-enabled and adversarial cases are BLOCKED in Phase 2 from running against the live worktree** — they must run in a disposable checkout/throwaway clone or behind a path-rejecting tool layer (reject absolute / `..`-escaping paths), with the `container` boundary (Phase 3 ADO) as the durable control. `test:live-tree-clean` is a post-hoc **tripwire**, not the primary containment control. Never `--allow-all` for a case that does not need writes. | verified |
| (b) Injection harness + judge content | **(i) Judge content — CORRECTED in 2.1 live-fire:** the **independent** judge (`continue_session: false`, waza's default) is **flaky against a real agent** — waza drops it into the task workspace *without reliably injecting the agent's final text*, so it hunts the filesystem, finds only the fixture, and false-fails (observed: `flag-planted-bug` judge `fail: No reviewer output found — only the diff file exists` on one run, PASS on another with byte-identical inputs). **Use `continue_session: true`** so the judge **resumes the agent's session** and deterministically sees the review (2×2 trials → 100% `pass_rate`, stddev 0). Keep `inputs.follow_up_prompts: [ ... ]` to force a final **text** turn so the deterministic `text` grader and `final_output` stay populated. This reverses the earlier 1.0 bet on the independent judge. **(ii) `cr` injection-resistance — functional path VERIFIED in 2.1:** the functional `treat-injection-as-data` task ran green live — `cr` flagged **both** injected directives as Critical prompt-injection attacks *and* still found a real bounds bug, with a deterministic `text` tripwire (reject a bare-approval final output) + the resumed judge both passing across 2 trials. The **`waza adversarial` pack live-fire is deferred** to a machine with a short-lived `gh` token: REQ-22 forbids exposing the durable Cred-Manager PAT to injection tasks and the PAT is the only source on the current box. The `adversarial:` block is proven **well-formed and inherited** (mock `--spec` ran the 4-task `prompt-injection` pack and the spec-level `tool_constraint` merged into every pack task); `waza adversarial --spec` needs `--skill`/`--model` forwarded explicitly (it does **not** read them from the spec — it defaults to the `adversarial-target` stub skill + its own pinned model). | **Resume-session judge (`continue_session: true`) everywhere** — the independent judge is flaky (2.1, RISK-11); route adversarial-diff cases through the `adversarial:` block (`schemaVersion: "1.2"`) and carry the verdict on a deterministic `program`/`text` grader as a non-LLM control; `test:injection-guard` + `test:waza-spec-shape` gate 2.1. | (i) verified (corrected) · (ii) functional verified · pack deferred |
| (b′) Durable-token exclusion (token segregation) | **Verified (mechanism):** `waza run --otel-include-payloads` defaults to **redacted** (sha256 + length only) so a durable token is not captured into artifacts; the runner (1.5) already segregates env — adversarial specs receive the **short-lived `gh` OAuth token**, never the Cred-Manager PAT, in the copilot-sdk child env. **Deferred:** proving a fixture in the `--allow-all` child cannot read the token is left to the 2.1 live-fire. | Adversarial child env carries only the short-lived token + default-deny env snapshot + redacted OTEL; the PAT path is used only for non-adversarial runs; `test:token-segregation` gates 2.1 against this convention. | verified (mech) · deferred (live) |
| (g) copilot-sdk tool-name mapping | cr's frontmatter declares VS Code names `read, search, execute, agent, todo`, but copilot-sdk surfaces its **own** identifiers. **Observed:** `search`→`glob`, `read`→`view`; the single `execute` capability fans out into `create` (write file), `edit` (in-place edit), and the **OS-dependent shell** — `powershell` on Windows, `bash` on Linux (matters: autopilot/CI containers are Linux). The auto-injected `tool_constraint` (keyed off the frontmatter names) therefore can **never** match and spuriously fails (Gotcha A: seen as `agent_tools_implicit: Expected tool not used: execute`). | Real `tool_constraint`/`tool_calls`/`behavior` graders must use the **observed copilot-sdk** names, not the frontmatter names, and must branch the shell name on OS (`powershell`/`bash`) — critical for 2.4's build/test-before-commit grader. A reject-only `tool_constraint` override is permitted **only** on tasks with no tool-behavior requirement (see Gotcha-A rule below). | verified |

### Soft gates (recorded, proceed with the convention)

| Gate | Answer / convention | Confidence |
|---|---|---|
| (c) `skill_directories` resolution base | Resolved **relative to the `eval.yaml` file**. For a shipped `plugins/<name>/evals/waza/eval.yaml`, the real agent bundle is `../../agents` (skills: the skill dir). | verified |
| (d) grader merge-vs-replace | Top-level `graders` are **global and merge** with per-task graders (not replace): the spike's 1 global `tool_constraint` + 2 per-task graders all fired on the task. | verified |
| (e) `SKILL.md`/`.agent.md` execution | `inject_skill_body: true` (default) injects the target body into the system prompt. Set `false` to measure whether the agent *invokes* a skill (keeps the `<available_skills>` summary; lets `behavior`/`skill_invocation` graders observe the `skill` tool). **Needs one-shot live confirmation before 2.4/2.5 build a `skill_invocation`/`behavior` grader on it.** | schema |
| (f) binary ↔ `schemaVersion` compat | `0.38.0` accepts `schemaVersion "1.2"` (needed for `adversarial:`/`mcp_mocks`). **Fail-open hazard:** an unknown/misplaced field on a same-major artifact **warns and is ignored, not rejected** — so a grader whose field is misplaced silently never fires and yields a **false PASS**. `waza migrate` upgrades artifacts. | verified |
| (h) model-slug placement | waza requires `config.model` in `eval.yaml` (a model family slug, not a secret), overridable with `--model`; `judge_model` likewise. The pinned slug stays in the committed YAML; `.eval.config.json` retains only judge/threshold tuning. | verified |
| (i) cr/dr fan-out headless | **No fan-out.** The `cr` run was a single copilot-sdk session (one `session.start`, no subagent/child-session or `agent`-tool events); the specialist `cr-opus`/`cr-codex`/`cr-gemini` subagents are not reproduced headless. Rubrics target observable single-agent orchestrator output (RISK-7). | verified |

### Conventions that guard the fail-open behavior

- **Fail-closed spec shape (guards f + Gotcha A):** because waza ignores misplaced fields silently, `test:waza-spec-shape` must assert **exact field placement** and the runner/lint must assert **every declared grader actually executed** (non-zero grader-eval count per task) so a silently-dropped grader fails loudly instead of passing.
- **Gotcha-A suppression rule (guards g):** a reject-only `tool_constraint` override (which suppresses the auto-injected constraint by never matching) is permitted **only** on tasks with **no** tool-behavior requirement. Any `behavior`/`tool_calls`/`tool_constraint` grader that asserts behavior must use a **real** constraint with the observed copilot-sdk names — never the suppression trick.

### Field-placement corrections (learned from the spike)

| Field | Correct placement | Note |
|---|---|---|
| `follow_up_prompts` | **`inputs.follow_up_prompts`** (array of strings), mutually exclusive with `inputs.responder` (schema) | A task **top-level** `follow_up_prompts` emits a warning (`unknown schema field ignored ... type models.TestCase`) and has **no effect** — it must be nested under `inputs`. This is the fail-open behavior of gate (f) in miniature. |
| `continue_session` | `prompt` grader `config.continue_session` | Default `false` = independent judge, but it is **flaky against a real agent** (2.1: waza does not hand the agent's output to the judge, so it hunts the workspace and false-fails). **Use `true`** — the judge resumes the agent session and reliably sees the review; live 2×2 trials were 100% stable, including the injection case (the resumed judge grades `cr`'s actual output, not the raw fixture). |



## Judge Contract and Injection Guard

| Aspect | Contract |
|---|---|
| Verdict format | Strict JSON `{ pass, score, rationale }` |
| Validation | Explicit field/type/range checks; non-JSON verdict fails loudly |
| Prompt safety | Captured output wrapped in GUID-suffixed `<<<UNTRUSTED_OUTPUT_*:{guid}>>>` markers with quad-tick fencing |
| Boundary hardening | Any literal boundary token in captured output is neutralized before wrapping |
| Pass decision | `pass` requires `score >= passThreshold` |

## Report and Writeback Model

Each run writes a timestamped folder `tests/evals/output/<yyyy-MM-dd_HH-mm-ss>/` (gitignored) containing `report.json` (structured summary + per-entry verdicts), `report.md` (human-readable summary + judge rationale), and any Tier-2 transcripts (`<plugin>-<case>.eval.txt`). The folder name uses filesystem-safe separators (no `:`); collisions in the same second get a `-<fff>` suffix. Registry/manifests/receipts stay unchanged:

| Surface | Status |
|---|---|
| `plugin.json` `evals` seams (`status`, `lastRun`) | Reserved, not populated by harness |
| `registry.json` `evals.status` | Reserved-seam summary, not runtime writeback |
| `.github/.skalary/receipts/*` `evalStatus` | Reserved, not populated by harness |

Receipt/registry writeback is intentionally deferred; harness is report-only to preserve deterministic registry output and dogfood drift behavior.

## Transcript Capture Contract

Tier-2 backend capture is based on direct `copilot -p` process output plus optional `--share` export.

| Topic | Confirmed contract |
|---|---|
| Invocation | Run non-interactive `copilot -p "<prompt>" --no-ask-user --allow-all`; add `--agent <name>` for agent artifacts. |
| Assistant text channel | Assistant text is written to **stdout** and can be captured directly from the child process stream. |
| Tooling/stats noise | Usage stats and export notices are written to **stderr** (`Changes`, `AI Credits`, `Tokens`, `Session exported to...`), so stdout remains parseable assistant prose. |
| Completion signal | Process completion is the contract boundary: wait for exit, then consume full stdout buffer. Exit code `0` indicates normal completion. |
| Share transcript | `--share <path>` writes a markdown transcript file after completion; this is useful for debugging but not required for runtime extraction. |
| Timeout behavior | External timeout termination yields non-zero exit (observed `124` via `timeout`), with no guaranteed transcript payload; treat as backend failure/skip per policy. |
| Size behavior | Large outputs (observed ~5.4 KB content) are delivered on stdout without truncation in these probes; harness still enforces an input-size ceiling before invocation. |
| Cleanup | Harness owns temp transcript artifacts and deletes sandbox state in `finally`; only copied-out `.eval-artifacts/*.txt` files persist. |

### Off-ramp outcome (DR2-#8)

Off-ramp was **not required** in this spike: both a prompt-only invocation and an agent invocation produced parseable stdout assistant text.

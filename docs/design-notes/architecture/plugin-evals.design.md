---
description: Two-tier plugin evaluation harness (structural Pester + waza LLM), report generation, per-task workspace isolation, token resolution, and judge/injection contract
globs:
  - plugins/**/evals/**
  - scripts/skalary/Test-Evals.ps1
  - scripts/skalary/Invoke-WazaEvals.ps1
  - scripts/skalary/Ensure-EvalTools.ps1
  - scripts/skalary/Resolve-EvalToken.ps1
  - tools/eval-tools.psd1
  - tests/evals/**
---

# Plugin Evals

## Architecture

| Tier | Scope | Execution mode | Gate policy |
|---|---|---|---|
| Structural (Tier-1) | Pester evals in `plugins/<name>/evals/*.Tests.ps1` validate frontmatter, required keys, names, links, and referenced assets | Direct `scripts/skalary/Test-Evals.ps1 -Plugin <name>` | Deterministic, selected-plugin-only local command |
| LLM (Tier-2) | Declarative **waza** specs in `plugins/<name>/evals/waza/eval.yaml` (+ `tasks/*.yaml`) run by the `copilot-sdk` executor and scored by graders | Direct `scripts/skalary/Invoke-WazaEvals.ps1 -Plugin <name>` | Premium opt-in; never part of deterministic validation |

`Test-Evals.ps1` runs Tier-1 only (structural-Pester); the bespoke `EvalLlm.psm1` backend was retired in Phase 4.4. Routine runs require one explicit plugin and validate only that plugin. The direct `-FullRepository` operator route verifies every id in the strict Markdown list `tools/structural-eval-required.md` exactly once. Tier-2 lives entirely under `Invoke-WazaEvals.ps1`, requires one validated plugin before provisioning or output creation, and remains auth-dependent and premium-cost.

`-PluginsRoot` and `-RequiredListPath` are executable test seams: ordinary tests point them at
fixture evals to prove missing, skipped, and duplicate required IDs fail. Routine runs omit both,
so the runner always resolves the repository `plugins/` tree and committed required-ID contract.

## File Layout and Contracts

| Surface | Contract |
|---|---|
| `plugins/<name>/evals/*.Tests.ps1` | Tier-1 structural assertions per plugin, using shared helpers |
| `plugins/<name>/evals/waza/eval.yaml` | Tier-2 spec: `skill:` (target artifact name), `config` (executor/model/judge_model/trials/timeout/`skill_directories`), spec-level `graders`, optional `adversarial:` block |
| `plugins/<name>/evals/waza/tasks/*.yaml` | One case each: `inputs.prompt` (+ `inputs.context.fixture` / `inputs.follow_up_prompts`) then `graders` |
| `plugins/<name>/evals/waza/fixtures/*` | Diffs/sample files a task feeds the agent (referenced by `inputs.context.fixture`) |
| `tests/evals/EvalCommon.psm1` | Tier-1 structural helper module (frontmatter parse, required keys, link/file resolution, section checks) |
| `tests/evals/Waza<Plugin>Convention.Tests.ps1` | Offline fail-closed shape guards per plugin: assert exact field placement so waza's fail-open (misplaced field warned-and-ignored) cannot yield a silent false PASS |
| `tests/evals/LegacyCutover.Tests.ps1` | Locks the migrated state: every plugin with a waza spec has no legacy `evals/llm/*.eval.json`, and `EvalLlm.psm1` stays deleted/unwired (`test:evalllm-retired`) |
| `tools/eval-tools.psd1` | Single source of truth for pinned tool versions (waza `0.38.0`, `gh`), sources, per-OS assets + committed checksums |

Structural cases that protect a cross-plugin runtime contract use a stable first token
(`eval:<Subsystem>.<Consumer>.<Invariant>`) followed by a human-readable description. Discovery gates
compare those tokens exactly, not Pester's display text, so renaming prose does not rewrite evidence
while deleting or merging one invariant fails loudly. Review reporting applies this to separate CR
and DR cases rather than treating one aggregate nonzero eval count as coverage. Their thin per-plugin
cases call the shared invariant assertions in `EvalCommon.psm1`, preserving plugin attribution without
copying the contract logic.

Fleet's five installed consumers each own one required structural identifier:
`eval:FleetDispatch.CIP.ConsumerContract`, `eval:FleetDispatch.CI.ConsumerContract`,
`eval:FleetDispatch.Autopilot.ConsumerContract`, `eval:FleetDispatch.CR.ConsumerContract`, and
`eval:FleetDispatch.DR.ConsumerContract`. Each case proves that consumer's pre-dispatch ordering,
role/task conservation, and native-host/Capture boundaries. Registering all five in
`tools/structural-eval-required.md` prevents an aggregate Fleet parity check from hiding a missing
consumer contract.

The migration is complete: all six previously-bespoke artifacts (`cr`, `dr`, `autopilot`, `ci`, `cip`, `design-notes`) plus the former coverage gap `process-pr-comments` now ship waza specs; no plugin retains legacy `evals/llm/*.eval.json`. The later-added `plugin-manager` plugin ships a waza spec from the start under the same convention (skill target `install-plugin`, two describe-only tasks, no adversarial block). `design-notes` prompts were consolidated into a single `design-notes` skill (Phase 4.1) so they became testable (copilot-sdk has no prompt executor). The `architecture-notes` plugin ships describe-only draft-by-default and human-review cases under the same convention, guarded by a fail-closed shape test. All ten current plugins use the two-tier harness.

## Backend and Isolation Boundary

Tier-2 runs on **waza** (`copilot-sdk` executor), which gives each task a **fresh temp workspace** (`%TEMP%\waza-<id>`, agent cwd = that dir) with fixtures copied in — replacing the bespoke sandbox-clone + Sync-Dogfood + push-disable dance the old `EvalLlm.psm1` backend performed per run.

Isolation is **partial** (see Waza Behavior gate (a)): **relative** writes are contained in the temp workspace, but waza has no OS-level/container executor, so an agent steered to an **absolute** repo path can escape and mutate the live tree. Conventions that hold the boundary:

- **Read-only / describe-only cases** run as-is (never `--allow-all` for a case that needs no writes). Most shipped cases are describe-only reasoning scenarios graded on the response.
- **Write-enabled and adversarial cases** must run in a disposable checkout or behind a path-rejecting tool layer; the `container` boundary (Phase 3 ADO) is the durable control. `test:live-tree-clean` is a post-hoc tripwire, not the primary containment.
- **Durable-token exclusion:** `Invoke-WazaEvals.ps1` gives `adversarial:` specs only the short-lived `gh` OAuth token (never the Cred-Manager PAT) in the child env, and waza's OTEL payloads default to redacted (sha256+length).

## Config and Auth

Tier-2 auth is resolved by `scripts/skalary/Resolve-EvalToken.ps1` with precedence **`gh auth token` → ambient `COPILOT_GITHUB_TOKEN`/`GH_TOKEN` → Cred-Manager `copilot-eval`→`copilot-autopilot` → actionable skip**; the resolved token is set into the child process env only. Tool provisioning is centralized in `scripts/skalary/Ensure-EvalTools.ps1` (the only provisioner; pins from `tools/eval-tools.psd1`, checksum-verified, explicit-approval installs).

`.eval.config.json` (gitignored; shape in committed `.eval.config.json.example`) now holds only the Cred-Manager fallback targets that `Resolve-EvalToken` consumes:

| Key | Purpose |
|---|---|
| `credentialTarget` / `credentialTargets` | Windows Credential Manager target(s) holding the eval PAT (fallback source); loaded into `COPILOT_GITHUB_TOKEN`/`GH_TOKEN`. A dedicated `copilot-eval` secret keeps eval auth separate from `copilot-autopilot` |
| `judgeModel` / `temperature` / `passThreshold` / `timeoutSeconds` | **Legacy tuning fields** — read by the retired `EvalLlm.psm1` backend. waza reads **none** of them: each `eval.yaml` pins its own `config.model` / `config.judge_model` / `timeout_seconds`. Kept for config compatibility |

Credential resolution is skip-not-error: an unset/missing target records an actionable `skip` and keeps the run green. On a non-Windows box (autopilot containers) the Cred-Manager source is skipped entirely and `gh`/ambient env carry auth.

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
| Fallback token source | Cred-Manager `copilot-eval` PAT present and resolvable; PoC ran 2/2 green against the real `cr` bundle on this token — retained as the unattended fallback |
| gh provisioning (`Ensure-EvalTools`) | winget resolves the pinned `GitHub.cli 2.96.0` and verifies the installer hash, but the MSI **requires elevation** — a non-elevated install aborts (winget exit `1602`). gh must therefore be pre-installed or installed from an elevated context on developer machines (feeds the Phase 3 ADO rollout). |

**Decision:** on a machine where a human can auth, **gh is the promoted seamless source** — the personal-box probe confirms a gh OAuth token is entitled and auto-refreshes, sidestepping the 7-day PAT regen. The Cred-Manager `copilot-eval` PAT stays the unattended fallback (resolver precedence already prefers gh when present). **Corp orgs remain PENDING** a work-machine run of the same probe under corp SSO; record the entitled orgs in the table above when known.

## Known Limitations

| Limitation | Current handling |
|---|---|
| `cr`/`dr` CLI fidelity | `cr`/`dr` are VS Code-hosted orchestrators; headless `copilot --agent` may not reproduce full subagent fan-out/model-vendor resolution. Tier-2 rubrics for these plugins target observable orchestrator behavior (e.g., injection-safe handling and structured findings), not exact multi-model consensus output. |

## Waza Behavior

The Tier-2 backend **is waza** (Microsoft Go CLI, pinned `0.38.0`, `copilot-sdk` executor); the bespoke `EvalLlm.psm1` was retired in Phase 4.4. Specs live at `plugins/<name>/evals/waza/eval.yaml` (+ `tasks/*.yaml`). This section records the live-verified behavior that the shipped conventions depend on. Confidence is per-**claim**, not per-row: **verified** = observed on this box against the real `cr` bundle; **inferred** = extrapolated, not yet observed; **schema** = confirmed from waza's embedded JSON schema but not executed; **deferred** = characterized but not yet live-fired. The **Phase 5.1 premium sweep has now run** (all 9 functional spec-runs green — see "### 5.1 live-fire sweep"), which resolves several rows previously marked *deferred*; where a specific sub-claim remains genuinely un-fired it is still flagged inline.

### Hard gates (a failing answer blocks the affected cases)

| Gate | Answer | Convention | Confidence |
|---|---|---|---|
| (a) Workspace isolation / absolute-path containment | **Partial.** Each task runs in a fresh temp workspace (`%TEMP%\waza-<id>`) with agent cwd = that dir; fixtures are copied in. **Relative** writes are contained there; an agent instructed to write an **absolute** repo path **escapes** and mutates the live tree — waza has **no** OS-level/container executor. A read-only `cr` run (tools resolved to `glob`+`view`) left the live tree byte-clean; a relative-write probe stayed inside the temp workspace. | **Read-only cases** run as-is on the live box. **Write-enabled and adversarial cases are BLOCKED in Phase 2 from running against the live worktree** — they must run in a disposable checkout/throwaway clone or behind a path-rejecting tool layer (reject absolute / `..`-escaping paths), with the `container` boundary (Phase 3 ADO) as the durable control. `test:live-tree-clean` is a post-hoc **tripwire**, not the primary containment control. Never `--allow-all` for a case that does not need writes. | verified |
| (b) Injection harness + judge content | **(i) Judge content — CORRECTED in 2.1 live-fire:** the **independent** judge (`continue_session: false`, waza's default) is **flaky against a real agent** — waza drops it into the task workspace *without reliably injecting the agent's final text*, so it hunts the filesystem, finds only the fixture, and false-fails (observed: `flag-planted-bug` judge `fail: No reviewer output found — only the diff file exists` on one run, PASS on another with byte-identical inputs). **Use `continue_session: true`** so the judge **resumes the agent's session** and deterministically sees the review (2×2 trials → 100% `pass_rate`, stddev 0). Keep `inputs.follow_up_prompts: [ ... ]` to force a final **text** turn so the deterministic `text` grader and `final_output` stay populated. This reverses the earlier 1.0 bet on the independent judge. **(ii) `cr` injection-resistance — functional path VERIFIED in 2.1:** the functional `treat-injection-as-data` task ran green live — `cr` flagged **both** injected directives as Critical prompt-injection attacks *and* still found a real bounds bug, with a deterministic `text` tripwire (reject a bare-approval final output) + the resumed judge both passing across 2 trials. The **`waza adversarial` pack live-fire ran in the 5.1 sweep** (on a short-lived `gh` OAuth token — REQ-22 forbids exposing the durable Cred-Manager PAT to injection tasks, so it was gated on gh entitlement, confirmed in 1.4) and is a **documented poor-fit** for `cr`: the generic pack feeds content inline (no file to read, so `cr_reads_under_review` can't hold) and its built-in `_output_not_contains` grader false-positives when `cr` correctly names a flagged credential variable — see "### 5.1 live-fire sweep" + Decisions. The functional `treat-injection-as-data` task is the authoritative injection coverage. The `adversarial:` block is proven **well-formed and inherited** (mock `--spec` ran the 4-task `prompt-injection` pack and the spec-level `tool_constraint` merged into every pack task); `waza adversarial --spec` needs `--skill`/`--model` forwarded explicitly (it does **not** read them from the spec — it defaults to the `adversarial-target` stub skill + its own pinned model). | **Resume-session judge (`continue_session: true`) everywhere** — the independent judge is flaky (2.1, RISK-11); route adversarial-diff cases through the `adversarial:` block (`schemaVersion: "1.2"`) and carry the verdict on a deterministic `program`/`text` grader as a non-LLM control; `test:injection-guard` + `test:waza-spec-shape` gate 2.1. | (i) verified (corrected) · (ii) functional verified · pack poor-fit (5.1) |
| (b′) Durable-token exclusion (token segregation) | **Verified (mechanism):** `waza run --otel-include-payloads` defaults to **redacted** (sha256 + length only) so a durable token is not captured into artifacts; the runner (1.5) already segregates env — adversarial specs receive the **short-lived `gh` OAuth token**, never the Cred-Manager PAT, in the copilot-sdk child env. **Deferred:** proving a fixture in the `--allow-all` child cannot read the token is left to the 2.1 live-fire. | Adversarial child env carries only the short-lived token + default-deny env snapshot + redacted OTEL; the PAT path is used only for non-adversarial runs; `test:token-segregation` gates 2.1 against this convention. | verified (mech) · deferred (live) |
| (g) copilot-sdk tool-name mapping | cr's frontmatter declares VS Code names `read, search, execute, agent, todo`, but copilot-sdk surfaces its **own** identifiers. **Observed:** `search`→`glob`, `read`→`view`; the single `execute` capability fans out into `create` (write file), `edit` (in-place edit), and the **OS-dependent shell** — `powershell` on Windows, `bash` on Linux (matters: autopilot containers are Linux). The auto-injected `tool_constraint` (keyed off the frontmatter names) therefore can **never** match and spuriously fails (Gotcha A: seen as `agent_tools_implicit: Expected tool not used: execute`). | Real `tool_constraint`/`tool_calls`/`behavior` graders must use the **observed copilot-sdk** names, not the frontmatter names, and must branch the shell name on OS (`powershell`/`bash`) — critical for 2.4's build/test-before-commit grader. A reject-only `tool_constraint` override is permitted **only** on tasks with no tool-behavior requirement (see Gotcha-A rule below). | verified |

### Soft gates (recorded, proceed with the convention)

| Gate | Answer / convention | Confidence |
|---|---|---|
| (c) `skill_directories` resolution base | Resolved **relative to the `eval.yaml` file**. For a shipped `plugins/<name>/evals/waza/eval.yaml`, the real agent bundle is `../../agents` (skills: the skill dir). | verified |
| (d) grader merge-vs-replace | Top-level `graders` are **global and merge** with per-task graders (not replace): the spike's 1 global `tool_constraint` + 2 per-task graders all fired on the task. | verified |
| (e) `SKILL.md`/`.agent.md` execution | `inject_skill_body: true` (default) injects the target body into the system prompt. Set `false` to measure whether the agent *invokes* a skill (keeps the `<available_skills>` summary; lets `behavior`/`skill_invocation` graders observe the `skill` tool). **Needs one-shot live confirmation before 2.4/2.5 build a `skill_invocation`/`behavior` grader on it.** | schema |
| (f) binary ↔ `schemaVersion` compat | `0.38.0` accepts `schemaVersion "1.2"` (needed for `adversarial:`/`mcp_mocks`). **Fail-open hazard:** an unknown/misplaced field on a same-major artifact **warns and is ignored, not rejected** — so a grader whose field is misplaced silently never fires and yields a **false PASS**. `waza migrate` upgrades artifacts. | verified |
| (h) model-slug placement | waza requires `config.model` in `eval.yaml` (a model family slug, not a secret), overridable with `--model`; `judge_model` likewise. The pinned slug stays in the committed YAML; `.eval.config.json` retains only judge/threshold tuning. | verified |
| (i) cr/dr fan-out headless | **No fan-out.** The `cr` run was a single copilot-sdk session (one `session.start`, no subagent/child-session or `agent`-tool events); the concern reviewers (`cr-<concern>` / `dr-<concern>`, formerly the per-model `*-opus`/`*-codex`/`*-gemini` specialists) are not reproduced headless. The concern split changed *which* subagents exist, not whether waza reproduces them, so the rubric stance is unchanged: target observable single-agent orchestrator output (RISK-7). A fixture or rubric naming a per-model reviewer is stale by construction — those agents were deleted. | verified |

### Conventions that guard the fail-open behavior

- **Fail-closed spec shape (guards f + Gotcha A):** because waza ignores misplaced fields silently, `test:waza-spec-shape` must assert **exact field placement** and the runner/lint must assert **every declared grader actually executed** (non-zero grader-eval count per task) so a silently-dropped grader fails loudly instead of passing.
- **Gotcha-A suppression rule (guards g):** a reject-only `tool_constraint` override (which suppresses the auto-injected constraint by never matching) is permitted **only** on tasks with **no** tool-behavior requirement. Any `behavior`/`tool_calls`/`tool_constraint` grader that asserts behavior must use a **real** constraint with the observed copilot-sdk names — never the suppression trick.

### Field-placement corrections (learned from the spike)

| Field | Correct placement | Note |
|---|---|---|
| `follow_up_prompts` | **`inputs.follow_up_prompts`** (array of strings), mutually exclusive with `inputs.responder` (schema) | A task **top-level** `follow_up_prompts` emits a warning (`unknown schema field ignored ... type models.TestCase`) and has **no effect** — it must be nested under `inputs`. This is the fail-open behavior of gate (f) in miniature. |
| `continue_session` | `prompt` grader `config.continue_session` | Default `false` = independent judge, but it is **flaky against a real agent** (2.1: waza does not hand the agent's output to the judge, so it hunts the workspace and false-fails). **Use `true`** — the judge resumes the agent session and reliably sees the review; live 2×2 trials were 100% stable, including the injection case (the resumed judge grades `cr`'s actual output, not the raw fixture). |
| `checkpoints` (`after_turn`) | task **top-level** `checkpoints: [{ after_turn: N, on_failure: continue, graders: [...] }]` (schema ≥ 1.1) | Runs graders at a **turn boundary** instead of only at final state. Used in 5.1 to grade a deterministic `text` pre-check at the **draft turn** (`after_turn: 1`) rather than `final_output`, because a `follow_up_prompts` confirmation **paraphrases** the graded concepts away ("eval"→"harness", "transcript"→"capture") and made a final-output `text` grader flake. Confirmed executed live: the result JSON carries a per-run `checkpoints[]` with the pre-check `passed`/`score`, separate from the final `validations` (the resumed judge). `on_failure: continue` keeps the judge running at the final turn. |

### 5.1 live-fire sweep (all shipped specs)

The full Tier-2 sweep ran live (`copilot-sdk`, `claude-sonnet-4.6`, gh OAuth token). After the grader-authoring fixes below, **all 9 functional spec-runs are green** (autopilot, cr, ci, cip, dr, pprc, design-notes). Findings that hardened the shipped conventions:

- **Deterministic `text` pre-checks belong at the draft turn, not `final_output` (design-notes).** For multi-turn *describe-only* tasks, the `follow_up_prompts` confirmation is a terse paraphrase — run-to-run it drops the checked tokens ("eval"→"harness", "transcript"→"capture", "sandbox"→"disposable"), so a `text` grader on `final_output` flaked at ~50% `pass_rate` even though the substantive **draft** always names the concepts verbatim and the resume-session judge passed 100%. **Fix:** grade the `text` pre-check in a `checkpoints: after_turn: 1` block (the draft turn) with `on_failure: continue`; the judge still grades the final turn via `continue_session: true`. Verified live: the checkpoint fires (per-run `checkpoints[]` in the result JSON) and design-notes went 3/3 at 100% `pass_rate`, stddev 0. Codified by `WazaDesignNotesConvention.Tests.ps1`.
- **Update-workflow tasks need an existing-note fixture.** The design-notes `update-design-note` task asks the agent to *update an existing note*, but the isolated workspace was empty, so the agent sometimes drafted a brand-new note and the judge (correctly) failed criterion 1 — a flaky, task-design artifact, not agent misbehavior. **Fix:** copy an existing note into the workspace via `inputs.context.fixture` (`fixtures/existing-eval-note.design.md`) and reference it in the prompt, making "update-oriented" deterministic.
- **`cr` generic adversarial pack (`waza adversarial`) is a documented poor-fit; the functional injection task is the authoritative coverage.** Two independent mismatches: (i) `cr`'s spec-level `cr_reads_under_review` expects a `view`/read tool call, but the generic pack feeds injected content *inline* so there is no file to read — the read-assertion cannot hold; (ii) the pack's built-in `_output_not_contains` safety grader false-positives when `cr` **correctly names/quotes** a flagged credential *variable name* (e.g. `AWS_SECRET_ACCESS_KEY`) in its review — the review is the safe outcome, but the grader reads the literal string as leakage. The **functional** `treat-injection-as-data` task (2/2 green live) — `cr` flags injected directives as attacks and still finds the real bug — remains the authoritative injection-safety coverage. **Recommendation:** keep the functional injection task; treat the generic-pack result as a documented poor-fit rather than chasing green. This narrows (does not remove) injection coverage for `cr`; surfaced for the security-scope owner (REQ-22/23).



## Per-plugin spec conventions

The runner (`Invoke-WazaEvals.ps1` → `Get-WazaEvalSpec`) discovers exactly **one** `eval.yaml` (one top-level `skill:`) per plugin, so each plugin consolidates its cases under a single skill. Shipped grader shape per plugin:

| Plugin | Skill target | Case style | Adversarial pack |
|---|---|---|---|
| `code-review` (`cr`) | agent | functional review-quality + injection resistance, including a malicious-directive/legitimate-policy contrast pair | `prompt-injection` |
| `design-review` (`dr`) | agent | describe-only feasibility/security reasoning | — |
| `autopilot` | agent | describe-only behavioral (execution forbidden — an un-constrained agent tries to really execute and times out) | — |
| `continue-implementation` (`ci`) | skill | one describe-only + one real `tool_calls`/`behavior` grader (build/test ran before commit) | — |
| `create-implementation-plan` (`cip`) | skill | describe-only plan-quality reasoning | — |
| `design-notes` | skill (consolidated from 3 prompts in 4.1) | describe-only bootstrap/create/update reasoning | — |
| `process-pr-comments` | skill (interactive-only, injection-aware) | describe-only: headless approval-gate refusal + reviewer-text-as-data | `prompt-injection` |
| `architecture-notes` | skill | describe-only: draft-by-default authoring, review drift/coverage, human-only lock refusal | — |
| `plugin-manager` | skill (`install-plugin`; 4 skills ship, but one body injects per spec) | describe-only: default-source + direct-invocation discipline, opt-in read-only auto-approval decision | — |

Rules baked in: a skill whose `SKILL.md` declares **no `tools:` frontmatter** gets **no** spec-level `tool_constraint` (waza auto-injects nothing to suppress — contrast cr/dr agent frontmatter, Gotcha A); describe-only cases assert on the response text only; every `prompt` judge sets `continue_session: true`; injection-aware skills carry the `prompt-injection` adversarial pack with `on_unsafe_outcome: fail`.

## Judge Contract and Injection Guard

Tier-2 grading is waza's grader stack, not a bespoke JSON-judge:

| Aspect | Contract |
|---|---|
| Deterministic pre-check | A `text` grader (`regex_match` / `regex_not_match`) — 0 judge tokens. Kept **broad** so a paraphrased-but-correct answer is not false-failed; the injection tripwire (`regex_not_match`) rejects a final output that is *only* compliance (e.g. a bare `LGTM`/approval) |
| LLM judge | A `prompt` grader with a pinned `model`; the judge calls `set_waza_grade_pass` / `set_waza_grade_fail`. Ported rubrics become the judge prompt criteria |
| Judge content channel | `continue_session: true` (always) — the independent judge (`continue_session: false`) is flaky against a real agent (it is dropped into the workspace without the agent's output and hunts the fixture). Resuming the session lets the judge see the real output. `inputs.follow_up_prompts` forces a final text turn so `final_output` + the `text` grader stay populated |
| Injection harness | Injection-aware skills route through the `adversarial:` block (`prompt-injection` pack, `schemaVersion: "1.2"`, `on_unsafe_outcome: fail`), run in a disposable workspace with the short-lived `gh` token only |
| Pass decision | Per-grader pass/fail aggregate to the task; use `trials_per_task` + `pass_rate` (not a single verdict) for flaky cases |

## Report and Writeback Model

`Invoke-WazaEvals.ps1` runs `waza run --output-dir tests/evals/output/<stamp>` (or `waza adversarial` for specs with an `adversarial:` block) per spec, aggregating exit codes; a requested run that executed **zero** evals is a distinct non-green outcome, not exit 0. waza writes per-task results JSON (per-grader score/passed/feedback), a summary, and usage/token counts under the gitignored `tests/evals/output/<stamp>/`. `Test-Evals.ps1` (Tier-1) still writes its own `report.json` / `report.md` there. Registry/manifests/receipts stay unchanged:

| Surface | Status |
|---|---|
| `plugin.json` `evals` seams (`status`, `lastRun`) | Reserved, not populated by harness |
| `registry.json` `evals.status` | Reserved-seam summary, not runtime writeback |
| `.github/.skalary/receipts/*` `evalStatus` | Reserved, not populated by harness |

Receipt/registry writeback is intentionally deferred; the harness is report-only to preserve deterministic registry output and dogfood drift behavior.

## Transcript Capture Contract

waza owns transcript capture for Tier-2. Today `Invoke-WazaEvals.ps1` only passes `--output-dir tests/evals/output/<stamp>`; the per-task results JSON written there already carries per-grader score/feedback, which covers routine triage, so the runner captures no separate transcript. waza's own richer capture/replay surfaces (per-task transcript + snapshot for `waza replay`) are available to invoke ad-hoc when debugging a specific task, but are **not** wired into the runner and are not part of the committed contract. waza redacts OTEL payloads by default (sha256 + length), so a durable token cannot leak into captured artifacts. All Tier-2 output lands under the gitignored `tests/evals/output/`.

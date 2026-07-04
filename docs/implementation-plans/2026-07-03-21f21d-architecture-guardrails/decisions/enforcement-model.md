# Decision: Enforcement Model (hybrid deterministic + LLM)

## Context
Pillar (b) needs architectural fitness tests that prove implementations honor the
high-level design — beyond compile/unit tests. Supported languages: C# and TypeScript.

## Decision
Two test kinds, one runner, with a strict separation between **executing** tests and
**verifying** their results.

1. **Deterministic (the only kind that can hard-block).** Native architecture-test frameworks
   executed through their own toolchains:
   - C# → **NetArchTest** (reflection over compiled assemblies).
   - TypeScript → **ts-arch** (AST/dependency analysis; pairs with dependency-cruiser
     for dependency graphs where needed).
   These are **assertion libraries used inside a compiled test project / vitest run**, not
   standalone tools. The plugin therefore **owns fixture templates** (a C# test project, a TS
   spec set) with **pinned package references**; contracts parameterize them. The runner shells
   to `dotnet test` / `npm`/`vitest`, parses a defined **result contract** (TRX / JUnit / JSON),
   and emits a receipt (below). Frameworks sit behind a **pluggable adapter interface**.

2. **LLM semantic (advisory in the gate — always).** Catches contract violations the
   structural frameworks cannot express (intent, naming semantics, layering rationale).
   Runs behind a **semantic-eval provider seam** so the LLM backend is swappable:
   - **Concrete provider interface** (`SemanticEvalProvider.ps1`):
     `Invoke-SemanticEvalProvider -ProviderName -ContractPath -TargetRoot -ConfigPath -CredentialTarget` →
     strict JSON `{ provider, status: pass|fail|skip-absent-toolchain|error, findings[],
     artifacts[] }`. The runner core depends only on this interface.
   - **`custom` provider (ships now):** reuses the eval-harness patterns with a **dedicated**
     credential target (not the eval PAT), skip-not-error when set-but-missing.
   - **`mock`/`null` provider (ships now):** a trivial second implementation so **swappability is
     actually exercised by two providers** — it cannot be *proven* with only `custom` shipping.
   - **`waza` provider (documentation until its schema is pinned):**
     [Waza](https://microsoft.github.io/waza/) YAML `eval.yaml`, LLM-as-judge `prompt` graders,
     `mock`/`copilot-sdk` executors. A drop-in adapter against an external tool's evolving schema
     — treated as a planned contract, not a shipped one.
   - **Never hard-blocks CI.** The semantic-eval gate outcome is **flat advisory regardless of
     contract maturity** — `Get-ArchGateOutcome` maps a `semantic-eval` verdict to `pass` (a real,
     ran pass) or `warn` (anything else), never `block`, so a non-deterministic verdict can never
     break the build. Maturity does not elevate an LLM finding in the gate; the locked hard-gate
     applies only to the deterministic adapters.

   > Decoupling rationale: the eval backend is under active evaluation (custom → Waza). The
   > runner must not hard-depend on `.eval.config.json`/`Test-Evals.ps1`; a thin provider seam
   > (mirroring the deterministic-framework adapter pattern) keeps the migration cheap.

## Lock-before-execute (untrusted code boundary, human-commit bound)
Agents may **draft** framework test code from contract content, but arch-note text (contracts,
prose, C#/TS stubs) is untrusted, so derived test code is **untrusted-influenced code that
would be compiled and run**. Therefore:
- Deriving and executing are **separate stages** with a **human review + `locked` gate**
  between them.
- **`locked` is not a self-grantable flag.** `maturity: locked` is honored **only when the
  `draft→locked` promotion landed in a human-authored/reviewed commit**. Autopilot/autonomous
  `/ci` is **forbidden** from promoting `draft→locked` — an agent may *propose* a lock; a human
  merges it. Otherwise the same agent that derives a body from untrusted prose could write
  `maturity: locked` and self-authorize execution (the highest-risk path).
- **Body-level lock, not just contract-level.** A `locked` *contract* and a reviewed *test body*
  are different things: an agent could mutate the executable body of an already-locked contract.
  So the runner re-checks a **`lockedBodySha256`** (hash of the reviewed body) immediately before
  execution and **refuses draft, unreviewed, or hash-mismatched bodies**.
This preserves the plan-workflow invariant that evidence is machine-checkable with no dynamic
execution of untrusted content.

## Execution boundary (toolchain never in the always-on CI gate)
- The toolchain-shelling runner runs **only inside `/ci` implementation/crosscheck**, opt-in
  like the eval harness's `-IncludeLlm`, with `npm ci --ignore-scripts` /
  `dotnet restore --locked-mode`.
- `scripts/validate.ps1` and `npm test` stay **dependency-free/structural** — they must run
  identically on the Windows host and the autopilot Linux container. They **pure-parse the
  receipt**; they never shell to `dotnet`/`npm`/`vitest`.
- **Containment honesty.** `--ignore-scripts` disables **install-lifecycle** scripts only;
  `vitest`/`dotnet test` still execute third-party framework/dev-dep code (and MSBuild targets
  from restored NuGet packages) in-process at test time. True containment needs the **container
  backend**, which `plugin-evals.design.md` marks **reserved/unimplemented**. This plan does
  **not** build it — until it exists, real fixture runs execute in the documented
  **non-containing sandbox**, and real runs are labelled/gated behind that caveat rather than
  claiming containment.

## Trust anchor = git history + human commit (not cryptography)
The threat being defended is **untrusted plan/contract text forging a pass** — *not* defending
against a component we already trust to run the tests. You cannot cryptographically defend
against the runner that also produces receipts: a compromised runner simply signs the forgery,
so HMAC/signing infra buys little and is not added. The anchor is the one `evidence.md` already
uses: the **human-authored commit + git review**. A human reviewing/committing the `locked`
contract **and** its receipt in the same PR is the tamper-evidence.

## Integrity/freshness receipt (the `arch:` verification substrate)
The `/ci` runner emits a receipt (`arch-test-receipt.schema.json`, shipped as a scaffolded
plugin asset) per contract: `contract-id`, **recorded parent-commit SHA**, `maturity`, a
**tree/content hash of contract + target sources**, and a verdict from the failure taxonomy. It
mirrors the existing `Build-EvidenceReceipt.ps1` / `evidence.md` pattern and is **committed
alongside `evidence.md`**. `Test-Plan.ps1` verifies an `arch:<ContractId>` marker by
**pure-parsing this receipt** — never by executing tests.
- **What it proves:** *integrity + freshness* — "a real run happened at this tree-state, here is
  its verdict." It does **not** prove anti-forgery (see trust anchor above); the marker tests are
  scoped to `reject stale/malformed`, not `reject forged`.
- **Freshness binds to the tree/content hash**, not raw `HEAD` equality — a strict
  `recorded-SHA == HEAD` check would go permanently red the moment the receipt is committed
  (committing advances HEAD). The recorded SHA is treated as the **parent commit**.
- **Extraction + fail-loud.** `Get-TypedEvidenceMarkers` is extended to extract `arch:`. An
  **unknown/unrecognized typed-marker prefix fails loud (unrun/error), never silently drops** —
  so a stale installed bundle (pre-`arch:` `PlanState.psm1`) **blocks** rather than false-greens.

## Failure taxonomy × maturity (explicit gate matrix)
Every check yields exactly one of `pass` · `fail` · `skip-absent-toolchain` · `error`. The gate
outcome is the **full matrix**, not left to implementers:

| verdict | `locked` | `draft`/`provisional` |
|---|---|---|
| `pass` | green | green |
| `fail` | **block** | warn |
| `error` | **block (unrun-required)** | warn |
| `skip-absent-toolchain` | **block (unrun-required)** | warn |

For a `locked` contract, **only `pass` greens** — `fail`, `error`, **and** `skip-absent-toolchain`
are all non-passing/unrun-required (they map onto the existing "unrun-required marker" gate
outcome, never green). This closes the bypass where an attacker or flaky harness converts a
would-be `fail` into an `error` and ships. LLM verdicts never enter the blocking set regardless
of maturity.

## Runner ownership (single source of truth)
The runner's **canonical source is `scripts/skalary/Invoke-ArchTests.ps1`** — the single source
of truth the bundling model requires, so `Sync-PluginScripts.ps1` (the sole writer of bundled
copies) bundles it into ci/cip like every other shared script. A plugin-owned canonical home
would create a second source of truth the drift gate cannot cover.

## Untrusted input hardening
Arch-note text into any LLM step must:
- **Neutralize literal boundary tokens** in the content before wrapping.
- Use **per-invocation GUID-suffixed** fences (`<<<UNTRUSTED_*:{guid}>>>`) so content cannot
  close the fence — multi-modal contracts (prose + code stubs) can contain literal fence tokens.
- Enforce a **strict-JSON verdict** contract and **fail loud on non-JSON**.

Additionally, harvested/auto-loaded arch content (brownfield harvest scans an untrusted repo)
is **gated behind human review before it becomes auto-loadable** into `/cip` and `/ci`.

> **Containment honesty on the auto-load path.** The GUID-fence machinery above lives **only in
> the LLM provider invocation**. Auto-loading works by `copilot-instructions.md` telling the
> agent to read the index + notes *directly* into its own context — there is **no wrapping step
> there**. So the containment story for auto-loaded arch/ADR content rests on the
> **human-review-before-auto-load gate + the terse template-constrained format**, not on runtime
> fencing. ADRs also append continuously, so the auto-loaded tier keeps **only active decisions**
> (superseded ADRs archived/summarized via `/uan`) to bound the always-on token cost.

## Rationale
Deterministic frameworks are fast, repeatable, and the industry standard (ArchUnit lineage);
they are the only kind trustworthy enough to break a build. LLM adds semantic reach but is
non-deterministic, so it stays advisory. The receipt + pure-parse split keeps `Test-Plan.ps1`
free of untrusted execution while still letting `arch:` prove real runs happened. The trust
anchor is deliberately **git + human review**, not crypto — you cannot sign your way out of
trusting the runner that signs. The taxonomy × maturity matrix removes the false-green/flaky
ambiguity (and the `error`-as-bypass hole) of a naive skip-not-fail rule.

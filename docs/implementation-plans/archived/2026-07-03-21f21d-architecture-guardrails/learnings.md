## Learnings Capture
Phase: 1

No entries for this phase.

## Learnings Capture
Phase: 2

- [-] [trigger:plan-contradiction] SKILL.md forward-referenced enforcement it cannot deliver alone (lock authorization, human-doc generator, runner). DR flagged as Criticals. Learning: a skill's prose must not claim a gate that a later-phase script provides; mark forward-references explicitly and state what the current gate does NOT do. Fold machine-enforcement gaps back into the owning phase's REQs.

## Learnings Capture
Phase: 3

- [-] [trigger:reusable-pattern] Generated docs with in-place regenerated regions (BEGIN/END marker splice) must HTML-escape angle brackets in any untrusted interpolated text, else the text can emit the region end marker and corrupt the next regen (IndexOf finds injected marker first). Pair with ordinal IndexOf. Same class as harvest glob-frontmatter leak: treat all contract-derived text as inert data at every render boundary (markdown cells, mermaid labels, HTML-comment markers).

## Learnings Capture
Phase: 4

- [-] [trigger:reusable-pattern] Freshness receipts must bind BOTH file content AND the semantic binding (adapter, spec, target set, maturity) via a NUL-prefixed synthetic hash record, so repointing a contract without editing files still invalidates prior receipts. And any pass verdict must be gated on ran=true at all three layers (builder throw, gate mapping, JSON schema conditional) to prevent a locked false-green.
- [4.2] [trigger:reusable-pattern] Lock a compiled test body by hashing the whole project DIRECTORY not the csproj leaf. dotnet test compiles every cs in the project so hashing only the csproj lets an agent gut a reviewed assertion cs while keeping the lock green. Expand any project file to its parent dir before computing lockedBodySha256.
- [4.3] [trigger:reusable-pattern] Locking a compiled C# or TS test body must exclude never-committed build-output dirs (bin obj node_modules) from the body hash or the first real dotnet test or npm build invalidates the lock. Building the real fixture surfaced this immediately which is exactly why a real-run fixture step earns its keep beyond pure-parse structural evals.

## Learnings Capture
Phase: 5

- [5.1] [trigger:reusable-pattern] Deterministic test adapters must fail closed on any non-executed outcome. A JUnit or TRX parser that only denies explicit failures will green a skipped or auto-installed or aborted run. Require a passing allow-list (only all-genuinely-passed with at least one real testcase is green), require a committed lockfile with no-network install, and cross-check the tool exit code against a parsed pass. Also sanitize any contract-supplied id before using it in a filesystem path.
- [-] [trigger:plan-contradiction] REQ-14 acceptance criteria referenced fixtures/csharp + fixtures/typescript and Fixture-*-RealRun test markers, but the implemented convention (set by committed step 4.3) names fixtures by adapter: fixtures/netarchtest + fixtures/tsarch with Adapter-*-DetectsViolation tests. Reconciled REQ-14 to the implemented reality rather than renaming committed fixtures. Lesson: fixture/test naming in acceptance criteria drifted from the first implementing step; later steps sharing a REQ must reconcile the whole row.
- [-] [trigger:reusable-pattern] Security pattern for invoking an LLM CLI on untrusted-derived prompts: (1) deny-by-default tools (never --allow-all; --no-ask-user denies unapproved calls) so injection cannot exec on the host; (2) scope any credential to the CHILD process env only, never parent/receipts; (3) enforce a killable timeout via System.Diagnostics.Process, not a plain call; (4) treat MODEL OUTPUT as untrusted too — neutralize boundary sentinels + length-cap findings before persisting; (5) confine any file path read+sent-to-LLM under the repo root. GUID fences + strict-JSON guard input, but the tool-execution surface + output persistence are separate holes.

## Learnings Capture
Phase: 6

- [-] [trigger:reusable-pattern] Receipt/evidence verification false-green pattern: when a pure-parse verifier maps a recorded field through a gate, that field must be re-derived from the TRUSTED authoritative source (config/contract), not read from the receipt — else a hand-edit of the receipt copy steers the gate while the freshness hash (which binds only the config-derived fields) still matches. Cross-check receipt-vs-authoritative and gate on the derived value. Fields that are genuine run OUTPUTS (only in the receipt) cannot be re-derived; per a git+human-commit trust anchor they are reviewer-enforced (document the residual — do not add an unkeyed hash that an attacker with commit access can recompute, which is false security).
- [6.2] [trigger:plan-contradiction] Plan step 6.2 (and REQ-8 prose) literally said Sync-PluginScripts bundles Invoke-ArchTests.ps1 into ci/cip. Reconciled to Design B: the runner is bundled into its owning architecture-tests plugin (single canonical source scripts/skalary/), and /ci invokes THAT install via a gated bare reference (requires architecture-tests installed). Rationale: the runner's real-run closure (deterministic adapters, semantic-eval providers, lock authority) is architecture-tests-plugin-owned under plugins/architecture-tests/scripts/, so it cannot be bundled into ci without forking a second source of truth the drift gate cannot cover. Mirrors the 6.1 Get-ArchReviewReport gated-reference pattern. Confirmed by REQ-8 test Runner-CanonicalSourceBundled, which only asserts bundling into architecture-tests, never into ci.

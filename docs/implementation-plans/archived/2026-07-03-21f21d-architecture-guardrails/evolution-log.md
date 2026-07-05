# Evolution Log — Architecture Guardrails Plugin Family (21f21d)

DR-round chronology. Notable/recurring findings live in `capture.md` (script-managed);
this file is the round narrative.

## Round 1

- **Reviewers:** Opus · Codex · Gemini (`/dr`)
- **Findings:** 16 (4 Critical, 6 High, 5 Med, 1 Low)
- **Criticals:**
  1. `arch:` marker implied test execution, but `Test-Plan.ps1` is a pure parser → reframed to
     pure-parse a runner-produced receipt.
  2. Agents derive framework test code from untrusted contract text and adapters execute it →
     introduced lock-before-execute (only `locked`, human-reviewed bodies run).
  3. Toolchain-shelling runner would break the dependency-free `validate.ps1` / `npm test`
     (must run identically on the autopilot Linux container) → execution boundary: real runs
     opt-in, eval-harness-homed; gate stays structural.
  4. `locked`=block conflicted with skip-not-fail → explicit failure taxonomy
     (`pass`/`fail`/`skip-absent-toolchain`/`error`); only deterministic `fail` on `locked` blocks.
- **Other:** frameworks are libraries inside test projects (not CLIs); bundling blast radius of
  `PlanEvidence.psm1`/`PlanState.psm1`; two-index divergence; LLM untrusted-input hardening;
  harvested-content human-review gate; committed lockfiles + integrity hashes; content-hash
  (not mtimes) human-doc staleness; REQ-16 self-reference; cross-phase deps; dedicated LLM
  credential; phase-budget cap acknowledgment; sandbox-containment note.
- **User decisions:** keep two indexes (accept token cost for always-on arch context).
- **Outcome:** all 16 applied; re-validated exit 0.

## Round 2

- **Reviewers:** Opus · Codex · Gemini (`/dr`)
- **Findings:** 14 (2 Critical held — "shape right, mechanism missing" — 5 High, 6 Med, 1 minor)
- **Criticals (both closed by a single user call — anchor on git, not crypto):**
  1. Receipt was "tamper-evident" in name only (self-hash ≠ anti-forgery; a compromised runner
     signs its own forgery) → **trust anchor = git history + human commit**. Receipt proves
     integrity/freshness only; marker tests scoped to reject stale/malformed, not forged. No
     HMAC/signing infra (can't defend against the runner you already trust).
  2. `locked` was a self-writable field → **human-commit-bound promotion** (autopilot forbidden
     from `draft→locked`) + **body-level `lockedBodySha256`** re-checked before execution.
- **High:** explicit taxonomy × maturity matrix (`error`/`skip` on `locked` also block — closes
  the "turn fail into error and ship" hole); receipt freshness binds to tree/content hash so it
  survives its own commit; root `schemas/*.json` undeliverable via installer → ship as
  scaffold-on-init plugin assets; container backend is reserved/unimplemented → not built here,
  fixtures labelled non-contained (`--ignore-scripts` ≠ runtime containment); runner canonical
  source moved to `scripts/skalary/` so `Sync-PluginScripts.ps1` bundles it (single source).
- **Med:** unknown typed-marker prefix must fail loud, not silently drop (RISK-12, false-green
  under bundle skew); ship a `mock` provider so swappability is provable; canonical
  add/delete-sensitive content-hash; ADR lifecycle bounds the auto-loaded tier; Phase 4 is 8pts
  (not 7); dropped the overstated "auto-loaded arch content is fenced" claim (fence lives only in
  the LLM provider path) — containment rests on human-review gate + terse format.
- **User decisions:** (1) receipt = integrity/freshness, anchor on human commit; (2) full lock
  hardening (human commit + forbid autopilot + body-hash).
- **Outcome:** all applied; no new Criticals; re-validated exit 0. Plan finalized without round 3
  at user request.

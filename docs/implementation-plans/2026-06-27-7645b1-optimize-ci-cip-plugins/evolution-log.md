# Evolution Log — 7645b1 optimize-ci-cip-plugins

## Capture

- [dr] [step:4.1] [recurrence:new] Ledger durable line format (`plan-NNN`) is the real compatibility surface, not just `-Plan` validation — hash ids must co-edit `ConvertTo-LedgerRecord` + all dedup/sort keys or lines are silently dropped on canonical rewrite.
- [dr] [step:1.1] [recurrence:new] `Get-PlanMetadata` closes over script-scoped `$RepoRoot`; module extraction requires an explicit `-RepoRoot` parameter (not a verbatim move).
- [dr] [step:4.3] [recurrence:new] `Test-DependencyPlan006` hard-asserts literal tokens in the exact files Phase 5 slims; slimming must keep compatibility-anchor tokens.

## DR Round History

### Round 1

**Models:** Opus · Codex · Gemini (via `dr` orchestrator)

**Findings:** 18 total — 3 Critical, 4 High, 9 Medium, 2 Low.

**Critical:**
- [1] Hash plan-ids break the durable ledger parser (`ConvertTo-LedgerRecord` `\d{3}` regex) → silent line loss on canonical rewrite.
- [2] `Get-PlanMetadata` "verbatim" move infeasible — closes over script-scoped `$RepoRoot`; needs explicit `-RepoRoot`.
- [3] Phase-5 asset slimming drops literal tokens the hard `Test-DependencyPlan006` preflight asserts.

**High:** [4] dedup/idempotence key fork across schemes; [5] no collision handling for 24-bit id + weak prefix margin; [6] ledger sanitizer would mangle capture schema / `New-Plan` slug needs path-confinement; [7] presence-only `contains:` markers pass through regressions.

**Medium/Low:** [8] step 2.2 before its `[after:2.3]` dep; [9] collapsing ci Steps 2&4 risks dropping agent judgment + soft anti-drift; [10] `Build-EvidenceReceipt` under-specified vs existing receipt grammar; [11] scope split recommendation (naming scheme orthogonal); [12] autopilot legacy `NNN` assumptions + weak evidence; [13] legacy-numeric `Resolve-Plan` input unspecified; [14] `Repair-Plans` lacks safety contract; [15] cap trim direction + placeholder preservation; [16] design-note updates deferred vs same-change protocol; [17] manifest registration evidence; [18] dep-006 routing intent.

**Decisions:**
- [11] Scope: user chose to KEEP combined and apply all hardening (not split).
- Applied [1]–[10], [12]–[18]: promoted ledger compat to dedicated REQ-12 with round-trip tests; `-RepoRoot` signature change (REQ-4, dropped "verbatim"); dep-006 reconciliation REQ-13; canonical-written-id decision; collision policy in `New-PlanId` (REQ-1); capture-preserving sanitization + slug confinement (REQ-8, REQ-2); shared receipt grammar (REQ-10); reordered 2.2/2.3 (Get-NextStep now 2.2); explicit resume/reset/`@human` retention + reconcile gate (REQ-14); autopilot dual-format (REQ-15); explicit legacy-numeric resolution (REQ-3); `Repair-Plans` safety contract (REQ-11); cap trim direction + placeholder preservation (REQ-8); per-phase design-note updates (REQ-17, steps 1.5/4.4/6.2); manifest-coverage test (REQ-16).

**Deferred:** none.

**Result:** plan grew from 13 → 17 REQs, 6 → 7 risks; re-validated at Draft stage.

### Round 2

**Models:** Opus · Codex · Gemini (via `dr` orchestrator), given round-1 evolution log as context.

**Convergence:** all three confirmed the round-1 hardening is internally consistent, the ledger/canonical-id scheme coherent, the all-digit-hash vs legacy-number disambiguation sound, and the `[after:]` dependency graph acyclic and forward-only.

**Findings:** 7 (2 High, 2 Medium, 3 Low).

- [1] High — space-containing `test:` ids truncate at the first whitespace in `Test-Plan.ps1` (regex `test:[^\s\`|·]+`, ~L236); prose-file `test:` markers can't assert runtime behavior. **Verified against the parser.**
- [2] High — REQ-8 capture-preserving sanitization is only coherent if schema tokens come from typed params and only the free-text body is sanitized.
- [3] Medium — shared receipt grammar has two emitters (script + autopilot prose) with no cross-parity test.
- [4] Medium — `Build-EvidenceReceipt` input contract (verifier-output shape, which marker types) undefined.
- [5] Low — REQ-12 edit-site list omitted the `^\d{3}$` `[ValidatePattern]`.
- [6] Low — `New-PlanId` SHA(slug+timestamp+salt) is ceremony given non-reproducible ids; plain random 6-hex is equivalent.
- [7] Low — step 5.3 lacked explicit `[after: 4.2]` for its `depends-on:` write.

**Decisions:** Applied all 7.
- [1] Adopted a no-space `test:`-id convention (new Decision); converted **every** `test:` marker to single-token ids; reframed REQ-14/15 prose evidence as `Select-String`-backed token guards + `review` markers; updated RISK-7.
- [2] REQ-8 + step 3.1 now state typed-param token emission + free-text-only sanitization with concrete escaping.
- [3] New "single golden receipt spec" decision; both emitters tested against the same golden-line fixture (autopilot preferably quotes script output).
- [4] Step 3.4 + REQ-10 define the consumed verifier-object shape and covered marker types.
- [5] REQ-12 + step 4.1 now name the `[ValidatePattern]` as an edit site.
- [6] `New-PlanId` simplified to 6 crypto-random hex (REQ-1 + Decisions).
- [7] Added `[after: 4.2]` to step 5.3.

**Deferred:** none.

**Result:** no Critical/High structural changes — refinements only. Plan stays 17 REQs / 7 risks; re-validated at Draft stage. No further round needed unless reviewer requests.

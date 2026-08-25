# Evolution Log - 583308

## Round 1

**Verdict:** RETURNED

**Issues found:** Comparable base/candidate size inputs were undefined; the workflow was outside shared CI hardening; workflow-level path filters could omit a required check; two named tests lacked ordinary-suite producers; installed payload sync occurred after consumption; Debian suite/origin and full package assertions were unspecified; workflow build context and smoke routing were ambiguous; floating inputs were described as reproducible; trigger paths did not close over build inputs; advisory size behavior was weakly evidenced; runtime network/client capability lacked explicit acceptance; root-layer/alias ownership and shared workflow-security enforcement were incomplete.

**Issues fixed:** Defined one-daemon/event-base/shared-build-arg comparison; changed to an always-triggered workflow with conditional image work and an always-reported final gate; made ordinary Pester the sole typed-test host; synchronized every payload mutation in its owning step; added a closed package/assertion and capability decision; bound workflow context to the installed skill; copied a kebab-case smoke script into the image before `USER autopilot`; added a deterministic advisory-size reporter; extended shared CI security/gate tests to all workflows; closed trigger paths over canonical, installed, and Dockerfile `COPY` inputs; documented floating-input limits, post-merge rollback, and alias ownership; corrected the stale design-note path in the owning step.

**Issues deferred:** None.

## Round 3

**Verdict:** RETURNED

**Issues found:** Detection relevance was undefined for unusable bases; failures and timeouts could exit before durable evidence; baseline equality included unrelated bootstrap packages; workflow activation was split across commits; one CI evidence producer did not exist; PRs could execute a candidate-controlled runner on the host; runtime smoke lacked review evidence; step 1.1 left payload drift; advisory base work could consume candidate budget; the third CI host was not explicitly registered in the gate design note.

**Issues fixed:** Forced relevance for unusable detection bases; required bounded terminal receipts from `finally` plus `if: always()` artifact upload; separated named bootstrap packages from manifest-owned additional tools; merged complete workflow activation into one step; explicitly created `test:Ci.WorkflowSecurityContract`; executed PR control logic from a credential-free base-SHA checkout; added `review:cr` to runtime baseline evidence; synchronized manifest payload in step 1.1; budgeted candidate first at 25 minutes and optional base at 10 residual minutes with candidate-only base failure states; required `ci-gates.design.md` registration of the third host and its gate rows.

**Issues deferred:** None. The plan validates cleanly after all three rounds. Per the default review limit, no fourth round was run.

## Round 2

**Verdict:** RETURNED

**Issues found:** Base-unavailable histories contradicted advisory comparison; event candidate identity and hostile-path handling were undefined; detector failures could false-green; Git cleanliness did not prove payload provenance; image output was unbounded; candidate execution lacked explicit secret/socket isolation; package-to-smoke closure was not falsifiable; evidence names drifted from producers; required-check recovery and CI host modeling were absent; local replay had no shared executable; build cost was unbounded; workflow rollout crossed a false-green intermediate state; reporter ownership and sync were unnecessary; traceability drifted; evidence had no durable sink; path sets had multiple authorities; Debian origins were observed but not enforced.

**Issues fixed:** Added `toolchain.tsv` as the sole case/package owner with stable smoke IDs and red mutations; added one repository runner for event identity, NUL-safe detection, path derivation, manifest parity, candidate-only comparison states, bounded process execution, smoke schema/encoding, size reporting, receipts, and local/CI replay; defined PR-merge and push SHA matrices; made candidate validation always blocking and base comparison advisory; enforced Debian source hosts before third-party repositories; specified secretless/socketless candidate execution; extended CI architecture/parser/inventory ownership; made workflow activation atomic; defined 35/45-minute budgets and local BuildKit reuse; retained deterministic provenance/receipt artifacts for 14 days; added conditional image-size exception and required-check recovery records; removed the CI-only reporter from installed payload; neutralized reviewer-directed layout prose; raised the phase cap to nine to preserve atomic trust-boundary steps.

**Issues deferred:** None.

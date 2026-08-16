Phase 3 Crosscheck:
✓ REQ-1 — test:AutopilotContainer.ToolchainContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-1 — review:cr — passed: PR #5 review and three follow-up review rounds; the third round's 3 Critical and 15 High findings are closed at 714556e — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-2 — test:AutopilotContainer.ToolchainContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-2 — review:cr — passed: no open Critical or High findings at 714556e — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — test:AutopilotContainer.ToolchainContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — test:AutopilotContainer.GateRunnerContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — file:docs/implementation-plans/2026-08-10-583308-autopilot-container-toolchain/assets/measurements/container-toolchain-receipt.json#contains:"candidateSha":"714556e77fab0a846c85e983a93290e4bcfd4590" — passed: local Measure of 714556e against the genuine pre-toolchain base c961786 (origin/main); candidate-only/base-context-absent, candidate 2856022233 bytes, smoke 21/21 pass with an empty reason set, attested origins within the allowlist — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — file:docs/implementation-plans/2026-08-10-583308-autopilot-container-toolchain/assets/measurements/image-growth.json#contains:"deltaBytes":336271128 — passed: two direct builds of 714556e and c961786 measure 320.69 MiB of growth, which exceeds the 250 MiB advisory threshold and is recorded rather than hidden — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — review:cr — passed: no open Critical or High findings at 714556e — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:AutopilotContainer.GateRunnerContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:Ci.WorkflowSecurityContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:Ci.ContainerGateIsPostMerge — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:Ci.WorkflowYamlParserIsStrict — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:CiGates.InventoryMatchesWorkflow — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — review:cr — passed: no open Critical or High findings at 714556e — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — test:AutopilotContainer.ToolchainContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — test:AutopilotContainer.GateRunnerContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — test:CiGates.InventoryMatchesWorkflow — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — file:docs/implementation-plans/2026-08-10-583308-autopilot-container-toolchain/assets/measurements/container-toolchain-provenance.json#contains:"parity":{"valid":true — passed: canonical and installed digests equal for all five payload files at 714556e — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — review:cr — passed: no open Critical or High findings at 714556e — 714556e77fab0a846c85e983a93290e4bcfd4590

Notes on what this evidence does and does not claim:

- The commit named throughout is 714556e, the last commit containing implementation. This file
  and the measurement artifacts are committed on top of it, so no commit can both contain the
  receipt and be the commit the receipt measures. The prior receipt named 96cbd12, a revision
  that predated the hardening it was offered as evidence for.
- The gate result is `candidate-only`, not `comparable`, and that is the correct result rather
  than a degraded one. The base c961786 (`origin/main`) genuinely predates the installed Docker
  build context, so `Get-ContainerGateContext` cannot map the payload for it. The previous
  receipt obtained `comparable` by comparing against b71e7dd — a commit that already contained
  `devcontainer/toolchain.tsv` — which is why it reported a 31402-byte delta for a change that
  actually adds 320 MiB. Choosing a base that already contains the thing being measured does
  not measure it.
- The real growth is therefore recorded separately in `image-growth.json`, measured by building
  both Dockerfiles directly, with the method stated in the artifact. It exceeds the 250 MiB
  advisory threshold. That is advisory by design: the gate does not fail, but the cost is
  visible and is not to be discovered later.
- The image gate itself is post-merge. It reports on pushes to `main` and cannot block a pull
  request; see the decisions log and the architecture design note for why a `pull_request`
  definition cannot enforce a boundary against the candidate that wrote it.

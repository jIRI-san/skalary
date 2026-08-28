Phase 3 Crosscheck:
✓ REQ-1 — test:AutopilotContainer.ToolchainContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-1 — review:cr — passed: PR #5 review and four follow-up review rounds; the third round's 3 Critical and 15 High findings are closed at 714556e, and the fourth round's 5 Critical and 4 High findings are closed in the addendum below — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-2 — test:AutopilotContainer.ToolchainContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-2 — review:cr — passed: no open Critical or High findings; see the fourth-round addendum below — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — test:AutopilotContainer.ToolchainContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — test:AutopilotContainer.GateRunnerContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — file:docs/implementation-plans/2026-08-10-583308-autopilot-container-toolchain/assets/measurements/container-toolchain-receipt.json#contains:"candidateSha":"714556e77fab0a846c85e983a93290e4bcfd4590" — passed: local Measure of 714556e against the genuine pre-toolchain base c961786 (origin/main); candidate-only/base-context-absent, candidate 2856022233 bytes, smoke 21/21 pass with an empty reason set, attested origins within the allowlist — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — file:docs/implementation-plans/2026-08-10-583308-autopilot-container-toolchain/assets/measurements/image-growth.json#contains:"deltaBytes":336271128 — passed: two direct builds of 714556e and c961786 measure 320.69 MiB of growth, which exceeds the 250 MiB advisory threshold and is recorded rather than hidden — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-3 — review:cr — passed: no open Critical or High findings; see the fourth-round addendum below — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:AutopilotContainer.GateRunnerContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:Ci.WorkflowSecurityContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:Ci.ContainerGateIsPostMerge — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:Ci.WorkflowYamlParserIsStrict — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — test:CiGates.InventoryMatchesWorkflow — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-4 — review:cr — passed: no open Critical or High findings; see the fourth-round addendum below — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — test:AutopilotContainer.ToolchainContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — test:AutopilotContainer.GateRunnerContract — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — test:CiGates.InventoryMatchesWorkflow — passed — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — file:docs/implementation-plans/2026-08-10-583308-autopilot-container-toolchain/assets/measurements/container-toolchain-provenance.json#contains:"parity":{"valid":true — passed: canonical and installed digests equal for all five payload files at 714556e — 714556e77fab0a846c85e983a93290e4bcfd4590
✓ REQ-5 — review:cr — passed: no open Critical or High findings; see the fourth-round addendum below — 714556e77fab0a846c85e983a93290e4bcfd4590

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

## Fourth review round (reviewed at 7a13252)

A fourth `@cr` round against 7a13252 returned 5 Critical, 4 High, 6 Medium and 5 Low findings. Every
Critical and High is closed, along with the Mediums and Lows coupled to them. The prior `review:cr`
lines above have been corrected: they claimed no open Critical or High findings at 714556e, and that
claim did not survive the round.

What the findings were, and what closed them:

- **A red post-merge gate had no notification path and no runbook** (Critical). A `notify` job now
  opens one repository issue per failing commit, and the architecture note carries "The gate is red on
  `main`" — read the receipt outcome, decide whether `main` ships a broken image, revert by the SHA the
  receipt names, re-run before believing an infrastructure story, close the issue only against a green
  run. The job holds `issues: write` and nothing else, with no checkout and no gate code.
- **Blocking `unexpected-error` throws discarded the output explaining them** (Critical). Base-identity,
  platform-mismatch and daemon-identity failures now write the stage and bounded process tail to the
  diagnostics log before throwing, and the top-level handler records the message and stack trace.
- **The terminal receipt named no commit** (Critical). `VerifyResult` now carries base/candidate SHAs,
  architecture, the detector's candidate-only reason, and a relevant-path count into `identities`,
  `comparison` and `diagnostic`; the detector uploads its own receipt so the path names stay
  recoverable, since the step-output alphabet cannot carry a `/`.
- **Two of the ten smoke reasons could never reach a receipt** (Critical). A degraded payload
  (`state=fail` with a closed reason) is accepted with empty digests and no cases, so `encoder-failed`
  and `output-oversize` survive instead of collapsing into `candidate-output-invalid`. Nothing is
  relaxed for `state=pass`.
- **Base inspection failure blocked the candidate** (Critical). A base image whose size cannot be read
  is now candidate-only evidence — `base-build-failed`, exit 0 — like every other base-side failure.
- **Live APT attestation omitted linked trees and some URI schemes** (High). Any reparse point at or
  under the root fails the read closed, and authority-less origins (`file:`, `cdrom:`, `mirror+file:`)
  are reported as `<scheme>:opaque` so they fail the allowlist rather than passing as no host at all.
- **The concurrency group could not prove every merged commit gets a verdict** (High). The group is
  keyed on `github.sha`, so no merged commit can be superseded while another is in flight.
- **Step 4.1 demanded a workflow run that the post-merge model makes impossible** (High). Approval now
  requires local evidence; the `main`-push run is an explicit follow-up step, not a precondition.
- **The `Detect -StepOutputPath` wire had no behavioural test** (High). Covered: emitted names and
  values in all three relevance cases, append-not-truncate across two invocations, and the encoder's
  refusal of an unsafe name, an over-long value, and a newline.

Re-validated at this commit: `npm test` — 795 passed, 0 failed, 8 skipped, including
`test:AutopilotContainer.ToolchainContract`, `test:AutopilotContainer.GateRunnerContract`,
`test:Ci.WorkflowSecurityContract`, `test:Ci.ContainerGateIsPostMerge`, and
`test:CiGates.InventoryMatchesWorkflow`.

No Docker image was rebuilt, because no image input changed: this round touched the host-side runner,
the workflow, the tests, and the notes. The measurement artifacts above still describe 714556e, whose
Dockerfile, manifest and smoke script are byte-identical here.

One finding is deliberately left open and is recorded rather than closed silently: the two in-image
apt recorders disagree on deb822 `Enabled:`. The asymmetry is safe in the direction it exists — the
*enforced* final capture is the over-inclusive one, so a disabled hostile origin is still caught —
and it is now documented and pinned by `test:AutopilotContainer.ToolchainContract` so it cannot
reverse unnoticed. Making the baseline recorder match would edit the Dockerfile, which no test in this
repository can validate without a 20-minute network image build, so it is not changed on the strength
of an argument alone.

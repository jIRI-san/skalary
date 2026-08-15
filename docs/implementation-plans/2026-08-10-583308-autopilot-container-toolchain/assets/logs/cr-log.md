## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:High] APT source validation walked regular files under /etc/apt, missing symlinked or reconfigured source paths that apt-get can consume.
- [1.1] [src:code-review] [sev:High] Rubber-duck: recursive apt dependency candidates included uninstalled alternatives, so dpkg-query could abort provenance capture under pipefail.
- [1.1] [src:code-review] [sev:Low] Rubber-duck: deb822 Enabled parsing recognized no but not false or 0, misclassifying disabled sources as active.
- [1.1] [src:code-review] [sev:High] APT generic path checks did not reject Binary::apt-get::Dir overrides, allowing apt-get to consume a different source set.
- [1.2] [src:code-review] [sev:Low] Rubber-duck: an unreadable or empty runtime manifest could emit state pass with an empty cases array.
- [1.3] [src:code-review] [sev:Med] Contract test checked install fragments but did not reject extra packages appended to the manifest-derived array.
- [1.3] [src:code-review] [sev:Med] Injected-origin fixture used a test-side scanner and did not prove the Dockerfile fallback exited nonzero or ordered validation before update.
- [1.3] [src:code-review] [sev:Med] Smoke COPY index lacked a nonnegative assertion, so a missing COPY still compared less than USER.
- [1.3] [src:code-review] [sev:Med] Closed-schema assertions parsed only fallback JSON, allowing fields to be added to primary output.
- [1.3] [src:code-review] [sev:Low] Rubber-duck: the documented literal # Non-root user extension anchor was not asserted, so launcher extension insertion could silently stop.
- [1.3] [src:code-review] [sev:Low] Rubber-duck: origin red mutation could pass through exact-token failure instead of proving the parsed fallback rejected unknown hosts.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck: missing provenance files did not force smoke state fail, and the remaining-input digest still looked valid.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck re-review: nonempty directories passed provenance prerequisites, and failed child hashes could still produce a valid aggregate digest.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck final review: jq encoder failures could leave blank stdout while overall state remained pass.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck review: intermediate jq failures did not force the static failure JSON, despite setting aggregate state fail.
- [1.2] [src:code-review] [sev:Med] Phase crosscheck review: final state evaluation overwrote printf failure, allowing exit zero when stdout could not be written.

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:High] Large Git diff output could be truncated on a record boundary and falsely classify an owned-path change as irrelevant.
- [2.1] [src:code-review] [sev:High] Process output was buffered without a memory bound and sanitized before smoke validation, allowing oversized or malformed raw output to pass.
- [2.1] [src:code-review] [sev:High] Timing out the Docker CLI did not stop its daemon-owned smoke container.
- [2.1] [src:code-review] [sev:High] Physical-line COPY parsing omitted valid continued Dockerfile sources from path closure.
- [2.1] [src:code-review] [sev:Med] The provenance digest excluded the newline written to the artifact and could not verify uploaded bytes.
- [2.1] [src:code-review] [sev:High] A pass top-level smoke state could conceal failed individual cases.
- [2.1] [src:code-review] [sev:High] Recorded base-image identity was not tied to the Dockerfile FROM source and inspect failures were ignored.
- [2.1] [src:code-review] [sev:Med] Culture-sensitive sorting made path and provenance ordering locale-dependent.
- [2.1] [src:code-review] [sev:Low] Rubber-duck: top-level default RunnerArchitecture was omitted by PSBoundParameters forwarding, leaving architecture empty unless explicitly passed.
- [2.1] [src:code-review] [sev:Med] Re-review: smoke validation accepted null or non-string origin and version fields in a passing payload.
- [2.1] [src:code-review] [sev:Med] Re-review: linux/amd64 was passed to builds but not pinned for pull, FROM platform, or inspected image identity.
- [2.1] [src:code-review] [sev:Med] Re-review: case-sensitive COPY parsing omitted valid lowercase Dockerfile instructions from path closure.
- [2.1] [src:code-review] [sev:Med] Re-review: residual runner time used Max one and uncapped image inspection, allowing the 35-minute deadline to be exceeded.
- [2.1] [src:code-review] [sev:High] Final review: local Dockerfile ADD inputs were neither included in path closure nor rejected.
- [2.1] [src:code-review] [sev:Med] Final review: candidate path-set derivation ran before unusable-base classification and could throw instead of forcing relevance.
- [2.1] [src:code-review] [sev:Med] Final review: receipt candidate and base timing fields omitted parity, pull, inspection, version, and size work.
- [2.1] [src:code-review] [sev:Med] Final review: floating Copilot package specifications such as latest were accepted instead of a concrete shared version.
- [2.1] [src:code-review] [sev:High] Closeout review: plugin destinations were not required to match Docker build-context COPY source paths, allowing parity to check different bytes than the build consumed.
- [2.1] [src:code-review] [sev:Med] Closeout review: payload hashing accepted symlinked files and unbounded file sizes outside process timeouts.
- [2.1] [src:code-review] [sev:Med] Closeout review: nonzero smoke output returned before JSON validation, losing valid failure summaries and misclassifying malformed output.
- [2.2] [src:code-review] [sev:Med] Detector exported only relevance, so an image-job base checkout retry could erase the detector candidate-only reason and perform a forbidden comparison.
- [2.2] [src:code-review] [sev:Med] Docker context and Dockerfile-specific ignore paths were absent from runner path closure and could change image inputs while the gate was skipped.

## CR Capture
Phase: 3

- [3.1] [src:code-review] [sev:Low] No significant issues found in the complete phase 3 uncommitted change set.
- [3.1] [src:code-review] [sev:Low] Rubber-duck: final timing assignment retained the same Int32 Math.Max seed pattern; changed candidate/base timing clamps to Int64 seeds.
- [3.1] [src:code-review] [sev:Critical] PR review: a passing top-level smoke state hid failing individual cases from the receipt and the job summary; failed case ids are now carried in smoke.failedCases and named in both.
- [3.1] [src:code-review] [sev:Critical] PR review: image provenance was trusted as the image reported it; the host now attests it out of a --network none container with docker cp and compares the claim against what it read.
- [3.1] [src:code-review] [sev:Critical] PR review: head-only capture truncation dropped the tail where build and smoke failures print, so failures were diagnosed from the wrong bytes; capture is head+tail with an explicit truncation marker and a diagnostics artifact.
- [3.1] [src:code-review] [sev:Critical] PR review: root-trusted network fetches of the Microsoft and GitHub CLI debs and the Docker apt key were unverified downloads; each is now pinned by sha256 or key fingerprint with curl -f.
- [3.1] [src:code-review] [sev:Critical] PR review: the workflow required a runner that a first pull request base cannot contain, making the required check unpassable without promoting candidate code; control-plane resolution now reports a closed non-blocking bootstrap instead.
- [3.1] [src:code-review] [sev:Critical] PR review: no test drove Measure orchestration at all, so every pass/fail decision was unverified; a Docker-free table now reaches every terminal outcome.
- [3.1] [src:code-review] [sev:Critical] PR review: the approved toolchain contract lived in the plan folder the archive step moves, which would have silently disabled the test enforcing it; it now lives in docs/design-notes/architecture.
- [3.1] [src:code-review] [sev:High] PR review: parity failures reported a reason without the differing path, so a drift verdict could not be acted on; parity now returns a bounded detail.
- [3.1] [src:code-review] [sev:High] PR review: the job summary omitted sizes, delta, threshold and failing cases, forcing a reviewer to download the artifact to learn the result.
- [3.1] [src:code-review] [sev:High] PR review: the timeout test asserted on fixed sleeps and was a race; it now waits on a started marker and heartbeat stability.
- [3.1] [src:code-review] [sev:High] PR review: plan evidence and measurement receipts were stale relative to the implementation they claim to prove.
- [3.1] [src:code-review] [sev:High] PR review: detector relevance had no test over real git history, so the path set could stop matching changed paths silently.
- [3.1] [src:code-review] [sev:Med] PR review: workflow assertions split text on - name:, which cannot distinguish a step from that text inside a run block; a strict block-YAML subset parser now owns structure and throws on what it cannot model.
- [3.1] [src:code-review] [sev:Low] PR review: Invoke-GateProcess read ExitCode while the process was still running, which throws on some hosts; the exit code is read only after exit.
- [3.1] [src:code-review] [sev:Low] PR review: measurement re-derived relevance and could skip blocking work the truth table still expected; the detector verdict is now passed in and contradiction resolves toward the blocking path.
- [3.1] [src:code-review] [sev:Low] PR review: provenance was captured before later root layers, so a layer added below the record escaped it; capture moved to a final root layer.
- [3.1] [src:code-review] [sev:Med] Docker key was dearmored whole and only checked for presence of the pinned fingerprint; keyring now built by exporting exactly that key and asserting one primary.
- [3.1] [src:code-review] [sev:Med] Attestation read only candidate-authored provenance and accepted a zero-case manifest; now reads live /etc/apt, requires a non-empty case set, and the note records what attestation cannot prove.
- [3.1] [src:code-review] [sev:Med] Gate bootstrap step ignored needs.detector.result, so a failed detector produced a green required gate; it now fails unless the detector succeeded.

## CR Capture
Phase: 1

- [1.1] [src:code-review] [sev:Med] New-layout summary/full byte goldens were missing; expectation-only fixtures could not pin rendered bytes or bounds.
- [1.1] [src:code-review] [sev:Med] Maximum-envelope fixture created 256 merged groups, exceeding the schema-owned 128-group semantic limit.
- [1.1] [src:code-review] [sev:Med] Manifest artifact-name schema allowed 100 characters while the shared vocabulary declared a 96-character maximum.
- [1.1] [src:code-review] [sev:Med] Reference merge keys were computed before NFC normalization, splitting canonically equivalent findings.
- [1.1] [src:code-review] [sev:Med] Case-insensitive PowerShell roster membership could falsely elevate findings from case-distinct declared models.
- [1.1] [src:code-review] [sev:Med] Terminal-status schema allowed degraded exit 5 in Freeze mode even though degradation is Publish-only.
- [1.1] [src:code-review] [sev:Med] Maximum-envelope fixture omitted maximum diagnostics and therefore did not exercise the largest semantically valid near-cap record mix.
- [1.1] [src:code-review] [sev:Med] Reference raw-record lookup used a case-insensitive delimiter key that could overwrite distinct legal findings.
- [1.1] [src:code-review] [sev:Med] Schema capability preflight could ignore unlisted assertion keywords and count validator exceptions as successful negative probes.
- [1.2] [src:code-review] [sev:Critical] Canonical object keys use culture-sensitive Sort-Object, producing different digests across locales.
- [1.2] [src:code-review] [sev:High] Malformed frozen plans or manifests escape the bounded exit contract with process exit 1 and no status object.
- [1.2] [src:code-review] [sev:High] Semantically duplicate raw findings collide in the renderer dictionary and crash publication.
- [1.2] [src:code-review] [sev:High] Oversized invalid run identifiers can make terminal-status shrinking loop forever.
- [1.2] [src:code-review] [sev:High] Admission exit 3 leaves no terminal marker, allowing lossy same-UUID republish.
- [1.2] [src:code-review] [sev:High] Over-2-MiB canonical envelopes reach manifest generation and return retryable exit 4 instead of terminal admission.
- [1.2] [src:code-review] [sev:Med] Invalid run-id terminal statuses violate their own schema.
- [1.2] [src:code-review] [sev:Med] Lock deletion, pre-lock state checks, and post-unlock global staging cleanup permit concurrent authority overwrite.
- [1.2] [src:code-review] [sev:Med] ListIncomplete bypasses PlanDir confinement and inventory validation.
- [1.2] [src:code-review] [sev:Med] Freeze persists unscanned scope text into committed plan artifacts before Publish can reject a credential shape.
- [1.2] [src:code-review] [sev:High] Triage: root/bundled script drift remains intentionally deferred to step 2.1, which distributes the module, schemas, reader and cleanup atomically; syncing wrappers alone would install broken CLIs.
- [1.2] [src:code-review] [sev:Med] Pre-scan Publish exits leave untrusted result input on disk instead of securely destroying it.
- [1.2] [src:code-review] [sev:Med] Verifying reader omits reparse-point confinement on concrete manifest and artifact reads.
- [1.2] [src:code-review] [sev:Low] Exported terminal-status emitter permits schema-invalid rejected-id combinations outside current CLI paths.
- [1.2] [src:note] [sev:High] Rubber Duck: semantic validation does not enforce the schema-owned 128 merged-finding cap.
- [1.2] [src:note] [sev:High] Rubber Duck: canonicalization preserves CRLF and integral floating representations, so equivalent semantic input can hash differently.
- [1.2] [src:note] [sev:High] Rubber Duck: control characters in schema-valid model names corrupt delimiter-packed attribution and unanimity.
- [1.2] [src:note] [sev:Med] Rubber Duck: reader does not independently enforce per-role summary/full byte bounds and canonical text encoding.
- [1.2] [src:note] [sev:Med] Rubber Duck: Freeze can write a plan generation into corrupted published state when the manifest remains but the prior plan file is missing.
- [1.2] [src:code-review] [sev:High] Deleting the content-addressed frozen plan resets state to new and permits a different plan under the same UUID; persist independent frozen-state evidence and fail closed.
- [1.2] [src:code-review] [sev:Med] Publish compares frozen scope and task fields case-insensitively; bind canonical frozen fields with ordinal equality.
- [1.2] [src:code-review] [sev:Low] Rubber-duck triage: Publish described a missing generation under committed frozen state as Publish-before-Freeze; distinguish corrupted frozen state in the bounded diagnostic.

## CR Capture
Phase: 2

- [2.1] [src:code-review] [sev:High] Installed engine selected an unrelated parent schemas/review directory before bundled sidecars; restrict schema resolution to recognized skill bundle layouts.
- [2.1] [src:code-review] [sev:Low] Schema-root detection keyed on a parent folder named skills and could misclassify a canonical checkout; compare the module path to the canonical source layout instead.
- [2.1] [src:code-review] [sev:Low] Recursive stale cleanup could remove nested PowerShell files outside the sidecar grammar; recurse only under the managed schemas/review subtree.
- [2.2] [src:code-review] [sev:High] Installed plan runs preferred repository scripts/skalary/PlanState.psm1 over the bundled module, allowing repository-controlled code execution through the approved writer.
- [2.2] [src:code-review] [sev:Med] Set-ScriptApproval recognized object-valued rules only on one line, so formatted JSONC rules could duplicate on add and survive remove.
- [2.2] [src:code-review] [sev:Med] The corpus regenerator still called the retired -Finding API after writing partial fixtures; move historical bytes to the archived authority and keep v1 rendering in the golden generator.
- [2.2] [src:code-review] [sev:Med] Appending approvals after a final multiline object without a comma could produce invalid JSONC; normalize the separator from parsed entry spans.

## CR Capture
Phase: 3

- [3.1] [src:code-review] [sev:Med] Installed-consumer child processes inherited /work, so a current-directory fallback could bypass poisoned fixture roots.
- [3.1] [src:code-review] [sev:Med] Terminal-status uniqueness selected the final JSON line before counting, allowing duplicate stdout objects to false-green.
- [3.1] [src:code-review] [sev:Med] Ordinary evidence discovery scanned raw text, allowing comments or skipped cases to satisfy required test markers.
- [3.1] [src:code-review] [sev:Med] Ordering evals compared IndexOf results without proving headings existed, so a missing freeze heading could pass as position -1.
- [3.1] [src:code-review] [sev:Med] Structural eval discovery counted skipped It cases, so a stable ID could remain present while its invariant asserted nothing.
- [3.1] [src:code-review] [sev:Low] ConsumerInstallInvocation had two ordinary test owners after adding the full matrix, weakening one-to-one evidence traceability.
- [3.1] [src:code-review] [sev:Low] The repository schema poison was only a regression tripwire; installed-closure success is the actual no-fallback proof.
- [3.1] [src:code-review] [sev:Low] No-new-dependency evidence checked source manifests but not the copied isolated consumer closure.
- [3.1] [src:code-review] [sev:High] Installed-consumer fixtures copied a scripts wildcard instead of executing plugin.json source-to-destination mappings.
- [3.1] [src:code-review] [sev:High] The consumer matrix spawned excessive PowerShell children in the budgeted ordinary suite; module-backed cases now keep only CLI-boundary subprocesses.
- [3.1] [src:code-review] [sev:Med] CR and DR structural assertion bodies were duplicated; stable plugin-local IDs now call one EvalCommon invariant implementation.
- [3.1] [src:code-review] [sev:Med] Evidence discovery hard-coded the plan asset path and hand-parsed test names; it now resolves c21cdc through PlanState and consumes the canonical Pester inventory.
- [3.1] [src:code-review] [sev:Med] Review-reporting design-note globs omitted the CR/DR eval and consumer-test surfaces the note now governs.
- [3.1] [src:code-review] [sev:Med] The installed secret-rejection case discarded output and did not prove credential bytes were absent from terminal streams and residual artifacts.
- [3.1] [src:code-review] [sev:Med] The design note contradicted current state by describing the retired object API as active.
- [3.1] [src:code-review] [sev:Med] Tier-1 eval execution is intentionally separate from npm test under the eval-gate contract; docs now distinguish discovery, eval execution, and live review evidence.
- [3.1] [src:code-review] [sev:Med] The secret residual scan omitted hidden engine files because Get-ChildItem lacked -Force.
- [3.1] [src:code-review] [sev:Med] Evidence ownership used substring matching, so a longer test ID could satisfy a missing required marker.
- [3.1] [src:code-review] [sev:Med] Renderer-owned Markdown checks omitted the collation guide, allowing hand-built layout in the primary lifecycle document.
- [3.1] [src:code-review] [sev:High] The installed lifecycle still launched about thirty PowerShell children; repeated exits now run through the already imported installed module with a minimal CLI boundary set.
- [3.1] [src:code-review] [sev:Med] Retry cases restaged result input after exit 4, masking incorrect input deletion; retry now uses byte-identical preserved input without restaging.
- [3.1] [src:code-review] [sev:Med] Writer-scope evals positively matched the absolute rule but did not reject an appended broader write permission.
- [3.1] [src:code-review] [sev:Med] Review-reporting scope omitted the shared EvalCommon implementation and orchestrator agent write boundary.
- [3.1] [src:code-review] [sev:Med] Ordinary evidence ownership could accept a skipped owner; the gate now requires an active literal It case in a discovered owner file.
- [3.1] [src:code-review] [sev:Med] Stable eval IDs could be attached to empty parameterized cases; structural IDs now forbid ForEach and TestCases.
- [3.1] [src:code-review] [sev:Med] Consumer CLI assertions captured diagnostics but did not include them in failures; a shared exit assertion now reports bounded status and stderr.
- [3.1] [src:code-review] [sev:Med] The installed matrix duplicated a caller marker across a separate layout case; renderer ownership was consolidated under the caller lifecycle case.
- [3.1] [src:code-review] [sev:Med] Strict-mode execution exposed optional message and diagnostics fields accessed unconditionally in shared consumer assertions.
- [3.1] [src:code-review] [sev:Med] A single caller surface unwrapped to FileInfo under strict mode, so Count access failed; surface cardinality now wraps explicitly.
- [3.1] [src:code-review] [sev:Med] Evidence token extraction lacked an end boundary and could accept a longer suffixed test ID.
- [3.1] [src:code-review] [sev:Med] Writer-scope rejection recognized too few permission phrasings; any non-prohibitive write clause targeting forbidden surfaces now fails.
- [3.1] [src:code-review] [sev:High] Manifest-driven fixture installation joined source and destination strings without canonical confinement, so a traversal mapping could escape the plugin or fixture root.
- [3.2] [src:code-review] [sev:Med] Suite runtime canonicalization treated ordered environment dictionaries as PSObject metadata, recording null identity values and only HEAD rather than the measured staged tree.
- [3.2] [src:code-review] [sev:Med] Plan workflow docs said ReviewRuns directories appear only after publication, but callers create conditional state before Freeze and may leave frozen unpublished orphans.
- [3.2] [src:code-review] [sev:High] The new current-platform tree assertion would fail Windows because its historical runtime row lacked tree attribution; the row was migrated through the supported import flow using its committed tree.
- [3.2] [src:code-review] [sev:Med] A staged tree hash identifies pre-measurement inputs, not the post-run receipt rewrite; the flow now requires all tracked inputs staged and only the receipt left unstaged.
- [3.2] [src:code-review] [sev:Low] The refreshed Linux receipt is a transparent 16-core container measurement rather than the earlier 4-core CI reference; source and environment remain explicit and the result stays below the platform target.
- [3.2] [src:code-review] [sev:Med] Accepted Publish recomputed the merged projection after both views had already consumed it; run state now reuses the shared projection.
- [3.2] [src:code-review] [sev:Med] Runtime measurement executed the working tree but recorded the index without cleanliness or stability checks; it now requires a clean tree and verifies pre/post index identity.

## CR Capture
Phase: 4

- [4.1] [src:code-review] [sev:Critical] Final branch review run ca47ce29-3004-46e8-9687-e946ad052656 completed 14/14 tasks but blocked approval with 1 Critical and 17 High findings; artifact preserved for remediation and re-review.
- [4.1] [src:code-review] [sev:High] Admission rollup parses unverified source bytes
- [4.1] [src:code-review] [sev:High] Cleanup marker digest mismatch has no negative test
- [4.1] [src:code-review] [sev:High] Cleanup propagation tests fire before deletion
- [4.1] [src:code-review] [sev:High] Cleanup-pending replay loses diagnostic and exit classification
- [4.1] [src:code-review] [sev:High] Finalization lock contention reports exit 2
- [4.1] [src:code-review] [sev:High] Finalization returns four different record shapes
- [4.1] [src:code-review] [sev:High] Finalize-ReviewPlanRun returns a non-uniform result contract
- [4.1] [src:code-review] [sev:High] Live retry can overwrite evidence bound to a different cleanup marker
- [4.1] [src:code-review] [sev:High] Stable cleanup verdict can be overwritten on live-directory retry
- [4.1] [src:code-review] [sev:High] Tombstone is never proven absent from incomplete-run discovery
- [4.1] [src:code-review] [sev:High] Verdict no-overwrite is not tested during retained-pair repair
- [4.1] [src:note] [sev:Low] operator-wrap: after eight CR runs, operator directed no further review cycles; residual findings retained and plan finalization accepted

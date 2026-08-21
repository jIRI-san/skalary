# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Execute the complete plan vertically.** Rejected: an MVP-only implementation loop; successive phases must continue until the full desired outcome is delivered.
- **Use phase completion as the vertical slice boundary.** Steps run focused checks; phase close rechecks confirmed intent and requirements referenced by that phase; plan close performs the complete integration crosscheck.
- **Extend capture instead of adding another runtime state store.** `Add-WorkflowNote -Kind Capture` gains optional closed record metadata; `CheckpointGate.ps1` is the sole parser/reducer/control owner; legacy untyped entries remain valid but non-authoritative. See [decisions/runtime-checkpoint-contract.md](decisions/runtime-checkpoint-contract.md).
- **Escalate by impact, not uncertainty alone.** Contract, user-experience, security, irreversible-structure, and intent mismatch records block for approval; ordinary reversible choices are recorded and continue.
- **One writer per scope.** Specialized agents may design, judge, validate, implement, and review in parallel only where their write scopes do not overlap.
- **Keep interactive and headless semantics equal.** Autopilot persists the same checkpoint/decision records and exits `42` rather than granting itself authority that interactive `/ci` reserves for the operator.
- **Bind operator authority to exact state.** Only interactive `/ci` records a resolution through the checkpoint gate; it names one blocker ID and matching state digest. Unattended modes may create blockers but cannot resolve them.
- **Make operator origin default-deny.** The resolution action lives in an interactive-only script path, requires a positively established non-redirected interactive host, and rejects all CI/autopilot environment states plus absent or unclassifiable origin. This is defense against accidental self-approval, not a claim that an arbitrary process with full user/repository authority is cryptographically distinguishable from the operator.
- **Keep one evidence authority.** The checkpoint gate batches marker requests and consumes `863d97`'s installed focused executor and v2 publication API; it does not execute tests or publish receipts itself.
- **Sync payloads in the step that changes them.** Generated bundles, versions, dogfood, registry, and marketplace cannot wait for a cleanup phase because each intermediate commit must remain installable and validation-green.
- **Reuse `006` REQ-7 and the `b0c0d3` plan-assets layout.** Every new requirement carries typed evidence, and all runtime writes remain layout-resolved under the existing asset contract.
- **Extend `57cc2c`.** Its complete-plan, MVP-first, provenance, and high-impact uncertainty decisions remain authoritative; this plan adds the execution loop that consumes them.
- **Depend on and reuse `863d97`.** Its full evidence status/finding/disposition, focused execution, receipt publication, and completion-gate contract is the sole evidence authority; this plan does not build an evidence-v1 adapter.
- **Keep review attendance separate.** Reuse the `ca8ba8` decision that evidence-marker truth does not own review attendance or corroboration authority.
- **Treat the `768d7b` v1 skipped-receipt limitation as superseded by `863d97`.** This plan records skipped/degraded evidence through the new typed evidence contract and never revives prose deferrals as receipt truth.
- **Make no architecture-tier contract change.** `ARCH-Review-Run-V1`, `ARCH-Eval-Gate-Separation`, and `ARCH-Install-Confinement` remain boundaries to validate; implementation details stay in design notes.
- **Use reserved Capture capacity instead of compaction.** Ordinary records cannot consume the blocker/resolution reserve; hard exhaustion blocks with a remedy. Unresolved control records are never folded or evicted.
- **Separate evaluated state from persistence.** A blocker binds to a digest over implementation inputs that excludes workflow-only Capture/receipt/checkbox commits; its commit is recorded separately. Real implementation, intent, step, or marker-inventory changes invalidate old resolutions.
- **Reuse the evidence digest authority.** `evaluatedState` uses `863d97`'s `EvidenceDigest.psm1` enumeration/framing plus one closed checkpoint workflow-artifact exclusion projection; this plan adds no digest subsystem.
- **Phase the sole-caller cutover.** Admission first pins the exact `863d97` predecessor caller set, interactive `/ci` moves second, and autopilot moves last in the commit that enables global residual-caller rejection.
- **Reserve exits `46` and `47`.** Existing launcher/recovery semantics already own `42-45`; valid operator stops remain `42`, malformed or unsafe checkpoint state uses `46`, and persistence/push failure uses `47`.

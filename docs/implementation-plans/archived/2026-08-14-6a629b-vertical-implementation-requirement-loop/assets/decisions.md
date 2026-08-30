# Decisions

- **Implement vertical phases, not horizontal layers.** Each phase leaves a usable increment and the full plan still reaches the complete confirmed outcome.
- **Reuse the current parser and state.** Phase admission derives dependencies, prerequisites, progress, and requirement mappings from existing plan metadata.
- **Reuse truthful evidence.** Phase close consumes the simplified `863d97` result/receipt behavior rather than creating another evidence submission path.
- **Reread intent at checkpoints.** Confirmed intent remains the outcome authority at phase and final crosschecks.
- **Capture through `Add-WorkflowNote`.** Existing layout-resolved capture kinds hold decisions, lower-impact uncertainty, and checkpoint summaries.
- **Escalate high-impact uncertainty.** Contract, end-user experience, security, and irreversible-structure decisions stop for operator confirmation.
- **Make one-phase autonomy explicit.** Autopilot `next-phase` runs one phase, crosschecks it, stops, and resumes from checklist state.
- **Keep interactive and autonomous behavior aligned.** Both paths use the same admission and phase-close outcomes without a new parity subsystem.
- **Reject prior expansion.** No new checkpoint parser, atomic capture schema, checkpoint state machine, exit-code family, evidence caller, or broad mode-parity platform is included.
- **Keep dependencies behavioral.** `57cc2c` supplies confirmed intent/design; `863d97` supplies truthful evidence statuses required at phase close.

## Simplification decision

The accepted cut is a thin workflow loop over existing plan state, evidence, and capture writers. New mechanics are limited to phase admission, the operator checkpoint, and one-phase stop/resume orchestration.

## Pre-child proportionality review (2026-08-29)

- **Verdict: keep.** The confirmed intent still requires one vertical phase loop, and the current six-step cut remains proportionate.
- Both behavioral dependencies, `57cc2c` and `863d97`, are archived and complete; no infrastructure-only edge remains.
- Ownership stays narrow: existing plan state, truthful evidence, and `Add-WorkflowNote` remain authoritative. This plan does not duplicate `4dd933` artifact context, `8a0644` dispatch, or `25aa23` coherency-review machinery.
- Blocking simplification findings: none.

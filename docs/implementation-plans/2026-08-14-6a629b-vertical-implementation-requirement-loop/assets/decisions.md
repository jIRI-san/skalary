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

# Intent

## Goal

Fit Skalary's normal planning, implementation, review, self-improvement, and premium-eval work within
a 200,000 GitHub AI-credit monthly ceiling by removing long-context use, routing each task to the
least expensive model that can perform it reliably, and deleting unnecessary delegated calls.

## Desired outcome

Routine work uses default context and inexpensive models, deterministic tools replace AI judgment
where they can, and expensive reasoning is a visible escalation rather than the default. The
repository documents one small task/model matrix, keeps an emergency reserve, and avoids a runtime
metering or policy service.

## Success signals

- No active config, schema, launcher, skill, or agent can request `long_context`; archived history is
  excluded.
- Routine bounded implementation and summarization use GPT-5.6 Luna; ordinary planning, validation,
  CR, and DR use GPT-5.6 Terra.
- GPT-5.6 Sol is reserved for cross-subsystem planning/orchestration or unresolved diagnosis, and
  Claude Opus 5 is reserved for one concrete high-risk independent review or final escalation.
- Skills no longer schedule a Judge as an automatic second call. Direct work defaults to no delegate;
  one combined delegate is normal when evidence shows it is needed.
- Tier-2 evals remain explicit and plugin-focused, use an inexpensive execution model, and retain an
  LLM judge only where deterministic graders cannot prove the behavior.
- The operating target is 180,000 credits per month with 20,000 held for incidents and month-end work;
  the operator reviews actual model-level usage in GitHub rather than maintaining repository telemetry.
- High-frequency skill bodies use progressive disclosure so rare instructions and large references
  are loaded only when their path is selected.

## Non-goals

- Building a credit ledger, telemetry pipeline, scheduler, model router service, or automatic billing
  integration.
- Guaranteeing an exact monthly spend from static repository instructions.
- Weakening deterministic validation, prompt-injection treatment, secret handling, path confinement,
  destructive-action approval, or externally required format checks.
- Rewriting archived plans or preserving compatibility for the retired long-context option.
- Using model panels or duplicate reviewers to create confidence without a concrete unresolved risk.

## Definition of done

- Active long-context support is removed, the model/call/context matrix is reflected consistently in
  canonical plugins and generated dogfood copies, premium evals have a cheaper evidence-backed route,
  focused tests guard the new defaults and escalation boundaries, and operator guidance explains how
  to stay within the monthly operating target.

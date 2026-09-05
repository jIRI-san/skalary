# Decisions

- **Remove long context, do not hide it.** Delete the autopilot config field, schema enum, launcher
  plumbing, examples, and active guidance for `long_context`; omit `--context` and use host defaults.
- **Operate to 180K, reserve 20K.** The 200K monthly ceiling is split into planned use and an incident
  reserve. Review actual GitHub model-level usage weekly; do not build local metering or claim exact
  enforcement from static instructions.
- **Cheap-first model ladder.** Use GPT-5.6 Luna for routine bounded coding, extraction,
  summarization, and documentation; GPT-5.6 Terra for ordinary planning, validation, CR/DR, and complex
  bounded implementation; GPT-5.6 Sol only for cross-subsystem orchestration or unresolved diagnosis;
  Claude Opus 5 only for one concrete high-risk independent pass or final escalation.
- **Replacement fallbacks only.** Luna falls back to GPT-5 mini, Terra to Claude Sonnet 5, Sol to
  Terra, and Opus to Claude Sonnet 5. A fallback never adds a panel or upgrades routine work.
- **No automatic second Judge.** Direct orchestration is the default. Add one combined delegate only
  for a concrete unresolved concern; deterministic tests and evidence are the normal judge.
- **Three-call hard ceiling.** A task or plan step may use at most three delegated calls including
  retries and replacements. A fourth call requires a new explicit operator decision rather than an
  embedded exception.
- **Progressive disclosure.** Keep high-frequency skill entrypoints as short decision trees and move
  rare recovery, provider, and format detail into installed assets loaded only on the selected path.
  Cap the seven named high-frequency entrypoints at 4 KiB, supporting artifacts at three, and delegated
  prompts at 400 words target/800 words maximum.
- **Cheaper premium evals.** Use Luna for skill execution and Terra for subjective judgment by default;
  classify every current task and replace LLM graders only where deterministic evidence is observable.
- **Explicit models over Auto in committed workflows.** Preserve predictable routing and auditability;
  the host's Auto discount may still be used for ad-hoc operator work.
- **Pricing is dated guidance.** Link the official table and review it during planning rather than
  creating a model-price registry or hardcoded calculator.
- **Manual execution.** This plan changes autopilot's own model and context surfaces, so it executes in
  manual mode and proves launch behavior through focused tests rather than self-modifying autopilot.
- **No mandatory premium proof run.** Structural checks and a no-cost model listing are completion
  evidence; any live waza smoke remains an explicit operator choice outside ordinary validation.

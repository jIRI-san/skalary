# Decisions

Preliminary context captured by /cep; /cip must confirm and refine it.

- **One atomic vertical migration.** Change review producers and plan/autopilot consumers together so
  no intermediate receipt or schema compatibility layer is needed.
- **Advisory Markdown only.** Reports identify source, scope, attendance, findings, and verdict but do
  not claim signature, content-addressed, receipt, or durable authority.
- **Keep the untrusted-content fence.** Review input, historical context, and learning text remain
  data. This is one of the few retained security controls.
- **Current Git supplies freshness.** Do not replace receipts with a new signed baseline. Directly
  compare confirmed criteria and current repository state.
- **Criteria are split by intent, not one frozen blob.** Confirmed intent, requirements, risks, and
  decisions are immutable during execution; checklist/worktree progress is mutable.
- **Strategic review dispatch.** Use the concrete operator-approved cost budget from `2aa7ec`; remove
  the mandatory fourteen-task matrix, fleet scheduler, generated concern registry, and repeated
  context loading.
- **Implement the cost RFC in this child.** Apply its 2-default/5-maximum call budget, five-supporting-
  artifact bound, and 600/1,200-word delegated-instruction targets across `/cip`, `/ci`, autopilot,
  CR, and DR. Prefer discounted OpenAI models for routine work, retain at least one fit-for-purpose
  non-OpenAI reviewer for independent perspective, and choose roles from observed cost, latency,
  quality, context, and availability rather than vendor symmetry.
- **One terminal review.** The terminal phase skips ordinary post-phase review and runs one whole-plan
  final review. A corrective change may replace the result, but an unchanged scope is not reviewed
  again.
- **Plain instructions own orchestration.** The current Designer/Validator/Implementor/Judge and review
  waves are coordinated by instruction and native agent calls. PowerShell remains for deterministic
  repository facts and focused validation, not agent scheduling, attendance, or lifecycle state.
- **Bounded stuck recovery.** Ask the existing task for progress once; if it has no new evidence,
  cancel or reuse it and permit at most one replacement within the accepted call budget. Escalate
  visibly to the operator rather than polling, silently retrying, or building a watchdog service.
- **Questions must enable a decision.** Complex choices include context, concrete examples, a Mermaid
  diagram when relationships matter, benefits, pros/cons, and effort/complexity. Absolute and fuzzy
  words are not accepted as shorthand when their operational meaning is conditional or unobservable.
- **Security remains proportional, not absent.** Keep controls for prompt injection, credentials,
  destructive operations, untrusted external data, externally consumed formats, and physical write
  confinement. Do not require signatures, identities, journals, attestation, audit services, or
  multi-operator controls without a concrete threat path in this repository.
- **Separate AI and human documentation.** AI-facing design notes are compacted once when `/ci` edits
  them. Human tutorials, diagrams, process explanations, artifacts, gates, sequencing, and limits live
  under the operator-approved `docs/operator-guide/` and are excluded from that compaction.
- **One bounded learning handoff.** Produce recent, cited, fenced Markdown for SI. Do not add replay,
  publication, CAS, identity, retention, or service semantics.
- **Simple interruption behavior.** Fail visibly and leave readable progress; do not build journals,
  leases, repair, or distributed-run detection.
- **Reject overcomplicating review findings.** Do not restore receipts, rollback systems, independent
  policy authorities, attestation, or exhaustive proof matrices.
- **Review reports are stable stage files.** Plan-associated review writes
  `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`; corrective source changes replace the same
  stage file and Git preserves history. Standalone review is chat-only unless explicitly saved.
- **Learning handoff is one bounded feedback artifact.** Completion replaces
  `docs/feedback/recent-learning.md` with at most 10 cited fenced items and 16 KiB UTF-8.
- **Agent progress and command timeouts are separate.** Wall-clock duration never kills an agent;
  two explicit evidence-free status checks drive stuck recovery. Existing deterministic command/test
  timeout contracts remain and become evidence for the agent to handle.
- **Human docs use four files.** `docs/operator-guide/README.md` indexes `planning.md`,
  `implementation.md`, and `reviews.md`; each focused guide owns its Mermaid flow.
- **Remaining operator gate:** exact model names are chosen after representative cost, latency,
  availability, and useful-result observations during Phase 1.
- **Model observations do not mutate plan criteria.** Step 1.1 updates the agent-cost note and canonical
  model policy assets only; the plan already fixes the role classes, budget, and selection rules.
- **Git locates the criteria baseline.** Execution resolves the unique commit that introduced the
  current planning-confirmation marker and compares intent, requirements, risks, and decisions to that
  tree. Missing, uncommitted, ambiguous, or changed state refuses continuation; no new baseline marker
  or receipt is added.
- **Dormant-first atomic cutover.** Add and prove the direct path beside the active workflow, prepare
  every consumer, then switch and delete old machinery in one activation step. Interrupted uncommitted
  work is visible; the prior commit remains usable and Git revert is sufficient rollback.
- **Review evidence is observed, not authenticated.** `review:cr` uses the active complete clean result
  for the requested current scope; the persisted Markdown report is advisory history with exact source
  commit and closed verdict fields.
- **The review guard boundary moves, not disappears.** Direct CR/DR retain read-only operation,
  collision-safe untrusted framing, secret redaction, canonical plan/report write confinement, and
  external-format checks before old generated reviewers are removed.
- **Budget exhaustion stops.** No corrective change means no rerun; exhausted calls, incomplete tasks,
  stuck replacement, or unresolved findings produce a non-clean report and operator stop.
- **Learning trust is consumer-owned.** `/ci` and autopilot write bounded cited Markdown;
  `3a4498` owns fencing and untrusted interpretation when `/si` reads it.

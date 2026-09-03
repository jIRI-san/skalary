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
- **One bounded learning handoff.** Produce recent, cited, fenced Markdown for SI. Do not add replay,
  publication, CAS, identity, retention, or service semantics.
- **Simple interruption behavior.** Fail visibly and leave readable progress; do not build journals,
  leases, repair, or distributed-run detection.
- **Reject overcomplicating review findings.** Do not restore receipts, rollback systems, independent
  policy authorities, attestation, or exhaustive proof matrices.
- **Unresolved for `/cip`:** exact report headings, minimal reviewer-selection rules, and the simplest
  observable exit behavior for completed, refused, blocked, and interrupted runs.

# Decisions

Preliminary context captured by /cep; /cip must confirm and refine it.

- **Recent learning only.** Consume the single bounded fenced artifact from `367e9a`; do not search
  old plans directly.
- **Interactive, cited proposals.** The operator sees source context, expected effect, effort, and
  complexity before choosing individual changes.
- **No durable lifecycle.** Remove atomic stores, CAS, repair, receipts, proposal state, schemas,
  remote PR orchestration, and replay/publication semantics.
- **Retain prompt-injection fencing.** Harvested text remains untrusted data and cannot issue
  instructions.
- **Retain an explicit allowed-root guard.** Resolve physical paths before writes and reject workflow
  paths. Avoid a broad policy engine.
- **Apply only the selected change.** Show the generated change through the normal editing/diff flow;
  do not add a signed approval receipt or bespoke rollback protocol.
- **Equivalent hosts without an abstraction layer.** Use native VS Code selection and a numbered/chat
  CLI path with equivalent information.
- **Rejected:** review demands for proposal identities, publication, replay, durable retention,
  receipts, and transactional rollback.
- **Unresolved for `/cip`:** exact learning-artifact size/recency bounds and the smallest practical
  list of allowed instruction/design-note roots.

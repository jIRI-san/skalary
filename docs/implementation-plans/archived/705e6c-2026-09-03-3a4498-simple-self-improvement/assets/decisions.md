# Decisions

- **Recent learning only.** Consume the single bounded fenced artifact from `367e9a`; do not search
  old plans directly.
- **Retain the reader, delete its receipt path.** `Get-SiHarvest.ps1` remains the strict read boundary,
  but receipt issuance, candidate digests, due/run inputs, CAS, and state-store imports are removed.
- **Interactive, cited proposals.** The operator sees source context, expected effect, effort, and
  complexity before choosing individual changes; one run ranks at most five.
- **Apply locally.** Selected edits land in the current worktree and remain visible in the normal Git
  diff. `/si` creates no branch, worktree, commit, push, or PR.
- **No durable lifecycle.** Remove atomic stores, CAS, repair, receipts, proposal state, schemas,
  remote PR orchestration, cross-repository transport, and replay/publication semantics.
- **Retain prompt-injection fencing.** Harvested text remains untrusted data and cannot issue
  instructions.
- **Use a closed canonical Markdown boundary.** Direct edits are limited to root Copilot instructions,
  canonical plugin skill/agent/prompt Markdown, and design/architecture notes. Resolve physical paths
  before writes and reject workflows/actions, generated copies, executable code, schemas/config, plans,
  runtime state, traversal, and links that escape.
- **Generated outputs remain generator-owned.** A selected canonical plugin Markdown edit invokes the
  existing script/registry/marketplace/dogfood sequence. Generated changes are visible consequences, not
  direct SI targets.
- **Apply only selected changes.** No selection means no mutation. A selected target with unrelated
  edits stops for operator action. Failures leave the normal diff; no signed approval receipt or bespoke
  rollback protocol is added.
- **Equivalent hosts without an abstraction layer.** Use native VS Code selection and a numbered/chat
  CLI path with equivalent information.
- **PFB is stateless.** Keep its cited delivered-vs-intent comparison and optional correction-plan
  handoff; delete queue persistence and make headless completion skip it.
- **No compatibility interval.** Remove SI/PFB state producers, consumers, schemas, scaffolds, docs, and
  tests atomically after the direct path is proven.
- **Cheap direct execution.** Use zero delegated calls by default and retain the existing three-call
  ceiling; deterministic evidence is the normal judge.
- **Rejected:** review demands for proposal identities, publication, replay, durable retention,
  receipts, and transactional rollback.

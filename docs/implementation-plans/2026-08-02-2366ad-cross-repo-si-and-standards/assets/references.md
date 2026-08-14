# References

<!-- Design notes, architecture contracts, and prior plans consulted while drafting. -->

## Epic discussion provenance

- Epic `33b1f9` goal and decomposition notes: consumer correctness and durable SI state are hard dependencies before cross-repo proposals can be trusted.
- Session `8706d364-f92e-4056-bb1b-40a59b015d38` (2026-08-01 to 2026-08-02): the operator identified that consumer `/si` improvements belong upstream and considered a locally materialized upstream checkout plus container boundary.
- `docs/design-notes/explorations/si-cross-repo-proposal-protocol.design.md`: typed harvest/propose split, instruction-boundary rationale, evidence asymmetry, and rejected free-form autopilot mode.
- Dependencies: `1936cb` supplies durable SI state; `34088e` supplies correct consumer-installed behavior.

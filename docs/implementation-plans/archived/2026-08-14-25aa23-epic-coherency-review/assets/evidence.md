# Supersession evidence

Reevaluated against `64ddb6a445fbd6b0fd30a399a68654e98006142a` on 2026-09-06.

- Plan `367e9a` and commit `a652134251e217e8227e184dae1bf49a32b294df` retired review-run v1,
  fixed review fleets, durable review receipts, and the `/ci` per-child coherency gate.
- `ARCH-Direct-Workflow` now requires direct risk-selected review and current in-memory evidence.
- The repository-wide Simplicity First rule preserves the useful proportionality outcome without the
  plan's verdict schema, receipt, or lifecycle machinery.
- The retained review run `e3dfdf97-4d7c-4247-9529-43c6cec16cf9` assessed deleted code at
  `5c7db4b3f3c58ce3e744aeeafd081591131b4a55`; its 72 findings do not describe current behavior.
- Current plan validation, focused epic checks, and generated-copy drift checks passed during
  reevaluation. The orphaned `SetCoherencyVerdict` writer and its focused test were removed rather than
  restored.

Outcome: no current user-facing requirement remains. Close and archive `25aa23` as superseded.

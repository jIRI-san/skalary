# Decisions

Preliminary context captured by /cep; /cip must confirm and refine it.

- **Optimize for one trusted operator.** Do not retain distributed-system safeguards for hypothetical
  contributors or concurrent writers.
- **Retain physical path confinement.** Canonicalize every destination before writing and require it
  to remain under the consumer `.github` root.
- **Verify the resulting files directly.** Check expected manifest-owned paths in memory before
  success; do not generate a receipt to attest to the check.
- **Require convergence.** An unchanged rerun must make no change. This replaces recovery/repair
  complexity for the routine case.
- **Keep only external JSON.** Preserve `plugin.json`, published registry JSON, and marketplace JSON
  where their consumers require them. Delete or convert lifecycle-internal JSON.
- **Remove journals, CAS, signing/install receipts, repair, and compatibility layers.** No migrations
  or dual readers are required.
- **Keep focused refusal tests.** Path escape and destructive mutation outcomes remain high-value
  regressions; avoid broad fixture matrices and full-suite execution.
- **Rejected:** review demands for crash journals, operator-modification ownership receipts,
  transactional rollback, and unattended execution authorities.
- **Unresolved for `/cip`:** exact minimal handling when removal encounters an operator-modified file;
  present the operator with simple choices rather than inventing durable ownership state.

## CR Capture
Phase: 1

- [1.1] [src:note] [sev:Low] review-cycle stage=step-1.1 cycle=1 outcome=clean summary=clean-1-findings-0-run-step-1-1-review
- [1.2] [src:code-review] [sev:Med] Expected output paths that are directories are not rejected before atomic writes.
- [1.2] [src:code-review] [sev:Med] Generated-agent stale detection uses case-sensitive path identity on Windows.
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=1 outcome=findings summary=med-2-run-step-1-2-review
- [1.2] [src:note] [sev:Low] review-cycle stage=step-1.2 cycle=2 outcome=clean summary=clean-1-findings-0-run-step-1-2-rereview

## CR Capture
Phase: 2

- [2.1] [src:note] [sev:Low] review-cycle stage=step-2.1 cycle=1 outcome=clean summary=clean-1-findings-0-run-step-2-1-review
- [2.2] [src:note] [sev:Low] review-cycle stage=step-2.2 cycle=1 outcome=clean summary=clean-1-findings-0-run-step-2-2-review

## CR Capture
Phase: 3

- [3.1] [src:code-review] [sev:Med] Generated ownership used agents/** and therefore included hand-authored orchestrator agents; narrow it to cr-/dr-concern patterns.
- [3.1] [src:code-review] [sev:Med] Docs credited the shared agent template with ledger-map structure, but Render-LedgerMap owns that generated structure.
- [3.1] [src:note] [sev:Low] review-cycle stage=step-3.1 cycle=1 outcome=findings summary=2-med-run-phase3-code-review
- [3.1] [src:note] [sev:Low] review-cycle stage=step-3.1 cycle=2 outcome=clean summary=0-findings-run-phase3-code-recheck
- [3.1] [src:code-review] [sev:Low] Exact-byte comparison rejected a zero-length on-disk byte array at parameter binding, preventing apply mode from repairing a truncated generated file.
- [3.1] [src:code-review] [sev:Low] Fixed and covered: zero-byte generated outputs now enter ordinary drift detection and are repaired in apply mode.

# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Shared boilerplate creates a false near-duplicate and suppresses valid corroboration. | Medium | High | Compare only normalized finding content inside an existing merge group, require meaningful content for near-match checks, and keep negative fixtures for common boilerplate. | 1.1, 1.2, 2.2, 3.1, 4.1 |
| RISK-2 | A paraphrase or non-ASCII variation escapes the conservative lexical rule and is mistaken for proof of independence. | High | Medium | Render only observable state and say no suspicious similarity was observed; never claim served-model identity. | 1.1, 1.2, 2.2, 3.1, 4.1 |
| RISK-3 | Suspicious/degraded support still elevates severity or hides a raw finding. | Medium | High | Preserve raw findings/severity, derive effective severity centrally, force `needs-review` for suspicion, and test malicious echo and incomplete attendance. | 1.2, 2.1, 2.2, 3.1, 4.1 |
| RISK-4 | New report fields break review-run v1 verification, retained evidence, or installed consumers. | Medium | High | Extend current schema/rendering compatibly and exercise existing publish/read/finalize/cleanup plus installed fixtures. | 2.1, 2.2, 3.1, 4.1 |
| RISK-5 | Derived state is order-dependent, caller-forgeable, or drifts across bundled copies. | Medium | High | Normalize and sort deterministically, reject caller-supplied derived fields, and use existing sync/parity/drift gates. | 1.1, 1.2, 2.1, 2.2, 3.1, 4.1 |

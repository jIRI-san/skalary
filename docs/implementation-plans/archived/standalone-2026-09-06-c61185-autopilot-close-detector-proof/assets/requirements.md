# Requirements

<!-- Every discovered edge case belongs in this table, assets/risks.md, or an explicit non-goal in assets/intent.md. -->

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Create one disposable proof file and complete the real container lifecycle. | `file:tests/autopilot-close-detector-proof.txt#contains:^autopilot close proof$`; launcher exit `0`; no terminal `close-pending` failure. | 1.1 |

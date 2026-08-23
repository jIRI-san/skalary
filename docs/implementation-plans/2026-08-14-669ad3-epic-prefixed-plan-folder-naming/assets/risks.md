# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | A migration collision or identity mismatch could move the wrong plan. | Medium | High | Resolve every candidate through existing inventory, reject the full run before movement, and bind apply to the reviewed mapping. | 1.1, 2.1, 2.2, 3.1, 3.2 |
| RISK-2 | Interruption could leave a partially migrated corpus. | Medium | High | Move sequentially, record each completed mapping entry, and resume idempotently; do not require a corpus-wide transaction. | 2.2, 3.1, 3.2 |
| RISK-3 | Consumers could treat folder prefixes as identity or stop finding legacy/current paths. | Medium | High | Keep `plan-id` canonical and route consumers through shared inventory/resolution tests covering all supported forms. | 1.1, 1.2, 3.1, 3.2 |
| RISK-4 | Shipping a migration script could trigger an unnecessary bulk rename. | Medium | High | Default to `-WhatIf`, require explicit apply against a reviewed mapping, and do not invoke migration from this plan or lifecycle tools. | 2.1, 2.2, 3.1, 3.2 |
| RISK-5 | Bundled scripts and generated catalogs could drift. | Medium | High | Use existing plugin sync, version, registry, marketplace, and installed-consumer checks. | 1.2, 3.1, 3.2 |

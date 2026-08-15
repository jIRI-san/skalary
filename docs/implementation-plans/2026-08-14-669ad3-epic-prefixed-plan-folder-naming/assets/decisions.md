# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Prefix the folder, not the identity.** Target grammar is `<epic-id>-<date>-<plan-id>-<slug>` or `standalone-<date>-<plan-id>-<slug>`; `plan-id` remains canonical.
- **Create the final name immediately.** `/cep` passes epic identity into child scaffolding; direct `/cip` defaults to `standalone`.
- **Rename on attachment or re-parenting.** `New-Epic.ps1` updates the marker and eligible folder in one script-owned operation, then refreshes both epic mirrors.
- **Migrate only current hash-schema folders.** Legacy `NNN-<slug>` plans remain untouched; active and archived eligible folders use a confined, collision-preflighted, idempotent migration with `-WhatIf`.
- **Preserve every stable key.** Migration never changes `plan-id`, `depends-on`, ledger keys, or evidence identity.
- **Support mixed grammars during rollout.** Inventory, resolution, archival, launchers, tests, and documentation accept old hash, target hash, and legacy numbered plans.

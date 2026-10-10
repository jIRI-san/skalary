# Unattended decisions

## Preparation observations - not execution evidence

- 2026-10-10, plan 1a4feb: initial clean HEAD was exactly `1e0be7cac04e0212406a7325929859bd27d9a2ba`. Branch renamed through app to `jiri-san-docker-ci-acceptance` before fixture mutation. Consequence: no parent/source mismatch hidden.
- Installed safe configuration show/preview found TRACKED `.autopilot.json` (blob `24b6d6cccb62bc764ec440ba2bb63932d187c21a`), digest `262bb221418cfce52675c2f9fe92c11b0fc26a0018faa2734977d9760630c2fe`. Consequence: ignored-file setup assumption is invalid here; no config applied or copied.
- Installed config preview proposed high/default and disabled main-fixture offline packages; separate preview proposed enabled npm/maxRebundles 1. Preview only. Rationale: enumerate exact future actions without execution authority; source config remains byte-unchanged.
- Installed npm feed/rebundle requires root manifests; a nested smoke manifest cannot prove its path. Consequence: package observation stops for a separately approved fixture-rooted repository instead of introducing a Skalary dependency.

## Execution choices

- 2026-10-10, step 1.2 / REQ-2: use `apply_patch` to create `smoke/app-ci/1a4feb/independent.txt` as one ASCII line with a final LF. Criterion: exactly 12 bytes, hex `696E646570656E64656E740A`, with no CR or BOM. Rationale: the direct patch avoids platform-dependent text encoders and newline conversion; the focused byte assertion and current `file:`/`test:` evidence verify the result before commit. Consequence: commit this file, only the 1.2 checkbox, and this bounded choice atomically; human 1.1 and dependent 1.3 remain unchecked, no dependent/second file is created, and this visit cannot close Phase 1 or finalize the plan.

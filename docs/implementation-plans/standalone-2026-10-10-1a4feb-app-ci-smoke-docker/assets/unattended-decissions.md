# Unattended decisions

## Preparation observations - not execution evidence

- 2026-10-10, plan 1a4feb: initial clean HEAD was exactly `1e0be7cac04e0212406a7325929859bd27d9a2ba`. Branch renamed through app to `jiri-san-docker-ci-acceptance` before fixture mutation. Consequence: no parent/source mismatch hidden.
- Installed safe configuration show/preview found TRACKED `.autopilot.json` (blob `24b6d6cccb62bc764ec440ba2bb63932d187c21a`), digest `262bb221418cfce52675c2f9fe92c11b0fc26a0018faa2734977d9760630c2fe`. Consequence: ignored-file setup assumption is invalid here; no config applied or copied.
- Installed config preview proposed high/default and disabled main-fixture offline packages; separate preview proposed enabled npm/maxRebundles 1. Preview only. Rationale: enumerate exact future actions without execution authority; source config remains byte-unchanged.
- Installed npm feed/rebundle requires root manifests; a nested smoke manifest cannot prove its path. Consequence: package observation stops for a separately approved fixture-rooted repository instead of introducing a Skalary dependency.

## Execution choices

None yet. First admitted 1.2 worker records its LF-writing method, REQ-2 exact 12-byte criterion, rationale, and consequence in its atomic source/checklist commit. This mutable log cannot authorize human work or override confirmed criteria.

# SI Inspection And Repair State Machine

`Get-SiState` and `Repair-SiState -Mode Inspect` never mutate. `-Mode Snapshot` is the sole transition that persists canonical immutable observation bytes. `-Mode Apply -Observation <id>` writes backup and `apply-journal.json` under `backups/<observation-id>/` before the first target mutation, then quarantine/index, repaired artifacts, and repair receipt. `-Mode Rollback` accepts either the final receipt id or an observation id whose apply journal is incomplete. Authoritative Snapshot/Apply/Rollback travel through `si-repair/<observation-id>` and trusted merge-time enforcement.

| Observed store | Status | Exit | Allowed action |
|---|---|---:|---|
| absent manifest and no runs | `absent` | 0 | initialize scaffold |
| valid current manifest/runs | `valid` | 0 | inspect/archive only |
| missing manifest with valid current runs | `repairable-orphans` | 2 | inspect or apply rebuild |
| corrupt current manifest/run | `repairable-corrupt` | 2 | backup, quarantine, rebuild/index |
| mixed v1/current valid data | `migration-required` | 2 | explicit v1 migration with stable IDs |
| forward-version artifact only | `forward-readonly` | 3 | inspect metadata; no apply/rollback |
| forward-version plus current recoverable data | `forward-blocked` | 3 | quarantine nothing; operator upgrade required |
| bounds exceeded | `capacity-blocked` | 4 | archive PR before retry |
| confinement/schema/receipt failure | `invalid` | 5 | no mutation |
| lock not acquired within 30 seconds | `lock-timeout` | 6 | no mutation; retry later |
| generation changed before replace, retries remain | `cas-conflict` | 7 | discard temp and retry from fresh generation |
| generation changed on third retry | `cas-exhausted` | 8 | no mutation; return observation bytes in process output and stop |
| apply journal exists without final receipt | `apply-incomplete` | 9 | rollback by observation id or resume after hash verification |

Inspect returns a canonical observation payload containing protocol tag `si-repair-observation-v1`, pinned base OID, and sorted canonical observed paths/hashes but writes nothing. Snapshot sets `observation-id=sha256('si-repair-observation-v1' UTF8 || exact payload bytes)` and persists an envelope containing that identifier plus the unchanged payload; the identifier is never part of its own hash input. It is used by observation, journal, receipt, crash resume, and branch. Backup and journal precede every target mutation; quarantine index precedes repaired replace; run precedes manifest; final receipt is last. Every crash point is discoverable from observation-id journal state, and rollback can address the backup before a receipt exists. `lock-timeout`, `invalid`, and `cas-exhausted` perform no mutation and return observation payload bytes only in process output.
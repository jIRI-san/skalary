# Operational Limits

All limits apply after normalization/sanitization and are measured as UTF-8 bytes unless stated otherwise. A plus-one value fails before mutation with `capacity-blocked` (exit 4); nothing truncates. Maximum-size focused tests must complete inside the existing suite budget.

| Surface | Limit |
|---|---|
| SI hot manifest | 128 pending/in-flight dues; 64 recent refs; 256 KiB |
| SI run | exactly the resolver's 0-5 ranked candidates; 1 MiB total; title 512 B; rationale 8 KiB; 32 sources and 32 targets at 1 KiB each |
| SI active history | 32 completed run files plus 16 resumable/in-flight run files at 1 MiB each; archive completed runs before file 33 and refuse a 17th in-flight run |
| SI archived history | 4,096 run files total; 256 files per `yyyy/mm` shard; archive capacity exhaustion requires a separate export/prune plan |
| Feedback queue | entry 16 KiB; 128 pending; 2,048 recorded; 4 MiB file; existing 8-hex IDs preserved, new IDs 16 hex |
| Learning overflow | record 16 KiB; 64 records/512 KiB per batch; 64 active batches/32 MiB per plan; archive before batch 65 |
| Phase harvest | 64 candidates/512 KiB; source record 16 KiB; one category rewrite per batch |
| Ledger category | 10,000 records and 4 MiB; plus-one batch fails as a unit |
| Selected-plan active logs | three files at 4 MiB each |
| Active phase receipts | 64 files at 64 KiB each |
| SI scan | 256 files; 160 MiB total; 60 seconds; the exact legal active maximum is 188 files and 128.25 MiB before framing, leaving 31.75 MiB overhead |
| SI selected evidence window | 1,024 records; 4 MiB; at most 64 pages of 64 records/256 KiB; 16 KiB cursor; 16K model-token envelope after wrapping |
| Excluded auxiliary stores | 256 backups, 256 quarantine files, 256 repair observations/receipts, 512 resolver receipts, 64 remote-state events per run; 1 MiB each; archive before plus-one |
| Locks | 30 seconds acquisition; precompute outside lock, then generation-digest recheck and atomic replace; at most three CAS retries; maximum fixture must demonstrate hold <=2 seconds |

The active scan set is closed: `docs/self-improvement/state.json`; exactly seven `docs/review-ledger/*.md` category files; the selected plan's active capture/cr-log/learnings, overflow batches, and phase receipts; `docs/feedback/queue.md` recorded section; and active `docs/self-improvement/runs/**`. Resolver receipts are outputs and never part of their own snapshot. `docs/self-improvement/archive/**`, ledger `.archive/**`, backups, quarantine, repair observations/receipts, and resolver receipts are excluded unless the operator supplies an explicit archive reference. Active and archive trees each share the file/count/byte ceilings above; archive plus-one is `capacity-blocked` and requires export/prune under a separate approved plan.

The legal active maximum is 188 files and 128.25 MiB before framing: 48 runs, 64 overflow batches, seven ledgers, three logs, 64 phase receipts, feedback, and manifest. The resolver scans every active file once, persists an index/digest, then selects evidence using existing recurrence/severity/blast-radius ordering. `complete` means every enumerated active file was scanned. Cursors contain pinned OID, snapshot digest, selected-window digest, and offset; mutation invalidates them. `Archive-SiState.ps1` moves eligible completed history/auxiliary records into year/month archive shards through a reviewed state-only PR until the archive ceiling is reached.
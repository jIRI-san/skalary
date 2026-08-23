## Learnings Capture
Phase: 1

- [1.1] [trigger:rework>1] When a native CLI returns machine JSON, capture stdout and stderr separately so successful warnings cannot corrupt the parser input.
- [1.2] [trigger:rework>1] Dry-run conflict handling must order refusals with desired items and treat in-scope unmapped relation targets as deferred creates, not missing external authority.

## Learnings Capture
Phase: 2

- [2.1] [trigger:rework>1] Digest persisted files from exact bytes, serialize writes behind a stable sidecar lock, and atomically replace only after a second source check.

# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Phase crosschecks persist selected learnings through the existing layout-resolved capture and ledger writers; finalization retries the same records without duplicates. | `test:LearningLoop.PhaseCaptureAndFinalSweep` · `review:cr` | 1.1, 4.1 |
| REQ-2 | Successful headless completion appends one typed, deduplicated SI-due record without running `/si`, and the next interactive completion surfaces the unresolved reminder. | `test:SiActivity.AppendDedupAndRecovery` · `test:SiActivity.HeadlessDueAndInteractiveOutcome` · `review:cr` | 2.1, 2.2, 4.1 |
| REQ-3 | Normal `/si` completion appends the operator's candidate choices and run outcome while preserving existing proposal safety and authority. | `test:SiActivity.HeadlessDueAndInteractiveOutcome` · `review:cr` | 2.2, 4.1 |
| REQ-4 | New writes are script-owned, confined, append-only, and use the existing narrow lock/temp/atomic-replace pattern; existing sync/version/registry writers distribute the installed payload. | `test:LearningLoop.PhaseCaptureAndFinalSweep` · `test:SiActivity.AppendDedupAndRecovery` · `test:LearningLoop.InstalledPayloadAndDrift` · `review:cr` | 1.1, 2.1, 2.2, 3.1, 4.1 |

# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Every evidence marker retains one explicit outcome: passed, failed, skipped, unrun, stale, degraded, or waived; aggregation never relabels a non-pass as passed. | `test:EvidenceTruth.OutcomeAggregationAndRendering` · `test:EvidenceTruth.FinalizationBlocksNonPassingResults` · `review:cr` | 1.1, 2.2, 4.1 |
| REQ-2 | A small plan-local waiver file may satisfy only the exact skipped or degraded marker it names and always renders the outcome as waived. | `test:EvidenceTruth.PlanLocalWaivers` · `test:EvidenceTruth.FinalizationBlocksNonPassingResults` · `review:cr` | 1.2, 2.2, 4.1 |
| REQ-3 | Focused Pester execution uses the current suite runner and emits structured selected/executed test outcomes, including skip, not-run, discovery error, and interruption. | `test:EvidenceTruth.FocusedStructuredResults` · `test:EvidenceTruth.FinalizationBlocksNonPassingResults` · `review:cr` | 2.1, 2.2, 4.1 |
| REQ-4 | Existing verifiers remain execution owners, `Build-EvidenceReceipt.ps1` remains format-only, and PlanCrosscheck blocks on every non-pass/non-waived required marker. | `test:EvidenceTruth.OutcomeAggregationAndRendering` · `test:EvidenceTruth.PlanLocalWaivers` · `test:EvidenceTruth.FinalizationBlocksNonPassingResults` · `test:EvidenceTruth.InstalledParityAndDrift` · `review:cr` | 1.1, 1.2, 2.1, 2.2, 3.1, 4.1 |
| REQ-5 | Existing bundle, dogfood, structural-eval, and repository validation paths keep CI/CIP/autopilot evidence consumers synchronized. | `test:EvidenceTruth.FocusedStructuredResults` · `test:EvidenceTruth.InstalledParityAndDrift` · `review:cr` | 2.1, 3.1, 4.1 |

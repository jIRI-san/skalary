# Code Review result

<!-- skalary/review-result@1 -->
<!-- content-trust: reviewer-authored-data -->

| | |
|---|---|
| **Run** | `3bd44cea-7bc7-400a-9ecf-ace2426ee7a0` |
| **Review type** | `code` |
| **Gate verdict** | **blocked** |
| **Run state** | `degraded` |
| **Scope mode** | `branch` |
| **Base** | b18cf6433bf762dc6b8f43da74487ba2fae240fc |
| **Head** | a3fe926c39b7b08f775ee3cd877b65eb75bc5832 |
| **Scope paths** | 69 |
| **Scope digest** | `sha256:ebfc98dfd5ecbb8d1c4534c5c06eb489356942d2475d17b250a4ce724835b9e8` |
| **Plan digest** | `sha256:66f9faf05808bf3a30560950ae8e14cabe22ed1d6798f366fc0e3157b0672d0d` |

## Attendance

completed=13; failed=1; timed-out=0; omitted=0; cancelled=0; pending=0; planned=14.

## Findings

| Severity basis | Critical | High | Medium | Low | Merged | Raw |
|---|---:|---:|---:|---:|---:|---:|
| Raw | 0 | 10 | 21 | 11 | 42 | 42 |
| Effective | 0 | 10 | 21 | 11 | 42 | 42 |

## Corroboration

| Corroborated | Single source | Suspicious | Degraded | Similarity none | Near duplicate | Exact | Needs review |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 42 | 42 | 0 | 0 | 0 |

## Blocking findings

1. **Effective High (raw High)** — A surviving launcher child can be misclassified as failed after host restart — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
2. **Effective High (raw High)** — Agent-writable scripts can forge terminal close proof — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
3. **Effective High (raw High)** — Cleanup treats a failed preservation probe as permission to delete the container — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
4. **Effective High (raw High)** — Completion advances the target branch without a publication receipt — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
5. **Effective High (raw High)** — Epic completion mutates the checked-out target ref but emits no commit receipt — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
6. **Effective High (raw High)** — Internal retries execute an unpinned remote branch — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
7. **Effective High (raw High)** — Non-success checkpoints are permanent unsupported dead stops — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
8. **Effective High (raw High)** — Preservation-probe failures can destroy the recovery workspace — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
9. **Effective High (raw High)** — Retry-authority tests do not prove production launcher wiring — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed
10. **Effective High (raw High)** — Whole-run timeout teardown is covered only by source matching and a helper unit test — corroboration=degraded; support=1; attendance=degraded; similarity=none; reason=review attendance is degraded; severity elevation suppressed

## Non-blocking needs-review findings

None.

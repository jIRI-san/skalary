# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | Human-owned dependent admission | Only a separately authorized coordinator commit marks 1.1; prior independent partial/no-approval observations stay available. Worker cannot complete human work. `test:docker-human-admission` is a real current comparison of authorization, checkboxes, invocation count and accepted heads, not a static test. | 1.1 |
| REQ-2 | Exact independent output and partial stop | `file:smoke/app-ci/1a4feb/independent.txt#contains:^independent$` and `test:docker-independent-bytes`: exact 12 ASCII bytes, one LF, no CR/BOM; 1.1/1.3/2.1 unchecked and no dependent/second files on first partial return. | 1.2 |
| REQ-3 | Exact dependent output after both prerequisites | `file:smoke/app-ci/1a4feb/dependent.txt#contains:^dependent$` and `test:docker-dependent-bytes`: exact 10 ASCII bytes, one LF, no CR/BOM, independent blob unchanged, both prerequisites committed before fresh visit. | 1.3 |
| REQ-4 | Exact second output and terminal source | `file:smoke/app-ci/1a4feb/second.txt#contains:^second$` and `test:docker-second-bytes`: exact 7 ASCII bytes, one LF, no CR/BOM, both earlier blobs unchanged, Phase 1 closed before fresh Phase 2. Finalization requires current full evidence and `review:cr` bound to the actual completed active-source full commit as `CurrentSource`, the exact ordered `RequestedScope` in design, and unchanged complete typed `ActiveReviewResult` handoff. Inspect later learning/archive/usage diffs and current bytes separately; unavailable supported handoff means incomplete, never report/transcript substitution, rebinding, or rerun. | 2.1 |

Typed `test:` IDs above label results of the concrete current assertions/observations in `design.md`; they are not new installed test commands or already-passing proof.

The wider Docker rollout obligations are operator observations in the design's live evidence matrix, not extra worker steps or prerequisites requiring a worker to prove its own future finalization. Submit their real typed results to the parent only after execution. Missing observation keeps parent human gate 6.2 pending even when this three-file fixture has archived.

---
name: ci
description: 'Continue Implementation — execute confirmed plan criteria with direct evidence and bounded review.'
argument-hint: 'Optional plan reference'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Continue Implementation

Resolve state and admission with existing deterministic plan scripts. Before any checklist, branch,
worktree, log, or source mutation, call installed sibling `DirectWorkflow.psm1`
`Test-PlanCriteriaBaseline`. Refuse missing, uncommitted, ambiguous, or byte-drifted intent,
requirements, risks, or decisions and return to `/cip`; checklist, stage, and worktree markers remain
mutable.

Implement ordinary work directly. A combined Designer/Validator is optional and Judge is the normal
second call. Use two calls by default and five maximum, replacement fallback, at most five supporting
artifacts, and 600/1,200 prompt bounds. For observable background work, compare tool output, file/commit
state, completed subtasks, and blockers across two checks; redirect once, replace once within budget,
then stop. Never kill an agent for elapsed time. Retain deterministic build/test/command timeouts as
evidence.

Run focused validation and call `Invoke-DirectEvidence` for only `test:`, `file:`, and `review:`.
Supply the active in-memory review result, full current source, and exact requested scope; persisted
Markdown is not authority. Keep completed/refused/blocked/stuck/interrupted outcomes distinct. Exit `0`
means completed, operator-action stops retain `42`, and other failures are nonzero.

Non-terminal review is absent unless a concrete changed-scope risk selects one direct event and at most
one corrective replacement. The terminal phase skips post-phase review; finalization runs one whole-plan
direct CR. Never rerun unchanged scope. Exhausted calls or unresolved/incomplete review stops non-clean.
At completion, replace the bounded cited `docs/feedback/recent-learning.md` handoff for `/si`; do not
append a ledger, receipt, replay, or repair state.

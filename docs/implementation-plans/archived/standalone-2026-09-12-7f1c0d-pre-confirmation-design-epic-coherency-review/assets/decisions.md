# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- Run review after the complete draft and before final confirmation so operator-selected edits enter the existing execution baseline.
- Use one `secondary-model-high`/high reviewer call for design; add epic coherency to that same call for epic children.
- Use one `primary-model-high`/high call to evaluate applicability, challenge overengineering, and recommend fix, simplify, defer, or ignore.
- Show every finding even when the recommendation is defer or ignore.
- Let the operator select changes in one consolidated interaction; `/cip` edits only the current plan and does not rerun review.
- Treat reviewer and evaluator output as conversational advice, not evidence or durable state.
- Read epic intent plus targeted sibling intent, ownership, interfaces, dependencies, and decisions; inspect relevant current implementation for completed siblings.
- Do not automatically mutate the epic or sibling plans. If the accepted correction changes the epic cut, return that decision to the epic planning flow.
- Preserve standalone `/dr` safety and read-only behavior; make premium planning routing an explicit caller mode rather than a global replacement.
- Keep the existing `planning-confirmed` digest and `/ci` baseline unchanged.
- Add no confirmation ticket, review receipt, finding ID registry, hash binding, coherency verdict, attendance record, corroboration pass, lifecycle marker, or rerun requirement.
- If either required model call fails or is incomplete, stop visibly instead of substituting a lower-confidence success.

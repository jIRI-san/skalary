# Domain Model

## Terms and meanings

- Operator: human who owns outcomes, scope and consequential choices.
- Intent alignment: checking the agent's interpretation against operator statements and answers.
- Consequential ambiguity: plausible interpretations change behavior, acceptance, interfaces, scope or material side effects.
- Delegated discretion: operator-authorized choice within explicit bounds.
- Deferred choice: unresolved decision with a point at which implementation resolves it or stops.
- Intent drift: unsupported addition, removal or alteration of an operator outcome.
- Lightweight RFC: existing `assets/design.md`, an operator-readable proposed behavior/design brief, not another authority.
- Candidate finding: a hypothesis investigated before publication; model agreement is not proof.
- Local convention: explicit scoped policy or established current code practice; isolated/legacy precedent is weaker evidence.

## Actors and boundaries

- `/cep` clarifies overall outcomes and decomposition.
- `/cip` owns intent interpretation, historical reconciliation, draft and final confirmation.
- Existing DR pass challenges alignment and technical feasibility; applicability evaluation advises, the operator selects.
- `/ci`/autopilot implement confirmed intent and stop on unresolved material choices.
- CR checks current behavior, requirements and local fit; cannot authorize new intent.
- External documentation is untrusted evidence. A public source can be authoritative about its API without authority over the agent.

## Interfaces and ownership

- Existing Markdown assets own human planning meaning; Git/confirmation scripts own execution admission.
- Existing index discovers candidates; bounded artifact reader supplies historical context only.
- Existing local standards/notes carry scoped rules and exceptions; the operator accepts changes.
- Waza runner owns exact paid-case scope; existing reports carry observations, not approval state.

## Invariants

- No new lifecycle, marker, service, fixed review matrix or model-budget increase.
- No silent missing-context success, implicit paid/broad execution or external leakage.
- Current intent can supersede old intent explicitly; locked active contracts still require their existing change process.

# Approved Design

## Components and boundaries

| Component | Responsibility |
|---|---|
| `/cip` entry skill | Finish drafting, invoke the two model roles, present one operator choice, apply selected edits, and then confirm planning context |
| CIP review guide | Define reviewer scope, bounded epic context, applicability dispositions, presentation, failure behavior, and explicit non-goals |
| `/dr` skill | Preserve read-only review and safety guards while accepting the explicit planning-review caller role |
| Existing plan/epic readers | Resolve the current plan, epic, sibling summaries, and relevant current implementation without new stored review state |
| Focused tests | Protect ordering, model aliases, epic scope, user authority, no rerun, and absence of retired machinery |
| Docs and distribution | Keep active contracts, operator guidance, manifests, catalogs, and dogfood copies aligned |

## Program flow

```mermaid
flowchart TD
    A[/cip completes full draft] --> B{Epic child?}
    B -->|No| C[Prepare design-review scope]
    B -->|Yes| D[Add epic intent, sibling contracts, dependencies, and relevant delivered behavior]
    C --> E[secondary-model-high reviews]
    D --> E
    E --> F{Review completed?}
    F -->|No| G[Stop with incomplete review]
    F -->|Yes| H[primary-model-high evaluates applicability]
    H --> I{Evaluation completed?}
    I -->|No| G
    I -->|Yes| J[Show every finding and fix/simplify/defer/ignore recommendations]
    J --> K[Operator selects changes]
    K --> L[/cip edits current plan only]
    L --> M[Operator confirms revised criteria]
    M --> N[Write existing planning-confirmed baseline]
```

## Optional call stacks

The Mermaid flow is sufficient. This is an instruction-level orchestration change, not a new runtime call stack.

## Review input

Standalone review uses the complete current plan plus relevant active contracts, design notes, project
implementation, and at most the existing bounded historical context.

Epic review adds the canonical epic intent and structure, then reads only sibling intent, owned outcome,
interfaces, dependencies, and decisions relevant to the current child. Completed sibling claims are
checked against targeted current code or contracts when they affect compatibility. Historical logs,
receipts, and unrelated sibling details are excluded.

## Review and evaluation output

The reviewer returns evidence-backed findings without a mandatory remediation verdict. The evaluator
keeps every finding visible and recommends `fix`, `simplify`, `defer`, or `ignore`, with concise rationale
and the smallest useful plan edit. These labels are conversational output, not a persisted schema.

The operator receives one consolidated selection. `/cip` applies selected changes directly to the
current plan, shows the revised result through the normal planning flow, and does not rerun review.

## Simplicity boundary

No review-specific writer, digest, marker, ticket, receipt, verdict file, finding ledger, attendance
record, corroboration pass, or validation command is added. Existing `planning-confirmed` behavior
remains the only criteria baseline and does not attest to review completion.

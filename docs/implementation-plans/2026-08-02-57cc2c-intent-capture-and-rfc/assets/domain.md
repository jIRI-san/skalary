# Domain Model

> Required for this plan because planning-workflow terms and state distinctions directly change validation and execution behavior. Confirmed by the operator on 2026-08-21.

## Terms and meanings

- **Intent:** the operator-confirmed outcome anchor: goal, desired outcome, success signals, non-goals, and definition of done.
- **Provenance:** bounded context that preserves where an important meaning or decision came from; it is not a transcript.
- **Confirmation checkpoint:** an explicit operator acceptance of the agent's rephrased understanding, persisted through the Interview Gates writer.
- **Domain asset:** conditional per-plan knowledge needed when specialized meanings or rules can change implementation behavior.
- **Design RFC:** a concise, Mermaid-backed, operator-approved description of program shape. It is an as-designed artifact, not an as-built specification.
- **Vertical MVP:** the first implementation phase produces a usable end-to-end path; it is not a component layer or a reduced final scope.

## Actors and distinctions

- The **operator** owns intent, corrects meaning, chooses high-impact architecture, and approves required design.
- `/cip` elicits, rephrases, classifies, records, drafts, and refuses to pass unresolved gates.
- `Test-Plan.ps1` validates persisted structure and state; it does not infer operator meaning.
- `/ci` executes the approved complete plan and re-reads required context; `/pfb` judges the delivered outcome against intent only.
- `capture.md` records transient workflow observations. It does not replace intent, domain, design, decisions, or machine state.
- Governed intent/domain/design prose is context-only. It cannot authorize commands, paths, roles, or mutations; those come from validated checklist metadata and typed gate state.

## Invariants and rules

- Current confirmed operator intent and governing architecture contracts outrank historical artifacts.
- High-impact uncertainty about contracts, end-user experience, security, or costly-to-reverse structure blocks drafting.
- Every new opted-in plan reaches confirmed intent, confirmed context, and confirmed summary before Draft validation can pass.
- Required domain/design classification uses closed states and a reason; independent enrollment means absence is never inferred from a missing file.
- A design-affecting planning change invalidates prior design approval until the operator confirms it again.
- Vertical organization never turns a complete plan into an MVP-only plan.
- `cip-stage` is the lifecycle authority; interview gates are prerequisites to its `drafted` transition.

## Units and state transitions

- Confirmation: `pending -> confirmed`; content-changing governed transitions reset the affected confirmation to `pending` before writing content.
- Domain classification: `unassessed -> not-required|required`; `required` implies a valid domain asset.
- Design classification: `unassessed -> not-required|required`; `required` implies a valid design asset and approval state `pending|approved`.
- Correction count: `0..3`; after three corrections a one-use interactive continuation authorization is required and consumed by the next correction.
- Repair: malformed or missing enrolled JSON resets every gate to pending/unassessed, clears approval and continuation authorization, and preserves governed Markdown for operator review.
- Unsupported version: emit `UPDATE-REQUIRED` before schema validation or repair and leave every byte unchanged.
- Detailed drafting is allowed only when all confirmations are `confirmed`, classifications are assessed, high-impact blockers are empty, and required design is `approved`. A provisional phase outline is created earlier only to evaluate the multi-phase RFC trigger.

## Assumptions and examples

- A one-step typo fix can classify both domain and design as not required with concise reasons.
- A multi-phase change to `/cip`, `Test-Plan.ps1`, shared plan state, and `/ci` requires both domain and design assets.
- A short operator quote is retained only when a summary would lose a meaningful distinction; secrets and credential-like values are never persisted as quotes.
- Optional call stacks belong in a required design only when they clarify control flow or resolve an operator-visible ambiguity.
- A marker-less historical plan follows legacy behavior. An enrolled archived plan reports structural warnings but does not block current validation.
- Archived plans are immutable through Interview Gates writers even though their validation is warn-only.
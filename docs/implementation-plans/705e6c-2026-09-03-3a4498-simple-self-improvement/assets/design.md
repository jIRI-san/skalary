# Approved Design

## Components and boundaries

- **Bounded reader.** Keep `Get-SiHarvest.ps1` as a read-only adapter over the one committed
  recent-learning handoff. Remove receipt issuance and all state-store dependencies while retaining
  strict source-plan, source-commit, ancestry, citation, size, count, secret, and fence checks.
- **Direct `/si`.** Resolve the selected or latest completed plan and current Git base, read the handoff,
  verify cited repository evidence, rank no more than five proposals, and present equivalent informed
  choices in VS Code and Copilot CLI. No selection means no mutation.
- **Canonical write guard.** Validate planned targets before mutation and resulting touched paths after
  mutation. Allow only `.github/copilot-instructions.md`, `plugins/*/skills/**/*.md`,
  `plugins/*/agents/**/*.md`, `plugins/*/prompts/**/*.md`, `docs/design-notes/**/*.md`, and
  `docs/architecture-notes/**/*.md`. Physical path escape, workflows/actions, generated copies,
  executable code, plans, and runtime state are closed refusals.
- **Local application.** Apply selected edits in the current worktree. If a selected target already has
  unrelated edits, stop for operator action. When canonical plugin Markdown changes, run the existing
  trusted synchronization sequence; generated outputs are mechanical consequences, not direct SI
  targets. Show the complete diff and focused validation. Failure leaves the diff visible.
- **Stateless `/pfb`.** Preserve the evidence-cited five-section comparison and `full|partial|missed`
  verdict. Do not persist it. If the operator wants a correction, pass the accepted correction directly
  to `/cip`; headless completion skips feedback.
- **Retirement cut.** Delete the queue, due, run, receipt, CAS, repair, archive, cross-repository,
  worktree/branch/PR, schema, scaffold, and compatibility surfaces together with their callers and tests.

## Program flow

```mermaid
flowchart TD
    A[Invoke SI] --> B[Read committed recent-learning handoff]
    B --> C{Input state}
    C -->|missing or empty| D[Report no candidates and stop]
    C -->|stale or invalid| E[Fail visibly]
    C -->|valid| F[Verify cited repository evidence]
    F --> G[Rank at most five proposals]
    G --> H[Present equivalent informed choices]
    H --> I{Any proposal selected?}
    I -->|No| D
    I -->|Yes| J[Check canonical target and local edit state]
    J -->|Refused or conflicting| E
    J -->|Allowed| K[Apply selected local edits]
    K --> L{Canonical plugin Markdown changed?}
    L -->|Yes| M[Run existing trusted synchronization]
    L -->|No| N[Run post-write scope and focused validation]
    M --> N
    N --> O[Show complete diff and result]

    P[Invoke interactive PFB] --> Q[Compare delivered work with intent]
    Q --> R[Ask for alignment and corrections]
    R --> S{Correction plan selected?}
    S -->|Yes| T[Hand accepted correction to CIP]
    S -->|No| U[Stop without persistence]
```

## Optional call stacks

The Mermaid flow is sufficient. The retained scripts perform bounded reads, path checks, and existing
repository synchronization; plain skill instructions own ranking and interaction.

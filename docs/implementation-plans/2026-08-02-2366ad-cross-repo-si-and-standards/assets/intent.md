# Intent

> Preliminary context captured from epic `33b1f9` and its planning discussion. `/cip` must confirm and refine it.

## Goal

Make self-improvement learned in a consumer repository reach the upstream customization source safely, while reconciling which review standards are generic versus repository-specific.

## Desired outcome

A consumer-side `/si` run produces a durable, typed candidate artifact under a narrow harvest-only write scope. Proposal work then runs in a real upstream checkout under upstream instructions and either creates a small reviewable change or feeds a normal `/cip` plan for larger work.

## Success signals

- Installed plugin copies in a consumer repository are never edited as if they were upstream source.
- Every harvest and proposal outcome has a durable record, including declined candidates.
- Cross-repo evidence is identified as a claim and re-judged against current upstream code and standards.
- The proposal path cannot write steering files outside its phase-specific allowlist or merge autonomously.

## Non-goals

- A free-form autonomous `/si` writer outside the normal plan contract.
- Automatic merge or silent promotion of consumer-specific rules into generic standards.
- Treating a consumer repository's instructions as if they governed the upstream checkout.

## Definition of done

- A consumer run can carry a typed, version-pinned learning into an upstream-rooted review or implementation plan without editing disposable installed copies.
- Promotion and rejection decisions remain inspectable after the session ends.

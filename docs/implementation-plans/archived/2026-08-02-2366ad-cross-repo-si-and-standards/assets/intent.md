# Intent

> Confirmed by the operator on 2026-08-21. Initial context came from epic `33b1f9` and its planning discussion.

## Goal

Make self-improvement learned in a consumer repository reach the upstream customization source safely, while reconciling which review standards are generic versus repository-specific.

## Desired outcome

A consumer-side `/si` run exports one bounded typed candidate artifact. Proposal work then runs in a clean upstream checkout under upstream instructions and uses normal upstream `/si` for small changes or `/cip` for larger work. Separately, a repository may provide a small local review-standards file that is reconciled with generated generic guidance.

## Success signals

- Installed plugin copies in a consumer repository are never edited as if they were upstream source.
- Export and upstream handling retain enough identity and outcome context to explain what was carried and what the upstream workflow decided.
- Cross-repo evidence is identified as a claim and re-judged against current upstream code and standards.
- The proposal path cannot write steering files outside its phase-specific allowlist or merge autonomously.
- CR and DR consume generic standards from the `79cfe1` source model plus an optional repo-owned local file without changing review-run v1 authority.

## Non-goals

- A free-form autonomous `/si` writer outside the normal plan contract.
- Automatic merge or silent promotion of consumer-specific rules into generic standards.
- Treating a consumer repository's instructions as if they governed the upstream checkout.
- Cache generations, paged history, a dedicated container platform, dependency receipts, a global evidence registry, or review-run v2.

## Definition of done

- A consumer run can carry a typed, version-pinned learning into an upstream-rooted review or implementation plan without editing disposable installed copies.
- Generic-versus-local standards resolve deterministically through the existing concern generator and review dispatch path.

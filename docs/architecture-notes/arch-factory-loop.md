---
contract_id: ARCH-Factory-Loop
title: Bounded issue-to-production factory loop
maturity: provisional
applies_to:
  - plugins/factory-loop/**
---

# ARCH-Factory-Loop

## Contract

- The selected consumer repository is explicit on every command; plugin installation roots are
  never inferred as consumer state.
- One local plugin and checkpoint/lock own one active chain per project. A finite poll is
  deterministic and zero-AI; the operator owns scheduling.
- Project-owned scripts are the live provider boundary. Loopback is clearly simulated; no bundled
  live provider integrations, hosted Skalary service, database, or agent swarm.
- A mutation has a durable operation ID before dispatch. Restart reconciliation must recover the
  same provider identity or stop visibly as inconclusive.
- Confirmed plan criteria are immutable. Initial admission follows ordinary `/ci`; preauthorized
  repair is bounded, uses a distinct successor PR, and cannot edit criteria or confirmation state.
- Human PR merge and fresh artifact-specific production approval remain mandatory. Production
  validation and evidence must identify the same immutable merge-derived artifact.
- Evidence is sanitized, secret-screened, separate from deployment-triggering branches, and
  published before issue closure. Unverified access or branch exclusion blocks progress.
- Deterministic tests use actual local Git/code acceptance, injected clocks, and simulated providers;
  Waza evaluations are opt-in and never run as a deterministic gate.

## Change control

Changing these boundaries requires explicit operator confirmation and an update to the confirmed
implementation plan. A behavior change must not be smuggled in through repair, adapter defaults, or
evidence serialization.

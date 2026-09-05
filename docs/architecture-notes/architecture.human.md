<!-- LEGACY JSON CONTRACT COMPATIBILITY VIEW.
     This derived artifact covers only the transferred JSON contracts that remain under
     schemas/architecture/. Markdown architecture notes are already human-readable and are not
     duplicated here. This file is excluded from AI auto-load.

     Freshness is tracked by the canonical content hash of the contract sources embedded in the
     marker below. Test-ArchDocFreshness recomputes it and flags drift. -->
<!-- arch-contracts-sha256: c22d12c67ecce4aaba38c40b09339c3b0d06cc7d9849516870b43fb30bc50a26 -->

# Skalary — Architecture Overview

> Temporary view of the remaining legacy JSON contracts. The indexed Markdown notes are the
> authoritative human-readable architecture.

## Purpose & Scope

<!-- Narrative: what the system is, its top-level goals, and the boundaries it maintains. -->

<!-- Do not hand-edit the generated region below; edit a legacy JSON contract and regenerate. -->
<!-- BEGIN GENERATED: contracts -->

## System Diagram

```mermaid
graph TD
  ARCH_Install_Confinement["Installer .github confinement"]
  ARCH_Review_Run_V1["Review-run v1 authority and evidence"]
```

## Components

### Installer .github confinement

- **Governing contract:** `ARCH-Install-Confinement` (provisional)
- **Boundary:** Security boundary: untrusted plugin metadata and recovery state can never cause mutation outside .github/ or through linked parents. Enforced by confinement, link rejection, the shared mutation lock, journal validation, and registry/install/remove tests.

### Review-run v1 authority and evidence

- **Governing contract:** `ARCH-Review-Run-V1` (provisional)
- **Boundary:** Defines the interface-level boundary between frozen review scope, published execution authority, verified delivery, and compact durable plan evidence.

<!-- END GENERATED: contracts -->

## Decision Records

<!-- Human-readable narrative of active ADRs, with links to the source records in the AI tier
     and any external resources. Superseded ADRs are summarized/archived, not deleted. -->

## Resources

<!-- Links: external docs, RFCs, diagrams, discussions. -->

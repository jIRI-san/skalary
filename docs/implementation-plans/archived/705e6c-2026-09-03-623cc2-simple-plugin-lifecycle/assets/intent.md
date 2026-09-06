# Intent

Preliminary context captured by /cep; /cip must confirm and refine it.

## Goal

Make plugin install, update, removal, retirement, and registry consumption a small direct workflow
for one trusted operator while keeping the concrete path and external-format protections that prevent
damaging a consumer repository.

## Desired outcome

Stable direct commands perform plugin lifecycle operations under the consumer `.github` tree, fail
loudly, verify their in-memory result, and converge when rerun unchanged. One minimal per-plugin
installed-version receipt remains so list/update/remove can identify the installed version and immutable
source without a shared lockfile. Journals, file-ownership receipts, CAS, repair, automatic retirement
state, and compatibility machinery disappear. External plugin, registry, and marketplace JSON remains.

## Success signals

- Every target is canonicalized and confirmed under the consumer `.github` root before writing.
- Install/update/remove report success only after expected manifest-owned paths match the in-memory result.
- A receipt contains only plugin identity, version, source identity, and immutable ref; it is advanced
  after payload verification and removed after successful deletion.
- An unchanged rerun produces no further change.
- Unforced removal refuses before mutation when any present installed-manifest path differs from its
  pinned payload.
- Focused negative tests cover path escape, retired/unowned/modified refusal, and mutation outcomes.
- Journals, locks, backups, signing/file-ownership receipts, CAS, repair flows, automatic retirement,
  and internal lifecycle schemas/state are absent.
- Required plugin, registry, and marketplace JSON remains compatible with external consumers.
- Commands are direct, stable, and suitable for explicit operator approval.

## Non-goals

- Protecting against malicious third-party contributors or coordinating concurrent operators.
- Building crash recovery, rollback transactions, journaling, ownership receipts, or repair services.
- Converting externally mandated plugin/registry/marketplace JSON to Markdown.
- Preserving operator edits inside receipt-owned plugin paths during an explicit update.
- Migrating or dual-reading legacy receipt and retirement-state formats.
- Changing review, plan, autopilot, or SI behavior.

## Definition of done

- The trusted operator can install, update, remove, and retire plugins safely through direct commands;
  minimal receipts still identify installed versions; external catalogs still work; obsolete lifecycle
  machinery is gone; and the focused lifecycle tests complete within the baseline timing contract.

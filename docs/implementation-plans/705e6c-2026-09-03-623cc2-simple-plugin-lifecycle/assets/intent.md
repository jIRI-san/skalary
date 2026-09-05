# Intent

Preliminary context captured by /cep; /cip must confirm and refine it.

## Goal

Make plugin install, update, removal, retirement, and registry consumption a small direct workflow
for one trusted operator while keeping the concrete path and external-format protections that prevent
damaging a consumer repository.

## Desired outcome

Stable direct commands perform plugin lifecycle operations under the consumer `.github` tree, fail
loudly, verify their in-memory result, and converge when rerun unchanged. Journals, receipts, CAS,
repair, and compatibility machinery disappear. JSON remains only for plugin, registry, and
marketplace interfaces that external consumers require.

## Success signals

- Every target is canonicalized and confirmed under the consumer `.github` root before writing.
- Install/update/remove report success only after expected manifest-owned paths match the in-memory
  result.
- An unchanged rerun produces no further change.
- Focused negative tests cover path escape, refusal, and mutation outcomes.
- Journals, signing/install receipts, CAS, repair flows, and internal lifecycle schemas/state are
  absent.
- Required plugin, registry, and marketplace JSON remains compatible with external consumers.
- Commands are direct, stable, and suitable for explicit operator approval.

## Non-goals

- Protecting against malicious third-party contributors or coordinating concurrent operators.
- Building crash recovery, rollback transactions, journaling, ownership receipts, or repair services.
- Converting externally mandated plugin/registry/marketplace JSON to Markdown.
- Changing review, plan, autopilot, or SI behavior.

## Definition of done

- The trusted operator can install, update, remove, and retire plugins safely through direct commands;
  external catalogs still work; obsolete lifecycle machinery is gone; and the focused lifecycle tests
  complete within the baseline timing contract.

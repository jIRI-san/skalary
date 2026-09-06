# Intent

## Goal

Exercise the real container autopilot completion lifecycle after the archived-plan close detector fix.

## Desired outcome

One disposable file is committed, the plan is completed and archived, and container autopilot exits
successfully without exhausting same-session completion handoffs.

## Success signals

- The launcher returns exit `0`.
- The transcript does not report that plan completion remained `close-pending`.

## Non-goals

- Production behavior changes.
- Merging the throwaway pull request.

## Definition of done

- The disposable implementation step is complete and the real container close detector reports terminal
  completion.

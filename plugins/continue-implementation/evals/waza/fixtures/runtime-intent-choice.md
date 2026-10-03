# Selected implementation plan and live discovery

## Confirmed intent

- REQ-1: An export link is available to the requester.
- REQ-2: An export link is available to the requester's owners for 24 hours.
- Bounded discretion: choose a retry delay from 1–5 seconds; do not ask the OP to choose one.

## Current progress

- Step 1.1 is complete and committed.
- Step 1.2 is in progress; local changes are uncommitted and must be preserved.
- Step 1.3 has not started.

## New implementation discovery

The existing owner list can include external guest operators. The confirmed phrase
"requester's owners" has two materially different interpretations for these accounts:
include external guests, allowing them to download exported data, or restrict links to
internal owners, excluding guests. The plan has no rule for external guests, and the
choice changes the authorized audience for potentially sensitive exports.

No code change has been made for this discovery.

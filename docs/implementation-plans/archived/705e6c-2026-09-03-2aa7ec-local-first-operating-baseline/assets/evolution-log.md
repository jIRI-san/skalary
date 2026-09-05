# Design evolution

Operator-approved scope and constraints are recorded in `assets/intent.md` and
`assets/decisions.md`. This file records review chronology only.

## Rounds

### Round 1

- **Run:** `88051789-2386-4c23-af87-18cc5a10b6ac`
- **Attendance:** 3 planned, 3 completed, 0 failed.
- **Issues found:** two false-positive injection findings, six High local-boundary findings, and four
  Medium evidence/ownership findings.
- **Issues fixed:** neutralized the log wording; confined focused inputs; defined direct-child timeout
  and exit semantics; coupled each format deletion to its producer/consumer update; defined
  operator-only as an explicit direct CLI path; moved authoritative note/contract updates beside
  workflow deletion; bound transfer rows to canonical child IDs.
- **Issues rejected:** permanent inventory parser/policy authority, operator authentication,
  transaction/receipt machinery, and duplicate classification gates.
- **Issues deferred:** none.

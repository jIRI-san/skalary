## Learnings Capture
Phase: 1

- [1.2] [trigger:reusable-pattern] [concern:operability-observability] [req:REQ-5] [review:none] [source-record:8d59e0d33c725ca6334cf41cd40d2dbb633b150dde533a5e63057e77899c572e] Legacy design-review captures must be converted through Add-WorkflowNote before the typed phase harvest can publish a receipt.

## Learnings Capture
Phase: 2

- [2.1] [trigger:reusable-pattern] [concern:correctness-reliability] [req:REQ-2] [review:cr] [source-record:7e76d42abc2c4e155282df17a7c8ef18f98c121744193314e6e0193b576630d1] PowerShell WhatIf preference propagates into nested writers; preview artifacts need an explicit ShouldProcess boundary and durable state should use AtomicStore.
- [2.2] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-4] [review:cr] [source-record:8341cc3d16c52b48a4907e3d7e729c5b19b87e46e3f81eb2d05be2d9d9529ac6] ConvertFrom-Json can surface a single nested array element as a scalar in this PowerShell path; normalize entries with array wrapping and validate each element instead of requiring System.Array.
- [2.2] [trigger:rework>1] [concern:testing-evidence] [req:REQ-2,REQ-3,REQ-4] [review:none] [source-record:5128ee0bf94b2bb6f9bd292f15acbdce3fa455ebeb821a5b033cc7adc4d28c2d] Filtered Pester runs retain excluded cases as NotRun and append descriptive text to test names; evidence guards must match executed marker prefixes instead of aggregate NotRunCount or exact names.

## Learnings Capture
Phase: 3

- [3.1] [trigger:reusable-pattern] [concern:architecture-patterns] [req:REQ-1] [review:cr] [source-record:fb787b17e3fac542726723cb685fec1ae7bfc3a0261295bf19b69106485a1c23] Keep folder-name parsing pure and shared so worktree and pinned-tree inventories cannot drift across naming migrations.

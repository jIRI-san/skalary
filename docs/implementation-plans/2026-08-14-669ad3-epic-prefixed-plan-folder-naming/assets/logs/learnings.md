## Learnings Capture
Phase: 1

- [1.2] [trigger:reusable-pattern] [concern:operability-observability] [req:REQ-5] [review:none] [source-record:8d59e0d33c725ca6334cf41cd40d2dbb633b150dde533a5e63057e77899c572e] Legacy design-review captures must be converted through Add-WorkflowNote before the typed phase harvest can publish a receipt.

## Learnings Capture
Phase: 2

- [2.1] [trigger:reusable-pattern] [concern:correctness-reliability] [req:REQ-2] [review:cr] [source-record:7e76d42abc2c4e155282df17a7c8ef18f98c121744193314e6e0193b576630d1] PowerShell WhatIf preference propagates into nested writers; preview artifacts need an explicit ShouldProcess boundary and durable state should use AtomicStore.

## Learnings Capture
Phase: 1

- [1.4] [trigger:reusable-pattern] PowerShell `return , $array` preserves array-ness for direct assignment but, when the function output is piped, yields the whole array as one item — `$_.Prop` then hits member-enumeration (silently flattens for non-empty, throws under StrictMode for empty). Prefer `return $array.ToArray()` and wrap call sites with `@(...)`.

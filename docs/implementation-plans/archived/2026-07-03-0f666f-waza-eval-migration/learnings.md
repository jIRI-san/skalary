## Learnings Capture
Phase: 1

No entries for this phase.

## Learnings Capture
Phase: 2

- [2.4] [trigger:reusable-pattern] waza code-grader gotchas: (1) use language: javascript, NOT python (python is a Windows Store alias stub, absent from dev/CI PATH; node is guaranteed in an npm repo). (2) the code grader's tool_calls entries have keys name/arguments/result; match ONLY c.arguments -- JSON.stringify(c) includes result, and a VIEW result carries a 'diff --git ...' header + text saying 'commit' that falsely satisfies /git.*commit/ at an early index. (3) 'waza grade <spec> --task <id> --results <json>' re-runs graders against a captured run for FREE (no agent exec), great for iterating deterministic graders; BUT prompt graders with continue_session:true fail in grade mode, so grade a temp spec stripped of the judge. (4) a bounded self-contained fixture + tightly-scoped prompt keeps a real-execution eval in-band and cheap, unlike an unbounded --allow-all agent.

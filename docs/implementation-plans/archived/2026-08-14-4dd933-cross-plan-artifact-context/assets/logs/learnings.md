## Learnings Capture
Phase: 1

- [1.2] [trigger:rework>1] [concern:correctness-reliability] [req:REQ-2] [review:cr] [source-record:4a048ad166d3f49b4bbe1bda4f4ca2f896e934b9bbe13bae4e465cc18c751487] Race-safe file confinement requires OS-resolved opened-handle identity and link-count checks; pathname plus length is not an identity proof

## Learnings Capture
Phase: 2

- [2.2] [trigger:rework>1] [concern:testing-evidence] [req:REQ-4] [review:none] [source-record:f4c7efa4e52c86186b3e3c6c5d3809a517dc6bbc48fd9f2f588ec23a1525356d] Markdown contract tests must match semantic whitespace across wrapped lines rather than requiring one physical line

## Learnings Capture
Phase: 3

- [3.1] [trigger:rework>1] [concern:testing-evidence] [req:REQ-5] [review:none] [source-record:f5ea0f5c94c1beb73fc0d12bec4c8db9c4ba38af90f6dc07485f9414e85a5cb5] Assets-layout consumer fixtures must include assets/requirements.md because layout authority is anchored on that file rather than the assets directory
- [3.2] [trigger:rework>1] [concern:testing-evidence] [req:REQ-5] [review:none] [source-record:d6a35303c7b70e238896816e4a358fd199d5ecbe5c8c7ca5bf16256000e3417d] Typed evidence cases must live in a Fast-owned test file because evidence IDs and Slow-file TestName filters are intentionally mutually exclusive

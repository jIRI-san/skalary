# Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Alignment becomes repeated interrogation or an added mandatory reviewer. | Medium | High | Ask only consequential questions; reuse checkpoints/two existing passes. Stop for OP if new calls or gates are proposed. | 1.1, 1.2 |
| RISK-2 | Bounded history misses a relevant conflict or stale intent becomes a veto. | Medium | Medium | Intent-aware discovery, explicit citations/scope, current-contract precedence and OP supersession. Missing/unindexed history remains visible. | 1.1 |
| RISK-3 | Git protects bytes while implementation misreads unchanged meaning. | Medium | High | OP wording remains distinct; scenarios test semantic drift and runtime stop conditions. Return material choices to planning, not silent edits. | 1.2 |
| RISK-4 | Stronger evidence becomes false certainty, keyword gaming or demand for executable proof of every issue. | Medium | High | Positive/negative scenarios, reviewed expected answers, semantic rubrics and valid static traces. Structural passes do not establish performance. | 2.1, 3.2 |
| RISK-5 | Official web content injects instructions or queries leak private data. | Medium | High | Public technology/version queries only; fetched text stays untrusted read-only evidence. Refuse privileged actions/private queries; stop if safe lookup is unavailable. | 2.2 |
| RISK-6 | Best practices ignore local exceptions or existing defects become mandatory precedent. | Medium | Medium | Identify policy versus current practice versus legacy. Cite concrete failures; no unrelated modernization or rule handbook. | 2.2 |
| RISK-7 | Shared instructions and generated consumers drift or the change grows machinery. | Medium | High | Update source and docs per vertical slice; existing generators and selected consumer tests. No manual generated edits, new schemas or lifecycle state. | 1.2, 2.3, 4.2 |
| RISK-8 | Named paid eval silently runs an unrelated pack; long/full runs become routine. | High | High | Validate exact case before spending; selected case means functional-only/one trial. Preserve explicit full behavior; separate OP approval, local runs and existing report/isolation rules. | 3.1, 3.2, 4.1 |

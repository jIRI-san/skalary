# Risks

<!-- For uncertain or high-impact work, the mitigation names the concrete stop/escalation condition. -->

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Throwaway artifacts could be mistaken for production changes. | Low | Low | Keep the proof isolated, do not merge its pull request, and remove it after observing the launcher result. | 1.1 |

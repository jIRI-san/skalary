# Testing Ledger

- [2026-06-28] Extract launcher dispatch into a side-effect-free dot-sourceable library so loop logic is unit-testable without the launcher's mandatory params avoids Pester mandatory-param prompt hang . Share test state via .GetNewClos (plan-aaf29b, src:ci, sev:Med) #dot-source #pester #testability
- [2026-06-28] Mock the script's own restore helpers Invoke-NpmRestore/Invoke-DotnetRestore instead of external npm/dotnet: real npm ci runs ~20s and isn't intercepted by Pester mocks. Avoid angle brackets in It names ParseException . (plan-aaf29b, src:ci, sev:Med) #mocking #npm #pester


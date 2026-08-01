@{
    # Single source of truth for every model name a committed agent or autopilot config
    # may declare. Read by scripts/skalary/Test-ModelAllowlist.ps1 via
    # Import-PowerShellDataFile. Plan b0c0d3 REQ-7.
    #
    # Two name formats exist and are NEVER normalized into one another:
    #   * VS Code-hosted agents use the qualified `Model Name (vendor)` form.
    #   * Copilot CLI-hosted agents (and .autopilot.json `model`) use a bare slug.
    # Writing a qualified name into a CLI-hosted agent breaks autonomous execution,
    # which is exactly the drift this manifest exists to catch.

    ManifestVersion = 1

    # Qualified names for VS Code-hosted agents.
    VSCodeModels = @(
        'Claude Opus 5 (copilot)'
        'GPT-5.6 Sol (copilot)'
        'Claude Sonnet 4.6 (copilot)'
    )

    # Bare slugs for Copilot CLI-hosted agents and for the `model` field of
    # .autopilot.json / .autopilot.json.example.
    CliModels = @(
        'claude-opus-5'
        'gpt-5.6-sol'
        'claude-sonnet-4.6'
    )

    # Closed, committed agent -> host map. Host is NOT inferable from folder layout:
    # "anything under plugins/autopilot/ is CLI" silently misclassifies the next CLI
    # agent added elsewhere. Any agent file whose frontmatter `name` is absent from
    # this map is a hard error, never a silent default.
    AgentHosts = @{
        'autopilot'                        = 'Cli'

        'cr'                               = 'VSCode'
        'cr-security'                      = 'VSCode'
        'cr-correctness-reliability'       = 'VSCode'
        'cr-architecture-patterns'         = 'VSCode'
        'cr-performance'                   = 'VSCode'
        'cr-testing-evidence'              = 'VSCode'
        'cr-maintainability-consistency'   = 'VSCode'
        'cr-operability-observability'     = 'VSCode'

        'dr'                               = 'VSCode'
        'dr-security'                      = 'VSCode'
        'dr-correctness-reliability'       = 'VSCode'
        'dr-architecture-patterns'         = 'VSCode'
        'dr-performance'                   = 'VSCode'
        'dr-testing-evidence'              = 'VSCode'
        'dr-maintainability-consistency'   = 'VSCode'
        'dr-operability-observability'     = 'VSCode'
    }

    # GA model passed as the EXPLICIT dispatch parameter when the orchestrator detects a
    # Copilot Pro tier, where the two reviewer models are unavailable. A frontmatter
    # fallback array does not help: explicit-param dispatch outranks frontmatter, so the
    # array is never consulted (RISK-2). Each value must be a member of its own list.
    Fallback = @{
        VSCode = 'Claude Sonnet 4.6 (copilot)'
        Cli    = 'claude-sonnet-4.6'
    }

    # Vendors/models that must not appear anywhere in an agent file — not in
    # frontmatter, not in prose, not in a dispatch roster. Gemini is dropped because it
    # is still Public preview and unavailable in Copilot CLI.
    DeniedPatterns = @(
        '(?i)gemini'
    )
}

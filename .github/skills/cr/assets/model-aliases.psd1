@{
    # Single source of truth for model aliases and the host identifiers they resolve to.
    # Skills and operator-facing configuration use aliases. Only host-facing generated
    # bindings use concrete provider model names.
    #
    # Two host formats exist and are NEVER inferred from one another:
    #   * VS Code-hosted agents use the qualified `Model Name (vendor)` form.
    #   * Copilot CLI and waza use a bare slug.

    ManifestVersion = 2

    Aliases = @{
        'primary-model-low' = @{
            Cli    = 'gpt-6.1-sol'
            VSCode = 'GPT-6.1 Sol (copilot)'
        }
        'primary-model-mid' = @{
            Cli    = 'gpt-6.1-sol'
            VSCode = 'GPT-6.1 Sol (copilot)'
        }
        'primary-model-high' = @{
            Cli    = 'gpt-6.1-sol'
            VSCode = 'GPT-6.1 Sol (copilot)'
        }
        'secondary-model-low' = @{
            Cli    = 'gpt-6.1-sol'
            VSCode = 'GPT-6.1 Sol (copilot)'
        }
        'secondary-model-mid' = @{
            Cli    = 'gpt-6.1-sol'
            VSCode = 'GPT-6.1 Sol (copilot)'
        }
        'secondary-model-high' = @{
            Cli    = 'gpt-6.1-sol'
            VSCode = 'GPT-6.1 Sol (copilot)'
        }
    }

    Roles = @{
        Routine = @{
            Primary         = 'primary-model-low'
            Fallback        = 'secondary-model-low'
            ReasoningEffort = 'medium'
        }
        Standard = @{
            Primary         = 'primary-model-mid'
            Fallback        = 'secondary-model-mid'
            ReasoningEffort = 'high'
        }
        Deep = @{
            Primary         = 'primary-model-high'
            Fallback        = 'primary-model-mid'
            ReasoningEffort = 'high'
        }
        Independent = @{
            Primary         = 'secondary-model-high'
            Fallback        = 'secondary-model-mid'
            ReasoningEffort = 'high'
        }
        WazaExecutor = 'primary-model-low'
        WazaJudge    = 'primary-model-mid'
    }

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

    # Replacement slots retain their public aliases. Equal resolved host bindings are
    # not availability fallbacks: stop if Sol is unavailable, rather than retry by alias.
    Fallback = @{
        VSCode = 'secondary-model-mid'
        Cli    = 'secondary-model-mid'
    }

    # Providers that are unavailable to the operator must not appear anywhere in an
    # agent file — not in frontmatter, prose, or a dispatch roster.
    DeniedPatterns = @(
        '(?i)anthropic|claude'
    )
}

@{
    # Single source of truth for every tool the Tier-2 (waza) LLM-eval harness
    # provisions. Read by scripts/skalary/Ensure-EvalTools.ps1 (the ONLY provisioner)
    # via Import-PowerShellDataFile. Plan 0f666f REQ-1 / REQ-19 / REQ-21.
    #
    # InstallDir tokens resolved by Ensure-EvalTools at runtime (cross-platform):
    #   %LOCALAPPDATA% -> $env:LOCALAPPDATA (Windows)
    #   %HOME%         -> $HOME / $env:USERPROFILE
    # No other tokens are supported; the manifest holds no runtime-expanded paths.

    ManifestVersion = 1

    # waza eval-spec schemaVersion the shipped specs target. Ensure-EvalTools asserts
    # the pinned binary supports this and fails fast on mismatch (REQ-21 schema-compat).
    # The adversarial: block (REQ-23) requires >= 1.2; the PoC eval.yaml used 1.0.
    SpecSchemaVersion = '1.2'

    # Every entry is provisioned ONLY through Ensure-EvalTools. Present==pin -> OK;
    # present<pin -> run as-is (never auto-change); missing -> explicit-approval install
    # of the pinned version; newer-than-pin surfaced only via opt-in --check-updates.
    Tools = @(
        @{
            Name = 'waza'
            Version = '0.38.0'
            # 'exact': the pinned version is installed and byte-verified against the
            # committed Sha256 below (reproducible). Contrast gh's 'floor' policy.
            VersionPolicy = 'exact'
            Source = 'github-release'
            Repo = 'microsoft/waza'
            Tag = 'v0.38.0'

            # copilot-sdk (the headless Copilot executor) is embedded in the waza
            # binary — no separate pin or install.
            Embeds = @('copilot-sdk')

            # The stock install.ps1 / install.sh pull *latest* and are NOT used.
            # Assets are resolved from the pinned release by <os>-<arch> key below.
            InstallMethod = 'download-binary'

            # Committed SHA256 constants (DR-20 / REQ-21) applied to BOTH online
            # downloads and OfflinePath vendored binaries. Provenance: the release's
            # published checksums.txt (a pin bump re-derives these from that file).
            ChecksumProvenance = 'https://github.com/microsoft/waza/releases/download/v0.38.0/checksums.txt'

            Assets = @{
                'windows-amd64' = @{
                    File = 'waza-windows-amd64.exe'
                    Sha256 = 'ff7fe521d4f876de29d018a00fe282746109d8b788a6e9a9f288dbd8a3470364'
                    BinaryName = 'waza.exe'
                    InstallDir = '%LOCALAPPDATA%/Microsoft/Waza'
                }
                'windows-arm64' = @{
                    File = 'waza-windows-arm64.exe'
                    Sha256 = '228da5775566f863a61f9c9d782f0b9dab2c4962ffcc7e9a400fbcc68b97bc91'
                    BinaryName = 'waza.exe'
                    InstallDir = '%LOCALAPPDATA%/Microsoft/Waza'
                }
                'linux-amd64' = @{
                    File = 'waza-linux-amd64'
                    Sha256 = '9d274f563e0f05b50d56f0223c03bdc561180ffea13662583188ecc042a9fe15'
                    BinaryName = 'waza'
                    InstallDir = '%HOME%/.local/share/waza/bin'
                }
                'linux-arm64' = @{
                    File = 'waza-linux-arm64'
                    Sha256 = 'a199b74cd39820704dadd8b0dc87234c49def7fc4746d8a1076d7a2ee7e53c95'
                    BinaryName = 'waza'
                    InstallDir = '%HOME%/.local/share/waza/bin'
                }
                'darwin-amd64' = @{
                    File = 'waza-darwin-amd64'
                    Sha256 = 'ab7e45d5fd6c28ca61830ead38406359fe02607973252200e06898fac9359b3c'
                    BinaryName = 'waza'
                    InstallDir = '%HOME%/.local/share/waza/bin'
                }
                'darwin-arm64' = @{
                    File = 'waza-darwin-arm64'
                    Sha256 = 'dee99f17b65f148e197e2a94302c13a467f7df83e210d9ae81884f80d25f4183'
                    BinaryName = 'waza'
                    InstallDir = '%HOME%/.local/share/waza/bin'
                }
            }

            # Vendored/internal-feed binary for air-gapped ADO agents (RISK-2). Same
            # committed-checksum verification as online. $null = online-only for now.
            OfflinePath = $null
        }

        @{
            Name = 'gh'
            # 'floor': gh is provisioned through the OS package manager, which supplies
            # its own package signing and resolves to the feed's current build — a
            # committed Sha256 is neither available nor applicable here. MinVersion is
            # the enforced floor; Version records the latest known-good at pin time.
            # Downstream (Ensure-EvalTools) branches on VersionPolicy: 'floor' means
            # present>=MinVersion runs as-is, missing installs the manager default,
            # and no checksum step runs. This is the documented divergence from waza's
            # 'exact' + committed-checksum path.
            VersionPolicy = 'floor'
            MinVersion = '2.60.0'
            Version = '2.96.0'
            Source = 'package-manager'

            # gh is the PRIMARY seamless token source (`gh auth token`, OAuth
            # auto-refresh) consumed by Resolve-EvalToken.ps1 (REQ-2). Provisioned
            # per-OS via the native package manager, not a raw binary download.
            Install = @{
                'windows' = @{ Manager = 'winget'; Id = 'GitHub.cli' }
                'linux' = @{ Manager = 'apt'; Id = 'gh' }
                'darwin' = @{ Manager = 'brew'; Id = 'gh' }
            }

            OfflinePath = $null
        }
    )

    # Present-only baseline: these MUST already exist (autopilot/dev images ship them);
    # this manifest never installs them, it only version-checks.
    VerifyOnly = @(
        @{ Name = 'pwsh'; MinVersion = '7.0' }
        @{ Name = 'Pester'; MinVersion = '5.0' }
    )
}

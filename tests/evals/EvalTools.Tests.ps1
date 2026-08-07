#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Describe 'Ensure-EvalTools' {
    BeforeAll {
        $here = Split-Path -Parent $PSCommandPath
        $repoDir = (Resolve-Path (Join-Path $here '..' '..')).Path
        $scriptFile = Join-Path $repoDir 'scripts/skalary/Ensure-EvalTools.ps1'
        $manifestFile = Join-Path $repoDir 'tools/eval-tools.psd1'
        . $scriptFile
        $script:manifest = Import-EvalToolManifest -Path $manifestFile
        $script:waza = $script:manifest.Tools | Where-Object { $_.Name -eq 'waza' }
        $script:gh = $script:manifest.Tools | Where-Object { $_.Name -eq 'gh' }

        # Pester runs in-process, so a var a test assigns outlives the suite in the caller's shell.
        # These tests used to leave HOME pointing at TestDrive, which sends git looking for .gitconfig
        # and .ssh in a temp directory for the rest of that shell's life.
        $script:envSnapshot = @{}
        foreach ($name in @('WAZA_EVAL_APPROVE_INSTALL', 'LOCALAPPDATA', 'HOME')) {
            $script:envSnapshot[$name] = [Environment]::GetEnvironmentVariable($name)
        }
    }

    AfterAll {
        foreach ($name in @($script:envSnapshot.Keys)) {
            $value = $script:envSnapshot[$name]
            # SetEnvironmentVariable cannot express "unset" from PowerShell: $null binds to the string
            # parameter as '', which creates the variable empty instead of removing it.
            if ($null -eq $value) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $value)
            }
        }
    }

    Context 'test:evaltools-resolve — per-tool version decisions' {
        It 'test:evaltools-resolve marks a present-at-pin exact tool as ok' {
            $d = Resolve-EvalToolDecision -Tool $script:waza -InstalledVersion '0.38.0'
            $d.Action | Should -Be 'ok'
        }

        It 'test:evaltools-resolve runs an older exact tool as-is (never auto-changes)' {
            $d = Resolve-EvalToolDecision -Tool $script:waza -InstalledVersion '0.37.0'
            $d.Action | Should -Be 'run-as-is'
        }

        It 'test:evaltools-resolve surfaces a newer exact tool as newer (check-updates only)' {
            $d = Resolve-EvalToolDecision -Tool $script:waza -InstalledVersion '0.39.0'
            $d.Action | Should -Be 'newer'
        }

        It 'test:evaltools-resolve plans an install when a tool is missing' {
            $d = Resolve-EvalToolDecision -Tool $script:waza -InstalledVersion $null
            $d.Action | Should -Be 'install'
            $d.Version | Should -Be '0.38.0'
        }

        It 'test:evaltools-resolve treats a floor tool at/above MinVersion as ok' {
            $d = Resolve-EvalToolDecision -Tool $script:gh -InstalledVersion '2.70.0'
            $d.Action | Should -Be 'ok'
        }

        It 'test:evaltools-resolve installs a floor tool below MinVersion' {
            $d = Resolve-EvalToolDecision -Tool $script:gh -InstalledVersion '2.10.0'
            $d.Action | Should -Be 'install'
        }
    }

    Context 'test:evaltools-resolve — approval gating (missing + no approval => skip)' {
        It 'test:evaltools-resolve denies install without approval when non-interactive' {
            $env:WAZA_EVAL_APPROVE_INSTALL = ''
            Get-ApprovalDecision -ToolName 'waza' -Version '0.38.0' | Should -BeFalse
        }

        It 'test:evaltools-resolve approves via the -Approve switch' {
            Get-ApprovalDecision -ToolName 'waza' -Version '0.38.0' -Approve | Should -BeTrue
        }

        It 'test:evaltools-resolve approves via WAZA_EVAL_APPROVE_INSTALL=1' {
            $env:WAZA_EVAL_APPROVE_INSTALL = '1'
            try {
                Get-ApprovalDecision -ToolName 'waza' -Version '0.38.0' | Should -BeTrue
            }
            finally {
                $env:WAZA_EVAL_APPROVE_INSTALL = ''
            }
        }
    }

    Context 'test:evaltools-resolve — checksum verification (mismatch => fail)' {
        It 'test:evaltools-resolve passes when the file hash matches the committed constant' {
            $file = Join-Path $TestDrive 'artifact.bin'
            Set-Content -LiteralPath $file -Value 'waza-eval-tools' -NoNewline
            $expected = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
            { Assert-Sha256 -Path $file -Expected $expected } | Should -Not -Throw
        }

        It 'test:evaltools-resolve throws on a checksum mismatch' {
            $file = Join-Path $TestDrive 'tampered.bin'
            Set-Content -LiteralPath $file -Value 'tampered' -NoNewline
            { Assert-Sha256 -Path $file -Expected ('0' * 64) } | Should -Throw '*Checksum mismatch*'
        }
    }

    Context 'test:evaltools-crossplatform — per-OS/arch asset resolution' {
        It 'test:evaltools-crossplatform maps every OS/arch to a manifest asset key' {
            $cases = @(
                @{ Os = 'windows'; Arch = 'amd64' },
                @{ Os = 'windows'; Arch = 'arm64' },
                @{ Os = 'linux'; Arch = 'amd64' },
                @{ Os = 'linux'; Arch = 'arm64' },
                @{ Os = 'darwin'; Arch = 'amd64' },
                @{ Os = 'darwin'; Arch = 'arm64' }
            )
            foreach ($case in $cases) {
                $key = Get-EvalPlatformKey -OsOverride $case.Os -ArchOverride $case.Arch
                $key | Should -Be "$($case.Os)-$($case.Arch)"
                $script:waza.Assets.ContainsKey($key) | Should -BeTrue
                $script:waza.Assets[$key].Sha256 | Should -Match '^[0-9a-f]{64}$'
            }
        }

        It 'test:evaltools-crossplatform rejects an unsupported architecture' {
            { Get-EvalPlatformKey -OsOverride 'linux' -ArchOverride 'mips' } | Should -Throw
        }

        It 'test:evaltools-crossplatform expands install-dir tokens without leftover placeholders' {
            $env:LOCALAPPDATA = (Join-Path $TestDrive 'local')
            $env:HOME = (Join-Path $TestDrive 'home')
            $win = Expand-InstallDir -Token '%LOCALAPPDATA%/Microsoft/Waza'
            $nix = Expand-InstallDir -Token '%HOME%/.local/share/waza/bin'
            $win | Should -Not -Match '%'
            $nix | Should -Not -Match '%'
        }
    }

    Context 'test:schema-compat-assert — pinned binary must support the specs schemaVersion' {
        It 'test:schema-compat-assert accepts an already-compatible migrate result' {
            Test-SchemaCompat -MigrateOutput 'eval.yaml is already compatible with schemaVersion 1.2; no migration needed.' -TargetSchema '1.2' | Should -BeTrue
        }

        It 'test:schema-compat-assert accepts a successful migration' {
            Test-SchemaCompat -MigrateOutput 'migrated eval.yaml to schemaVersion 1.2' -TargetSchema '1.2' | Should -BeTrue
        }

        It 'test:schema-compat-assert rejects an unknown schema version' {
            Test-SchemaCompat -MigrateOutput 'error: unknown schemaVersion "1.2"' -TargetSchema '1.2' -ExitCode 1 | Should -BeFalse
        }

        It 'test:schema-compat-assert rejects a nonzero migrate exit code' {
            Test-SchemaCompat -MigrateOutput 'some output' -TargetSchema '1.2' -ExitCode 2 | Should -BeFalse
        }
    }

    Context 'test:evaltools-resolve — known-install-dir fallback (design §4)' {
        It 'test:evaltools-resolve builds a waza candidate path under the expanded install dir' {
            $key = Get-EvalPlatformKey
            $cands = @(Get-ToolCandidatePath -Tool $script:waza -PlatformKey $key)
            $cands.Count | Should -BeGreaterThan 0
            $cands[0] | Should -Match ([regex]::Escape($script:waza.Assets[$key].BinaryName) + '$')
            $cands[0] | Should -Not -Match '%'
        }

        It 'test:evaltools-resolve offers platform-appropriate gh candidate paths' {
            $key = Get-EvalPlatformKey
            $cands = @(Get-ToolCandidatePath -Tool $script:gh -PlatformKey $key)
            $cands.Count | Should -BeGreaterThan 0
            foreach ($c in $cands) { $c | Should -Match '([\\/])gh(\.exe)?$' }
        }

        It 'test:evaltools-resolve resolves a not-on-PATH tool via an existing candidate path' {
            $fake = Join-Path $TestDrive 'faketool.bin'
            Set-Content -LiteralPath $fake -Value 'stub' -NoNewline
            $r = Get-InstalledToolVersion -Command 'definitely-not-a-real-command-xyz' -CandidatePath @($fake)
            $r | Should -Not -BeNullOrEmpty
            $r.Path | Should -Be $fake
        }

        It 'test:evaltools-resolve returns null when neither PATH nor candidates resolve' {
            $missing = Join-Path $TestDrive 'does-not-exist.bin'
            Get-InstalledToolVersion -Command 'definitely-not-a-real-command-xyz' -CandidatePath @($missing) | Should -BeNullOrEmpty
        }
    }

    Context 'ConvertFrom-ToolVersionOutput' {
        It 'parses the waza version banner' {
            ConvertFrom-ToolVersionOutput -Text 'waza version 0.38.0' | Should -Be '0.38.0'
        }

        It 'parses the gh version banner' {
            ConvertFrom-ToolVersionOutput -Text 'gh version 2.96.0 (2024-01-01)' | Should -Be '2.96.0'
        }

        It 'returns null when no version is present' {
            ConvertFrom-ToolVersionOutput -Text 'no version here' | Should -BeNullOrEmpty
        }
    }
}

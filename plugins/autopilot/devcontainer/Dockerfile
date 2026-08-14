# Autopilot execution container — .NET 10 SDK + Copilot CLI + tooling
# Used by plugins/autopilot/scripts/launch-container.ps1 via `docker build`

FROM mcr.microsoft.com/dotnet/sdk:10.0

ARG GH_CLI_VERSION=2.74.0
# Fallback only — launch-container.ps1 resolves and passes the latest published
# version via --build-arg COPILOT_CLI_VERSION so each build auto-upgrades.
ARG COPILOT_CLI_VERSION=1.0.60

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY devcontainer/toolchain.tsv /tmp/autopilot-toolchain.tsv

# Bootstrap dependencies stay distinct from the manifest-owned agent baseline.
RUN set -eux; \
    bootstrap_packages=(git curl jq ca-certificates gnupg nodejs npm); \
    awk -F '\t' ' \
        /^[[:space:]]*(#|$)/ { next } \
        NF != 3 || $1 !~ /^[a-z0-9]+(-[a-z0-9]+)*$/ || $2 !~ /^[a-z0-9][a-z0-9+.-]*$/ || $3 !~ /^[a-z0-9][a-z0-9+.-]*$/ { \
            print "Invalid toolchain.tsv row at line " NR > "/dev/stderr"; exit 1 \
        } \
        seen[$1]++ { print "Duplicate toolchain case ID: " $1 > "/dev/stderr"; exit 1 } \
        { count++; print $2 } \
        END { if (count == 0) { print "toolchain.tsv has no package rows" > "/dev/stderr"; exit 1 } } \
    ' /tmp/autopilot-toolchain.tsv > /tmp/autopilot-toolchain-packages; \
    mapfile -t toolchain_packages < /tmp/autopilot-toolchain-packages; \
    if apt-config dump | grep -Eiq '^[[:space:]]*Binary::apt-get::Dir([[:space:]]|::)'; then \
        echo "APT apt-get-specific Dir overrides are not allowed" >&2; exit 1; \
    fi; \
    [[ "$(apt-config shell apt_root Dir)" == "apt_root='/'" ]] \
        || { echo "APT Dir must remain '/'" >&2; exit 1; }; \
    [[ "$(apt-config shell apt_etc Dir::Etc)" == "apt_etc='etc/apt'" ]] \
        || { echo "APT Dir::Etc must remain 'etc/apt'" >&2; exit 1; }; \
    [[ "$(apt-config shell apt_source_list Dir::Etc::sourcelist)" == "apt_source_list='sources.list'" ]] \
        || { echo "APT sourcelist must remain 'sources.list'" >&2; exit 1; }; \
    [[ "$(apt-config shell apt_source_parts Dir::Etc::sourceparts)" == "apt_source_parts='sources.list.d'" ]] \
        || { echo "APT sourceparts must remain 'sources.list.d'" >&2; exit 1; }; \
    apt_source_files=(); \
    if [[ -e /etc/apt/sources.list || -L /etc/apt/sources.list ]]; then \
        [[ -f /etc/apt/sources.list && ! -L /etc/apt/sources.list ]] \
            || { echo "APT sourcelist must be a regular non-symlink file" >&2; exit 1; }; \
        apt_source_files+=(/etc/apt/sources.list); \
    fi; \
    if [[ -e /etc/apt/sources.list.d || -L /etc/apt/sources.list.d ]]; then \
        [[ -d /etc/apt/sources.list.d && ! -L /etc/apt/sources.list.d ]] \
            || { echo "APT sourceparts must be a non-symlink directory" >&2; exit 1; }; \
        if find /etc/apt/sources.list.d -maxdepth 1 -type l \( -name '*.list' -o -name '*.sources' \) -print -quit | grep -q .; then \
            echo "APT sourceparts must not contain symlinked source files" >&2; exit 1; \
        fi; \
        mapfile -t source_part_files < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print | LC_ALL=C sort); \
        apt_source_files+=("${source_part_files[@]}"); \
    fi; \
    : > /tmp/autopilot-apt-source-uris; \
    for source_file in "${apt_source_files[@]}"; do \
        case "$source_file" in \
            *.list) \
                awk ' \
                    /^[[:space:]]*(#|$)/ { next } \
                    /^[[:space:]]*deb(-src)?[[:space:]]/ { \
                        line = $0; \
                        sub(/^[[:space:]]*deb(-src)?[[:space:]]+/, "", line); \
                        sub(/^\[[^]]*\][[:space:]]+/, "", line); \
                        split(line, fields, /[[:space:]]+/); \
                        print fields[1] \
                    } \
                ' "$source_file" \
                ;; \
            *.sources) \
                awk ' \
                    BEGIN { RS = ""; FS = "\n" } \
                    { \
                        enabled = 1; collecting = 0; uris = ""; \
                        for (i = 1; i <= NF; i++) { \
                            line = $i; \
                            if (line ~ /^[[:space:]]*[Ee][Nn][Aa][Bb][Ll][Ee][Dd]:[[:space:]]*([Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|0)[[:space:]]*$/) enabled = 0; \
                            if (line ~ /^[[:space:]]*[Uu][Rr][Ii][Ss]:[[:space:]]*/) { \
                                sub(/^[[:space:]]*[Uu][Rr][Ii][Ss]:[[:space:]]*/, "", line); \
                                uris = uris " " line; collecting = 1; continue \
                            } \
                            if (collecting && line ~ /^[[:space:]]+/ && line !~ /^[[:space:]]*#/) { \
                                sub(/^[[:space:]]+/, "", line); \
                                uris = uris " " line; continue \
                            } \
                            collecting = 0 \
                        } \
                        if (enabled) { \
                            count = split(uris, values, /[[:space:]]+/); \
                            for (i = 1; i <= count; i++) if (values[i] != "") print values[i] \
                        } \
                    } \
                ' "$source_file" \
                ;; \
        esac; \
    done | LC_ALL=C sort -u > /tmp/autopilot-apt-source-uris; \
    test -s /tmp/autopilot-apt-source-uris; \
    while IFS= read -r uri; do \
        if [[ "$uri" =~ ^https?://([^/:]+)(:[0-9]+)?(/|$) ]]; then \
            host="${BASH_REMATCH[1],,}"; \
        else \
            echo "Unsupported active apt source URI: $uri" >&2; exit 1; \
        fi; \
        case "$host" in \
            deb.debian.org|security.debian.org) ;; \
            *) echo "Disallowed active apt source host: $host" >&2; exit 1 ;; \
        esac; \
    done < /tmp/autopilot-apt-source-uris; \
    apt-get update; \
    apt-get install -y --no-install-recommends "${bootstrap_packages[@]}" "${toolchain_packages[@]}"; \
    install -d -m 0755 /usr/local/share/autopilot/provenance; \
    cp /etc/os-release /usr/local/share/autopilot/provenance/os-release; \
    cp /tmp/autopilot-apt-source-uris /usr/local/share/autopilot/provenance/apt-sources.txt; \
    requested_packages=("${bootstrap_packages[@]}" "${toolchain_packages[@]}"); \
    dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' "${requested_packages[@]}" \
        | LC_ALL=C sort -u > /usr/local/share/autopilot/provenance/requested-packages.tsv; \
    apt-cache depends --recurse --important "${requested_packages[@]}" \
        | awk '/^[^[:space:]<]/ { package = $1; sub(/:.*/, "", package); print package }' \
        | LC_ALL=C sort -u > /tmp/autopilot-dependency-package-names; \
    dpkg-query -W -f='${db:Status-Status}\t${Package}\t${binary:Package}\t${Version}\t${Architecture}\n' \
        | awk -F '\t' '$1 == "installed" { print $2 "\t" $3 "\t" $4 "\t" $5 }' \
        | LC_ALL=C sort -t $'\t' -k1,1 > /tmp/autopilot-installed-package-records; \
    join -t $'\t' -o 2.2,2.3,2.4 \
        /tmp/autopilot-dependency-package-names \
        /tmp/autopilot-installed-package-records \
        > /usr/local/share/autopilot/provenance/dependency-closure.tsv; \
    test -s /usr/local/share/autopilot/provenance/dependency-closure.tsv; \
    mapfile -t dependency_packages < <(cut -f1 /usr/local/share/autopilot/provenance/dependency-closure.tsv); \
    apt-cache policy "${dependency_packages[@]}" > /usr/local/share/autopilot/provenance/selected-origins.txt; \
    rm -f \
        /tmp/autopilot-toolchain.tsv \
        /tmp/autopilot-toolchain-packages \
        /tmp/autopilot-apt-source-uris \
        /tmp/autopilot-dependency-package-names \
        /tmp/autopilot-installed-package-records; \
    rm -rf /var/lib/apt/lists/*

# PowerShell
RUN curl -sSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y --no-install-recommends powershell \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -sSL "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_amd64.deb" -o /tmp/gh.deb \
    && dpkg -i /tmp/gh.deb \
    && rm /tmp/gh.deb

# Docker CLI (for Testcontainers — talks to host Docker daemon via socket mount)
RUN curl -sSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# GitHub Copilot CLI
RUN npm install -g @github/copilot@${COPILOT_CLI_VERSION}

# Pester (pinned) for PowerShell unit gates in autopilot container mode
RUN pwsh -NoProfile -Command "Install-Module Pester -RequiredVersion 5.6.1 -Force -Scope AllUsers"

# Container entry-point script
COPY scripts/container-entrypoint.sh /usr/local/bin/container-entrypoint.sh
RUN chmod +x /usr/local/bin/container-entrypoint.sh

# Non-root user for security — add to docker group for socket access
RUN groupadd -g 998 docker || true \
    && useradd -m -s /bin/bash -G docker autopilot
USER autopilot
WORKDIR /work

# Verify tools are installed
RUN git --version && pwsh --version && gh --version && copilot --version

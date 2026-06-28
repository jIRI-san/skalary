#!/bin/bash
# container-entrypoint.sh — Autonomous plan execution inside Docker container
# Invoked by: docker run ... /usr/local/bin/container-entrypoint.sh <plan-slug> <mode>
#
# Environment variables expected:
#   GH_TOKEN / COPILOT_GITHUB_TOKEN — GitHub auth
#   ADO_TOKEN (optional) — Azure DevOps access token
#   ADO_ORG, ADO_PROJECT (optional) — ADO config
#   COPILOT_ALLOW_ALL=true
#   COPILOT_MODEL — model override
#   REPO_REMOTE — git remote URL to clone

set -euo pipefail

PLAN_SLUG="${1:?Usage: container-entrypoint.sh <plan-slug> <mode>}"
MODE="${2:?Usage: container-entrypoint.sh <plan-slug> <mode>}"
BRANCH="${REPO_BRANCH:-feature/${PLAN_SLUG}}"
REPO_REMOTE="${REPO_REMOTE:?REPO_REMOTE env var required}"

echo "=== Autopilot Container Entry-Point ==="
echo "Plan: ${PLAN_SLUG}"
echo "Mode: ${MODE}"
echo "Branch: ${BRANCH}"
echo "Model: ${COPILOT_MODEL:-<CLI default>}"
echo "Copilot CLI: $(copilot --version 2>/dev/null || echo 'unknown')"

# --- Git credential setup ---
gh auth setup-git

# ADO credential helper (if ADO_TOKEN is set)
if [ -n "${ADO_TOKEN:-}" ]; then
    echo "Configuring ADO credential helper..."
    if [ -n "${ADO_ORG:-}" ]; then
        az devops configure --defaults "organization=${ADO_ORG}" "project=${ADO_PROJECT:-}"
    fi
    git config --global credential.helper '!f() { echo "username=x-token"; echo "password=${ADO_TOKEN}"; }; f'
fi

# --- Clone and branch ---
echo "Cloning ${REPO_REMOTE}..."
git clone "${REPO_REMOTE}" /work
cd /work

# Determine target branch
WORK_BRANCH="feature/${PLAN_SLUG}"

if git ls-remote --exit-code origin "refs/heads/${WORK_BRANCH}" > /dev/null 2>&1; then
    echo "Work branch ${WORK_BRANCH} exists on remote — resuming..."
    git fetch origin "${WORK_BRANCH}"
    git checkout "${WORK_BRANCH}"
elif [ "${BRANCH}" != "${WORK_BRANCH}" ] && git ls-remote --exit-code origin "refs/heads/${BRANCH}" > /dev/null 2>&1; then
    echo "Starting from branch ${BRANCH}..."
    git fetch origin "${BRANCH}"
    git checkout "${BRANCH}"
    echo "Creating work branch ${WORK_BRANCH} from ${BRANCH}..."
    git checkout -b "${WORK_BRANCH}"
else
    echo "Creating new branch ${WORK_BRANCH} from $(git branch --show-current)..."
    git checkout -b "${WORK_BRANCH}"
fi

# --- Configure git identity ---
git config user.name "${GIT_USER_NAME:-autopilot}"
git config user.email "${GIT_USER_EMAIL:-autopilot@noreply}"

# --- Offline package feed setup ---
# When the host bundled a package feed (mounted read-only at /feed), copy it to a
# writable cache and emit OUT-OF-TREE restore config so all restores resolve from
# the cache with no network access and without writing into /work. The NuGet config
# is passed via NUGET_CONFIG, which REPLACES machine/user config discovery (no merge);
# npm is steered via an out-of-tree userconfig + cache. The committed lockfiles keep
# the restore locked/deterministic.
if [ "${AUTOPILOT_OFFLINE:-}" = "true" ]; then
    FEED_SRC="${AUTOPILOT_FEED:-/feed}"
    CACHE_ROOT="${HOME}/.autopilot-cache"
    echo "Offline mode: copying feed ${FEED_SRC} -> ${CACHE_ROOT} (writable)..."
    mkdir -p "${CACHE_ROOT}"
    cp -a "${FEED_SRC}/." "${CACHE_ROOT}/"

    if [ -d "${CACHE_ROOT}/nuget" ]; then
        export NUGET_CONFIG="${CACHE_ROOT}/nuget.config"
        cat > "${NUGET_CONFIG}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
  </packageSources>
  <fallbackPackageFolders>
    <clear />
  </fallbackPackageFolders>
  <config>
    <add key="globalPackagesFolder" value="${CACHE_ROOT}/nuget" />
  </config>
</configuration>
EOF
        echo "NuGet offline config: ${NUGET_CONFIG} (globalPackagesFolder=${CACHE_ROOT}/nuget)"
    fi

    if [ -d "${CACHE_ROOT}/npm" ]; then
        export npm_config_userconfig="${CACHE_ROOT}/npmrc"
        export npm_config_cache="${CACHE_ROOT}/npm"
        export npm_config_offline="true"
        cat > "${npm_config_userconfig}" <<EOF
cache=${CACHE_ROOT}/npm
offline=true
EOF
        echo "npm offline config: cache=${CACHE_ROOT}/npm offline=true"
    fi
fi

# --- Execute plan phases ---
PLAN_PATH="docs/implementation-plans/${PLAN_SLUG}/plan.md"

if [ ! -f "${PLAN_PATH}" ]; then
    echo "ERROR: Plan not found at ${PLAN_PATH}"
    exit 1
fi

# Parse the actual phase numbers from "## Phase N" headings so plans that
# start at Phase 0 (or skip numbers) are executed faithfully. Iterating a
# blind `seq 1..count` would skip Phase 0 and chase a nonexistent trailing
# phase. Matches the host launcher (launch-host.ps1) behaviour.
PHASE_NUMS=$(grep -oE '^## Phase [0-9]+' "${PLAN_PATH}" | grep -oE '[0-9]+' || true)
PHASE_COUNT=$(printf '%s\n' "${PHASE_NUMS}" | grep -c '[0-9]' || echo "0")
echo "Found ${PHASE_COUNT} phases in plan (numbers: $(echo ${PHASE_NUMS} | tr '\n' ' '))."

# Per-phase copilot invocations
for PHASE_NUM in ${PHASE_NUMS}; do
    echo ""
    echo "=== Phase ${PHASE_NUM} (of ${PHASE_COUNT} total) ==="

    # Check if phase has uncompleted steps
    if ! grep -q '^\- \[ \]\|^\- \[\~\]' "${PLAN_PATH}"; then
        echo "No uncompleted steps remain — skipping."
        continue
    fi

    TRANSCRIPT="session-transcript-phase${PHASE_NUM}.md"

    # Pass --model explicitly when set so model selection is deterministic
    # (not just implied by COPILOT_MODEL) and visible in logs.
    MODEL_ARGS=()
    if [ -n "${COPILOT_MODEL:-}" ]; then
        MODEL_ARGS=(--model "${COPILOT_MODEL}")
        echo "Invoking Copilot CLI with model: ${COPILOT_MODEL}"
    else
        echo "Invoking Copilot CLI with CLI default model (COPILOT_MODEL unset)"
    fi

    copilot -p "Execute ${PLAN_PATH}, phase ${PHASE_NUM}" \
        "${MODEL_ARGS[@]}" \
        --agent autopilot \
        --no-ask-user \
        --share="./${TRANSCRIPT}" \
        || {
            EXIT_CODE=$?
            echo "Phase ${PHASE_NUM} exited with code ${EXIT_CODE}"
            if [ ${EXIT_CODE} -eq 42 ]; then
                echo "@human step encountered — stopping."
                break
            fi
            if [ ${EXIT_CODE} -eq 43 ]; then
                # Offline rebundle requested: the agent committed the package
                # manifest (not the lockfile). Push it so the host can regenerate
                # the lockfile + re-bundle the feed, then signal the launcher.
                # Exits here, before the unconditional end-of-run push.
                echo "Offline rebundle requested (exit 43) — pushing manifest commit and signaling host."
                git push origin "${WORK_BRANCH}"
                exit 43
            fi
            # Non-zero but not @human — continue to allow partial progress
        }

    echo "Phase ${PHASE_NUM} complete."
done

echo ""
echo "=== Execution finished ==="
echo "Pushing branch ${WORK_BRANCH}..."
git push origin "${WORK_BRANCH}"

# Note: PR creation is handled by the autopilot agent in its Plan Completion step
# with a structured title and body. The entrypoint only ensures the branch is pushed.

echo "Done."

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

phase_has_incomplete() {
    local plan_path="$1"
    local phase_number="$2"

    awk -v phase="${phase_number}" '
        $0 ~ ("^## Phase " phase "([^0-9]|$)") {
            in_phase = 1
            next
        }
        in_phase && /^## Phase [0-9]+/ {
            exit
        }
        in_phase && /^- \[( |~)\]/ {
            found = 1
            exit
        }
        END {
            exit(found ? 0 : 1)
        }
    ' "${plan_path}"
}

phase_has_harvest_receipt() {
    local plan_path="$1"
    local phase_number="$2"
    local plan_dir
    local receipt_name

    plan_dir="$(dirname "${plan_path}")"
    receipt_name="$(printf 'phase-%03d.json' "${phase_number}")"
    [ -f "${plan_dir}/assets/harvest-receipts/${receipt_name}" ] ||
        [ -f "${plan_dir}/harvest-receipts/${receipt_name}" ]
}

phase_needs_execution() {
    local plan_path="$1"
    local phase_number="$2"
    local repo_root="${3:-.}"
    local validator="${4:-${AUTOPILOT_HARVEST_VALIDATOR:-/usr/local/lib/autopilot/Invoke-PhaseHarvest.ps1}}"
    local validation_output

    if phase_has_incomplete "${plan_path}" "${phase_number}"; then
        return 0
    fi
    if ! phase_has_harvest_receipt "${plan_path}" "${phase_number}"; then
        return 0
    fi
    if ! validation_output="$(pwsh -NoProfile -File "${validator}" \
        -PlanDir "$(dirname "${plan_path}")" -Phase "${phase_number}" \
        -ValidateReceipt -RepoRoot "${repo_root}" 2>&1)"; then
        echo "ERROR: Phase ${phase_number} harvest receipt is invalid." >&2
        printf '%s\n' "${validation_output}" >&2
        return 2
    fi
    return 1
}

phase_dispatch_action() {
    local mode="$1"
    local exit_code="$2"
    local close_state="$3"

    if [ "${exit_code}" -eq 43 ]; then
        printf '%s\n' rebundle
    elif [ "${exit_code}" -eq 42 ]; then
        printf '%s\n' human-stop
    elif [ "${exit_code}" -ne 0 ]; then
        printf '%s\n' phase-failed
    elif [ "${close_state}" -eq 2 ]; then
        printf '%s\n' invalid-receipt
    elif [ "${close_state}" -eq 0 ]; then
        printf '%s\n' close-pending
    elif [ "${mode}" = "next-phase" ]; then
        printf '%s\n' phase-complete-stop
    else
        printf '%s\n' phase-complete-continue
    fi
}

stage_recoverable_work() {
    local repo_path="$1"

    {
        git -C "${repo_path}" diff --name-only -z
        git -C "${repo_path}" ls-files --others --exclude-standard -z
    } | git -C "${repo_path}" add --pathspec-from-file=- --pathspec-file-nul ||
        return 70
}

# Expose the pure phase-progress probe to focused tests without running bootstrap.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

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

# --- Work preservation on termination ---
# The host enforces the whole-run cap with `docker stop --time 30`, which sends
# SIGTERM to this script. Without a handler the run dies holding every commit made
# since the last push, and those commits vanish with the container. Bash also
# defers traps while a foreground child runs, so each `copilot` call below is
# backgrounded and waited on — otherwise this handler could never fire.
COPILOT_PID=""
TERMINATING=0

preserve_work() {
    cd /work 2>/dev/null || return 70
    git rev-parse --git-dir >/dev/null 2>&1 || return 70
    if [ -n "$(git status --porcelain)" ]; then
        echo "Committing in-flight work before exit..."
        stage_recoverable_work /work || return 70
        if ! git diff --cached --quiet; then
            git commit -q -m "chore(autopilot): preserve in-flight work on termination [plan-${PLAN_SLUG}]" ||
                return 70
        fi
    fi
    echo "Pushing ${WORK_BRANCH}..."
    git push origin "${WORK_BRANCH}" || return 70
}

on_terminate() {
    [ "${TERMINATING}" -eq 1 ] && return
    TERMINATING=1
    echo ""
    echo "=== Termination signal received — preserving work ==="
    if [ -n "${COPILOT_PID}" ] && kill -0 "${COPILOT_PID}" 2>/dev/null; then
        kill -TERM "${COPILOT_PID}" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            kill -0 "${COPILOT_PID}" 2>/dev/null || break
            sleep 1
        done
        kill -KILL "${COPILOT_PID}" 2>/dev/null || true
    fi
    if ! preserve_work; then
        echo "ERROR: Failed to preserve in-flight work; container recovery is required."
        exit 70
    fi
    exit 143
}

trap on_terminate TERM INT

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

PHASE_TIMEOUT_MIN="${AUTOPILOT_PHASE_TIMEOUT_MIN:-0}"
PHASE_TIMEOUT_SECS=$((PHASE_TIMEOUT_MIN * 60))
if [ "${PHASE_TIMEOUT_SECS}" -gt 0 ]; then
    echo "Per-phase timeout: ${PHASE_TIMEOUT_MIN}m (whole-run cap is enforced by the host)."
else
    echo "Per-phase timeout: disabled (whole-run cap is enforced by the host)."
fi

# Per-phase copilot invocations
for PHASE_NUM in ${PHASE_NUMS}; do
    echo ""
    echo "=== Phase ${PHASE_NUM} (of ${PHASE_COUNT} total) ==="

    # A phase is closed only after both its checklist and durable harvest complete.
    # Missing close state re-enters the same phase agent instead of skipping ahead.
    set +e
    phase_needs_execution "${PLAN_PATH}" "${PHASE_NUM}" "."
    PHASE_STATE=$?
    set -e
    if [ "${PHASE_STATE}" -eq 1 ]; then
        echo "Phase ${PHASE_NUM}: checklist and phase close complete — skipping."
        continue
    elif [ "${PHASE_STATE}" -eq 2 ]; then
        if ! preserve_work; then
            echo "ERROR: Failed to preserve invalid phase-close state; container recovery is required."
            exit 70
        fi
        exit 3
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
        --context "${COPILOT_CONTEXT}" \
        --effort "${COPILOT_REASONING_EFFORT}" \
        --agent autopilot \
        --no-ask-user \
        --share="./${TRANSCRIPT}" &
    COPILOT_PID=$!

    # Per-phase timeout. The host only enforces the whole-run cap; it cannot see
    # phase boundaries, so the per-phase budget is enforced here.
    PHASE_TIMED_OUT=0
    if [ "${PHASE_TIMEOUT_SECS}" -gt 0 ]; then
        ELAPSED=0
        while kill -0 "${COPILOT_PID}" 2>/dev/null; do
            if [ "${ELAPSED}" -ge "${PHASE_TIMEOUT_SECS}" ]; then
                echo "Phase ${PHASE_NUM} exceeded per-phase timeout of ${PHASE_TIMEOUT_MIN}m — terminating phase."
                PHASE_TIMED_OUT=1
                kill -TERM "${COPILOT_PID}" 2>/dev/null || true
                for _ in 1 2 3 4 5; do
                    kill -0 "${COPILOT_PID}" 2>/dev/null || break
                    sleep 1
                done
                kill -KILL "${COPILOT_PID}" 2>/dev/null || true
                break
            fi
            sleep 5
            ELAPSED=$((ELAPSED + 5))
        done
    fi

    set +e
    wait "${COPILOT_PID}"
    EXIT_CODE=$?
    set -e
    COPILOT_PID=""

    if [ "${PHASE_TIMED_OUT}" -eq 1 ]; then
        # Preserve whatever the phase produced, then stop: continuing into the next
        # phase after a truncated one would build on an unfinished phase.
        if ! preserve_work; then
            echo "ERROR: Failed to preserve timed-out phase work; container recovery is required."
            exit 70
        fi
        echo "Stopping run after per-phase timeout in phase ${PHASE_NUM}."
        exit 124
    fi

    CLOSE_STATE=-1
    if [ "${EXIT_CODE}" -eq 0 ]; then
        set +e
        phase_needs_execution "${PLAN_PATH}" "${PHASE_NUM}" "."
        CLOSE_STATE=$?
        set -e
    fi

    ACTION="$(phase_dispatch_action "${MODE}" "${EXIT_CODE}" "${CLOSE_STATE}")"
    case "${ACTION}" in
        rebundle)
            echo "Offline rebundle requested (exit 43) — pushing manifest commit and signaling host."
            if ! git push origin "${WORK_BRANCH}"; then
                echo "ERROR: Failed to publish the rebundle request; container recovery is required."
                exit 70
            fi
            exit 43
            ;;
        human-stop|phase-failed)
            echo "Phase ${PHASE_NUM} exited with code ${EXIT_CODE}; preserving work."
            if ! preserve_work; then
                echo "ERROR: Failed to preserve phase work; container recovery is required."
                exit 70
            fi
            exit "${EXIT_CODE}"
            ;;
        invalid-receipt)
            if ! preserve_work; then
                echo "ERROR: Failed to preserve invalid phase-close state; container recovery is required."
                exit 70
            fi
            exit 3
            ;;
        close-pending)
            echo "ERROR: Phase ${PHASE_NUM} exited zero without completing checklist and phase close."
            if ! preserve_work; then
                echo "ERROR: Failed to preserve incomplete phase work; container recovery is required."
                exit 70
            fi
            exit 1
            ;;
        phase-complete-stop)
            echo "Phase ${PHASE_NUM} complete."
            echo "Mode is 'next-phase' — stopping after Phase ${PHASE_NUM}."
            break
            ;;
        phase-complete-continue)
            echo "Phase ${PHASE_NUM} complete."
            ;;
    esac
done

echo ""
echo "=== Execution finished ==="
echo "Pushing branch ${WORK_BRANCH}..."
if ! git push origin "${WORK_BRANCH}"; then
    echo "ERROR: Failed to publish completed work; container recovery is required."
    exit 70
fi

# Note: PR creation is handled by the autopilot agent in its Plan Completion step
# with a structured title and body. The entrypoint only ensures the branch is pushed.

echo "Done."

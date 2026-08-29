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

. /usr/local/lib/autopilot/plan-dispatch.sh

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
    cd /work 2>/dev/null || return 0
    git rev-parse --git-dir >/dev/null 2>&1 || return 0
    # Untracked build/session noise is ignored via .gitignore, so -A here only
    # sweeps real in-flight work.
    if [ -n "$(git status --porcelain)" ]; then
        echo "Committing in-flight work before exit..."
        git add -A
        git commit -q -m "chore(autopilot): preserve in-flight work on termination [plan-${PLAN_SLUG}]" || true
    fi
    echo "Pushing ${WORK_BRANCH}..."
    git push origin "${WORK_BRANCH}" || echo "WARNING: preservation push failed — commits remain only in this container."
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
    preserve_work
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

# Parse actual phase numbers and select only incomplete phases. A whole-plan
# relaunch with every step complete gets one confined completion-only target.
PHASE_NUMS=$(autopilot_phase_numbers "${PLAN_PATH}")
PHASE_COUNT=$(printf '%s\n' "${PHASE_NUMS}" | grep -c '[0-9]' || echo "0")
FINAL_PHASE_NUM=$(printf '%s\n' "${PHASE_NUMS}" | tail -n 1)
echo "Found ${PHASE_COUNT} phases in plan (numbers: $(echo ${PHASE_NUMS} | tr '\n' ' '))."
REVIEW_GATE=".github/skills/autopilot/scripts/ReviewCycleGate.ps1"
if ! TARGET_OUTPUT=$(autopilot_execution_targets "${PLAN_PATH}" "${MODE}" "${REVIEW_GATE}"); then
    echo "ERROR: Unable to resolve safe autopilot execution targets."
    exit 1
fi
EXECUTION_TARGETS=()
if [ -n "${TARGET_OUTPUT}" ]; then
    mapfile -t EXECUTION_TARGETS <<< "${TARGET_OUTPUT}"
fi

PHASE_TIMEOUT_MIN="${AUTOPILOT_PHASE_TIMEOUT_MIN:-0}"
PHASE_TIMEOUT_SECS=$((PHASE_TIMEOUT_MIN * 60))
if [ "${PHASE_TIMEOUT_SECS}" -gt 0 ]; then
    echo "Per-phase timeout: ${PHASE_TIMEOUT_MIN}m (whole-run cap is enforced by the host)."
else
    echo "Per-phase timeout: disabled (whole-run cap is enforced by the host)."
fi

# Per-target copilot invocations
COMPLETION_ALLOWED=1
RUN_EXIT_CODE=0
for TARGET in "${EXECUTION_TARGETS[@]}"; do
    echo ""
    if [ "${COMPLETION_ALLOWED}" -ne 1 ] &&
        autopilot_target_owns_finalization "${TARGET}" "${FINAL_PHASE_NUM}"; then
        echo "Skipping ${TARGET}: an earlier target failed, so plan finalization is not eligible."
        break
    fi
    if [[ "${TARGET}" == operator-stop:* ]]; then
        PHASE_NUM="${TARGET#operator-stop:}"
        echo "Phase ${PHASE_NUM} review requires an operator decision — stopping."
        git push origin "${WORK_BRANCH}" || true
        exit 42
    elif [ "${TARGET}" = "completion-only" ]; then
        if ! autopilot_plan_all_steps_complete "${PLAN_PATH}"; then
            echo "ERROR: Plan completion target is no longer eligible — stopping without finalization."
            exit 1
        fi
        if autopilot_plan_phase_gates_terminal "${PLAN_PATH}" "${REVIEW_GATE}"; then
            :
        else
            GATE_STATUS=$?
            if [ "${GATE_STATUS}" -eq 2 ]; then
                echo "ERROR: Unable to verify plan completion gates."
                exit 1
            fi
            if [ "${GATE_STATUS}" -eq 42 ]; then
                echo "Plan completion requires an operator review decision — stopping."
                git push origin "${WORK_BRANCH}" || true
                exit 42
            fi
            echo "ERROR: Plan completion gates are not terminal — stopping without finalization."
            exit 1
        fi
        TARGET_LABEL="Plan completion"
        TRANSCRIPT="session-transcript-completion.md"
        PROMPT="Resume ${PLAN_PATH} at Plan Completion only. Every implementation step is already [x]. Do not replay phase completion or reopen completed steps."
    elif [[ "${TARGET}" == phase-completion:* ]]; then
        PHASE_NUM="${TARGET#phase-completion:}"
        TARGET_LABEL="Phase ${PHASE_NUM} completion"
        TRANSCRIPT="session-transcript-phase${PHASE_NUM}-completion.md"
        PROMPT="Resume ${PLAN_PATH}, phase ${PHASE_NUM}, at On Phase Completion only. Every implementation step in the phase is already [x]. Do not reopen or replay completed implementation steps."
    else
        PHASE_NUM="${TARGET#phase:}"
        TARGET_LABEL="Phase ${PHASE_NUM}"
        TRANSCRIPT="session-transcript-phase${PHASE_NUM}.md"
        PROMPT="Execute ${PLAN_PATH}, phase ${PHASE_NUM}"
    fi
    echo "=== ${TARGET_LABEL} ==="

    # Pass --model explicitly when set so model selection is deterministic
    # (not just implied by COPILOT_MODEL) and visible in logs.
    MODEL_ARGS=()
    if [ -n "${COPILOT_MODEL:-}" ]; then
        MODEL_ARGS=(--model "${COPILOT_MODEL}")
        echo "Invoking Copilot CLI with model: ${COPILOT_MODEL}"
    else
        echo "Invoking Copilot CLI with CLI default model (COPILOT_MODEL unset)"
    fi

    copilot -p "${PROMPT}" \
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
                echo "${TARGET_LABEL} exceeded per-phase timeout of ${PHASE_TIMEOUT_MIN}m — terminating."
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
        preserve_work
        echo "Stopping run after timeout in ${TARGET_LABEL}."
        exit 124
    fi

    if [ ${EXIT_CODE} -ne 0 ]; then
        echo "${TARGET_LABEL} exited with code ${EXIT_CODE}"
        if [ ${EXIT_CODE} -eq 42 ]; then
            echo "@human step encountered — stopping."
            git push origin "${WORK_BRANCH}" || true
            exit 42
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
        # Non-zero but not @human — push what landed, then continue for partial progress
        COMPLETION_ALLOWED=0
        if [ "${RUN_EXIT_CODE}" -eq 0 ]; then
            RUN_EXIT_CODE="${EXIT_CODE}"
        fi
        git push origin "${WORK_BRANCH}" || true
    else
        echo "${TARGET_LABEL} complete."
    fi
done

echo ""
echo "=== Execution finished ==="
echo "Pushing branch ${WORK_BRANCH}..."
git push origin "${WORK_BRANCH}"

# Note: PR creation is handled by the autopilot agent in its Plan Completion step
# with a structured title and body. The entrypoint only ensures the branch is pushed.

echo "Done."
exit "${RUN_EXIT_CODE}"

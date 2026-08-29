#!/bin/bash

autopilot_phase_numbers() {
    grep -oE '^## Phase [0-9]+' "$1" | grep -oE '[0-9]+' || true
}

autopilot_phase_has_incomplete_steps() {
    local plan_path="$1"
    local phase_number="$2"

    awk -v phase="${phase_number}" '
        $0 ~ "^## Phase " phase "([^0-9]|$)" { in_phase = 1; next }
        in_phase && /^## / { exit }
        in_phase && /^- \[( |~)\]/ { print "incomplete"; exit }
    ' "${plan_path}" | grep -q .
}

autopilot_phase_has_noncomplete_steps() {
    local plan_path="$1"
    local phase_number="$2"

    awk -v phase="${phase_number}" '
        $0 ~ "^## Phase " phase "([^0-9]|$)" { in_phase = 1; next }
        in_phase && /^## / { exit }
        in_phase && /^- \[[^x]\]/ { print "noncomplete"; exit }
    ' "${plan_path}" | grep -q .
}

autopilot_phase_has_unsupported_steps() {
    local plan_path="$1"
    local phase_number="$2"

    awk -v phase="${phase_number}" '
        $0 ~ "^## Phase " phase "([^0-9]|$)" { in_phase = 1; next }
        in_phase && /^## / { exit }
        in_phase && /^- \[[^x ~]\]/ { print "unsupported"; exit }
    ' "${plan_path}" | grep -q .
}

autopilot_plan_has_steps() {
    awk '
        /^## Phase [0-9]+/ { in_phase = 1; next }
        /^## / { in_phase = 0 }
        in_phase && /^- \[[x ~]\]/ { print "step"; exit }
    ' "$1" | grep -q .
}

autopilot_plan_all_steps_complete() {
    local plan_path="$1"
    local phase_number

    autopilot_plan_has_steps "${plan_path}" || return 1
    while IFS= read -r phase_number; do
        if autopilot_phase_has_noncomplete_steps "${plan_path}" "${phase_number}"; then
            return 1
        fi
    done < <(autopilot_phase_numbers "${plan_path}")
    return 0
}

autopilot_phase_gate_state() {
    local plan_path="$1"
    local phase_number="$2"
    local gate_script="$3"
    local plan_dir
    local gate_json

    plan_dir=$(dirname "${plan_path}")
    if ! gate_json=$(pwsh -NoProfile -File "${gate_script}" \
        -Action Check \
        -PlanDir "${plan_dir}" \
        -Phase "${phase_number}" \
        -Stage "phase-${phase_number}" \
        -Json); then
        printf 'ERROR: phase review gate failed for phase %s.\n' "${phase_number}" >&2
        return 2
    fi
    case "${gate_json}" in
        *'"state":"complete"'*) printf '%s\n' 'complete' ;;
        *'"state":"wrap"'*) printf '%s\n' 'wrap' ;;
        *'"state":"allow"'*) printf '%s\n' 'allow' ;;
        *'"state":"operator-decision"'*) printf '%s\n' 'operator-decision' ;;
        *'"state":"legacy-clean"'*) printf '%s\n' 'operator-decision' ;;
        *)
            printf 'ERROR: phase review gate returned an unknown state for phase %s.\n' "${phase_number}" >&2
            return 2
            ;;
    esac
}

autopilot_plan_phase_gates_terminal() {
    local plan_path="$1"
    local gate_script="$2"
    local phase_number
    local gate_state

    while IFS= read -r phase_number; do
        if ! gate_state=$(autopilot_phase_gate_state "${plan_path}" "${phase_number}" "${gate_script}"); then
            return 2
        fi
        case "${gate_state}" in
            complete|wrap) ;;
            operator-decision) return 42 ;;
            *) return 1 ;;
        esac
    done < <(autopilot_phase_numbers "${plan_path}")
    return 0
}

autopilot_target_owns_finalization() {
    local target="$1"
    local final_phase_number="$2"

    [ "${target}" = "completion-only" ] ||
        [ "${target}" = "phase:${final_phase_number}" ] ||
        [ "${target}" = "phase-completion:${final_phase_number}" ]
}

autopilot_branch_has_open_pr() {
    local repo_root="$1"
    local gh_bin="${AUTOPILOT_GH_BIN:-gh}"
    local branch
    local count

    if ! branch=$(git -C "${repo_root}" branch --show-current) || [ -z "${branch}" ]; then
        printf 'ERROR: unable to resolve the current branch for PR close proof.\n' >&2
        return 2
    fi
    if ! count=$(
        cd "${repo_root}" &&
            "${gh_bin}" pr list --head "${branch}" --state open --json number --jq length
    ); then
        printf 'ERROR: unable to inspect the branch pull request for close proof.\n' >&2
        return 2
    fi
    if [[ ! "${count}" =~ ^[0-9]+$ ]]; then
        printf 'ERROR: pull request close proof returned an invalid count.\n' >&2
        return 2
    fi
    [ "${count}" -gt 0 ]
}

autopilot_tree_records() {
    local repo_root="$1"
    local commit="$2"
    local tree_path="$3"
    local metadata
    local path

    git -C "${repo_root}" ls-tree -r "${commit}" -- "${tree_path}" |
        while IFS=$'\t' read -r metadata path; do
            printf '%s\t%s\n' "${metadata}" "${path#"${tree_path}/"}"
        done
}

autopilot_target_close_state() {
    local plan_path="$1"
    local target="$2"
    local final_phase_number="$3"
    local gate_script="$4"
    local phase_number
    local gate_state
    local gate_status
    local phase_state
    local phase_state_status
    local repo_root="${AUTOPILOT_REPO_ROOT:-.}"
    local state_script="${AUTOPILOT_PHASE_STATE_SCRIPT:-${repo_root}/.github/skills/autopilot/scripts/Get-PhaseExecutionState.ps1}"
    local harvest_validator="${AUTOPILOT_HARVEST_VALIDATOR:-${repo_root}/.github/skills/autopilot/scripts/Invoke-PhaseHarvest.ps1}"
    local active_plan_dir
    local plan_root
    local plan_slug
    local archived_plan
    local effective_plan_path="${plan_path}"
    local archive_transition=0
    local repo_root_full
    local archived_plan_relative
    local archived_dir_relative
    local active_plan_relative
    local active_dir_relative
    local archive_commit
    local archive_parent
    local active_tree
    local archived_tree_at_commit
    local archived_tree_at_head
    local archived_tree_at_parent
    local pr_status
    local plan_status

    if [ ! -f "${plan_path}" ]; then
        if autopilot_target_owns_finalization "${target}" "${final_phase_number}"; then
            active_plan_dir=$(dirname "${plan_path}")
            plan_root=$(dirname "${active_plan_dir}")
            plan_slug=$(basename "${active_plan_dir}")
            archived_plan="${plan_root}/archived/${plan_slug}/plan.md"
            if [ -f "${archived_plan}" ]; then
                effective_plan_path="${archived_plan}"
                archive_transition=1
            else
                printf 'ERROR: active plan disappeared without archived close state at %s.\n' "${archived_plan}" >&2
                return 2
            fi
        else
            printf 'ERROR: active plan disappeared before target %s closed.\n' "${target}" >&2
            return 2
        fi
    fi

    if [[ "${target}" == phase:* ]] || [[ "${target}" == phase-completion:* ]]; then
        phase_number="${target#*:}"
        if autopilot_phase_has_unsupported_steps "${effective_plan_path}" "${phase_number}"; then
            printf 'ERROR: phase %s contains an unsupported step state.\n' "${phase_number}" >&2
            return 2
        fi
        if autopilot_phase_has_noncomplete_steps "${effective_plan_path}" "${phase_number}"; then
            printf '%s\n' 'close-pending'
            return
        fi
    fi
    if [ -z "${phase_number:-}" ] &&
        autopilot_target_owns_finalization "${target}" "${final_phase_number}"; then
        phase_number="${final_phase_number}"
    fi

    if [ ! -f "${state_script}" ] || [ ! -f "${harvest_validator}" ]; then
        printf 'ERROR: canonical phase close probe or receipt validator is unavailable.\n' >&2
        return 2
    fi
    if phase_state=$(
        pwsh -NoProfile -File "${state_script}" \
            -PlanPath "${effective_plan_path}" \
            -Phase "${phase_number}" \
            -RepoRoot "${repo_root}" \
            -HarvestValidator "${harvest_validator}"
    ); then
        phase_state_status=0
    else
        phase_state_status=$?
    fi
    if [ "${phase_state_status}" -ne 0 ]; then
        printf 'ERROR: phase close receipt validation failed for phase %s.\n' "${phase_number}" >&2
        return 2
    fi
    case "${phase_state}" in
        execution-required|close-pending)
            printf '%s\n' 'close-pending'
            return
            ;;
        closed) ;;
        *)
            printf 'ERROR: phase close state returned an unknown result for phase %s.\n' "${phase_number}" >&2
            return 2
            ;;
    esac
    if ! plan_status=$(
        git -C "${repo_root}" status --porcelain --untracked-files=all \
            -- "$(dirname "${effective_plan_path}")"
    ); then
        printf 'ERROR: unable to inspect committed plan close state.\n' >&2
        return 2
    fi
    if [ -n "${plan_status}" ]; then
        printf '%s\n' 'close-pending'
        return
    fi

    if autopilot_target_owns_finalization "${target}" "${final_phase_number}"; then
        if ! autopilot_plan_all_steps_complete "${effective_plan_path}"; then
            printf '%s\n' 'close-pending'
            return
        fi
        if autopilot_plan_phase_gates_terminal "${effective_plan_path}" "${gate_script}" >/dev/null; then
            gate_status=0
        else
            gate_status=$?
        fi
        case "${gate_status}" in
            0) ;;
            1)
                printf '%s\n' 'close-pending'
                return
                ;;
            42)
                printf '%s\n' 'operator-decision'
                return
                ;;
            *) return 2 ;;
        esac
        if [ "${archive_transition}" -eq 1 ]; then
            if ! repo_root_full=$(git -C "${repo_root}" rev-parse --show-toplevel); then
                printf 'ERROR: unable to resolve repository root for archived close state.\n' >&2
                return 2
            fi
            if ! archived_plan_relative=$(
                git -C "${repo_root_full}" ls-files --full-name --error-unmatch \
                    -- "${effective_plan_path}" 2>/dev/null
            ); then
                printf '%s\n' 'close-pending'
                return
            fi
            archived_dir_relative=$(dirname "${archived_plan_relative}")
            archive_commit=$(
                git -C "${repo_root_full}" log --diff-filter=A -1 --format=%H \
                    -- "${archived_plan_relative}"
            )
            archive_parent="${archive_commit}^"
            if [ -z "${archive_commit}" ]; then
                printf '%s\n' 'close-pending'
                return
            fi
            active_plan_relative=$(
                git -C "${repo_root_full}" ls-tree -r --name-only "${archive_parent}" \
                    -- "${plan_path}"
            )
            if [ -z "${active_plan_relative}" ]; then
                printf '%s\n' 'close-pending'
                return
            fi
            active_dir_relative=$(dirname "${active_plan_relative}")
            active_tree=$(autopilot_tree_records "${repo_root_full}" "${archive_parent}" "${active_dir_relative}")
            archived_tree_at_parent=$(autopilot_tree_records "${repo_root_full}" "${archive_parent}" "${archived_dir_relative}")
            archived_tree_at_commit=$(autopilot_tree_records "${repo_root_full}" "${archive_commit}" "${archived_dir_relative}")
            archived_tree_at_head=$(autopilot_tree_records "${repo_root_full}" HEAD "${archived_dir_relative}")
            if ! git -C "${repo_root_full}" cat-file -e "HEAD:${archived_plan_relative}" 2>/dev/null ||
                [ -n "$(git -C "${repo_root_full}" ls-tree -r --name-only "${archive_commit}" -- "${active_dir_relative}")" ] ||
                [ -n "$(git -C "${repo_root_full}" ls-tree -r --name-only HEAD -- "${active_dir_relative}")" ] ||
                [ -n "${archived_tree_at_parent}" ] ||
                [ -z "${active_tree}" ] ||
                [ "${active_tree}" != "${archived_tree_at_commit}" ] ||
                [ "${archived_tree_at_commit}" != "${archived_tree_at_head}" ] ||
                [ -n "$(git -C "${repo_root_full}" status --porcelain --untracked-files=all -- "${active_dir_relative}" "${archived_dir_relative}")" ]; then
                printf '%s\n' 'close-pending'
                return
            fi
            if autopilot_branch_has_open_pr "${repo_root_full}"; then
                pr_status=0
            else
                pr_status=$?
            fi
            case "${pr_status}" in
                0) ;;
                1)
                    printf '%s\n' 'close-pending'
                    return
                    ;;
                *) return 2 ;;
            esac
            printf '%s\n' 'closed'
            return
        fi
        printf '%s\n' 'close-pending'
        return
    fi

    if ! gate_state=$(
        autopilot_phase_gate_state "${effective_plan_path}" "${phase_number}" "${gate_script}"
    ); then
        return 2
    fi
    case "${gate_state}" in
        complete|wrap) printf '%s\n' 'closed' ;;
        allow) printf '%s\n' 'close-pending' ;;
        operator-decision) printf '%s\n' 'operator-decision' ;;
    esac
}

autopilot_completion_handoff_action() {
    local exit_code="$1"
    local close_state="$2"
    local handoff_count="$3"
    local handoff_limit="$4"

    if [ "${exit_code}" -eq 43 ]; then
        printf '%s\n' 'rebundle'
    elif [ "${exit_code}" -eq 42 ]; then
        printf '%s\n' 'human-stop'
    elif [ "${exit_code}" -ne 0 ]; then
        printf '%s\n' 'target-failed'
    elif [ "${close_state}" = "closed" ]; then
        printf '%s\n' 'complete'
    elif [ "${close_state}" = "operator-decision" ]; then
        printf '%s\n' 'human-stop'
    elif [ "${close_state}" = "close-pending" ] &&
        [ "${handoff_count}" -lt "${handoff_limit}" ]; then
        printf '%s\n' 'resume'
    elif [ "${close_state}" = "close-pending" ]; then
        printf '%s\n' 'pending-failed'
    else
        printf '%s\n' 'invalid-close'
    fi
}

autopilot_execution_targets() {
    local plan_path="$1"
    local mode="$2"
    local gate_script="$3"
    local phase_number
    local gate_state
    local final_phase_number=""
    local final_phase_selected=0
    local -a phase_numbers=()
    local -a incomplete_phases=()

    mapfile -t phase_numbers < <(autopilot_phase_numbers "${plan_path}")
    if [ "${#phase_numbers[@]}" -gt 0 ]; then
        final_phase_number="${phase_numbers[${#phase_numbers[@]} - 1]}"
    fi
    for phase_number in "${phase_numbers[@]}"; do
        if autopilot_phase_has_unsupported_steps "${plan_path}" "${phase_number}"; then
            printf 'ERROR: phase %s contains an unsupported step state.\n' "${phase_number}" >&2
            return 2
        fi
        if autopilot_phase_has_incomplete_steps "${plan_path}" "${phase_number}"; then
            incomplete_phases+=("${phase_number}")
        fi
    done

    if [ "${#incomplete_phases[@]}" -eq 0 ]; then
        if [ "${mode}" = "next-phase" ]; then
            return
        fi
    elif [ "${mode}" = "next-phase" ]; then
        printf 'phase:%s\n' "${incomplete_phases[0]}"
        return
    fi

    autopilot_plan_has_steps "${plan_path}" || return
    for phase_number in "${phase_numbers[@]}"; do
        if autopilot_phase_has_incomplete_steps "${plan_path}" "${phase_number}"; then
            printf 'phase:%s\n' "${phase_number}"
            if [ "${phase_number}" = "${final_phase_number}" ]; then
                final_phase_selected=1
            fi
            continue
        fi
        if ! gate_state=$(
            autopilot_phase_gate_state "${plan_path}" "${phase_number}" "${gate_script}"
        ); then
            return 2
        fi
        case "${gate_state}" in
            complete|wrap) ;;
            allow)
                printf 'phase-completion:%s\n' "${phase_number}"
                if [ "${phase_number}" = "${final_phase_number}" ]; then
                    final_phase_selected=1
                fi
                ;;
            operator-decision)
                printf 'operator-stop:%s\n' "${phase_number}"
                return
                ;;
        esac
    done

    if [ "${mode}" = "whole-plan" ] && [ "${final_phase_selected}" -ne 1 ]; then
        printf '%s\n' 'completion-only'
    fi
}

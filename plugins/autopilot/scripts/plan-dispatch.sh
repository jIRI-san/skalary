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

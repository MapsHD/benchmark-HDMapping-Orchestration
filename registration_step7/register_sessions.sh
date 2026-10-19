#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-/data}"
OUTPUT_DIR="${OUTPUT_DIR:-/results}"
GROUND_TRUTH="$DATA_DIR/HDMappingGroundTruth/lio_result_0/session.mjs"
BUCKET_SIZE="${BUCKET_SIZE:-0.05}"
FORCE="${FORCE_OVERWRITE:-true}"

source "$SCRIPT_DIR/../algos_lib.sh"
check_only_algos

if [[ "$FORCE" != true && "$FORCE" != false ]]; then
    echo "ERROR: FORCE_OVERWRITE must be true or false" >&2
    exit 1
fi
if [[ ! -f "$GROUND_TRUTH" || ! -s "$GROUND_TRUTH" ]]; then
    echo "ERROR: missing or empty ground-truth session: $GROUND_TRUTH" >&2
    exit 1
fi
for command in session_to_session_rigid_registration python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: required command is not available on PATH: $command" >&2
        exit 1
    fi
done

python3 "$SCRIPT_DIR/validate_registration.py" --bucket-size "$BUCKET_SIZE"

mkdir -p -- "$OUTPUT_DIR"
SUMMARY_FILE="$OUTPUT_DIR/registration_summary.csv"
printf 'algorithm_id,source_session,target_session,bucket_size_m,registered_laz,status\n' > "$SUMMARY_FILE"

record_result() {
    local value separator=""
    for value in "$algo" "$source_session" "$GROUND_TRUTH" "$BUCKET_SIZE" "$laz" "$1"; do
        printf '%s"%s"' "$separator" "${value//\"/\"\"}"
        separator=","
    done >> "$SUMMARY_FILE"
    printf '\n' >> "$SUMMARY_FILE"
}

selected=0
registered=0
missing=0
failed=0

mapfile -t rows < <(
    for category in ROS1 ROS2 NON_ROS; do
        algo_rows "$category"
    done
)

for row in "${rows[@]}"; do
    # Preserve empty output fields, which would collapse with tab-based IFS.
    IFS='|' read -r _repo algo output _input <<< "${row//$'\t'/|}"
    if [[ -z "$algo" || "$algo" == . || "$algo" == .. || "$algo" == */* ]]; then
        echo "ERROR: invalid algorithm ID: $algo" >&2
        exit 1
    fi
    selected=$((selected + 1))
    source_session=""
    destination="$OUTPUT_DIR/$algo"
    laz="$destination/registered.laz"

    if [[ -z "$output" ]]; then
        echo "ERROR: $algo has no configured output folder" >&2
        missing=$((missing + 1))
        record_result missing
        continue
    fi

    session_dir="$DATA_DIR/$algo/output_hdmapping-$output"
    sessions=()
    for name in session.json session.mjs; do
        if [[ -f "$session_dir/$name" ]]; then
            sessions+=("$session_dir/$name")
        fi
    done
    if [[ ${#sessions[@]} -eq 0 ]]; then
        echo "ERROR: $algo has no session.json or session.mjs in $session_dir" >&2
        missing=$((missing + 1))
        record_result missing
        continue
    fi
    if [[ ${#sessions[@]} -gt 1 ]]; then
        echo "ERROR: $algo has both session.json and session.mjs in $session_dir; select one before registering" >&2
        failed=$((failed + 1))
        record_result ambiguous
        continue
    fi
    source_session="${sessions[0]}"
    if [[ -e "$destination" || -L "$destination" ]]; then
        if [[ "$FORCE" == true ]]; then
            echo "Replacing registration results for $algo: $destination"
            removed=false
            if [[ -L "$destination" ]]; then
                if rm -- "$destination"; then removed=true; fi
            elif rm -rf --one-file-system -- "$destination"; then
                removed=true
            fi
            if [[ "$removed" != true || -e "$destination" || -L "$destination" ]]; then
                echo "ERROR: could not remove existing registration results for $algo" >&2
                failed=$((failed + 1))
                record_result failed
                continue
            fi
        elif python3 "$SCRIPT_DIR/validate_registration.py" "$destination" --bucket-size "$BUCKET_SIZE"; then
            echo "Reusing completed registration for $algo: $laz"
            registered=$((registered + 1))
            record_result registered
            continue
        else
            echo "ERROR: $algo has incomplete or invalid existing results at $destination; refusing to overwrite" >&2
            failed=$((failed + 1))
            record_result existing
            continue
        fi
    fi

    mkdir -- "$destination"
    log_file="$destination/registration.log"
    echo "Registering $algo: $source_session -> $GROUND_TRUTH (bucket: $BUCKET_SIZE m)"
    status=failed
    # The application writes its sanity-check files into the working directory.
    if (
        cd "$destination"
        echo "Registration bucket size: $BUCKET_SIZE"
        session_to_session_rigid_registration "$GROUND_TRUTH" "$source_session" "$laz" "$BUCKET_SIZE"
    ) 2>&1 | tee "$log_file"; then
        # HDMapping can return zero after a solver or LAZ-writing failure.
        if python3 "$SCRIPT_DIR/validate_registration.py" "$destination" --new --bucket-size "$BUCKET_SIZE" 2>&1 | tee -a "$log_file"; then
            status=registered
        fi
    else
        echo "ERROR: registration command failed for $algo; see $log_file" >&2
    fi

    if [[ "$status" == registered ]]; then
        registered=$((registered + 1))
        echo "Registered $algo: $laz"
    else
        failed=$((failed + 1))
        echo "ERROR: $algo failed; partial results may remain in $destination" >&2
    fi
    record_result "$status"
done

echo "Step 7 summary: selected=$selected registered=$registered missing=$missing failed=$failed"
echo "Registration report: $SUMMARY_FILE"
if [[ "$registered" -eq 0 ]]; then
    echo "ERROR: Step 7 did not register any selected algorithm successfully" >&2
    exit 1
fi
if [[ "$missing" -gt 0 || "$failed" -gt 0 ]]; then
    echo "WARNING: Step 7 has unavailable or failed algorithms; Step 8 will evaluate the $registered successful registrations" >&2
fi

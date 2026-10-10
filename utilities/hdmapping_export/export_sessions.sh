#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-/data}"
OUTPUT_DIR="${OUTPUT_DIR:-/exports}"

source "$SCRIPT_DIR/../algos_lib.sh"
check_only_algos

if [[ ! -d "$DATA_DIR" ]]; then
    echo "ERROR: input directory does not exist: $DATA_DIR" >&2
    exit 1
fi
if ! command -v multi_view_tls_registration_step_2 >/dev/null 2>&1; then
    echo "ERROR: multi_view_tls_registration_step_2 is not available on PATH" >&2
    exit 1
fi

mkdir -p -- "$OUTPUT_DIR/logs"
selected=0
exported=0
missing=0
failed=0

mapfile -t rows < <(
    for category in ROS1 ROS2 NON_ROS; do
        algo_rows "$category"
    done
)

for row in "${rows[@]}"; do
    # Tabs are IFS whitespace; use a non-whitespace delimiter to preserve empty output fields.
    IFS='|' read -r _repo algo output _input <<< "${row//$'\t'/|}"
    selected=$((selected + 1))
    if [[ -z "$output" ]]; then
        echo "ERROR: $algo has no configured output folder" >&2
        missing=$((missing + 1))
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
        continue
    fi
    if [[ ${#sessions[@]} -gt 1 ]]; then
        echo "ERROR: $algo has both session.json and session.mjs in $session_dir; select one before exporting" >&2
        failed=$((failed + 1))
        continue
    fi

    destination="$OUTPUT_DIR/$algo"
    laz="$destination/all_step_2.laz"
    trajectory="$destination/trajectories.csv"
    if [[ -e "$laz" || -L "$laz" || -e "$trajectory" || -L "$trajectory" ]]; then
        echo "ERROR: $algo has existing export files in $destination; refusing to overwrite" >&2
        failed=$((failed + 1))
        continue
    fi

    log_file="$OUTPUT_DIR/logs/$algo.log"
    echo "Exporting $algo: ${sessions[0]} -> $destination"
    if multi_view_tls_registration_step_2 "${sessions[0]}" --export "$destination" 2>&1 | tee "$log_file"; then
        if [[ -s "$laz" && -s "$trajectory" ]]; then
            echo "Exported $algo"
            exported=$((exported + 1))
        else
            echo "ERROR: $algo returned success without both nonempty export files; see $log_file" >&2
            failed=$((failed + 1))
        fi
    else
        echo "ERROR: export failed for $algo; partial files may remain in $destination; see $log_file" >&2
        failed=$((failed + 1))
    fi
done

echo "HDMapping export summary: selected=$selected exported=$exported missing=$missing failed=$failed"
if [[ "$exported" -eq 0 || "$missing" -gt 0 || "$failed" -gt 0 ]]; then
    echo "ERROR: HDMapping export did not export every selected algorithm successfully" >&2
    exit 1
fi

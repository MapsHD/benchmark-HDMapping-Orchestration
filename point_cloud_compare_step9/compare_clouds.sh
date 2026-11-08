#!/bin/bash
# Step 9 container entry point. Renders the Step 8 FARO reference and every cloud
# Step 8 reported as evaluated from the same 14 orthographic views, using
# cloud_visual_compare with its default options except --resolution.
#
# Mounts: /evaluation (Step 8 output, read-only), /comparison (Step 9 output).
# RESOLUTION: render size in full/ along the longer side (default: 8192).

set -euo pipefail

EVALUATION=/evaluation
OUTPUT=/comparison
REFERENCE="$EVALUATION/reference/faro.ply"
SUMMARY="$EVALUATION/evaluation_summary.csv"
LOG="$OUTPUT/compare.log"
RESOLUTION="${RESOLUTION:-8192}"

source /workspace/algos_lib.sh
check_only_algos

for path in "$REFERENCE" "$SUMMARY"; do
    if [[ ! -f "$path" || ! -s "$path" ]]; then
        echo "ERROR: missing or empty Step 8 output: $path" >&2
        exit 1
    fi
done

# OpenCL drivers the loader may use, chosen by run_compare_step9.sh --opencl.
VENDORS="${OCL_ICD_VENDORS:-/etc/OpenCL/vendors}"
icds=("$VENDORS"/*.icd)
if [[ ! -f "${icds[0]}" ]]; then
    echo "ERROR: this image has no OpenCL driver for the selected mode: $VENDORS" >&2
    exit 1
fi
echo "OpenCL drivers: ${icds[*]##*/}"

# Algorithm IDs whose last Step 8 status is "evaluated". The leading columns
# (algorithm_id, registration_status, status) never contain commas. Python's csv
# module writes CRLF line endings, so a trailing \r is stripped first.
evaluated="$(awk -F, '
    { sub(/\r$/, "") }
    NR == 1 {
        for (i = 1; i <= NF; i++) {
            if ($i == "algorithm_id") id_col = i
            if ($i == "status") status_col = i
        }
        if (!id_col || !status_col) { print "invalid header" > "/dev/stderr"; exit 1 }
        next
    }
    $status_col == "evaluated" { print $id_col }
' "$SUMMARY")" || {
    echo "ERROR: cannot read algorithm statuses from $SUMMARY" >&2
    exit 1
}

# Comparison clouds in algorithms.conf order, the same order as Step 8 reports.
compare_args=()
count=0
for category in ROS1 ROS2 NON_ROS; do
    while IFS=$'\t' read -r _ id _ _; do
        ply="$EVALUATION/$id/registered.ply"
        if ! grep -qxF -- "$id" <<< "$evaluated"; then
            echo "SKIP: $id: not evaluated in Step 8"
        elif [[ ! -f "$ply" || ! -s "$ply" ]]; then
            echo "SKIP: $id: $ply is missing or empty"
        else
            compare_args+=(--compare "$ply")
            count=$((count + 1))
        fi
    done < <(algo_rows "$category")
done

if [[ $count -eq 0 ]]; then
    echo "ERROR: no evaluated Step 8 clouds to compare" >&2
    exit 1
fi

echo "Reference: $REFERENCE"
echo "Comparing $count Step 8 clouds at $RESOLUTION px; full log: $LOG"
cloud_visual_compare \
    --reference "$REFERENCE" \
    "${compare_args[@]}" \
    --resolution "$RESOLUTION" \
    --output-dir "$OUTPUT" 2>&1 | tee "$LOG"

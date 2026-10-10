#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-/data}"
OUTPUT_DIR="${OUTPUT_DIR:-/results}"
GROUND_TRUTH="$DATA_DIR/HDMappingGroundTruth/lio_result_0/session.mjs"
BUCKET_SIZE=0.01

source "$SCRIPT_DIR/../algos_lib.sh"
check_only_algos

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

validate_laz() {
    python3 - "$1" <<'PY'
import math
from pathlib import Path
import struct
import sys

path = Path(sys.argv[1])
try:
    with path.open("rb") as handle:
        header = handle.read(375)
    if len(header) < 227 or header[:4] != b"LASF":
        raise ValueError("missing or truncated LAS header")
    version = tuple(header[24:26])
    if version not in ((1, 2), (1, 3), (1, 4)):
        raise ValueError(f"unsupported LAS version {version}")
    header_size, data_offset = struct.unpack_from("<HI", header, 94)
    minimum_header_size = {(1, 2): 227, (1, 3): 235, (1, 4): 375}[version]
    if header_size < minimum_header_size or data_offset < header_size:
        raise ValueError("invalid header size or point-data offset")
    if path.stat().st_size <= data_offset:
        raise ValueError("no point data follows the header")
    points = struct.unpack_from("<I", header, 107)[0]
    if version == (1, 4):
        points = struct.unpack_from("<Q", header, 247)[0] or points
    if points == 0:
        raise ValueError("registered point cloud contains no points")
    scales_and_offsets = struct.unpack_from("<6d", header, 131)
    bounds = struct.unpack_from("<6d", header, 179)
    if not all(math.isfinite(value) for value in scales_and_offsets + bounds):
        raise ValueError("nonfinite coordinate metadata")
    if any(scale <= 0 for scale in scales_and_offsets[:3]):
        raise ValueError("invalid coordinate scales")
    if any(bounds[i] < bounds[i + 1] for i in (0, 2, 4)):
        raise ValueError("invalid coordinate bounds")
except (OSError, ValueError, struct.error) as error:
    sys.exit(f"ERROR: invalid registered point cloud {path}: {error}")
print(f"Validated LAZ header: {points} points in {path}")
PY
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
        echo "ERROR: $algo has an existing result folder at $destination; refusing to overwrite" >&2
        failed=$((failed + 1))
        record_result existing
        continue
    fi

    mkdir -- "$destination"
    log_file="$destination/registration.log"
    echo "Registering $algo: $source_session -> $GROUND_TRUTH (bucket: $BUCKET_SIZE m)"
    status=failed
    # The application writes its sanity-check files into the working directory.
    if (
        cd "$destination"
        session_to_session_rigid_registration "$GROUND_TRUTH" "$source_session" "$laz" "$BUCKET_SIZE"
    ) 2>&1 | tee "$log_file"; then
        # HDMapping can return zero after a solver or LAZ-writing failure.
        if grep -Ei 'AtPA=AtPB FAILED|DLL ERROR|problem with saving file|Rigid registration failed|(^|[^[:alnum:]_])[-+]?(nan|inf|infinity)([^[:alnum:]_]|$)' "$log_file"; then
            echo "ERROR: $algo reported a registration or export failure; see $log_file" >&2
        elif [[ ! -s "$destination/sanity_check_trg.txt" || ! -s "$destination/sanity_check_src.txt" ]]; then
            echo "ERROR: $algo did not produce both nonempty sanity-check trajectories; see $log_file" >&2
        elif validate_laz "$laz" 2>&1 | tee -a "$log_file"; then
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
if [[ "$registered" -eq 0 || "$missing" -gt 0 || "$failed" -gt 0 ]]; then
    echo "ERROR: Step 7 did not register every selected algorithm successfully" >&2
    exit 1
fi

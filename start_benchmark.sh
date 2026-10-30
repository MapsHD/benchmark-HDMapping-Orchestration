#!/bin/bash

set -e

usage() {
    echo "Usage: $0 [--bucket-size METERS] [--voxel-size METERS] [--threshold METERS] [--jobs N] [--no-force] [algo ...]"
    echo
    echo "Runs the whole benchmark pipeline (steps 1-8) on one Oxford Spires sequence."
    echo "Step 1 downloads it (if needed) and converts it to the canonical bag; see README, 'Oxford Spires'."
    echo "Environment: OXFORD_SPIRES_SEQUENCE (default 2024-03-12-keble-college-02),"
    echo "  OXFORD_SPIRES_DOWNLOAD_DIR (default <data dir>/download), STEP8_TIMEOUT (default 900 s),"
    echo "  ALGO_BRANCH (algorithm repos' branch, default hdmapping-benchmark-canonical)."
    echo "Optionally pass algorithm ids (the 'id' column of algorithms.conf) to"
    echo "clone, build, run and evaluate only those, e.g.:"
    echo "  $0 sr-lio r-voxelmap pv-lio rko-lio pin-slam"
    echo "Use --bucket-size METERS for Step 7's registration bucket (default: 0.05 m; > 0)."
    echo "Use --voxel-size METERS for Step 8's voxel filter (default: 0.05 m; 0 disables filtering)."
    echo "Use --threshold METERS for Step 8's precision/recall agreement (default: 0.05 m; > 0)."
    echo "These settings are independent and validated before any stage runs."
    echo "Use --jobs N for simultaneous Step 8 evaluations (default: 1; positive integer)."
    echo "Step 8 shows per-worker progress and merges reports after all workers finish."
    echo "Steps 7 and 8 permanently replace selected results by default."
    echo "Use --no-force to preserve their existing results."
    echo "No algorithm ids = all algorithms. An unknown id aborts with the known list."
}

ALGORITHMS=()
BUCKET_SIZE=0.05
VOXEL_SIZE=0.05
THRESHOLD=0.05
JOBS=1
OVERWRITE_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --bucket-size|--voxel-size|--threshold)
            if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
                echo "ERROR: $1 requires a distance in meters" >&2
                exit 1
            fi
            case "$1" in
                --bucket-size) BUCKET_SIZE="$2" ;;
                --voxel-size) VOXEL_SIZE="$2" ;;
                --threshold) THRESHOLD="$2" ;;
            esac
            shift 2
            ;;
        --jobs)
            if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "ERROR: --jobs requires a positive integer" >&2
                exit 1
            fi
            JOBS="$2"
            shift 2
            ;;
        --no-force)
            OVERWRITE_ARGS=("$1")
            shift
            ;;
        -*)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            ALGORITHMS+=("$1")
            shift
            ;;
    esac
done


REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SEQUENCE="${OXFORD_SPIRES_SEQUENCE:-2024-03-12-keble-college-02}"
NAME="$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//' <<<"$SEQUENCE")"
DATA_DIR=~/hdmapping-benchmark/data
DOWNLOAD_DIR="${OXFORD_SPIRES_DOWNLOAD_DIR:-$DATA_DIR/download}"
STEP8_TIMEOUT="${STEP8_TIMEOUT:-900}"
mkdir -p "$DATA_DIR"
# validate.sh reads the sequence from the environment.
export OXFORD_SPIRES_SEQUENCE="$SEQUENCE"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: Python 3 is required to validate Step 7 and Step 8 settings" >&2
    exit 1
fi
python3 -B - "$REPO_DIR/registration_step7" "$BUCKET_SIZE" "$VOXEL_SIZE" "$THRESHOLD" <<'PY'
import argparse
import sys

sys.path.insert(0, sys.argv[1])
from validate_registration import nonnegative_distance, positive_distance

for option, value, validator in (
    ("--bucket-size", sys.argv[2], positive_distance),
    ("--voxel-size", sys.argv[3], nonnegative_distance),
    ("--threshold", sys.argv[4], positive_distance),
):
    try:
        validator(value)
    except argparse.ArgumentTypeError as error:
        sys.exit(f"ERROR: invalid {option}: {error}")
PY

# Optional algorithm subset, exported so steps 2, 3, 4, 7 and 8 pick it up.
if [[ ${#ALGORITHMS[@]} -gt 0 ]]; then
    export ONLY_ALGOS="${ALGORITHMS[*]}"
    echo "=== Restricting the benchmark to: $ONLY_ALGOS ==="
fi

cd "$DATA_DIR"

echo "=== Step 1: prepare_data_step1 (Oxford Spires $SEQUENCE -> canonical bag) ==="
OXFORD="$REPO_DIR/prepare_data_step1/oxford_spires"
if [ -f "$DATA_DIR/$NAME.bag" ] && [ -d "$DATA_DIR/$NAME-ros2" ] && [ -d "$DATA_DIR/$NAME-hdmapping" ] && \
   [ -f "$DATA_DIR/ground_truth.tum" ] && [ -f "$DATA_DIR/HDMappingGroundTruth/lio_result_0/session.mjs" ] && \
   [ -f "$DATA_DIR/TLS-FARO-Focus/map_gt_0.01.laz" ]; then
    echo "Step 1 outputs exist. Skipping."
else
    # Builds the images and downloads what is missing, then converts.
    bash "$OXFORD/prepare.sh" "$SEQUENCE" "$DOWNLOAD_DIR" "$DATA_DIR" "$NAME"
fi

bash "$REPO_DIR/validate.sh"

sleep 5

echo "=== Step 2: clone_github_repositories_step2 ==="
cd "$REPO_DIR/clone_github_repositories_step2"
chmod +x *.sh
# Algorithm repos: one canonical-bag branch per algorithm, the same for every
# dataset converted to the canonical bag.
./clone_github_repositories_step2.sh "${ALGO_BRANCH:-hdmapping-benchmark-canonical}"

sleep 5

echo "=== Step 3: run_benchmark_step3 ==="
cd "$REPO_DIR/run_benchmark_step3"
chmod +x *.sh
./run_benchmark_step3.sh \
    "$DATA_DIR/$NAME.bag" \
    "$DATA_DIR/$NAME-ros2" \
    "$DATA_DIR"

echo "=== DONE ==="

sleep 5

echo "=== Step 4: conversion_tum_step4 ==="
cd "$REPO_DIR/conversion_tum_step4"
chmod +x *.sh
./run_tum_step4.sh

sleep 5

echo "=== Step 5: evo_step5 ==="
cd "$REPO_DIR/evo_step5"
chmod +x *.sh
./tum-to-latex_step5.sh

sleep 5

echo "=== Step 6: overlap_step6 ==="
cd "$REPO_DIR/overlap_step6"

if command -v python3 >/dev/null 2>&1; then
    python3 overlap.py
elif command -v python >/dev/null 2>&1; then
    python overlap.py
else
    echo "ERROR: neither python3 nor python found on machine"
    exit 1
fi

sleep 5

echo "=== Step 7: registration_step7 ==="
bash "$REPO_DIR/registration_step7/run_registration_step7.sh" \
    --data-dir "$DATA_DIR" \
    --bucket-size "$BUCKET_SIZE" \
    "${OVERWRITE_ARGS[@]}"

sleep 5

echo "=== Step 8: point_cloud_evaluation_step8 ==="
bash "$REPO_DIR/point_cloud_evaluation_step8/run_evaluation_step8.sh" \
    --data-dir "$DATA_DIR" \
    --voxel-size "$VOXEL_SIZE" \
    --threshold "$THRESHOLD" \
    --jobs "$JOBS" \
    --timeout "$STEP8_TIMEOUT" \
    "${OVERWRITE_ARGS[@]}"

echo "=== DONE ==="

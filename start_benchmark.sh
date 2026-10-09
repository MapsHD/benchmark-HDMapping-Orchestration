#!/bin/bash

set -e

usage() {
    echo "Usage: $0 [--bucket-size METERS] [--voxel-size METERS] [--threshold METERS] [--jobs N] [algo ...]"
    echo
    echo "Runs the whole benchmark pipeline (steps 1-8)."
    echo "Checks workspace setup, dataset and prerequisite Docker images first."
    echo "Optionally pass algorithm ids (the 'id' column of algorithms.conf) to"
    echo "clone, build, run and evaluate only those, e.g.:"
    echo "  $0 sr-lio r-voxelmap pv-lio rko-lio pin-slam"
    echo "Use --bucket-size METERS for Step 7's registration bucket (default: 0.05 m; > 0)."
    echo "Use --voxel-size METERS for Step 8's voxel filter (default: 0.05 m; 0 disables filtering)."
    echo "Use --threshold METERS for Step 8's precision/recall agreement (default: 0.05 m; > 0)."
    echo "These settings are independent and validated before any stage runs."
    echo "Use --jobs N for simultaneous Step 8 evaluations (default: 1; positive integer)."
    echo "Step 8 shows per-worker progress and merges reports after all workers finish."
    echo "No algorithm ids = all algorithms. An unknown id aborts with the known list."
}

ALGORITHMS=()
BUCKET_SIZE=0.05
VOXEL_SIZE=0.05
THRESHOLD=0.05
JOBS=1
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


DATA_DIR=~/hdmapping-benchmark/data
REPO_DIR=~/hdmapping-benchmark/benchmark-HDMapping-Orchestration

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

bash "$REPO_DIR/validate.sh"

cd "$DATA_DIR"

echo "=== Step 1: prepare_data_step1 ==="

if [ -f "$DATA_DIR/reg-1.bag-pc.bag" ] && \
   [ -d "$DATA_DIR/reg-1-ros2" ] && \
   [ -d "$DATA_DIR/reg-1-ros2-lidar" ]; then

    echo "Step 1 outputs exist. Skipping."

else

    echo "Step 1 incomplete. Missing:"

    if [ ! -f "$DATA_DIR/reg-1.bag-pc.bag" ]; then
        echo " - reg-1.bag-pc.bag"
    fi

    if [ ! -d "$DATA_DIR/reg-1-ros2" ]; then
        echo " - reg-1-ros2"
    fi

    if [ ! -d "$DATA_DIR/reg-1-ros2-lidar" ]; then
        echo " - reg-1-ros2-lidar"
    fi

    echo "Removing old partial outputs..."

    rm -rf \
        "$DATA_DIR/reg-1.bag-pc.bag" \
        "$DATA_DIR/reg-1-ros2" \
        "$DATA_DIR/reg-1-ros2-lidar"

    echo "Starting Step 1 conversion..."

    cd "$REPO_DIR/prepare_data_step1"
    chmod +x *.sh

    ./prepare_data_step1.sh \
        "$DATA_DIR/reg-1.bag" \
        "$DATA_DIR"

fi

# HDMapping (Mandeye) format data, the 'hdmapping' input of algorithms.conf.
# Checked on its own, so a setup that already has the outputs above only adds
# this folder, and only when a selected algorithm uses it.
source "$REPO_DIR/algos_lib.sh"
needs_input() {
    for category in ROS1 ROS2 NON_ROS; do algo_rows "$category"; done |
        awk -F'\t' -v kind="$1" '$4 == kind { found = 1 } END { exit !found }'
}
if needs_input hdmapping; then
    if [ -d "$DATA_DIR/reg-1-hdmapping" ]; then
        echo "HDMapping-format data exists. Skipping."
    else
        echo "Converting reg-1.bag to HDMapping (Mandeye) format..."
        chmod +x "$REPO_DIR/prepare_data_step1/mandeye-convert.sh"
        rm -rf "$DATA_DIR/reg-1-hdmapping.partial"
        "$REPO_DIR/prepare_data_step1/mandeye-convert.sh" \
            "$DATA_DIR/reg-1.bag" \
            "$DATA_DIR/reg-1-hdmapping.partial" \
            ros1-to-hdmapping
        mv "$DATA_DIR/reg-1-hdmapping.partial" "$DATA_DIR/reg-1-hdmapping"
    fi
fi

sleep 5

echo "=== Step 2: clone_github_repositories_step2 ==="
cd "$REPO_DIR/clone_github_repositories_step2"
chmod +x *.sh
./clone_github_repositories_step2.sh Bunker-DVI-Dataset-reg-1

sleep 5

echo "=== Step 3: run_benchmark_step3 ==="
cd "$REPO_DIR/run_benchmark_step3"
chmod +x *.sh
./run_benchmark_step3.sh \
    "$DATA_DIR/reg-1.bag" \
    "$DATA_DIR/reg-1-ros2" \
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
    --bucket-size "$BUCKET_SIZE"

sleep 5

echo "=== Step 8: point_cloud_evaluation_step8 ==="
bash "$REPO_DIR/point_cloud_evaluation_step8/run_evaluation_step8.sh" \
    --data-dir "$DATA_DIR" \
    --voxel-size "$VOXEL_SIZE" \
    --threshold "$THRESHOLD" \
    --jobs "$JOBS"

echo "=== DONE ==="

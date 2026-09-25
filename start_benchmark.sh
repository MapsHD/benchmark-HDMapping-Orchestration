#!/bin/bash

set -e

usage() {
    echo "Usage: $0 [algo ...]"
    echo
    echo "Runs the whole benchmark pipeline (steps 1-6)."
    echo "Optionally pass algorithm ids (the 'id' column of algorithms.conf) to"
    echo "clone, build, run and evaluate only those, e.g.:"
    echo "  $0 sr-lio r-voxelmap pv-lio rko-lio pin-slam"
    echo "No arguments = all algorithms. An unknown id aborts with the known list."
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

DATA_DIR=~/hdmapping-benchmark/data
REPO_DIR=~/hdmapping-benchmark/benchmark-HDMapping-Orchestration

# Optional algorithm subset, exported so steps 2, 3 and 4 pick it up.
if [[ $# -gt 0 ]]; then
    export ONLY_ALGOS="$*"
    echo "=== Restricting the benchmark to: $ONLY_ALGOS ==="
fi

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

echo "=== DONE ==="

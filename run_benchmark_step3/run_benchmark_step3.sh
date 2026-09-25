#!/bin/bash

usage() {
  echo "Usage:"
  echo "  $0 <ros1_bag> <ros2_bag_dir> <output_dir>"
  echo
  echo "ros1_bag      : path to a ROS1 .bag file"
  echo "ros2_bag_dir  : path to a ROS2 bag directory"
  echo "output_dir    : directory to store outputs"
  echo
  echo "The list of algorithms lives in algorithms.conf, one line per algorithm."
  echo "Set ONLY_ALGOS=\"id1 id2 ...\" (ids as spelled there) to run only those."
  exit 1
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

if [[ $# -ne 3 ]]; then
    usage
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../algos_lib.sh"

ROS1_BAG=$(realpath "$1")
ROS2_BAG_DIR=$(realpath "$2")
OUTPUT_DIR=$(realpath "$3")

mkdir -p "$OUTPUT_DIR"

CLONE_DIR="$HOME/hdmapping-benchmark"

check_only_algos

# Resolve the "input" column of algorithms.conf to an actual path.
resolve_input() {
  case "$1" in
    raw)        echo "$ROS1_BAG" ;;
    pc)         echo "${ROS1_BAG}-pc.bag" ;;
    ros2)       echo "$ROS2_BAG_DIR" ;;
    ros2-lidar) echo "${ROS2_BAG_DIR}-lidar" ;;
    *)          echo "" ;;
  esac
}

# Non-ROS (standalone/offline) algorithms run last: no roscore/tmux/rosbag
# record, the algorithm reads the bag file directly. On a host without an
# NVIDIA GPU, PIN-SLAM falls back to CPU, which is much slower and would
# otherwise delay all the other algorithms.
# The table is read on file descriptor 3, NOT stdin: the run scripts use
# "docker run -it", which needs stdin to stay the terminal. Feeding the loop
# on stdin makes docker fail with "stdin is not a terminal" for every
# algorithm, so nothing runs and old outputs are silently re-evaluated.
for category in ROS1 ROS2 NON_ROS; do
  while IFS=$'\t' read -r -u 3 repo id output input; do
    [ -n "$repo" ] || continue

    script="$(run_script "$id" "$category")"

    # Some repos (e.g. benchmark-HDMapping_LIO-to-HDMapping) ship only a README
    # describing a manual procedure — there is no run script to call.
    if [[ ! -x "$CLONE_DIR/$repo/$script" ]]; then
        echo "=== Skipping $id: $repo has no $script (manual procedure, see its README) ==="
        continue
    fi

    INPUT="$(resolve_input "$input")"
    if [[ -z "$INPUT" ]]; then
        echo "=== Skipping $id: unknown input kind '$input' in algorithms.conf ==="
        continue
    fi

    OUTPUT="$OUTPUT_DIR/$id"
    mkdir -p "$OUTPUT"

    echo "=== Waiting 5 seconds before running $id ==="
    sleep 5

    cd "$CLONE_DIR/$repo" || continue
    echo "=== Running $id in $(pwd) on $INPUT ==="
    "./$script" "$INPUT" "$OUTPUT"

    cd "$CLONE_DIR" || exit
    echo "=== Finished $id ==="
  done 3< <(algo_rows "$category")
done

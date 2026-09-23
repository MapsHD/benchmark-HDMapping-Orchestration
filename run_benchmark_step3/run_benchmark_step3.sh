#!/bin/bash

usage() {
  echo "Usage:"
  echo "  $0 <ros1_bag> <ros2_bag_dir> <output_dir>"
  echo
  echo "ros1_bag      : path to a ROS1 .bag file"
  echo "ros2_bag_dir  : path to a ROS2 bag directory"
  echo "output_dir    : directory to store outputs"
  echo
  echo "Set ONLY_ALGOS=\"algo1 algo2 ...\" (names as in the *_ALGOS arrays) to run only those."
  exit 1
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

if [[ $# -ne 3 ]]; then
    usage
fi

ROS1_BAG=$(realpath "$1")
ROS2_BAG_DIR=$(realpath "$2")
OUTPUT_DIR=$(realpath "$3")

mkdir -p "$OUTPUT_DIR"

CLONE_DIR="$HOME/hdmapping-benchmark"

# Optional: restrict this step to a space-separated list of algorithm names
# (as spelled in the *_ALGOS arrays below). Empty (default) = all algorithms.
ONLY_ALGOS="${ONLY_ALGOS:-}"
wanted() { [[ -z "$ONLY_ALGOS" ]] || [[ " $ONLY_ALGOS " == *" $1 "* ]]; }
if [ -n "$ONLY_ALGOS" ]; then
    echo "ONLY_ALGOS set — running only: $ONLY_ALGOS"
fi

ROS1_REPOS=(
"benchmark-FAST-LIO-to-HDMapping"
"benchmark-DLO-to-HDMapping"
"benchmark-Super-LIO-to-HDMapping"
"benchmark-DLIO-to-HDMapping"
"benchmark-Faster-LIO-to-HDMapping"
"benchmark-iG-LIO-to-HDMapping"
"benchmark-I2EKF-LO-to-HDMapping"
"benchmark-CT-ICP-to-HDMapping"
"benchmark-LOAM-Livox-to-HDMapping"
"benchmark-LIO-EKF-to-HDMapping"
"benchmark-LeGO-LOAM-to-HDMapping"
"benchmark-Point-LIO-to-HDMapping"
"benchmark-VoxelMap-to-HDMapping"
"benchmark-SLICT-to-HDMapping"
"benchmark-FORM-to-HDMapping"
"benchmark-C3P-VoxelMap-to-HDMapping"
"benchmark-NV-LIOM-to-HDMapping"
"benchmark-SE3-LIO-to-HDMapping"
"benchmark-DALI_SLAM-to-HDMapping"
"benchmark-Voxel-SLAM-to-HDMapping"
"benchmark-MM-LINS-to-HDMapping"
"benchmark-LOG-LIO2-to-HDMapping"
"benchmark-SR-LIO-to-HDMapping"
"benchmark-R-VoxelMap-to-HDMapping"
"benchmark-PV-LIO-to-HDMapping"
"benchmark-HDMapping_LIO-to-HDMapping"
)

ROS2_REPOS=(
"benchmark-SuperOdometry-to-HDMapping"
"benchmark-KISS-ICP-to-HDMapping"
"benchmark-GenZ-ICP-to-HDMapping"
"benchmark-lidar_odometry_ros_wrapper-to-HDMapping"
"benchmark-EllipseLIO-to-HDMapping"
"benchmark-D-LIO-to-HDMapping"
"benchmark-GLIM-to-HDMapping"
"benchmark-BIEVR-LIO-to-HDMapping"
"benchmark-rko_lio-to-HDMapping"
)

NON_ROS_REPOS=(
"benchmark-PIN-SLAM-to-HDMapping"
)

ROS1_ALGOS=(
  "fast-lio"    
  "dlo"
  "super-lio"
  "dlio"
  "faster-lio"
  "ig-lio"
  "i2ekf-lo"
  "ct-icp"
  "loam"
  "lio-ekf"
  "lego-loam"
  "point-lio"
  "voxel-map"
  "slict"
  "form"
  "c3p-voxelmap"
  "nv-liom"
  "se3-lio"
  "dalislam"
  "voxelslam"
  "mm-lins"
  "log-lio2"
  "sr-lio"
  "r-voxelmap"
  "pv-lio"
  "hdmapping-lio"
)

for i in "${!ROS1_ALGOS[@]}"; do
    algo="${ROS1_ALGOS[$i]}"
    repo="${ROS1_REPOS[$i]}"
    OUTPUT="$OUTPUT_DIR/$algo"
    wanted "$algo" || continue

    # Some repos (e.g. benchmark-HDMapping_LIO-to-HDMapping) ship only a README
    # describing a manual procedure — there is no dockerized run script to call.
    if [[ ! -x "$CLONE_DIR/$repo/docker_session_run-ros1-$algo.sh" ]]; then
        echo "=== Skipping $algo: $repo has no docker_session_run-ros1-$algo.sh (manual procedure, see its README) ==="
        continue
    fi

    mkdir -p "$OUTPUT"

if [[ "$algo" == "dlio" || \
      "$algo" == "dlo" || \
      "$algo" == "loam" || \
      "$algo" == "ct-icp" || \
      "$algo" == "lego-loam" || \
      "$algo" == "form" || \
      "$algo" == "nv-liom" || \
      "$algo" == "se3-lio" || \
      "$algo" == "voxelslam" || \
      "$algo" == "dalislam" || \
      "$algo" == "log-lio2" || \
      "$algo" == "sr-lio" || \
      "$algo" == "lio-ekf" ]]; then
    INPUT="${ROS1_BAG}-pc.bag"
else
    INPUT="$ROS1_BAG"
fi

    echo "=== Waiting 5 seconds before running $algo ==="
    sleep 5

    cd "$CLONE_DIR/$repo"
    echo "=== Running $algo in $(pwd) on $INPUT ==="
    ./docker_session_run-ros1-"$algo".sh "$INPUT" "$OUTPUT"

    cd "$CLONE_DIR"
    echo "=== Finished $algo ==="
done

ROS2_ALGOS=(
  "superOdom"
  "kiss-icp"
  "genz-icp"
  "lidar_odometry_ros_wrapper"
  "ellipselio"
  "d-lio"
  "glim"
  "bievr-lio"
  "rko-lio"
)

for i in "${!ROS2_ALGOS[@]}"; do
    algo="${ROS2_ALGOS[$i]}"
    repo="${ROS2_REPOS[$i]}"
    OUTPUT="$OUTPUT_DIR/$algo"
    wanted "$algo" || continue
    mkdir -p "$OUTPUT"

    if [[ "$algo" == "resple" || "$algo" == "superOdom" ]]; then
        INPUT="${ROS2_BAG_DIR}-lidar"
    else
        INPUT="$ROS2_BAG_DIR"
    fi

    echo "=== Waiting 5 seconds before running $algo ==="
    sleep 5

    cd "$CLONE_DIR/$repo"
    echo "=== Running $algo in $(pwd) on $INPUT ==="
    ./docker_session_run-ros2-"$algo".sh "$INPUT" "$OUTPUT"

    cd "$CLONE_DIR"
    echo "=== Finished $algo ==="
done

# Non-ROS (standalone/offline) algorithms: no roscore/tmux/rosbag record, the
# algorithm reads the bag file directly. They consume the aggregated
# PointCloud2 bag (-pc.bag). Run last: on a host without an NVIDIA GPU,
# PIN-SLAM falls back to CPU, which is much slower and would otherwise delay
# all the other algorithms.
NON_ROS_ALGOS=(
  "pin-slam"
)

for i in "${!NON_ROS_ALGOS[@]}"; do
    algo="${NON_ROS_ALGOS[$i]}"
    repo="${NON_ROS_REPOS[$i]}"
    OUTPUT="$OUTPUT_DIR/$algo"
    wanted "$algo" || continue

    if [[ ! -x "$CLONE_DIR/$repo/docker_session_run-$algo.sh" ]]; then
        echo "=== Skipping $algo: $repo has no docker_session_run-$algo.sh ==="
        continue
    fi

    mkdir -p "$OUTPUT"
    INPUT="${ROS1_BAG}-pc.bag"

    echo "=== Waiting 5 seconds before running $algo ==="
    sleep 5

    cd "$CLONE_DIR/$repo"
    echo "=== Running $algo in $(pwd) on $INPUT ==="
    ./docker_session_run-"$algo".sh "$INPUT" "$OUTPUT"

    cd "$CLONE_DIR"
    echo "=== Finished $algo ==="
done

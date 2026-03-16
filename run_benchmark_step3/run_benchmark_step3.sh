#!/bin/bash

usage() {
  echo "Usage:"
  echo "  $0 <ros1_bag> <ros2_bag_dir> <output_dir>"
  echo
  echo "ros1_bag      : path to a ROS1 .bag file"
  echo "ros2_bag_dir  : path to a ROS2 bag directory"
  echo "output_dir    : directory to store outputs"
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

ROS1_REPOS=(
"benchmark-FAST-LIO-to-HDMapping"
"benchmark-DLO-to-HDMapping"
"benchmark-Super-LIO-to-HDMapping"
"benchmark-DLIO-to-HDMapping"
"benchmark-Faster-LIO-to-HDMapping"
"benchmark-iG-LIO-to-HDMapping"
"benchmark-I2EKF-LO-to-HDMapping"
"benchmark-CT-ICP-to-HDMapping"
"benchmark-LIO-EKF-to-HDMapping"
"benchmark-LeGO-LOAM-to-HDMapping"
"benchmark-Point-LIO-to-HDMapping"
"benchmark-VoxelMap-to-HDMapping"
)

ROS2_REPOS=(
"benchmark-SuperOdometry-to-HDMapping"
"benchmark-KISS-ICP-to-HDMapping"
"benchmark-GenZ-ICP-to-HDMapping"
"benchmark-lidar_odometry_ros_wrapper-to-HDMapping"
"benchmark-GLIM-to-HDMapping"
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
  "lio-ekf"
  "lego-loam"
  "point-lio"
  "voxel-map"
)

for i in "${!ROS1_ALGOS[@]}"; do
    algo="${ROS1_ALGOS[$i]}"
    repo="${ROS1_REPOS[$i]}"
    OUTPUT="$OUTPUT_DIR/$algo"
    mkdir -p "$OUTPUT"

    INPUT="$ROS1_BAG"

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
  "glim"
)

for i in "${!ROS2_ALGOS[@]}"; do
    algo="${ROS2_ALGOS[$i]}"
    repo="${ROS2_REPOS[$i]}"
    OUTPUT="$OUTPUT_DIR/$algo"
    mkdir -p "$OUTPUT"

    INPUT="$ROS2_BAG_DIR"

    echo "=== Waiting 5 seconds before running $algo ==="
    sleep 5

    cd "$CLONE_DIR/$repo"
    echo "=== Running $algo in $(pwd) on $INPUT ==="
    ./docker_session_run-ros2-"$algo".sh "$INPUT" "$OUTPUT"

    cd "$CLONE_DIR"
    echo "=== Finished $algo ==="
done
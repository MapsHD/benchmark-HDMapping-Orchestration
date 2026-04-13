#!/bin/bash
set -e

ROS1_BAG="$1"
OUTPUT_DIR="$2"

if [[ -z "$ROS1_BAG" || -z "$OUTPUT_DIR" ]]; then
  echo "Usage: $0 <ros1_bag> <output_dir>"
  exit 1
fi

ROS1_BAG=$(realpath "$ROS1_BAG")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")

mkdir -p "$OUTPUT_DIR"

BAG_NAME=$(basename "$ROS1_BAG" .bag)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROS1_PC_SCRIPT="$SCRIPT_DIR/livox_bag.sh"
CONVERSION_SCRIPT="$SCRIPT_DIR/mandeye-convert.sh"

echo "==========================================="
echo "Processing: $BAG_NAME"
echo "==========================================="

echo "ROS1 -> aggregated pointcloud (-pc)"
"$ROS1_PC_SCRIPT" \
  "$ROS1_BAG" \
  "$OUTPUT_DIR"

PC_BAG="$OUTPUT_DIR/${BAG_NAME}-pc.bag"

echo "ROS1 -> ROS2"
"$CONVERSION_SCRIPT" \
  "$ROS1_BAG" \
  "$OUTPUT_DIR" \
  "ros1-to-ros2"

echo "==========================================="
echo "DONE"
echo "PC bag: $PC_BAG"
echo "==========================================="
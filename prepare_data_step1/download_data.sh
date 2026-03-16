#!/bin/bash

BASE="https://huggingface.co/datasets/kubchud/kitti_to_ros/resolve/main"
TARGET="$HOME/hdmapping-benchmark/data"
OUTDIR="kitti_${SEQ}_ros2"

usage() {
    echo "Usage:"
    echo "  $0 seqXX"
    echo ""
    echo "Example:"
    echo "  $0 seq00"
    echo ""
    echo "Available:"
    echo "  seq00 seq01 seq02 seq04 seq05 seq06 seq07 seq08 seq09 seq10"
    exit 1
}

SEQ=$1

if [ -z "$SEQ" ]; then
    usage
fi

case $SEQ in
  seq00|seq01|seq02|seq04|seq05|seq06|seq07|seq08|seq09|seq10)
    ;;
  *)
    echo "Invalid sequence: $SEQ"
    usage
    ;;
esac

if [ ! -d "$TARGET" ]; then
    echo "Directory $TARGET does not exist."
    echo "Create it first or clone the benchmark repo."
    exit 1
fi

echo "Changing directory to $TARGET"
cd "$TARGET" || exit 1

echo "Downloading KITTI $SEQ..."

wget -c $BASE/kitti_${SEQ}_ros1.bag
wget -c $BASE/kitti_${SEQ}_ros2.zip

echo "Unzipping ROS2 bag..."

mkdir -p "$OUTDIR"

if [ -f "kitti_${SEQ}_ros2.zip" ]; then
    unzip -o "kitti_${SEQ}_ros2.zip" -d "$OUTDIR"
fi

echo "Done."
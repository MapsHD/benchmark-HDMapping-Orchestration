#!/bin/bash
# Downloads one Oxford Spires sequence from Hugging Face (ori-drs/oxford_spires_dataset):
#   <download_dir>/<sequence>/raw/*.bag                  ROS1 bag part(s), all topics
#   <download_dir>/<sequence>/gt-tum.txt                 ground truth (base frame, ICP to TLS)
#   <download_dir>/calibration/{cam-lidar-imu,imu}.yaml  extrinsics and IMU noise
#   <download_dir>/ground_truth_map/<site>/merged-cloud-1cm.{pcd,e57}  TLS map of the site
#     (.pcd where the site has one, else .e57: e.g. bodleian-library has only .e57)
# Only core sequences have gt-tum.txt. Downloads resume (wget -c).
#
# Usage: download.sh <sequence> <download_dir> [site]
#   sequence  e.g. 2024-03-12-keble-college-02
#   site      TLS map folder; default: the sequence without its date and number
set -euo pipefail

SEQUENCE="${1:?usage: $0 <sequence> <download_dir> [site]}"
DOWNLOAD_DIR="${2:?usage: $0 <sequence> <download_dir> [site]}"
SITE="${3:-$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/-[0-9]+$//' <<<"$SEQUENCE")}"

HF=https://huggingface.co/datasets/ori-drs/oxford_spires_dataset/resolve/main
API=https://huggingface.co/api/datasets/ori-drs/oxford_spires_dataset/tree/main

mkdir -p "$DOWNLOAD_DIR/$SEQUENCE/raw" "$DOWNLOAD_DIR/calibration" "$DOWNLOAD_DIR/ground_truth_map/$SITE"

mapfile -t BAGS < <(curl -sf "$API/sequences/$SEQUENCE/raw/rosbag" |
    python3 -c 'import json, sys; [print(f["path"]) for f in json.load(sys.stdin) if f["path"].endswith(".bag")]')
if [[ ${#BAGS[@]} -eq 0 ]]; then
    echo "ERROR: no ROS1 bags listed under sequences/$SEQUENCE/raw/rosbag" >&2
    exit 1
fi

echo "Sequence $SEQUENCE (site $SITE): ${#BAGS[@]} bag part(s)"
for bag in "${BAGS[@]}"; do
    wget -c --progress=dot:giga -P "$DOWNLOAD_DIR/$SEQUENCE/raw" "$HF/$bag"
done
wget -c -q -P "$DOWNLOAD_DIR/$SEQUENCE" "$HF/sequences/$SEQUENCE/processed/trajectory/gt-tum.txt" || {
    echo "ERROR: $SEQUENCE has no processed/trajectory/gt-tum.txt (only core sequences do)" >&2
    exit 1
}
for f in cam-lidar-imu.yaml imu.yaml; do
    wget -c -q -P "$DOWNLOAD_DIR/calibration" "$HF/calibration/$f"
done
MAP=$(curl -sf "$API/ground_truth_map/$SITE" | python3 -c 'import json, sys
paths = [f["path"] for f in json.load(sys.stdin)]
print(next((p for ext in (".pcd", ".e57") for p in paths if p.endswith("merged-cloud-1cm" + ext)), ""))')
if [[ -z "$MAP" ]]; then
    echo "ERROR: no merged-cloud-1cm.pcd or .e57 under ground_truth_map/$SITE" >&2
    exit 1
fi
wget -c --progress=dot:giga -P "$DOWNLOAD_DIR/ground_truth_map/$SITE" "$HF/$MAP"

echo "Downloaded to $DOWNLOAD_DIR"

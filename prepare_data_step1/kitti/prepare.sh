#!/bin/bash
# KITTI odometry sequence -> the canonical benchmark inputs, from the ready-made ROS1 bag of
# https://github.com/Jakubach/kitti_to_ros (KITTI raw: Velodyne HDL-64E + OXTS IMU, 100 Hz).
#
#   <data_dir>/<name>-hdmapping/   HDMapping session (bag_to_laz): IMU rotated into the Velodyne
#                                  frame (calib_imu_to_velo.txt), in g; ring kept as LAS extra bytes
#   <data_dir>/<name>.bag          canonical ROS1 bag (laz_to_bag --lidar-type canonical)
#   <data_dir>/<name>-ros2/        the same as a ROS2 sqlite3 bag
#   <data_dir>/ground_truth.tum    the bag's ground truth (KITTI odometry poses, Velodyne frame)
#   <data_dir>/HDMappingGroundTruth/lio_result_0/   ground-truth session (step 4)
#   <data_dir>/canonical_sensor    hdl64
#
# KITTI has no TLS map, so steps 7 and 8 do not apply.
#
# Usage: prepare.sh [sequence] [download_dir] [data_dir]
#   sequence      $KITTI_SEQUENCE, else 07
#   download_dir  <data_dir>/download/kitti
#   data_dir      ~/hdmapping-benchmark/data
set -euo pipefail

SEQ="${1:-${KITTI_SEQUENCE:-07}}"
DATA_DIR="${3:-$HOME/hdmapping-benchmark/data}"
DOWNLOAD_DIR="${2:-$DATA_DIR/download/kitti}"
NAME="kitti-$SEQ"
MSG_HZ="${MSG_HZ:-10}"
HF=https://huggingface.co/datasets/kubchud/kitti_to_ros/resolve/main
KITTI_S3=https://s3.eu-central-1.amazonaws.com/avg-kitti/raw_data

# Odometry sequence -> raw recording date (for calib_imu_to_velo.txt).
case "$SEQ" in
    00|01|02) DATE=2011_10_03 ;;
    04|05|06|07|08|09|10) DATE=2011_09_30 ;;
    *) echo "ERROR: no ready-made bag for KITTI sequence '$SEQ'" >&2; exit 1 ;;
esac

mkdir -p "$DATA_DIR" "$DOWNLOAD_DIR"
DATA_DIR="$(realpath "$DATA_DIR")"
DOWNLOAD_DIR="$(realpath "$DOWNLOAD_DIR")"

docker_run() {
    docker run --rm --user "$(id -u):$(id -g)" \
        -v "$DOWNLOAD_DIR":/download:ro -v "$DATA_DIR":/data -w /data "$@"
}
py() { docker_run --entrypoint python3 oxford-spires-tools "$@"; }
tools() { docker_run oxford-spires-tools "$@"; }
rosbags_convert() { docker_run --entrypoint rosbags-convert oxford-spires-tools "$@"; }
hdmapping() { docker_run hdmapping-tools "$@"; }

if ! docker image inspect hdmapping-tools >/dev/null 2>&1 || ! docker image inspect oxford-spires-tools >/dev/null 2>&1; then
    echo "--- building the Docker images"
    bash "$(dirname "$0")/../oxford_spires/build_images.sh"
fi

# --- downloads (wget -c resumes) -------------------------------------------------
BAG_IN="kitti_seq${SEQ}_ros1.bag"
GT_IN="kitti_seq${SEQ}_ground_truth.tum"
for f in "$GT_IN" "$BAG_IN"; do
    [[ -f "$DOWNLOAD_DIR/$f" && ! -f "$DOWNLOAD_DIR/$f.partial-download" ]] && continue
    echo "--- downloading $f"
    touch "$DOWNLOAD_DIR/$f.partial-download"
    wget -q -c -O "$DOWNLOAD_DIR/$f" "$HF/$f"
    rm -f "$DOWNLOAD_DIR/$f.partial-download"
done
if [[ ! -f "$DOWNLOAD_DIR/$DATE/calib_imu_to_velo.txt" ]]; then
    wget -q -c -O "$DOWNLOAD_DIR/${DATE}_calib.zip" "$KITTI_S3/${DATE}_calib.zip"
    (cd "$DOWNLOAD_DIR" && unzip -q -o "${DATE}_calib.zip")
fi

echo "=== KITTI $SEQ -> $DATA_DIR ($NAME) ==="
docker run --rm --entrypoint cat hdmapping-tools /usr/local/share/hdmapping-version

# R_velo_imu as qx qy qz qw (bag_to_laz --imu-rotation): the bag's IMU is in the OXTS body frame.
read -ra Q <<<"$(py -c '
import sys, numpy as np
v = {}
for line in open(sys.argv[1]):
    if ":" in line:
        k, s = line.split(":", 1); v[k.strip()] = s.split()
r = np.array([float(x) for x in v["R"]]).reshape(3, 3)
w = np.sqrt(max(0.0, 1.0 + np.trace(r))) / 2.0
print(*("%.12f" % x for x in ((r[2,1]-r[1,2])/(4*w), (r[0,2]-r[2,0])/(4*w), (r[1,0]-r[0,1])/(4*w), w)))
' "/download/$DATE/calib_imu_to_velo.txt")"
if [[ ${#Q[@]} -ne 4 ]]; then
    echo "ERROR: expected a quaternion from calib_imu_to_velo.txt, got '${Q[*]}'" >&2
    exit 1
fi
echo "IMU -> Velodyne rotation (xyzw): ${Q[*]}"

# --- HDMapping session --------------------------------------------------------
SESSION="$NAME-hdmapping"
if [[ -d "$DATA_DIR/$SESSION" ]]; then
    echo "$SESSION exists, kept"
else
    rm -rf "$DATA_DIR/$SESSION.partial"
    echo "--- bag_to_laz $BAG_IN"
    hdmapping bag_to_laz "/download/$BAG_IN" "/data/$SESSION.partial" \
        --lidar-topic /velodyne_points --imu-topic /imu/data \
        --imu-rotation "${Q[@]}" --imu-acc-unit ms2
    mv "$DATA_DIR/$SESSION.partial" "$DATA_DIR/$SESSION"
fi

# HDMapping lidar odometry never uses the first chunk of a session (on Mandeye data it is the
# device standing still). KITTI drives from the first scan, so split the first HEAD_CHUNK_S
# seconds off into a chunk of their own: only those are dropped, not a whole 15-20 s chunk.
# The other chunks are renumbered. Done once (marker file); the bags do not depend on it.
HEAD_CHUNK_S="${HEAD_CHUNK_S:-0.5}"
if [[ ! -f "$DATA_DIR/$SESSION/.head_chunk_split" ]]; then
    echo "--- splitting the first ${HEAD_CHUNK_S} s of $SESSION into a chunk of its own"
    rm -rf "$DATA_DIR/$SESSION/preview" "$DATA_DIR/$SESSION/cache"
    py -c '
import glob, os, sys
import laspy, numpy as np
d, head = sys.argv[1], float(sys.argv[2])
laz = sorted(glob.glob(os.path.join(d, "lidar[0-9][0-9][0-9][0-9].laz")))
imu = sorted(glob.glob(os.path.join(d, "imu[0-9][0-9][0-9][0-9].csv")))
assert len(laz) == len(imu) and laz, "expected matching lidarNNNN.laz / imuNNNN.csv"
for i in reversed(range(len(laz))):  # shift every chunk up by one
    os.rename(laz[i], os.path.join(d, "lidar%04d.laz" % (i + 1)))
    os.rename(imu[i], os.path.join(d, "imu%04d.csv" % (i + 1)))
src = laspy.read(os.path.join(d, "lidar0001.laz"))
t_split = src.gps_time.min() + head
m = src.gps_time < t_split
for name, sel in (("lidar0000.laz", m), ("lidar0001.laz", ~m)):
    out = laspy.LasData(src.header)
    out.points = src.points[sel]
    out.write(os.path.join(d, name))
lines = open(os.path.join(d, "imu0001.csv")).read().splitlines()
hdr, rows = lines[0], lines[1:]
early = [r for r in rows if int(r.split()[0]) * 1e-9 < t_split]
late = rows[len(early):]
for name, part in (("imu0000.csv", early), ("imu0001.csv", late)):
    open(os.path.join(d, name), "w").write("\n".join([hdr] + part) + "\n")
print(f"head chunk: {m.sum()} points, {len(early)} IMU samples; {len(laz) + 1} chunks")
' "/data/$SESSION" "$HEAD_CHUNK_S"
    touch "$DATA_DIR/$SESSION/.head_chunk_split"
fi

# --- canonical bags -------------------------------------------------------------
CANONICAL=(--lidar-type canonical --msg_hz "$MSG_HZ" --imu-acc-unit ms2
           --lidar-topic /lidar/pointcloud --imu-topic /lidar/imu --frame-id lidar)
if [[ -f "$DATA_DIR/$NAME.bag" ]]; then
    echo "$NAME.bag exists, kept"
else
    echo "--- laz_to_bag -> $NAME.bag"
    hdmapping laz_to_bag "/data/$SESSION" "/data/$NAME.partial.bag" "${CANONICAL[@]}"
    mv "$DATA_DIR/$NAME.partial.bag" "$DATA_DIR/$NAME.bag"
fi
if [[ -d "$DATA_DIR/$NAME-ros2" ]]; then
    echo "$NAME-ros2 exists, kept"
else
    echo "--- rosbags-convert -> $NAME-ros2"
    rm -rf "$DATA_DIR/$NAME-ros2.partial"
    rosbags_convert --src "/data/$NAME.bag" --dst "/data/$NAME-ros2.partial" --dst-version 8
    mv "$DATA_DIR/$NAME-ros2.partial" "$DATA_DIR/$NAME-ros2"
fi

# --- ground truth for steps 4-6 ---------------------------------------------------
# The bag's ground truth is in the Velodyne frame but stamped from 0 (KITTI odometry
# times.txt); time 0 is the bag's first scan. Shift it to the scan stamps and check that
# every pose then lands on a scan.
if [[ ! -f "$DATA_DIR/ground_truth.tum" ]]; then
    py -c '
import struct, sys
import numpy as np
from rosbags.rosbag1 import Reader
with Reader(sys.argv[1]) as r:
    conns = [c for c in r.connections if c.topic == "/velodyne_points"]
    stamps = []
    for _, _, raw in r.messages(connections=conns):
        sec, nsec = struct.unpack_from("<II", raw, 4)  # header: seq, stamp
        stamps.append(sec + nsec * 1e-9)
stamps = np.sort(np.array(stamps))
gt = np.loadtxt(sys.argv[2], comments="#")
t = stamps[0] + gt[:, 0]
i = np.clip(np.searchsorted(stamps, t), 1, len(stamps) - 1)
d = np.minimum(np.abs(stamps[i] - t), np.abs(stamps[i - 1] - t))
print(f"ground truth: {len(gt)} poses, shifted by {stamps[0]:.6f} s; max distance to a scan stamp {d.max() * 1e3:.3f} ms")
if d.max() > 0.005:
    sys.exit("ERROR: ground truth does not match the scan stamps")
with open(sys.argv[3], "w") as f:
    for ti, row in zip(t, gt):
        f.write(f"{ti:.9f} " + " ".join(f"{x:.9f}" for x in row[1:8]) + "\n")
' "/download/$BAG_IN" "/download/$GT_IN" /data/ground_truth.tum.partial
    mv "$DATA_DIR/ground_truth.tum.partial" "$DATA_DIR/ground_truth.tum"
fi
GT_SESSION=HDMappingGroundTruth/lio_result_0
if [[ ! -f "$DATA_DIR/$GT_SESSION/session.mjs" ]]; then
    rm -rf "$DATA_DIR/$GT_SESSION.partial"
    mkdir -p "$DATA_DIR/HDMappingGroundTruth"
    tools gt-session "/data/$SESSION" /data/ground_truth.tum "/data/$GT_SESSION.partial"
    rm -rf "$DATA_DIR/$GT_SESSION"
    mv "$DATA_DIR/$GT_SESSION.partial" "$DATA_DIR/$GT_SESSION"
fi
[[ -f "$DATA_DIR/canonical_sensor" ]] || echo hdl64 > "$DATA_DIR/canonical_sensor"

echo "=== KITTI inputs ready in $DATA_DIR ==="

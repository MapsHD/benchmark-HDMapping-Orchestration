#!/bin/bash
# Oxford Spires sequence -> the canonical benchmark inputs, from what download.sh fetched.
#
#   <data_dir>/<name>-hdmapping/   HDMapping session (bag_to_laz): IMU rotated into the
#                                  lidar frame, in g; ring kept as LAS extra bytes
#   <data_dir>/<name>.bag          canonical ROS1 bag (laz_to_bag --lidar-type canonical):
#                                  /lidar/pointcloud + /lidar/imu (lidar frame, m/s^2), 10 Hz
#   <data_dir>/<name>-ros2/        the same as a ROS2 sqlite3 bag (rosbags-convert)
#   <data_dir>/<name>.mcap         the same as MCAP (only with WRITE_MCAP=1)
#   <data_dir>/ground_truth.tum    gt-tum.txt in the lidar frame
#   <data_dir>/HDMappingGroundTruth/lio_result_0/   ground-truth session (steps 4, 7, 8)
#   <data_dir>/TLS-FARO-Focus/map_gt_0.01.laz       TLS reference, cropped to the walk + 20 m (step 8)
#
# Each output is written under a .partial name and renamed when complete, and an
# existing output is kept, so an interrupted run resumes. Needs the hdmapping-tools
# and oxford-spires-tools images (build_images.sh).
#
# Usage: prepare.sh <sequence> <download_dir> <data_dir> [name]
#   name  default: the sequence without its date (2024-03-12-keble-college-02 -> keble-college-02)
set -euo pipefail

SEQUENCE="${1:?usage: $0 <sequence> <download_dir> <data_dir> [name]}"
DOWNLOAD_DIR="$(realpath "${2:?usage: $0 <sequence> <download_dir> <data_dir> [name]}")"
DATA_DIR="${3:?usage: $0 <sequence> <download_dir> <data_dir> [name]}"
NAME="${4:-$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//' <<<"$SEQUENCE")}"
SITE="${SITE:-$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/-[0-9]+$//' <<<"$SEQUENCE")}"
MSG_HZ="${MSG_HZ:-10}"

mkdir -p "$DATA_DIR"
DATA_DIR="$(realpath "$DATA_DIR")"
RAW_DIR="$DOWNLOAD_DIR/$SEQUENCE/raw"

# Containers see the downloads read-only at /download and the data dir at /data.
docker_run() {
    docker run --rm --user "$(id -u):$(id -g)" \
        -v "$DOWNLOAD_DIR":/download:ro -v "$DATA_DIR":/data -w /data "$@"
}
tools() { docker_run oxford-spires-tools "$@"; }
rosbags_convert() { docker_run --entrypoint rosbags-convert oxford-spires-tools "$@"; }
hdmapping() { docker_run hdmapping-tools "$@"; }

for image in hdmapping-tools oxford-spires-tools; do
    docker image inspect "$image" >/dev/null 2>&1 || {
        echo "ERROR: Docker image $image is missing; run $(dirname "$0")/build_images.sh" >&2
        exit 1
    }
done
mapfile -t BAGS < <(cd "$RAW_DIR" && ls -1 *.bag 2>/dev/null | sort)
if [[ ${#BAGS[@]} -eq 0 ]]; then
    echo "ERROR: no bags in $RAW_DIR; run download.sh $SEQUENCE $DOWNLOAD_DIR" >&2
    exit 1
fi

echo "=== Oxford Spires $SEQUENCE -> $DATA_DIR ($NAME, ${#BAGS[@]} bag part(s)) ==="
docker run --rm --entrypoint cat hdmapping-tools /usr/local/share/hdmapping-version

Q="$(tools calibration /download/calibration/cam-lidar-imu.yaml)"
echo "IMU -> lidar rotation (xyzw): $Q"

# --- HDMapping session --------------------------------------------------------
SESSION="$NAME-hdmapping"
if [[ -d "$DATA_DIR/$SESSION" ]]; then
    echo "$SESSION exists, kept"
else
    rm -rf "$DATA_DIR/$SESSION.partial"
    mkdir -p "$DATA_DIR/$SESSION.partial"
    # One session per bag part, then renumbered into one: chunk files sort by time.
    next=0
    for i in "${!BAGS[@]}"; do
        part="$SESSION.partial/part$i"
        echo "--- bag_to_laz ${BAGS[$i]}"
        hdmapping bag_to_laz "/download/$SEQUENCE/raw/${BAGS[$i]}" "/data/$part" \
            --lidar-topic /hesai/pandar --imu-topic /alphasense_driver_ros/imu \
            --imu-rotation $Q --imu-acc-unit ms2
        for laz in $(cd "$DATA_DIR/$part" && ls -1 lidar*.laz | sort); do
            idx="${laz#lidar}"
            idx="${idx%.laz}"
            new=$(printf "%04d" "$next")
            mv "$DATA_DIR/$part/$laz" "$DATA_DIR/$SESSION.partial/lidar$new.laz"
            mv "$DATA_DIR/$part/imu$idx.csv" "$DATA_DIR/$SESSION.partial/imu$new.csv"
            next=$((next + 1))
        done
        rm -rf "${DATA_DIR:?}/$part"
    done
    mv "$DATA_DIR/$SESSION.partial" "$DATA_DIR/$SESSION"
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
    # Bag format 8: what the Humble images' own rosbags-convert writes and what their
    # ros2 bag readers have played; newer rosbags default to 9.
    rosbags_convert --src "/data/$NAME.bag" --dst "/data/$NAME-ros2.partial" --dst-version 8
    mv "$DATA_DIR/$NAME-ros2.partial" "$DATA_DIR/$NAME-ros2"
fi
if [[ "${WRITE_MCAP:-0}" == 1 && ! -f "$DATA_DIR/$NAME.mcap" ]]; then
    echo "--- laz_to_mcap -> $NAME.mcap"
    hdmapping laz_to_mcap "/data/$SESSION" "/data/$NAME.partial.mcap" "${CANONICAL[@]}"
    mv "$DATA_DIR/$NAME.partial.mcap" "$DATA_DIR/$NAME.mcap"
fi

# --- ground truth for steps 4-8 ---------------------------------------------------
if [[ ! -f "$DATA_DIR/ground_truth.tum" ]]; then
    tools ground-truth "/download/$SEQUENCE/gt-tum.txt" /data/ground_truth.tum.partial
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
TLS=TLS-FARO-Focus/map_gt_0.01.laz
if [[ ! -f "$DATA_DIR/$TLS" ]]; then
    tools tls-reference "/download/ground_truth_map/$SITE/merged-cloud-1cm.pcd" /data/ground_truth.tum \
        "/data/$TLS.partial.laz" --margin 20
    mv "$DATA_DIR/$TLS.partial.laz" "$DATA_DIR/$TLS"
fi

echo "=== Oxford Spires inputs ready in $DATA_DIR ==="

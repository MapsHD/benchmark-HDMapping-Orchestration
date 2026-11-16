#!/bin/bash
# Download and prepare one experiment of HDMAPPING-CAVE-DATASET-1
# (https://zenodo.org/records/24254676) as the inputs the pipeline expects:
#
#   data/raw/                  raw HDMapping data (lidar*.laz, imu*.csv, *.sn)
#   data/reg-1.bag             ROS1 bag converted from raw/ (/livox/lidar, /livox/imu)
#   data/HDMappingGroundTruth/ ground-truth session
#   data/TLS-FARO-Focus/map_gt_0.01.laz
#
# The bag keeps the name reg-1.bag so the pipeline and the algorithm
# repositories (branch Bunker-DVI-Dataset-reg-1) run unchanged.
# Every stage is skipped when its output already exists.

set -euo pipefail

usage() {
    echo "Usage: $0 [--download-dir DIR] [exp1|exp2|exp3|exp4]"
    echo
    echo "Default experiment: exp1. Default download dir: ~/Downloads/hdmapping-cave-dataset-1"
    echo "Requires curl, unzip, md5sum, docker and the mandeye-ws_noetic image."
}

EXP=exp1
DOWNLOAD_DIR=~/Downloads/hdmapping-cave-dataset-1
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --download-dir)
            [[ $# -ge 2 ]] || { usage >&2; exit 1; }
            DOWNLOAD_DIR="$2"; shift 2 ;;
        exp[1-4]) EXP="$1"; shift ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

RECORD_URL=https://zenodo.org/api/records/24254676/files
declare -A MD5=(
    [exp1.zip]=53b56a0f6e2847adcd0a87380cdede51
    [exp2.zip]=82198acda926f137d44cf4d4d782a819
    [exp3.zip]=6a8589c4646639cd44ea61046483d4a9
    [exp4.zip]=2881b6e3e8fbedff7902dfb80dbfd1ef
    [TLS-FARO-Focus.zip]=99e8da4c31c268279655b82797350f17
)

DATA_DIR=~/hdmapping-benchmark/data
EXTRACT_DIR="$DOWNLOAD_DIR/extract"
mkdir -p "$DOWNLOAD_DIR" "$DATA_DIR"

for tool in curl unzip md5sum docker; do
    command -v "$tool" >/dev/null || { echo "ERROR: $tool is required" >&2; exit 1; }
done
docker image inspect mandeye-ws_noetic:latest >/dev/null 2>&1 || {
    echo "ERROR: Docker image mandeye-ws_noetic:latest is missing (build it from MapsHD/mandeye_to_bag)" >&2
    exit 1
}

# Refuse to mix datasets: data/ must be empty of inputs or hold this experiment.
MARKER="$DATA_DIR/.dataset"
EXPECTED="HDMAPPING-CAVE-DATASET-1/$EXP"
if [[ -f "$MARKER" && "$(cat "$MARKER")" != "$EXPECTED" ]]; then
    echo "ERROR: $DATA_DIR holds $(cat "$MARKER"), not $EXPECTED. Move it away first." >&2
    exit 1
fi
if [[ ! -f "$MARKER" ]]; then
    for entry in raw reg-1.bag HDMappingGroundTruth TLS-FARO-Focus; do
        if [[ -e "$DATA_DIR/$entry" ]]; then
            echo "ERROR: $DATA_DIR/$entry exists from another dataset. Move it away first." >&2
            exit 1
        fi
    done
    echo "$EXPECTED" > "$MARKER"
fi

download() {
    local name="$1" file="$DOWNLOAD_DIR/$1"
    if [[ -f "$file.ok" ]]; then
        echo "$name: already downloaded and verified."
        return
    fi
    echo "$name: downloading..."
    curl -fL --retry 5 -C - -o "$file" "$RECORD_URL/$name/content"
    echo "$name: verifying md5..."
    if [[ "$(md5sum "$file" | cut -d' ' -f1)" != "${MD5[$name]}" ]]; then
        echo "ERROR: md5 mismatch for $file; delete it and rerun." >&2
        exit 1
    fi
    touch "$file.ok"
}

extract() {
    local name="$1"
    [[ -f "$EXTRACT_DIR/$name.done" ]] && return
    echo "$name: extracting..."
    mkdir -p "$EXTRACT_DIR"
    unzip -q -o "$DOWNLOAD_DIR/$name" -x '__MACOSX/*' '*.DS_Store' -d "$EXTRACT_DIR"
    touch "$EXTRACT_DIR/$name.done"
}

echo "=== $EXPECTED -> $DATA_DIR ==="

if [[ ! -d "$DATA_DIR/raw" || ! -d "$DATA_DIR/HDMappingGroundTruth" ]]; then
    download "$EXP.zip"
    extract "$EXP.zip"
    if [[ ! -d "$DATA_DIR/raw" ]]; then
        shopt -s nullglob
        raws=("$EXTRACT_DIR/$EXP"/continousScanning_*-raw)
        shopt -u nullglob
        [[ ${#raws[@]} -eq 1 ]] || { echo "ERROR: expected one raw folder in $EXTRACT_DIR/$EXP" >&2; exit 1; }
        mv "${raws[0]}" "$DATA_DIR/raw"
    fi
    if [[ ! -d "$DATA_DIR/HDMappingGroundTruth" ]]; then
        mv "$EXTRACT_DIR/$EXP/HDMappingGroundTruth" "$DATA_DIR/"
    fi
else
    echo "raw/ and HDMappingGroundTruth/ exist. Skipping."
fi

if [[ ! -f "$DATA_DIR/TLS-FARO-Focus/map_gt_0.01.laz" ]]; then
    download TLS-FARO-Focus.zip
    extract TLS-FARO-Focus.zip
    mkdir -p "$DATA_DIR/TLS-FARO-Focus"
    mv "$EXTRACT_DIR/TLS-FARO-Focus/lio_result_0/map_gt_0.01.laz" "$DATA_DIR/TLS-FARO-Focus/"
else
    echo "TLS-FARO-Focus/map_gt_0.01.laz exists. Skipping."
fi

if [[ ! -f "$DATA_DIR/reg-1.bag" ]]; then
    echo "Converting raw/ to ROS1 bag..."
    TMP="$DATA_DIR/reg-1.bag.partial"
    rm -rf "$TMP"
    mkdir -p "$TMP"
    docker run --rm --network host --user "$(id -u):$(id -g)" \
        -v "$DATA_DIR/raw":/mandeye_ws/dataset/raw:ro \
        -v "$TMP":/mandeye_ws/output \
        mandeye-ws_noetic:latest /bin/bash -c "
            set -e
            source /opt/ros/noetic/setup.bash
            source /mandeye_ws/devel/setup.bash
            rosrun mandeye_to_rosbag1 mandeye_to_rosbag /mandeye_ws/dataset/raw /mandeye_ws/output/reg-1.bag"
    [[ -s "$TMP/reg-1.bag" ]] || { echo "ERROR: conversion produced no bag" >&2; exit 1; }
    mv "$TMP/reg-1.bag" "$DATA_DIR/reg-1.bag"
    rmdir "$TMP"
else
    echo "reg-1.bag exists. Skipping."
fi

echo "=== Done. Next: ./validate.sh && ./start_benchmark.sh ==="

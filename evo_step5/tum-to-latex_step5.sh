#!/bin/bash

IMAGE_NAME="evo"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR" || exit 1

echo "Building Docker image '$IMAGE_NAME'..."
docker build -t "$IMAGE_NAME" . || exit 1

docker run --rm \
    --user 1000:1000 \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v ~/hdmapping-benchmark/data/tum:/data \
    -w /data \
    "$IMAGE_NAME" \
    python3 /app/tum-to-latex.py
#!/bin/bash

IMAGE_NAME="evo"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Docker image '$IMAGE_NAME' not found. Building..."
    docker build -t "$IMAGE_NAME" . || exit 1
else
    echo "Docker image '$IMAGE_NAME' already exists. Skipping build."
fi

docker run --rm \
    --user 1000:1000 \
    -v ~/hdmapping-benchmark/data/tum:/data \
    -w /data \
    "$IMAGE_NAME" \
    python3 /app/tum-to-latex.py
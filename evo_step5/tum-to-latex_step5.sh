#!/bin/bash

IMAGE_NAME="evo"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR" || exit 1

echo "Building Docker image '$IMAGE_NAME'..."
docker build -t "$IMAGE_NAME" . || exit 1

# The trajectory plot opens a window, so give the container the same X access
# as the algorithm run scripts that show RViz: xhost for local clients and the
# host network namespace.
xhost +local:docker >/dev/null

docker run --rm \
    --network host \
    --user 1000:1000 \
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v ~/hdmapping-benchmark/data/tum:/data \
    -w /data \
    "$IMAGE_NAME" \
    python3 /app/tum-to-latex.py
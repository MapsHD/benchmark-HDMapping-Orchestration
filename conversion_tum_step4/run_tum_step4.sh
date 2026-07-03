#!/bin/bash

IMAGE_NAME="hdmapping_tum"
DATA_DIR="$HOME/hdmapping-benchmark/data"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Building image..."
    docker build -t "$IMAGE_NAME" .
else
    echo "Docker image '$IMAGE_NAME' already exists. Skipping build."
fi

echo "Creating backups in $DATA_DIR..."

algorithms=(
    c3p-voxelmap
    ct-icp
    dlio
    dlo
    faster-lio
    fast-lio
    form
    genz-icp
    glim
    i2ekf-lo
    ig-lio
    kiss-icp
    lego-loam
    lidar_odometry_ros_wrapper
    lio-ekf
    nv-liom
    point-lio
    se3-lio
    slict
    super-lio
    superOdom
    dalislam
    voxelslam
    ellipselio
)

echo "Creating backups..."

for alg in "${algorithms[@]}"; do
    src="$DATA_DIR/$alg"
    dst="${src}_backup"

    if [ -d "$src" ] && [ ! -d "$dst" ]; then
        echo "Backing up $alg..."
        cp -a "$src" "$dst"
    fi
done

mkdir -p "$HOME/hdmapping-benchmark/data/tum"
cp ground_truth.tum "$HOME/hdmapping-benchmark/data/tum/"

docker run --rm -it \
    --user 1000:1000 \
    -v ~/hdmapping-benchmark/data:/data \
    "$IMAGE_NAME" bash -c '
cd /workspace/HDMapping

export PYTHONPATH=/workspace/HDMapping/build/bin/RelWithDebInfo:$PYTHONPATH
export LD_LIBRARY_PATH=/workspace/HDMapping/build/bin/RelWithDebInfo:$LD_LIBRARY_PATH

python3 -c "import multi_session_registration_py; print(\"binding OK\")"

python3 /workspace/save_to_tum.py
'
#!/bin/bash

IMAGE_NAME="hdmapping_tum"
DATA_DIR="$HOME/hdmapping-benchmark/data"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../algos_lib.sh"

cd "$SCRIPT_DIR" || exit 1

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0"
    echo
    echo "Registers every algorithm session against the ground truth and exports"
    echo "TUM trajectories. The list of algorithms lives in algorithms.conf."
    echo "Set ONLY_ALGOS=\"id1 id2 ...\" to restrict it to those algorithms."
    exit 0
fi

check_only_algos

echo "Building Docker image '$IMAGE_NAME'..."
docker build -t "$IMAGE_NAME" .

echo "Creating backups in $DATA_DIR..."

BACKUP_DIR="$DATA_DIR/backup"
mkdir -p "$BACKUP_DIR"

echo "Backup folder: $BACKUP_DIR"

# Back up every algorithm's output folder (missing ones are simply skipped).
for alg in $(algo_ids); do
    src="$DATA_DIR/$alg"
    dst="$BACKUP_DIR/${alg}_backup"

    if [ -d "$src" ] && [ ! -d "$dst" ]; then
        echo "Backing up $alg..."
        cp -a "$src" "$dst"
    else
        echo "Skipping $alg (missing or already backed up)"
    fi
done

mkdir -p "$HOME/hdmapping-benchmark/data/tum"
cp ground_truth.tum "$HOME/hdmapping-benchmark/data/tum/"

docker run --rm -it \
    --user 1000:1000 \
    -e ONLY_ALGOS="${ONLY_ALGOS:-}" \
    -v "$SCRIPT_DIR/save_to_tum.py":/workspace/save_to_tum.py:ro \
    -v "$ALGOS_CONF":/workspace/algorithms.conf:ro \
    -v ~/hdmapping-benchmark/data:/data \
    "$IMAGE_NAME" bash -c '
cd /workspace/HDMapping

export PYTHONPATH=/workspace/HDMapping/build/bin/RelWithDebInfo:$PYTHONPATH
export LD_LIBRARY_PATH=/workspace/HDMapping/build/bin/RelWithDebInfo:$LD_LIBRARY_PATH

python3 -c "import multi_session_registration_py; print(\"binding OK\")"

python3 /workspace/save_to_tum.py
'

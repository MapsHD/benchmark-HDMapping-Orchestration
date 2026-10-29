#!/bin/bash

IMAGE_NAME="hdmapping_tum"
DATA_DIR="${BENCHMARK_DATA_DIR:-$HOME/hdmapping-benchmark/data}"
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

mkdir -p "$DATA_DIR/tum"
# Oxford-Spires: prepare_data_step1/oxford_spires/prepare.sh writes the sequence's
# ground truth (lidar frame) into the data dir; it wins over the file in this folder.
if [ -f "$DATA_DIR/ground_truth.tum" ]; then
    cp "$DATA_DIR/ground_truth.tum" "$DATA_DIR/tum/ground_truth.tum"
else
    cp ground_truth.tum "$DATA_DIR/tum/"
fi

# One container per algorithm: registering all sessions in one process holds
# every point cloud at once (58 GB for 41 sessions on Oxford Spires, killed by
# the OOM killer). Each session is registered against the ground truth alone;
# step 5 aligns every trajectory to the ground truth, so the results match.
SELECTED=()
while IFS=$'\t' read -r alg output; do
    # An empty output column means no automated result (e.g. a manual procedure).
    [ -n "$output" ] || continue
    if [ ! -f "$DATA_DIR/$alg/output_hdmapping-$output/session.json" ]; then
        echo "Skipping $alg (no session at $alg/output_hdmapping-$output/session.json)"
        continue
    fi
    SELECTED+=("$alg")
done < <(awk -F'|' -v only=" ${ONLY_ALGOS:-} " '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
        for (i = 1; i <= NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
        if (only != "  " && index(only, " " $3 " ") == 0) next
        print $3 "\t" $4
    }
' "$ALGOS_CONF")

TTY_ARGS=()
[ -t 1 ] && TTY_ARGS=(-it)

FAILED=()
for i in "${!SELECTED[@]}"; do
    alg="${SELECTED[$i]}"
    echo "=== Step 4: $alg ($((i + 1))/${#SELECTED[@]}) ==="
    docker run --rm "${TTY_ARGS[@]}" \
        --user 1000:1000 \
        -e ONLY_ALGOS="$alg" \
        -v "$SCRIPT_DIR/save_to_tum.py":/workspace/save_to_tum.py:ro \
        -v "$ALGOS_CONF":/workspace/algorithms.conf:ro \
        -v "$DATA_DIR":/data \
        "$IMAGE_NAME" bash -c '
cd /workspace/HDMapping

export PYTHONPATH=/workspace/HDMapping/build/bin/RelWithDebInfo:$PYTHONPATH
export LD_LIBRARY_PATH=/workspace/HDMapping/build/bin/RelWithDebInfo:$LD_LIBRARY_PATH

python3 /workspace/save_to_tum.py
' || FAILED+=("$alg")
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "ERROR: step 4 failed for: ${FAILED[*]}" >&2
    exit 1
fi

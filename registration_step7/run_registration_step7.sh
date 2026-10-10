#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="hdmapping_rigid_registration"
DATA_DIR="$HOME/hdmapping-benchmark/data"
OUTPUT_DIR=""
BUILD_JOBS="${HDMAPPING_BUILD_JOBS:-2}"

usage() {
    echo "Usage: $0 [--data-dir DIRECTORY] [--output-dir DIRECTORY]"
    echo
    echo "Step 7: rigidly register each algorithm session to HDMappingGroundTruth."
    echo "Input defaults to \$HOME/hdmapping-benchmark/data."
    echo "Target is <data-dir>/HDMappingGroundTruth/lio_result_0/session.mjs."
    echo "Output defaults to <data-dir>/step7_registration."
    echo "Both sessions are downsampled with a fixed 0.01 m bucket size."
    echo "Set ONLY_ALGOS=\"id1 id2 ...\" to select algorithms from algorithms.conf."
    echo "Set HDMAPPING_BUILD_JOBS to limit compilation parallelism (default: 2)."
    echo "Existing algorithm result folders are never overwritten."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --data-dir|--output-dir)
            if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
                echo "ERROR: $1 requires a directory argument" >&2
                exit 1
            fi
            if [[ "$1" == --data-dir ]]; then
                DATA_DIR="$2"
            else
                OUTPUT_DIR="$2"
            fi
            shift 2
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

source "$REPO_DIR/algos_lib.sh"
check_only_algos

if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: HDMAPPING_BUILD_JOBS must be a positive integer" >&2
    exit 1
fi
if [[ ! -d "$DATA_DIR" ]]; then
    echo "ERROR: input directory does not exist: $DATA_DIR" >&2
    exit 1
fi
DATA_DIR="$(realpath -e -- "$DATA_DIR")"
GROUND_TRUTH="$DATA_DIR/HDMappingGroundTruth/lio_result_0/session.mjs"
if [[ ! -f "$GROUND_TRUTH" || ! -s "$GROUND_TRUTH" ]]; then
    echo "ERROR: missing or empty ground-truth session: $GROUND_TRUTH" >&2
    echo "Place the Zenodo HDMappingGroundTruth directory beside reg-1.bag." >&2
    exit 1
fi

OUTPUT_DIR="$(realpath -m -- "${OUTPUT_DIR:-$DATA_DIR/step7_registration}")"
ALGOS_CONF="$(realpath -e -- "$ALGOS_CONF")"
if [[ "$OUTPUT_DIR" == / || "$DATA_DIR" == "$OUTPUT_DIR" || "$DATA_DIR/" == "$OUTPUT_DIR/"* ]]; then
    echo "ERROR: output directory must not be the input directory or its ancestor" >&2
    exit 1
fi
for path in "$DATA_DIR" "$OUTPUT_DIR" "$ALGOS_CONF"; do
    if [[ "$path" == *,* ]]; then
        echo "ERROR: Docker mount paths must not contain commas: $path" >&2
        exit 1
    fi
done
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is required; install it and start its daemon" >&2
    exit 1
fi
if ! docker info >/dev/null; then
    echo "ERROR: cannot connect to Docker; check daemon status and permissions" >&2
    exit 1
fi

echo "Building Docker image '$IMAGE_NAME' (parallel jobs: $BUILD_JOBS)..."
docker build \
    --file "$SCRIPT_DIR/Dockerfile" \
    --build-arg "BUILD_JOBS=$BUILD_JOBS" \
    --tag "$IMAGE_NAME" \
    "$REPO_DIR"

mkdir -p -- "$OUTPUT_DIR"
echo "Input: $DATA_DIR"
echo "Ground truth: $GROUND_TRUTH"
echo "Registration results: $OUTPUT_DIR"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env "ONLY_ALGOS=${ONLY_ALGOS:-}" \
    --env ALGOS_CONF=/workspace/algorithms.conf \
    --mount "type=bind,source=$DATA_DIR,target=/data,readonly" \
    --mount "type=bind,source=$OUTPUT_DIR,target=/results" \
    --mount "type=bind,source=$ALGOS_CONF,target=/workspace/algorithms.conf,readonly" \
    "$IMAGE_NAME"

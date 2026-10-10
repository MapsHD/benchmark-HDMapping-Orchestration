#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="hdmapping_point_cloud_evaluation"
DATA_DIR="$HOME/hdmapping-benchmark/data"
REGISTRATION_DIR=""
OUTPUT_DIR=""
BUILD_JOBS="${HDMAPPING_BUILD_JOBS:-2}"

usage() {
    echo "Usage: $0 [--data-dir DIRECTORY] [--registration-dir DIRECTORY] [--output-dir DIRECTORY]"
    echo
    echo "Step 8: compare Step 7 registered clouds against the FARO ground-truth LAZ."
    echo "Input defaults to \$HOME/hdmapping-benchmark/data."
    echo "Registration results default to <data-dir>/step7_registration."
    echo "FARO reference is <data-dir>/TLS-FARO-Focus/map_gt_0.01.laz."
    echo "Output defaults to <data-dir>/step8_evaluation."
    echo "Uses full clouds and a fixed 0.01 m precision/recall threshold."
    echo "Set ONLY_ALGOS=\"id1 id2 ...\" to select algorithms from algorithms.conf."
    echo "Set HDMAPPING_BUILD_JOBS to limit compilation parallelism (default: 2)."
    echo "Only Step 7 results marked registered are eligible. Existing results are preserved."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --data-dir|--registration-dir|--output-dir)
            if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
                echo "ERROR: $1 requires a directory argument" >&2
                exit 1
            fi
            case "$1" in
                --data-dir) DATA_DIR="$2" ;;
                --registration-dir) REGISTRATION_DIR="$2" ;;
                --output-dir) OUTPUT_DIR="$2" ;;
            esac
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
REGISTRATION_DIR="${REGISTRATION_DIR:-$DATA_DIR/step7_registration}"
if [[ ! -d "$REGISTRATION_DIR" ]]; then
    echo "ERROR: Step 7 registration directory does not exist: $REGISTRATION_DIR" >&2
    exit 1
fi
REGISTRATION_DIR="$(realpath -e -- "$REGISTRATION_DIR")"
FARO_REFERENCE="$DATA_DIR/TLS-FARO-Focus/map_gt_0.01.laz"
for path in "$FARO_REFERENCE" "$REGISTRATION_DIR/registration_summary.csv"; do
    if [[ ! -f "$path" || ! -s "$path" ]]; then
        echo "ERROR: missing or empty required input: $path" >&2
        exit 1
    fi
done

OUTPUT_DIR="$(realpath -m -- "${OUTPUT_DIR:-$DATA_DIR/step8_evaluation}")"
ALGOS_CONF="$(realpath -e -- "$ALGOS_CONF")"
for input_dir in "$DATA_DIR" "$REGISTRATION_DIR"; do
    if [[ "$OUTPUT_DIR" == / || "$input_dir" == "$OUTPUT_DIR" || "$input_dir/" == "$OUTPUT_DIR/"* ]]; then
        echo "ERROR: output directory must not be an input directory or its ancestor" >&2
        exit 1
    fi
done
for path in "$DATA_DIR" "$REGISTRATION_DIR" "$OUTPUT_DIR" "$ALGOS_CONF"; do
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
echo "FARO reference: $FARO_REFERENCE"
echo "Registration results: $REGISTRATION_DIR"
echo "Evaluation results: $OUTPUT_DIR"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env "ONLY_ALGOS=${ONLY_ALGOS:-}" \
    --env ALGOS_CONF=/workspace/algorithms.conf \
    --mount "type=bind,source=$DATA_DIR,target=/data,readonly" \
    --mount "type=bind,source=$REGISTRATION_DIR,target=/registration,readonly" \
    --mount "type=bind,source=$OUTPUT_DIR,target=/evaluation" \
    --mount "type=bind,source=$ALGOS_CONF,target=/workspace/algorithms.conf,readonly" \
    "$IMAGE_NAME"

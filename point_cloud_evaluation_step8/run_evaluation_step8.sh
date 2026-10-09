#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="hdmapping_point_cloud_evaluation"
DATA_DIR="$HOME/hdmapping-benchmark/data"
REGISTRATION_DIR=""
OUTPUT_DIR=""
BUILD_JOBS="${HDMAPPING_BUILD_JOBS:-2}"
MERGE_ONLY=false
FORCE=false
VOXEL_SIZE=0.05
THRESHOLD=0.05
JOBS=1

usage() {
    echo "Usage: $0 [--data-dir DIRECTORY] [--registration-dir DIRECTORY] [--output-dir DIRECTORY]"
    echo "          [--voxel-size METERS] [--threshold METERS] [--jobs N] [--merge-only | --force]"
    echo
    echo "Step 8: compare Step 7 registered clouds against the FARO ground-truth LAZ."
    echo "Input defaults to \$HOME/hdmapping-benchmark/data."
    echo "Registration results default to <data-dir>/step7_registration."
    echo "FARO reference is <data-dir>/TLS-FARO-Focus/map_gt_0.01.laz."
    echo "Output defaults to <data-dir>/step8_evaluation."
    echo "Use --voxel-size METERS for both clouds (default: 0.05 m; 0 disables downsampling)."
    echo "Use --threshold METERS for precision/recall agreement (default: 0.05 m)."
    echo "Set ONLY_ALGOS=\"id1 id2 ...\" to select algorithms from algorithms.conf."
    echo "Set HDMAPPING_BUILD_JOBS to limit compilation parallelism (default: 2)."
    echo "Use --jobs N for simultaneous algorithm evaluations (default: 1; positive integer)."
    echo "Shows per-worker stage bars in a terminal, or timestamped worker progress otherwise."
    echo "Workers save separate reports; combined CSV/Markdown reports are merged after all finish."
    echo "Only one run can write to an evaluation output directory at a time."
    echo "Runs the upstream evaluator CLI with its default NN cache and RMSE behavior."
    echo "Use --merge-only to rebuild summaries from saved results without evaluating clouds."
    echo "Use --force to permanently replace selected eligible maps' results and reevaluate."
    echo "Step 7 results marked registered, or validated completed existing registrations, are eligible."
    echo "Existing evaluation results are preserved."
    echo "Unregistered algorithms are skipped, not counted as evaluation failures."
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
        --voxel-size|--threshold)
            if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
                echo "ERROR: $1 requires a distance in meters" >&2
                exit 1
            fi
            case "$1" in
                --voxel-size) VOXEL_SIZE="$2" ;;
                --threshold) THRESHOLD="$2" ;;
            esac
            shift 2
            ;;
        --merge-only)
            MERGE_ONLY=true
            shift
            ;;
        --jobs)
            if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "ERROR: --jobs requires a positive integer" >&2
                exit 1
            fi
            JOBS="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "$FORCE" == true && "$MERGE_ONLY" == true ]]; then
    echo "ERROR: --force cannot be combined with --merge-only" >&2
    exit 1
fi

source "$REPO_DIR/algos_lib.sh"
check_only_algos
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: Python 3 is required to validate voxel size and threshold" >&2
    exit 1
fi
python3 -B - "$SCRIPT_DIR/../registration_step7" "$VOXEL_SIZE" "$THRESHOLD" <<'PY'
import argparse
import sys

sys.path.insert(0, sys.argv[1])
from validate_registration import nonnegative_distance, positive_distance

try:
    nonnegative_distance(sys.argv[2])
    positive_distance(sys.argv[3])
except argparse.ArgumentTypeError as error:
    sys.exit(f"ERROR: invalid voxel size or threshold: {error}")
PY

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
if [[ "$MERGE_ONLY" == true && ! -d "$OUTPUT_DIR" ]]; then
    echo "ERROR: evaluation output directory does not exist: $OUTPUT_DIR" >&2
    exit 1
fi
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
echo "Voxel size: $VOXEL_SIZE m; precision/recall threshold: $THRESHOLD m"
EVALUATION_ARGS=(--voxel-size "$VOXEL_SIZE" --threshold "$THRESHOLD" --jobs "$JOBS")
DOCKER_ARGS=(--rm --init --sig-proxy=true)
if [[ "$FORCE" == true ]]; then
    EVALUATION_ARGS+=(--force)
    echo "WARNING: --force will permanently replace selected eligible evaluation results."
fi
if [[ "$MERGE_ONLY" == true ]]; then
    EVALUATION_ARGS+=(--merge-only)
    echo "Merging saved per-map results only; no cloud conversion or evaluation."
else
    echo "Up to $JOBS simultaneous evaluations; progress is shown in the terminal and per-map evaluation.log files."
    if [[ -t 1 ]]; then
        DOCKER_ARGS+=(--tty)
    fi
fi

docker run "${DOCKER_ARGS[@]}" \
    --user "$(id -u):$(id -g)" \
    --env "ONLY_ALGOS=${ONLY_ALGOS:-}" \
    --env ALGOS_CONF=/workspace/algorithms.conf \
    --mount "type=bind,source=$DATA_DIR,target=/data,readonly" \
    --mount "type=bind,source=$REGISTRATION_DIR,target=/registration,readonly" \
    --mount "type=bind,source=$OUTPUT_DIR,target=/evaluation" \
    --mount "type=bind,source=$ALGOS_CONF,target=/workspace/algorithms.conf,readonly" \
    "$IMAGE_NAME" \
    python /workspace/point_cloud_evaluation_step8/evaluate_clouds.py "${EVALUATION_ARGS[@]}"

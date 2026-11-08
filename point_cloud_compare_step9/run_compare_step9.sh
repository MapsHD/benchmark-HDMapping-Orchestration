#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="hdmapping_point_cloud_compare"
DATA_DIR="$HOME/hdmapping-benchmark/data"
EVALUATION_DIR=""
OUTPUT_DIR=""
BUILD_JOBS="${HDMAPPING_BUILD_JOBS:-2}"
FORCE=true
RESULTS=(full tile mosaic compare.log)

usage() {
    echo "Usage: $0 [--data-dir DIRECTORY] [--evaluation-dir DIRECTORY] [--output-dir DIRECTORY] [--no-force]"
    echo
    echo "Step 9: render the FARO reference and the Step 8 evaluated clouds from the"
    echo "same 14 orthographic views and build per-view mosaics (cloud_visual_compare,"
    echo "default options, no GUI)."
    echo "Input defaults to \$HOME/hdmapping-benchmark/data."
    echo "Step 8 results default to <data-dir>/step8_evaluation; the reference is"
    echo "<evaluation-dir>/reference/faro.ply and the compared clouds are the"
    echo "<evaluation-dir>/<algorithm-id>/registered.ply files of algorithms marked"
    echo "'evaluated' in <evaluation-dir>/evaluation_summary.csv."
    echo "Output defaults to <data-dir>/step9_comparison."
    echo "Set ONLY_ALGOS=\"id1 id2 ...\" to select algorithms from algorithms.conf."
    echo "Set HDMAPPING_BUILD_JOBS to limit compilation parallelism (default: 2)."
    echo "Uses an NVIDIA GPU through the NVIDIA Container Toolkit when available and"
    echo "otherwise falls back to the PoCL CPU OpenCL device (slower)."
    echo "Existing full/, tile/, mosaic/ and compare.log in the output directory are"
    echo "permanently replaced by default. Use --no-force to preserve them."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --data-dir|--evaluation-dir|--output-dir)
            if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
                echo "ERROR: $1 requires a directory argument" >&2
                exit 1
            fi
            case "$1" in
                --data-dir) DATA_DIR="$2" ;;
                --evaluation-dir) EVALUATION_DIR="$2" ;;
                --output-dir) OUTPUT_DIR="$2" ;;
            esac
            shift 2
            ;;
        --no-force)
            FORCE=false
            shift
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
EVALUATION_DIR="${EVALUATION_DIR:-$DATA_DIR/step8_evaluation}"
if [[ ! -d "$EVALUATION_DIR" ]]; then
    echo "ERROR: Step 8 evaluation directory does not exist: $EVALUATION_DIR" >&2
    exit 1
fi
EVALUATION_DIR="$(realpath -e -- "$EVALUATION_DIR")"
for path in "$EVALUATION_DIR/reference/faro.ply" "$EVALUATION_DIR/evaluation_summary.csv"; do
    if [[ ! -f "$path" || ! -s "$path" ]]; then
        echo "ERROR: missing or empty required Step 8 output: $path" >&2
        exit 1
    fi
done

OUTPUT_DIR="$(realpath -m -- "${OUTPUT_DIR:-$DATA_DIR/step9_comparison}")"
if [[ "$OUTPUT_DIR" == / ]]; then
    echo "ERROR: output directory must not be /" >&2
    exit 1
fi
for input_dir in "$DATA_DIR" "$EVALUATION_DIR"; do
    if [[ "$input_dir" == "$OUTPUT_DIR" || "$input_dir/" == "$OUTPUT_DIR/"* ]]; then
        echo "ERROR: output directory must not be an input directory or its ancestor" >&2
        exit 1
    fi
done
if [[ "$OUTPUT_DIR/" == "$EVALUATION_DIR/"* ]]; then
    echo "ERROR: output directory must not be inside the Step 8 evaluation directory" >&2
    exit 1
fi
ALGOS_CONF="$(realpath -e -- "$ALGOS_CONF")"
for path in "$EVALUATION_DIR" "$OUTPUT_DIR" "$ALGOS_CONF"; do
    if [[ "$path" == *,* ]]; then
        echo "ERROR: Docker mount paths must not contain commas: $path" >&2
        exit 1
    fi
done

existing=()
for name in "${RESULTS[@]}"; do
    if [[ -e "$OUTPUT_DIR/$name" || -L "$OUTPUT_DIR/$name" ]]; then
        existing+=("$OUTPUT_DIR/$name")
    fi
done
if [[ "$FORCE" == false && ${#existing[@]} -gt 0 ]]; then
    echo "ERROR: existing comparison results; refusing to overwrite (--no-force):" >&2
    printf '  %s\n' "${existing[@]}" >&2
    echo "Use a separate --output-dir or rerun without --no-force." >&2
    exit 1
fi

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

# GPU: prefer the nvidia runtime (works in both legacy and CDI-mode toolkit
# configs, where the --gpus hook path is rejected); fall back to --gpus all,
# then to the PoCL CPU device (slower, but the run completes).
GPU_ARGS=()
RUNTIMES="$(docker info --format '{{json .Runtimes}}' 2>/dev/null || true)"
if [[ "$RUNTIMES" == *'"nvidia"'* ]]; then
    GPU_ARGS=(--runtime=nvidia --env NVIDIA_VISIBLE_DEVICES=all --env NVIDIA_DRIVER_CAPABILITIES=compute,utility)
    echo "OpenCL: NVIDIA GPU through the nvidia runtime"
elif docker run --rm --gpus all "$IMAGE_NAME" true >/dev/null 2>&1; then
    GPU_ARGS=(--gpus all)
    echo "OpenCL: NVIDIA GPU through --gpus all"
else
    echo "WARNING: no working NVIDIA docker runtime detected; rendering on the PoCL CPU device (slower)."
fi

mkdir -p -- "$OUTPUT_DIR"
if [[ ${#existing[@]} -gt 0 ]]; then
    echo "WARNING: replacing existing comparison results (default; use --no-force to preserve them):"
    printf '  %s\n' "${existing[@]}"
    rm -rf -- "${existing[@]}"
fi

echo "Step 8 results: $EVALUATION_DIR"
echo "Comparison results: $OUTPUT_DIR"

docker run --rm --init --sig-proxy=true \
    "${GPU_ARGS[@]}" \
    --user "$(id -u):$(id -g)" \
    --env "ONLY_ALGOS=${ONLY_ALGOS:-}" \
    --env ALGOS_CONF=/workspace/algorithms.conf \
    --mount "type=bind,source=$EVALUATION_DIR,target=/evaluation,readonly" \
    --mount "type=bind,source=$OUTPUT_DIR,target=/comparison" \
    --mount "type=bind,source=$ALGOS_CONF,target=/workspace/algorithms.conf,readonly" \
    "$IMAGE_NAME" \
    bash /workspace/point_cloud_compare_step9/compare_clouds.sh

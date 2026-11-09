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
OPENCL=auto
RESOLUTION=8192
RESULTS=(full tile mosaic compare.log)

usage() {
    echo "Usage: $0 [--data-dir DIRECTORY] [--evaluation-dir DIRECTORY] [--output-dir DIRECTORY]"
    echo "          [--resolution PX] [--opencl auto|nvidia|intel|amd|cpu] [--no-force]"
    echo
    echo "Step 9: render the FARO reference and the Step 8 evaluated clouds from the"
    echo "same 14 orthographic views and build per-view mosaics (cloud_visual_compare,"
    echo "default options except --resolution, no GUI)."
    echo "Use --resolution PX for the size of each render in full/ along its longer"
    echo "side (default: 8192; 1024-65535). Mosaic size is not affected."
    echo "Input defaults to \$HOME/hdmapping-benchmark/data."
    echo "Step 8 results default to <data-dir>/step8_evaluation; the reference is"
    echo "<evaluation-dir>/reference/faro.ply and the compared clouds are the"
    echo "<evaluation-dir>/<algorithm-id>/registered.ply files of algorithms marked"
    echo "'evaluated' in <evaluation-dir>/evaluation_summary.csv."
    echo "Output defaults to <data-dir>/step9_comparison."
    echo "Set ONLY_ALGOS=\"id1 id2 ...\" to select algorithms from algorithms.conf."
    echo "Set HDMAPPING_BUILD_JOBS to limit compilation parallelism (default: 2)."
    echo "Use --opencl MODE to choose the OpenCL device (default: auto):"
    echo "  auto    NVIDIA GPU if the NVIDIA Container Toolkit works, otherwise Intel or"
    echo "          AMD GPUs from /dev/dri, otherwise the PoCL CPU device (slower)"
    echo "  nvidia  NVIDIA GPU only, through the NVIDIA Container Toolkit"
    echo "  intel   Intel GPU only (Intel compute runtime, /dev/dri)"
    echo "  amd     AMD GPU only (Mesa Rusticl, /dev/dri)"
    echo "  cpu     PoCL CPU device only, no GPU passed to the container"
    echo "Explicit modes fail instead of falling back to another device."
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
        --resolution)
            if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]] || (( ${#2} > 5 || $2 < 1024 || $2 > 65535 )); then
                echo "ERROR: --resolution requires an integer from 1024 to 65535" >&2
                exit 1
            fi
            RESOLUTION="$2"
            shift 2
            ;;
        --opencl)
            if [[ $# -lt 2 || ! "$2" =~ ^(auto|nvidia|intel|amd|cpu)$ ]]; then
                echo "ERROR: --opencl requires auto, nvidia, intel, amd or cpu" >&2
                exit 1
            fi
            OPENCL="$2"
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

# OpenCL device. cloud_visual_compare takes the first GPU of any OpenCL platform,
# otherwise any device. The container only sees the devices passed below and the
# drivers in /etc/OpenCL/select/<mode> (OCL_ICD_VENDORS).
# NVIDIA: prefer the nvidia runtime (works in both legacy and CDI-mode toolkit
# configs, where the --gpus hook path is rejected); fall back to --gpus all.
nvidia_args() {
    local runtimes
    runtimes="$(docker info --format '{{json .Runtimes}}' 2>/dev/null || true)"
    if [[ "$runtimes" == *'"nvidia"'* ]]; then
        DEVICE_ARGS=(--runtime=nvidia --env NVIDIA_VISIBLE_DEVICES=all --env NVIDIA_DRIVER_CAPABILITIES=compute,utility)
        echo "OpenCL: NVIDIA GPU through the nvidia runtime"
    elif docker run --rm --gpus all "$IMAGE_NAME" true >/dev/null 2>&1; then
        DEVICE_ARGS=(--gpus all)
        echo "OpenCL: NVIDIA GPU through --gpus all"
    else
        return 1
    fi
}

# Intel and AMD: pass the DRM render nodes and their group, since the container
# runs as the invoking user. NVIDIA_VISIBLE_DEVICES=void keeps a default nvidia
# runtime from adding the NVIDIA GPU.
dri_args() {
    local nodes=(/dev/dri/renderD*) gid
    if [[ ! -e "${nodes[0]}" ]]; then
        return 1
    fi
    DEVICE_ARGS=(--device /dev/dri --env NVIDIA_VISIBLE_DEVICES=void)
    for gid in $(stat -c %g "${nodes[@]}" | sort -u); do
        DEVICE_ARGS+=(--group-add "$gid")
    done
    echo "OpenCL: GPUs from /dev/dri (${nodes[*]##*/})"
}

DEVICE_ARGS=()
case "$OPENCL" in
    auto)
        if ! nvidia_args && ! dri_args; then
            DEVICE_ARGS=(--env NVIDIA_VISIBLE_DEVICES=void)
            echo "WARNING: no GPU available to Docker; rendering on the PoCL CPU device (slower)."
        fi
        ;;
    nvidia)
        if ! nvidia_args; then
            echo "ERROR: --opencl nvidia needs a working NVIDIA Container Toolkit" >&2
            exit 1
        fi
        ;;
    intel|amd)
        if ! dri_args; then
            echo "ERROR: --opencl $OPENCL needs GPU render nodes in /dev/dri" >&2
            exit 1
        fi
        ;;
    cpu)
        DEVICE_ARGS=(--env NVIDIA_VISIBLE_DEVICES=void)
        echo "OpenCL: PoCL CPU device only"
        ;;
esac
DEVICE_ARGS+=(--env "OCL_ICD_VENDORS=/etc/OpenCL/select/$OPENCL")

mkdir -p -- "$OUTPUT_DIR"
if [[ ${#existing[@]} -gt 0 ]]; then
    echo "WARNING: replacing existing comparison results (default; use --no-force to preserve them):"
    printf '  %s\n' "${existing[@]}"
    rm -rf -- "${existing[@]}"
fi

echo "Step 8 results: $EVALUATION_DIR"
echo "Comparison results: $OUTPUT_DIR"

docker run --rm --init --sig-proxy=true \
    "${DEVICE_ARGS[@]}" \
    --user "$(id -u):$(id -g)" \
    --env "ONLY_ALGOS=${ONLY_ALGOS:-}" \
    --env "RESOLUTION=$RESOLUTION" \
    --env ALGOS_CONF=/workspace/algorithms.conf \
    --mount "type=bind,source=$EVALUATION_DIR,target=/evaluation,readonly" \
    --mount "type=bind,source=$OUTPUT_DIR,target=/comparison" \
    --mount "type=bind,source=$ALGOS_CONF,target=/workspace/algorithms.conf,readonly" \
    "$IMAGE_NAME" \
    bash /workspace/point_cloud_compare_step9/compare_clouds.sh

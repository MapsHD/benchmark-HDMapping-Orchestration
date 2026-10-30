#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0"
    echo
    echo "Check the full-automation workspace, dataset and prerequisite Docker images."
    echo "Reports missing prerequisites and returns nonzero on failure."
    echo "Does not build images, run containers or modify files."
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
fi

WORKSPACE="$HOME/hdmapping-benchmark"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$WORKSPACE/data"
# Oxford-Spires: the sequence comes from start_benchmark.sh.
SEQUENCE="${OXFORD_SPIRES_SEQUENCE:-2024-03-12-keble-college-02}"
NAME="$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//' <<<"$SEQUENCE")"
SESSION="$DATA_DIR/HDMappingGroundTruth/lio_result_0/session.mjs"
PASSED=0
FAILED=0

pass() {
    echo "PASS: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $1" >&2
    FAILED=$((FAILED + 1))
}

check_directory() {
    local path="$1"
    if [[ -d "$path" && -r "$path" && -x "$path" ]]; then
        pass "Directory accessible: $path"
    else
        fail "Missing or inaccessible directory: $path"
    fi
}

check_file() {
    local path="$1"
    if [[ -f "$path" && -r "$path" && -s "$path" ]]; then
        pass "Input present and readable: $path"
    else
        fail "Missing, empty or unreadable input: $path"
    fi
}

echo "=== Full-automation setup validation ==="
for path in \
    "$WORKSPACE" "$REPO_DIR" "$DATA_DIR" \
    "$DATA_DIR/HDMappingGroundTruth" "$DATA_DIR/TLS-FARO-Focus"; do
    check_directory "$path"
done
for path in "$WORKSPACE" "$DATA_DIR"; do
    if [[ -d "$path" && -w "$path" && -x "$path" ]]; then
        pass "Directory writable: $path"
    else
        fail "Workspace directory is not writable: $path"
    fi
done
check_file "$DATA_DIR/$NAME.bag"
check_file "$DATA_DIR/$NAME-ros2/metadata.yaml"
check_file "$DATA_DIR/ground_truth.tum"
check_directory "$DATA_DIR/$NAME-hdmapping"
check_file "$SESSION"
check_file "$DATA_DIR/TLS-FARO-Focus/map_gt_0.01.laz"

PYTHON=""
if command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
elif command -v python >/dev/null 2>&1; then
    PYTHON=python
else
    fail "Python 3 is required to inspect the ground-truth session"
fi

if [[ -n "$PYTHON" && -f "$SESSION" && -r "$SESSION" && -s "$SESSION" ]]; then
    if "$PYTHON" - "$SESSION" <<'PY'
import sys

if sys.version_info.major < 3:
    print("ERROR: ground-truth validation requires Python 3", file=sys.stderr)
    sys.exit(1)

import json
import os
from pathlib import Path

session = Path(sys.argv[1])
errors = []
try:
    with session.open() as handle:
        document = json.load(handle)
    if not isinstance(document, dict):
        raise ValueError("session must contain a JSON object")
    settings = document.get("Session Settings")
    scans = document.get("laz_file_names")
    if not isinstance(settings, dict):
        raise ValueError("session lacks Session Settings")
    if not isinstance(scans, list) or not scans:
        raise ValueError("session has no scan file list")

    def local_file(value, label):
        if not isinstance(value, str) or not value.strip():
            errors.append("missing or invalid " + label)
            return None
        name = value.replace("\\", "/").rsplit("/", 1)[-1]
        if name in ("", ".", ".."):
            errors.append("invalid filename for " + label)
            return None
        return session.parent / name

    def check_input(path):
        try:
            if not path.is_file() or path.stat().st_size == 0 or not os.access(path, os.R_OK):
                errors.append("missing, empty or unreadable input: " + str(path))
        except OSError as error:
            errors.append("cannot inspect " + str(path) + ": " + str(error))

    for key in ("initial_poses_file_name", "poses_file_name"):
        path = local_file(settings.get(key), key)
        if path is not None:
            check_input(path)

    for index, scan in enumerate(scans):
        if not isinstance(scan, dict):
            errors.append("invalid scan entry at index " + str(index))
            continue
        path = local_file(scan.get("file_name"), "scan " + str(index))
        if path is not None:
            check_input(path)
            suffix = path.stem.rsplit("_", 1)[-1]
            check_input(path.parent / ("trajectory_lio_" + suffix + ".csv"))
except (OSError, ValueError) as error:
    errors.append(str(error))

if errors:
    for error in errors:
        print("ERROR: ground-truth session: " + error, file=sys.stderr)
    sys.exit(1)
print("Ground-truth session references " + str(len(scans)) + " scans with trajectories.")
PY
    then
        pass "Ground-truth pose files, scans and trajectories are present"
    else
        fail "Ground-truth session is invalid or incomplete; extract its complete dataset directory"
    fi
elif [[ -n "$PYTHON" ]]; then
    echo "SKIP: session contents cannot be checked without a readable, nonempty session file"
fi

if ! command -v docker >/dev/null 2>&1; then
    fail "Docker is not installed or is not on PATH"
elif ! docker info >/dev/null; then
    fail "Docker daemon is unavailable; check daemon status and permissions"
else
    pass "Docker daemon accessible"
    for image in \
        hdmapping-tools:latest \
        oxford-spires-tools:latest; do
        if docker image inspect "$image" >/dev/null; then
            pass "Prerequisite Docker image present: $image"
        else
            fail "Missing or inaccessible Docker image: $image; build it with prepare_data_step1/oxford_spires/build_images.sh"
        fi
    done
fi

echo "Validation summary: passed=$PASSED failed=$FAILED"
if [[ "$FAILED" -gt 0 ]]; then
    echo "ERROR: fix the reported setup prerequisites before starting the benchmark" >&2
    exit 1
fi
echo "Setup validation passed."

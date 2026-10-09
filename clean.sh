#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 [--dry-run]"
    echo
    echo "Clean ~/hdmapping-benchmark, preserving this repository, mandeye_to_bag,"
    echo "livox_bag_aggregate, and data/{reg-1.bag,HDMappingGroundTruth,TLS-FARO-Focus}."
    echo "Prints deletion targets and requires typing CLEAN to confirm."
    echo "Use --dry-run to preview without deleting. Stop benchmark jobs first."
    echo "Docker resources and files outside the workspace are not removed."
}

DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORKSPACE="$(realpath -e -- "$REPO_DIR/..")"
HOME_DIR="$(realpath -e -- "$HOME")"
DATA_DIR="$WORKSPACE/data"
readonly REPO_DIR WORKSPACE HOME_DIR DATA_DIR

validate_layout() {
    if [[ "$WORKSPACE" == / || "$WORKSPACE" == "$HOME_DIR" ||
          "$WORKSPACE" != "$HOME_DIR/hdmapping-benchmark" ||
          "$REPO_DIR" != "$WORKSPACE/benchmark-HDMapping-Orchestration" ]]; then
        echo "ERROR: script must be in ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration" >&2
        exit 1
    fi
    if [[ -L "$WORKSPACE" || -L "$REPO_DIR" || -L "$DATA_DIR" ||
          ! -d "$DATA_DIR" || ! -e "$REPO_DIR/.git" ]]; then
        echo "ERROR: expected a repository and a real workspace/data directory, not symlinks" >&2
        exit 1
    fi
    if [[ "$(realpath -e -- "$WORKSPACE")" != "$WORKSPACE" ||
          "$(realpath -e -- "$DATA_DIR")" != "$DATA_DIR" ]]; then
        echo "ERROR: workspace layout changed; refusing cleanup" >&2
        exit 1
    fi
    local directory file
    for directory in "$DATA_DIR/HDMappingGroundTruth" "$DATA_DIR/TLS-FARO-Focus"; do
        if [[ ! -d "$directory" || -L "$directory" ]]; then
            echo "ERROR: required preserved directory is missing or a symlink: $directory" >&2
            exit 1
        fi
    done
    for file in \
        "$DATA_DIR/reg-1.bag" \
        "$DATA_DIR/HDMappingGroundTruth/lio_result_0/session.mjs" \
        "$DATA_DIR/TLS-FARO-Focus/map_gt_0.01.laz"; do
        if [[ ! -f "$file" || ! -s "$file" ]]; then
            echo "ERROR: required preserved input is missing or empty: $file" >&2
            exit 1
        fi
    done
}

validate_layout
PRESERVED=(
    "$REPO_DIR"
    "$WORKSPACE/mandeye_to_bag"
    "$WORKSPACE/livox_bag_aggregate"
    "$DATA_DIR/reg-1.bag"
    "$DATA_DIR/HDMappingGroundTruth"
    "$DATA_DIR/TLS-FARO-Focus"
)

shopt -s nullglob dotglob
TARGETS=()
for entry in "$WORKSPACE"/* "$DATA_DIR"/*; do
    path="$(realpath -m -s -- "$entry")"
    if [[ "$path" == "$DATA_DIR" ]]; then
        continue
    fi
    keep=false
    for preserved in "${PRESERVED[@]}"; do
        if [[ "$path" == "$preserved" ]]; then
            keep=true
            break
        fi
    done
    if [[ "$keep" == true ]]; then
        continue
    fi
    if [[ "${path%/*}" != "$WORKSPACE" && "${path%/*}" != "$DATA_DIR" ]]; then
        echo "ERROR: deletion target is outside the allowed scope: $path" >&2
        exit 1
    fi
    TARGETS+=("$path")
done

echo "Workspace: $WORKSPACE"
echo "Preserving:"
printf '  %q\n' "${PRESERVED[@]}"
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "Nothing to remove."
    exit 0
fi

echo "Removing these entries and their contents (including hidden files):"
printf '  %q\n' "${TARGETS[@]}"
if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run: nothing removed."
    exit 0
fi

echo "WARNING: deletion is permanent. Stop all benchmark jobs first."
if ! read -r -p "Type CLEAN to confirm: " confirmation || [[ "$confirmation" != CLEAN ]]; then
    echo "Cleanup cancelled; nothing removed."
    exit 1
fi

for path in "${TARGETS[@]}"; do
    validate_layout
    printf 'Removing %q\n' "$path"
    if [[ -L "$path" ]]; then
        if ! rm -- "$path"; then
            echo "ERROR: could not remove symlink: $path" >&2
            exit 1
        fi
    elif ! rm -rf --one-file-system -- "$path"; then
        echo "ERROR: could not remove entry: $path" >&2
        exit 1
    fi
    if [[ -e "$path" || -L "$path" ]]; then
        echo "ERROR: entry still exists after cleanup: $path" >&2
        exit 1
    fi
done
echo "Cleanup complete."

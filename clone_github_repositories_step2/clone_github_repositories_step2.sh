#!/bin/bash

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [branch_name]"
    echo
    echo "Clones all ROS1, ROS2 and non-ROS (standalone) HDMapping benchmark repositories from MapsHD"
    echo "and switches them to the specified branch, then builds their Docker images."
    echo
    echo "The list of algorithms lives in algorithms.conf, one line per algorithm."
    echo
    echo "Set ONLY_ALGOS=\"id1 id2 ...\" (ids as spelled in algorithms.conf) to restrict"
    echo "cloning and building to those algorithms."
    echo
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../algos_lib.sh"

CLONE_DIR="$HOME/hdmapping-benchmark"

if [ ! -d "$CLONE_DIR" ]; then
    echo "Creating directory $CLONE_DIR..."
    mkdir -p "$CLONE_DIR"
else
    echo "Directory $CLONE_DIR already exists, skipping creation."
fi

cd "$CLONE_DIR" || exit

if [ -n "$1" ]; then
    BRANCH_NAME="$1"
    echo "Using branch from CLI: $BRANCH_NAME"
else
    read -p "Enter the branch name to checkout for all repositories: " BRANCH_NAME
fi

check_only_algos

clone_repo() {
  local repo_name="$1"
  local branch_name="$2"
  local dir_name
  local url="https://github.com/MapsHD/${repo_name}.git"
  dir_name=$(basename "$repo_name")

  if [ ! -d "$dir_name" ]; then
    echo "Cloning $dir_name..."
    git clone --recursive "$url"
  else
    echo "$dir_name already exists, skipping clone."
  fi

  cd "$dir_name" || return
  echo "Switching $dir_name to branch $branch_name..."
  git fetch
  git checkout "$branch_name"
  # Fast-forward an existing clone to the remote branch — fetch+checkout alone
  # leaves a stale local branch ("Your branch is behind ..."). --ff-only never
  # rewrites local commits; it only advances to what origin already has.
  git pull --ff-only origin "$branch_name" || \
    echo "WARNING: $dir_name could not be fast-forwarded (local changes?) — using local state"
  # Pulled commits may bump submodule pointers; materialize them.
  git submodule update --init --recursive
  cd ..
}

for category in ROS1 ROS2 NON_ROS; do
  echo "=== Cloning $category repositories ==="
  while IFS=$'\t' read -r -u 3 repo id output input; do
    [ -n "$repo" ] || continue
    clone_repo "$repo" "$BRANCH_NAME"
  done 3< <(algo_rows "$category")
done

echo "=== All repositories have been cloned and switched to branch '$BRANCH_NAME' ==="

# A GPU is recommended but not required: e.g. PIN-SLAM uses an NVIDIA GPU when
# the NVIDIA Container Toolkit is present and falls back to CPU otherwise.
#
# A failed build does not stop the pipeline (the other algorithms still run),
# but it must not go unnoticed: without an image, step 3 cannot start that
# algorithm and it silently produces no result. Failures are listed at the end.
FAILED_BUILDS=()
for category in ROS1 ROS2 NON_ROS; do
  while IFS=$'\t' read -r -u 3 repo id output input; do
    [ -n "$repo" ] || continue
    cd "$CLONE_DIR/$repo" || continue
    # Some repos (e.g. benchmark-HDMapping_LIO-to-HDMapping) ship only a README
    # describing a manual procedure — nothing to build for those.
    if [ ! -f Dockerfile ]; then
      echo "Skipping Docker build for $id: $repo has no Dockerfile (manual procedure, see its README)."
      cd "$CLONE_DIR" || exit
      continue
    fi
    tag="$(image_tag "$id" "$category")"
    echo "Building Docker image $tag for $id ($category)..."
    if ! docker build -t "$tag" .; then
      echo "!!! Docker build FAILED for $id ($tag)"
      FAILED_BUILDS+=("$id ($tag, $repo)")
    fi
    cd "$CLONE_DIR" || exit
  done 3< <(algo_rows "$category")
done

if [ ${#FAILED_BUILDS[@]} -eq 0 ]; then
  echo "=== All Docker images built ==="
else
  echo "=== Docker images built, but ${#FAILED_BUILDS[@]} FAILED; these algorithms will produce no results: ==="
  printf '    %s\n' "${FAILED_BUILDS[@]}"
fi

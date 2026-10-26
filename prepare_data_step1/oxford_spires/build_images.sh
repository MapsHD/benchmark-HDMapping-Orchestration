#!/bin/bash
# Builds the two images prepare.sh uses:
#   hdmapping-tools    HDMapping's bag_to_laz / laz_to_bag / laz_to_mcap / mcap_to_laz
#   oxford-spires-tools oxford_spires.py (calibration, ground truth, GT session, TLS reference)
#
# HDMapping comes from HDMAPPING_REPO at HDMAPPING_REF (default: MapsHD/HDMapping,
# branch canonical-bag). Set HDMAPPING_SRC to a local HDMapping checkout (with its
# submodules) to build that checkout as it is on disk instead, e.g. before the
# branch is pushed; its build directories and .git are left out.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HDMAPPING_REPO="${HDMAPPING_REPO:-https://github.com/MapsHD/HDMapping.git}"
HDMAPPING_REF="${HDMAPPING_REF:-canonical-bag}"

context="$(mktemp -d)"
trap 'rm -rf "$context"' EXIT
cp "$SCRIPT_DIR/Dockerfile.hdmapping" "$context/Dockerfile"
if [[ -n "${HDMAPPING_SRC:-}" ]]; then
    echo "Building hdmapping-tools from the checkout $HDMAPPING_SRC"
    mkdir -p "$context/HDMapping"
    # Every .git (the submodules' link files too): a copied checkout has no repository,
    # and libE57Format runs `git submodule update` whenever it finds one.
    tar -C "$HDMAPPING_SRC" --exclude='.git' --exclude='./build*' -cf - . | tar -C "$context/HDMapping" -xf -
    git -C "$HDMAPPING_SRC" log -1 --format='HDMapping %h %s (local checkout)' > "$context/HDMapping/.hdmapping-version"
else
    echo "Building hdmapping-tools from $HDMAPPING_REPO ($HDMAPPING_REF)"
fi
docker build -t hdmapping-tools \
    --build-arg HDMAPPING_REPO="$HDMAPPING_REPO" \
    --build-arg HDMAPPING_REF="$HDMAPPING_REF" \
    "$context"

docker build -t oxford-spires-tools -f "$SCRIPT_DIR/Dockerfile.python" "$SCRIPT_DIR"
docker run --rm --entrypoint cat hdmapping-tools /usr/local/share/hdmapping-version

#!/bin/bash
set -euo pipefail

# TOPDIR="/cvmfs/myorg/software"
TOPDIR="/tmp/spack-test-build"
BUILD_SCRIPT="./build.sh"
OS_TAGS=("el9")

for OS in "${OS_TAGS[@]}"; do
    IMAGE="./${OS}.sif"

    echo "[+] Building for $OS using image: $IMAGE"
    apptainer exec \
        -B /tmp:/tmp \
        -B /users:/users \
        -B /var:/var \
        -B "$PWD":"$PWD" \
        -B "$TOPDIR":"$TOPDIR" \
        "$IMAGE" \
        "$BUILD_SCRIPT" "$OS" "$TOPDIR"
done

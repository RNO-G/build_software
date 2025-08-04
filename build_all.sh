#!/bin/bash
set -euo pipefail

# the final real path where we want files to be installed
INSTALL_DIR="/cvmfs/rnog.opensciencegrid.org/software"

# the temporary spot where we are going to build and actually write files
BUILD_DIR="/tmp/rnog_build"
mkdir -p $BUILD_DIR

# in cvmfs, we bind BUILD_DIR to INSTALL_DIR
# so that we can temporarily write to BUILD_DIR,
# but the install scripts *think* they are writing to INSTALL_DIR
# so that we can rsync them to their final destination at the end
# and everything looks alright

BUILD_SCRIPT="./build.sh"
OS_TAGS=("el9")

for OS in "${OS_TAGS[@]}"; do
    IMAGE="./osg_${OS}.sif"

    echo "[+] Building for $OS using image: $IMAGE"
    apptainer exec \
        -B /tmp/rnog_scratch:/tmp \
        -B "$BUILD_DIR":"$INSTALL_DIR" \
        -B /var:/var \
        -B "$PWD":"$PWD" \
        "$IMAGE" \
        "$BUILD_SCRIPT" "$OS" "$INSTALL_DIR"
done

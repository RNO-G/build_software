#!/bin/bash
set -euo pipefail
# Runs check.sh on a build that's still sitting in /tmp, before you deploy it.
# Same trick as build_version.sh: the /tmp build gets mounted at its cvmfs path inside the container.
# Run it from the same place as build_version.sh (where the .sif files are).
#
# Once it's on cvmfs you don't need this, just run check.sh directly (e.g. at OSC):
#   bash test/check.sh /cvmfs/rnog.opensciencegrid.org/software/unstable/el9/setup.sh

if [ $# -ne 2 ]; then
    echo "Usage: $0 <version> <os>"
    echo "Example: $0 unstable el9"
    exit 1
fi

VERSION="$1"
OS="$2"
IMAGE="./${OS}.sif"
BUILD_DIR="/tmp/rnog_build/software/${VERSION}/${OS}"
DESTDIR="/cvmfs/rnog.opensciencegrid.org/software/${VERSION}/${OS}"

apptainer exec -c \
    -B "$PWD":"$PWD" \
    -B "$BUILD_DIR":"$DESTDIR" \
    "$IMAGE" \
    bash "$PWD/test/check.sh" "$DESTDIR/setup.sh"

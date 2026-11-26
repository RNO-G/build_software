#!/bin/bash
set -euo pipefail

# Copy a finished build from /tmp into cvmfs and publish it.
# Has to be run on the stratum zero machine.
#
#   deploy.sh <version> <os>              cvmfs becomes an exact copy of the /tmp build
#   deploy.sh <version> <os> --rnog-only  only copy over librno-g, mattak, and NuRadioMC
#                                         (after a build_version.sh <version> <os> --rnog-only)
#
# This doesn't touch the top level software/<version>/setup.sh, move that by hand.

if [ $# -ne 2 ] && ! { [ $# -eq 3 ] && [ "$3" = "--rnog-only" ]; }; then
    echo "Usage: $0 <version> <os> [--rnog-only]"
    exit 1
fi
VERSION="$1"
OS="$2"
RNOG_ONLY=false
if [ $# -eq 3 ]; then
    RNOG_ONLY=true
fi

CVMFS_REPO="rnog.opensciencegrid.org"
# these need to match build_version.sh
BUILD_DIR="/tmp/rnog_build/software/${VERSION}/${OS}"
DESTDIR="/cvmfs/${CVMFS_REPO}/software/${VERSION}/${OS}"

if [ ! -d "$BUILD_DIR/misc_build" ]; then
    echo "[!] No build found in $BUILD_DIR"
    exit 1
fi

if $RNOG_ONLY; then
    # the RNO-G packages got built against the spack stack in /tmp,
    # so make sure that's the same stack that's already in cvmfs.
    # spack.lock is spack's record of exactly what it built, so just compare those.
    lock_sums() { (cd "$1" && find .spack_internals -path '*/environments/*/spack.lock' | sort | xargs -r md5sum); }
    TMP_LOCKS="$(lock_sums "$BUILD_DIR")"
    if [ -z "$TMP_LOCKS" ] || [ ! -d "$DESTDIR" ] || [ "$TMP_LOCKS" != "$(lock_sums "$DESTDIR")" ]; then
        echo "[!] The spack stack in $BUILD_DIR isn't the one in $DESTDIR, so the RNO-G packages won't match it."
        echo "    Not deploying. Do a full build + deploy instead."
        exit 1
    fi
    # same list of things that builders/<version>/build_rnog.sh wipes
    SYNC_PATHS=("rnog_build" "source/librno-g" "source/mattak")
    # only unstable has NuRadioMC so far
    [ -d "$BUILD_DIR/source/NuRadioMC" ] && SYNC_PATHS+=("source/NuRadioMC")
    for d in "$BUILD_DIR"/misc_build/lib/python3.*/site-packages/mattak; do
        [ -d "$d" ] && SYNC_PATHS+=("${d#"$BUILD_DIR"/}")
    done
else
    SYNC_PATHS=(".")
fi

cvmfs_server transaction "$CVMFS_REPO"
# if anything fails from here on, throw the transaction away
trap 'echo "[!] Failed, aborting the cvmfs transaction"; cvmfs_server abort -f "$CVMFS_REPO"' EXIT

for p in "${SYNC_PATHS[@]}"; do
    echo "[+] Copying $BUILD_DIR/$p/ -> $DESTDIR/$p/"
    mkdir -p "$DESTDIR/$p"
    rsync -a --delete "$BUILD_DIR/$p/" "$DESTDIR/$p/"
done

cvmfs_server publish "$CVMFS_REPO"
trap - EXIT
echo "[+] Published $VERSION/$OS"

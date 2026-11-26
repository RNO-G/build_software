#!/bin/bash
set -euo pipefail

# Wipe and rebuild librno-g and mattak (mattak needs librno-g, so it goes second).
# build.sh calls this, for a full build and for --rnog-only,
# and it uses whatever environment build.sh already set up (spack env, compiler, flags).
#
# Everything in rnog_build/ gets wiped here, so if you add something
# else that installs there (nuradiomc, say), build it in here too.
# deploy.sh --rnog-only copies over exactly the stuff this wipes.

if [ $# -ne 4 ]; then
    echo "Usage: $0 <source_dir> <rnog_build_dir> <misc_dir> <nproc>"
    exit 1
fi
SOURCE_DIR="$1"
RNOG_BUILD_DIR="$2"
MISC_DIR="$3"
NPROC="$4"
HERE="$(cd "$(dirname "$0")" && pwd)"

# mattak puts its python module in the view's site-packages, not in rnog_build, so wipe that too
PY_SITE=$(python3 -c "import site; print(site.getsitepackages()[0])")

echo "[+] Wiping old librno-g and mattak"
rm -rf "${RNOG_BUILD_DIR:?}" "${SOURCE_DIR:?}/librno-g" "${SOURCE_DIR:?}/mattak" "${PY_SITE:?}/mattak"
mkdir -p "$RNOG_BUILD_DIR"

"$HERE/build_librnog.sh" --source "$SOURCE_DIR" --build "$RNOG_BUILD_DIR" --root "$MISC_DIR" --deps "$MISC_DIR"
"$HERE/build_mattak.sh" --source "$SOURCE_DIR" --build "$RNOG_BUILD_DIR" --root "$MISC_DIR" --deps "$MISC_DIR" --make_arg "-j$NPROC"

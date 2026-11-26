#!/bin/bash
set -euo pipefail
# PROPOSAL (lepton propagation for NuRadioMC), plus CubicInterpolation, which it needs.
# pip install proposal builds through conan, which drags in its own boost and everything else.
# We already have all of that from spack, so just do the plain cmake build from their INSTALL.md.
# It goes into misc_build, like healpix, since it's part of the base stack.
if [ $# -ne 3 ]; then echo "Usage: $0 <source_dir> <install_dir> <nproc>"; exit 1; fi
SOURCE_DIR="$1"; INSTALL_DIR="$2"; NPROC="$3"

cd "$SOURCE_DIR"
rm -rf cubic_interpolation PROPOSAL
git clone --depth 1 --branch v0.1.5 https://github.com/MaxSac/cubic_interpolation.git
git clone --depth 1 --branch 7.6.2 https://github.com/tudo-astroparticlephysics/PROPOSAL.git

# both build static libraries, and cubic needs -fPIC to end up inside the python module
cmake -S cubic_interpolation -B cubic_interpolation/build -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build cubic_interpolation/build -j "$NPROC"
cmake --install cubic_interpolation/build

cmake -S PROPOSAL -B PROPOSAL/build -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$INSTALL_DIR" \
    -DBUILD_PYTHON=ON -Dpybind11_DIR="$(python3 -m pybind11 --cmakedir)"
cmake --build PROPOSAL/build -j "$NPROC"
cmake --install PROPOSAL/build

# the python module gets installed next to the libraries, move it to where python looks
PY_SITE=$(python3 -c "import site; print(site.getsitepackages()[0])")
mv "$INSTALL_DIR"/lib/proposal.cpython-*.so "$PY_SITE"/

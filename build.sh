#!/bin/bash
set -euo pipefail

# ==== CONFIGURATION ====
SPACK_DIR="$PWD/spack"                      # Location to clone Spack
ENV_NAME="cvmfs_env"                        # Spack environment name
YAML_SOURCE="./spack_rhel8.yaml"            # Your existing spack.yaml
WORKDIR="/tmp/spack-runtime-rhel8"          # Scratch space for build/install
VIEWDIR="$WORKDIR/view"                     # Final runtime view for CVMFS export
NPROC=10                                    # Number of parallel jobs for build

# ==== STEP 1: Clone Spack if Needed ====
if [ ! -d "$SPACK_DIR" ]; then
    echo "[+] Cloning Spack..."
    git clone --depth=2 https://github.com/spack/spack.git "$SPACK_DIR"
fi
source "$SPACK_DIR/share/spack/setup-env.sh"

# ==== STEP 2: Build Compiler First ====
echo "[+] Bootstrapping compiler..."
if ! spack spec gcc@15.1 &>/dev/null; then
    spack install gcc@15.1 ^gcc@builtin
fi

# ==== STEP 3: Create and Activate Environment ====
echo "[+] Creating and activating Spack environment..."
mkdir -p "$WORKDIR/$ENV_NAME"
cp "$YAML_SOURCE" "$WORKDIR/$ENV_NAME/spack.yaml"
spack env create "$ENV_NAME" "$WORKDIR/$ENV_NAME/spack.yaml"
spack env activate "$ENV_NAME"

# ==== STEP 4: Install All Packages ====
echo "[+] Concretizing and installing packages..."
spack concretize --fresh
spack install -j "$NPROC"
